import AppKit
import CryptoKit
import UniformTypeIdentifiers

final class FlowApp: NSObject, NSApplicationDelegate, NSMenuItemValidation {
  let startupTimeline: NativeStartupTimeline?
  let isolated: Bool
  let devIsolatedServicePreview: Bool
  let fixture: URL?
  var fixtureMode: Bool { isolated && fixture != nil }
  var openExternalURL: (URL) -> Bool = { NSWorkspace.shared.open($0) }
  var revealExternalFiles: ([URL]) -> Void = { NSWorkspace.shared.activateFileViewerSelecting($0) }
  let noActivate: Bool
  let showNativeWindow: Bool
  let nativeRuntime: NativeReaderRuntime?
  let copyText: (String) -> Bool
  static func extractDevIsolatedServicePreview(from arguments: [String]) -> (enabled: Bool, remaining: [String]) {
    let enabled = arguments.contains("--dev-isolated-service-preview")
    let remaining = arguments.filter { $0 != "--dev-isolated-service-preview" }
    return (enabled, remaining)
  }
  static func validateDevIsolatedServicePreview(_ enabled: Bool, configuration: FlowRuntimeConfiguration) throws {
    guard enabled else { return }
    guard configuration.isolated else {
      throw FlowError(message: "Dev presentation/runtime options require an explicit dev root")
    }
    guard configuration.fixture == nil else {
      throw FlowError(message: "Fixture mode cannot be combined with isolated service preview")
    }
  }
  /// Stable per isolated home so an independent inspector can read only its board.
  static func isolatedCopyBoard(home: URL) -> NSPasteboard.Name {
    let digest = SHA256.hash(data: Data(home.standardizedFileURL.path.utf8))
      .map { String(format: "%02x", $0) }.joined()
    return NSPasteboard.Name("io.github.kimpossible-ty.lagrangian.dev.copy." + digest)
  }
  var nativeProfile: Profile?
  private var consentedEditors: [String: NativeReaderManagedEditor] = [:]
  private var readerEditorConsent: (window: NativeReaderWindowController, profileID: String, editor: NativeReaderManagedEditor)?
  var managedResolver: NativeReaderManagedResolver?
  var nativeWindow: NativeReaderWindowController?
  var crossProjectNavigationStack = CrossProjectNavigationStack()
  var nativeWindowControllerFactory: ((Profile) -> NativeReaderWindowController?)?
  var crossProjectOpen: ((NativeReaderWindowController, Profile, @escaping (NativeReadProgress) -> Void) -> () -> Void)?
  var crossProjectDocumentLoader: ((Profile) async throws -> NativeReaderDocument)?
  private var pendingCrossProjectWindow: NativeReaderWindowController?
  private var pendingCrossProjectCancel: (() -> Void)?
  private var pendingCrossProjectEditor: (profileID: String, editor: NativeReaderManagedEditor)?
  private var crossProjectNavigationSerial = 0
  private var activeNativeReadCancel: (() -> Void)?
  private var nativeReadSessionToken = 0
  private var nativeSessionOriginProfileID: String?
  var offlineWindow: NativeReaderWindowController?
  var nativeReadOverride: ReadingSessionController.NativeRead?
  let environment: AppEnvironment
  let store: SettingsStore
  let launchAgents: LaunchAgentService
  private let serviceController: ProjectControlling
  let projectService: ProjectService
  var settings = Settings()
  lazy var session = ReadingSessionController(
    launchAgents: serviceController,
    onChange: { [weak self] snapshot in self?.render(snapshot) },
    openBrowser: { [weak self] url in
      guard let self, !self.fixtureMode else { return false }
      return self.openExternalURL(url)
    },
    startupTimeline: startupTimeline,
    nativeRead: { [weak self] profile, progress in
      guard let self else { return {} }
      return self.readNative(profile, progress: progress)
    },
    nativeEvent: { [weak self] event in
      guard let self, (self.nativeProfile == self.active ||
        (self.nativeSessionOriginProfileID != nil && self.nativeSessionOriginProfileID == self.active?.id)),
        let window = self.nativeWindow else { return false }
      return MainActor.assumeIsolated { window.environmentChanged(event) }
    },
    probe: devIsolatedServicePreview
      ? { [serviceController] profile, completion in
        let ready = serviceController.jobPID(profile.label) != nil
        completion(ready ? .ready : .waiting("엔진이 아직 실행되지 않았습니다."))
        return {}
      }
      : PreviewReadinessProbe.start
  )
  /// The same production composition is called by Read and isolated offscreen
  /// tests; service inventory and window visibility remain explicit inputs.
  func crossProjectCatalog(for profile: Profile?) -> CrossProjectCatalog? {
    let packages = profile?.packages ?? ""
    let root = packages.isEmpty
      ? environment.userHome.appendingPathComponent("Library/Application Support/typst/packages")
      : URL(fileURLWithPath: packages, isDirectory: true)
    return try? CrossProjectCatalog.load(from: root.appendingPathComponent("local/project-references/0.1.0/projects.json"))
  }

  @MainActor func makeNativeReaderWindowController(for profile: Profile, editor: NativeReaderManagedEditor? = nil) -> NativeReaderWindowController? {
    let controller: NativeReaderWindowController
    if let factory = nativeWindowControllerFactory {
      guard let made = factory(profile) else { return nil }
      controller = made
    } else if let fixture, isolated {
      let provider = NativeReaderFixtureProvider(url: fixture)
      controller = NativeReaderWindowController(provider: provider, target: { _ in try await provider.load().identity },
        assets: { document, _ in
          try await Task.detached {
            var bytes = [String: Data]()
            for asset in document.assets {
              bytes[asset.id] = try Data(contentsOf: fixture.deletingLastPathComponent().appendingPathComponent("assets").appendingPathComponent(asset.id))
            }
            return bytes
          }.value
        }, runtime: nativeRuntime, show: showNativeWindow, avoidActivation: noActivate, fixtureMode: fixtureMode,
        offlineStorage: NativeReaderOfflineStorage(owner: NativeReaderRecoveryStore(root: environment.nativeRecoveryRoot(for: profile))))
    } else {
      guard let resolver = managedResolver else { return nil }
      let client = NativeReaderManagedClient(resolver: resolver, root: profile.root, entry: profile.entry, editor: editor)
      controller = NativeReaderWindowController(provider: client, target: { _ in try await client.target() },
        assets: { document, context in
          let actions = try await client.currentActions()
          var assets = [String: Data]()
          for asset in document.assets { assets[asset.id] = try await actions.transport.asset(asset, context: context) }
          return assets
        }, runtime: nativeRuntime, actions: { try await client.currentActions() },
        invalidate: { await client.invalidate() }, show: showNativeWindow, avoidActivation: noActivate, fixtureMode: fixtureMode,
        offlineStorage: NativeReaderOfflineStorage(owner: NativeReaderRecoveryStore(root: environment.nativeRecoveryRoot(for: profile))))
    }
    configureNativeWindowController(controller, for: profile)
    return controller
  }

  @MainActor func configureNativeWindowController(_ controller: NativeReaderWindowController, for profile: Profile) {
    controller.copyText = copyText
    controller.openHomepage = { [weak self] url in
      guard let self, !self.fixtureMode else { return }
      _ = self.openExternalURL(url)
    }
    controller.crossProjectCatalogProvider = { [weak self] in self?.crossProjectCatalog(for: profile) }
    controller.crossProjectSnippetLoader = { [weak self] target in
      guard let self, let catalog = self.crossProjectCatalog(for: profile),
            let targetProfile = catalog.matchProfile(for: target.projectKey, in: self.settings.profiles) else { return nil }
      do {
        let document: NativeReaderDocument
        if let loader = self.crossProjectDocumentLoader {
          document = try await loader(targetProfile)
        } else {
          guard let resolver = self.managedResolver else { return nil }
          let client = NativeReaderManagedClient(resolver: resolver, root: targetProfile.root, entry: targetProfile.entry, editor: nil)
          do {
            let identity = try await client.target()
            let context = NativeReaderRequestContext(requestID: UUID(), viewID: UUID(), generation: 1, target: identity)
            document = try await client.document(for: context)
            await client.dispose()
          } catch {
            await client.dispose()
            throw error
          }
        }
        guard let snippet = CrossProjectSnippetExtractor.extract(from: document, label: target.label, referenceText: target.entry.text) else { return nil }
        return CrossProjectPreviewContent(projectKey: target.projectKey, projectTitle: target.project.title,
          referenceText: target.entry.text, label: target.label, snippetText: snippet.text, truncated: snippet.truncated)
      } catch { return nil }
    }
    controller.onOpenCrossProjectTarget = { [weak self] content, returnEntry in
      guard let self, let target = self.crossProjectCatalog(for: profile)?.matchProfile(for: content.projectKey, in: self.settings.profiles) else { return }
      let location = CrossProjectNavigationEntry(profileID: target.id, documentTitle: target.name, anchor: content.label, blockID: nil, scrollOffset: 0)
      self.beginCrossProjectTransition(to: target, targetLocation: location, pushOnSuccess: returnEntry, popOnSuccess: false)
    }
    controller.canReturnFromCrossProject = { [weak self] in self?.crossProjectNavigationStack.canGoBack ?? false }
    controller.onReturnFromCrossProject = { [weak self] in
      guard let self else { return false }
      while let entry = self.crossProjectNavigationStack.peek() {
        let matches = self.settings.profiles.filter { $0.id == entry.profileID }
        guard matches.count == 1 else { _ = self.crossProjectNavigationStack.pop(); continue }
        let hasBlockID = entry.blockID.map { !$0.isEmpty } ?? false
        let location = CrossProjectNavigationEntry(profileID: entry.profileID, documentTitle: entry.documentTitle,
          anchor: hasBlockID ? nil : entry.anchor, blockID: entry.blockID, scrollOffset: entry.scrollOffset)
        return self.beginCrossProjectTransition(to: matches[0], targetLocation: location, pushOnSuccess: nil, popOnSuccess: true)
      }
      return false
    }
  }

  @MainActor @discardableResult func beginCrossProjectTransition(to targetProfile: Profile, targetLocation: CrossProjectNavigationEntry,
      pushOnSuccess: CrossProjectNavigationEntry?, popOnSuccess: Bool) -> Bool {
    cancelPendingCrossProjectTransition()
    // Reserve the descriptor while the candidate prepares; origin tracking stays
    // intact until successful adoption. Only a pre-attach failure/cancel can
    // return the reservation; disposal closes any consent used by attach.
    let editor = consentedEditors.removeValue(forKey: targetProfile.id)
    guard let candidate = makeNativeReaderWindowController(for: targetProfile, editor: editor) else {
      if let editor { consentedEditors[targetProfile.id] = editor }
      return false
    }
    if let editor { pendingCrossProjectEditor = (targetProfile.id, editor) }
    candidate.pendingCrossProjectTarget = targetLocation
    crossProjectNavigationSerial += 1
    let serial = crossProjectNavigationSerial
    pendingCrossProjectWindow = candidate
    var committed = false
    var cancel: (() -> Void)?
    let onProgress: (NativeReadProgress) -> Void = { [weak self, weak candidate] progress in
      guard let self, let candidate, self.crossProjectNavigationSerial == serial,
            self.pendingCrossProjectWindow === candidate, !committed else { return }
      switch progress {
      case .windowInitialized:
        committed = true
        self.pendingCrossProjectWindow = nil; self.pendingCrossProjectCancel = nil
        if let entry = pushOnSuccess { self.crossProjectNavigationStack.push(entry) }
        if popOnSuccess { _ = self.crossProjectNavigationStack.pop() }
        self.pendingCrossProjectEditor = nil
        self.nativeWindow?.dispose()
        self.readerEditorConsent = editor.map { (candidate, targetProfile.id, $0) }
        self.nativeWindow = candidate; self.nativeProfile = targetProfile
        self.activeNativeReadCancel = cancel
        candidate.hostWindow.updateNavigation()
      case .failed:
        self.pendingCrossProjectWindow = nil; self.pendingCrossProjectCancel = nil
        self.restorePendingCrossProjectEditor(candidate: candidate)
        candidate.dispose()
      default: break
      }
    }
    let openCancel = crossProjectOpen?(candidate, targetProfile, onProgress) ?? candidate.open(targetProfile, progress: onProgress)
    cancel = bindNativeReaderClose(candidate, cancel: openCancel)
    if pendingCrossProjectWindow === candidate { pendingCrossProjectCancel = cancel }
    return true
  }

  @MainActor private func restorePendingCrossProjectEditor(candidate: NativeReaderWindowController?) {
    if let pending = pendingCrossProjectEditor, candidate?.returnUnattachedEditorConsent() == true {
      consentedEditors[pending.profileID] = pending.editor
    }
    pendingCrossProjectEditor = nil
  }

  @MainActor func cancelPendingCrossProjectTransition() {
    crossProjectNavigationSerial += 1
    let cancel = pendingCrossProjectCancel
    let candidate = pendingCrossProjectWindow
    pendingCrossProjectCancel = nil; pendingCrossProjectWindow = nil
    restorePendingCrossProjectEditor(candidate: candidate)
    cancel?(); candidate?.dispose()
  }

  @MainActor func readNative(_ profile: Profile, progress: @escaping (NativeReadProgress) -> Void) -> () -> Void {
    cancelPendingCrossProjectTransition()
    crossProjectNavigationStack = CrossProjectNavigationStack()
    if let read = nativeReadOverride { return read(profile, progress) }
    if nativeProfile != profile || nativeWindow?.session.hasRecoveryCopy == true {
      nativeWindow?.dispose(); nativeWindow = nil; readerEditorConsent = nil; nativeProfile = profile
    }
    if nativeWindow == nil {
      let editor = consentedEditors.removeValue(forKey: profile.id)
      nativeWindow = makeNativeReaderWindowController(for: profile, editor: editor)
      if let editor {
        if let window = nativeWindow { readerEditorConsent = (window, profile.id, editor) }
        else { consentedEditors[profile.id] = editor }
      }
    }
    guard let window = nativeWindow else {
      progress(.failed("네이티브 문서 서비스가 아직 연결되지 않았습니다. 명시적으로 구성된 Reader manager가 필요합니다."))
      return {}
    }
    nativeReadSessionToken += 1
    let token = nativeReadSessionToken
    nativeSessionOriginProfileID = profile.id
    let openCancel = window.open(profile, progress: progress)
    activeNativeReadCancel = bindNativeReaderClose(window, cancel: openCancel)
    return { [weak self] in
      guard let self, self.nativeReadSessionToken == token else { return }
      self.cancelPendingCrossProjectTransition()
      self.nativeSessionOriginProfileID = nil
      let cancel = self.activeNativeReadCancel
      self.activeNativeReadCancel = nil
      cancel?()
    }
  }
  @MainActor private func bindNativeReaderClose(_ window: NativeReaderWindowController, cancel: @escaping () -> Void) -> () -> Void {
    let close = window.hostWindow.onClose
    var cancelled = false
    window.hostWindow.onClose = { [weak self, weak window] in
      close?()
      guard let self, let window, self.readerEditorConsent?.window === window else { return }
      // The Reader revokes on normal close; disposal owns cancelled tickets.
      self.readerEditorConsent = nil
      if cancelled {
        if self.nativeWindow === window { self.nativeWindow = nil }
        window.dispose()
      }
      self.refreshMenu()
    }
    refreshMenu()
    return { cancelled = true; cancel() }
  }
  lazy var readingEnvironment = NativeReadingEnvironment(
    onSleep: { [weak self] in self?.sleepChanged($0) },
    onNetwork: { [weak self] in self?.networkChanged($0) },
    onPower: { [weak self] in self?.powerChanged($0) }
  )
  var snapshot: ReadingSessionSnapshot?
  var mutating = false
  var loginEnabled = false
  var readingIntent = 0

  init(environment: AppEnvironment, projectService: ProjectService? = nil,
       isolated: Bool = false, devIsolatedServicePreview: Bool = false, fixture: URL? = nil,
       noActivate: Bool = false, startupTimeline: NativeStartupTimeline? = nil, nativeRuntime: NativeReaderRuntime? = nil, nativeManager: URL? = nil, showNativeWindow: Bool = true) {
    self.startupTimeline = startupTimeline
    self.noActivate = noActivate
    self.showNativeWindow = showNativeWindow
    self.nativeRuntime = nativeRuntime
    self.isolated = isolated
    self.fixture = fixture
    let previewService = isolated && fixture == nil && devIsolatedServicePreview
    self.devIsolatedServicePreview = previewService
    self.environment = environment
    let privateBoard = isolated ? NSPasteboard(name: Self.isolatedCopyBoard(home: environment.userHome)) : nil
    copyText = { text in
      let board = privateBoard ?? NSPasteboard.general
      board.clearContents()
      return board.setString(text, forType: .string)
    }
    store = SettingsStore(directory: environment.support, localReplacement: environment.fixtureRoot != nil)
    let realAgents = LaunchAgentService(environment: environment)
    launchAgents = realAgents
    let effectiveAgents: ProjectControlling
    if isolated {
      effectiveAgents = previewService ? SimulatedIsolatedProjectController() as ProjectControlling : IsolatedProjectController()
    } else {
      effectiveAgents = realAgents
    }
    self.serviceController = effectiveAgents
    self.projectService = projectService ?? ProjectService(store: store, launchAgents: effectiveAgents)
    super.init()
    startupTimeline?.owner = self
    if let manager = nativeManager, !fixtureMode {
      managedResolver = NativeReaderManagedResolver(attach: { arguments in
        guard manager.isFileURL, FileManager.default.isExecutableFile(atPath: manager.path) else {
          throw NativeReaderOperationFailure.unavailable
        }
        return try await CommandRunner.nativeReaderManager(manager.path, arguments)
      }, network: .urlSession())
    }
  }
  var settingsWindow: NSWindow?
  private(set) var isSettingsPresented = false
  private var settingsSaved = false
  /// Explicit profile-local consent. Choosing a descriptor never scans editors or
  /// grants registration through HTTP. Reconnect requires this action again.
  @MainActor @objc func connectEditor() {
    guard !fixtureMode, let profile = active else { return }
    let panel = NSOpenPanel()
    panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
    panel.message = "Choose the private local editor descriptor for this project. Connect permits explicit Locate Source moves only."
    panel.begin { [weak self] response in
      guard let self, response == .OK, let url = panel.url, self.active?.id == profile.id else { return }
      Task { @MainActor in
        do {
          _ = try await self.connectEditor(descriptor: url, for: profile) {
            let consent = NSAlert()
            consent.messageText = "Connect this editor for the selected project?"
            consent.informativeText = "Only explicit Locate Source actions may move its cursor. Unsaved buffers and source files are preserved. Closing the connection or restarting the service requires new consent."
            consent.addButton(withTitle: "Connect"); consent.addButton(withTitle: "Cancel")
            return consent.runModal() == .alertFirstButtonReturn
          }
        } catch {
          let alert = NSAlert(); alert.messageText = "Editor descriptor unavailable"
          alert.informativeText = "Use an existing private local descriptor with an exact executable, address, live owner and private control file."
          alert.runModal()
        }
      }
    }
  }
  /// Descriptor validation and adoption have one owner. Only the explicit UI
  /// consent decision is supplied as an operation; no process/port discovery.
  @MainActor @discardableResult func connectEditor(descriptor: URL, for profile: Profile,
                                                   consent: () -> Bool) async throws -> Bool {
    guard !fixtureMode else { throw NativeReaderOperationFailure.unavailable }
    let editor = try await Task.detached { try NativeReaderManagedEditor.consentedDescriptor(descriptor) }.value
    guard active == profile else { throw NativeReaderContractError.wrongTarget }
    guard consent() else { return false }
    cancelPendingCrossProjectTransition()
    nativeWindow?.dispose(); nativeWindow = nil; readerEditorConsent = nil
    if let resolver = managedResolver,
       !(await resolver.retryEditorCleanup(root: profile.root, entry: profile.entry)) {
      throw NativeReaderOperationFailure.unavailable
    }
    guard active == profile else { throw NativeReaderContractError.wrongTarget }
    consentedEditors[profile.id] = editor
    refreshMenu()
    return true
  }
  @MainActor @objc func disconnectEditor() {
    guard !fixtureMode else { return }
    guard let profile = active else { return }
    cancelPendingCrossProjectTransition()
    consentedEditors.removeValue(forKey: profile.id)
    nativeWindow?.dispose(); nativeWindow = nil; readerEditorConsent = nil
    refreshMenu()
  }
  /// Explicit local action does not enter ReadingSessionController.read/start or
  /// resolve a manager. Keep the current live document/service independent.
  @MainActor @objc func openOffline() {
    guard let profile = active else { return }
    offlineWindow?.dispose()
    let window = NativeReaderWindowController(provider: NativeReaderOfflineProvider(), target: { _ in throw NativeReaderOperationFailure.unavailable },
      runtime: nativeRuntime, show: showNativeWindow, avoidActivation: noActivate, fixtureMode: fixtureMode,
      offlineStorage: NativeReaderOfflineStorage(owner: NativeReaderRecoveryStore(root: environment.nativeRecoveryRoot(for: profile))))
    window.copyText = copyText
    offlineWindow = window
    window.openOfflineLibrary(profile)
  }
  private func syncFieldsFromActive() {
    if let p = active {
      for (key, value) in [
        "name": p.name, "root": p.root, "entry": p.entry, "fonts": p.fonts.joined(separator: "; "),
        "packages": p.packages, "port": String(p.port), "publicURL": p.publicURL,
      ] { fields[key]?.stringValue = value }
    } else {
      for field in fields.values { field.stringValue = "" }
    }
    refreshSettingsHeader()
  }
  private func clearSettingsStatus() {
    settingsStatus.stringValue = ""
    settingsStatus.isHidden = true
    refreshStatusColor()
  }
  private func discardUnsavedSettingsEdits() {
    syncFieldsFromActive()
    clearSettingsStatus()
  }
  @objc func showSettings() {
    guard active != nil, !isSettingsPresented, window?.attachedSheet == nil else { return }
    showWindow()
    settingsSaved = false
    discardUnsavedSettingsEdits()
    guard let sheet = settingsWindow else { return }
    isSettingsPresented = true
    if NSApp.activationPolicy() != .prohibited, let window, window.isVisible, window.attachedSheet == nil {
      window.beginSheet(sheet) { [weak self] _ in
        guard let self else { return }
        self.isSettingsPresented = false
        if !self.settingsSaved {
          self.discardUnsavedSettingsEdits()
        }
        self.settingsSaved = false
      }
    }
    sheet.makeFirstResponder(fields["name"])
  }
  @objc func closeSettings() {
    guard !mutating else { return }
    let wasPresented = isSettingsPresented
    isSettingsPresented = false
    guard let sheet = settingsWindow else { return }
    if let window, window.attachedSheet === sheet {
      window.endSheet(sheet)
    } else {
      sheet.orderOut(nil)
      if wasPresented && !settingsSaved {
        discardUnsavedSettingsEdits()
      }
      settingsSaved = false
    }
  }
  var statusItem: NSStatusItem!
  var window: NSWindow!
  let picker = NSPopUpButton()
  let status = NSTextField(labelWithString: "")
  let activity = NSProgressIndicator()
  let brandMark = NativeBrandMarkView()
  let serviceToggleButton = NativeDesignButton(title: "", target: nil, action: nil)
  let overflowButton = NativeDesignButton(title: "", target: nil, action: nil)
  private let feedbackStack = NSStackView()
  private let feedbackIcon = NSImageView()
  private var feedbackHeight: NSLayoutConstraint?
  private var copyConfirmation: DispatchWorkItem?
  private let settingsProjectLabel = NSTextField(labelWithString: "")
  private let settingsEntryLabel = NSTextField(labelWithString: "")
  private let settingsHintLabel = NSTextField(wrappingLabelWithString: "글꼴 경로는 프로젝트 기준이며, HTTPS 주소는 선택 사항입니다.")
  let settingsStatus = NSTextField(wrappingLabelWithString: "")
  var controls: [Selector: NSButton] = [:]
  var fields: [String: NSTextField] = [:]
  private var appearanceObservation: NSKeyValueObservation?
  private var accessibilityObservation: NSObjectProtocol?
  var active: Profile? { settings.profiles.first { $0.id == settings.selectedID } }
  deinit {
    copyConfirmation?.cancel()
    appearanceObservation?.invalidate()
    if let accessibilityObservation {
      NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObservation)
    }
  }
  func applicationDidFinishLaunching(_ note: Notification) {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.button?.title = ""
    statusItem.button?.image = NativeBrandMark.statusImage(phase: .idle)
    buildMenu()
    buildWindow()
    if !CommandLine.arguments.contains("--background") { showWindow() }
    let store = self.store
    let agents = launchAgents
    mutate(
      "프로젝트 설정을 불러오는 중…",
      work: {
        let timeline = self.startupTimeline
        timeline?.record("load-begin")
        do {
          let loaded = (try store.load(), self.isolated ? false : agents.loginEnabled())
          timeline?.record("load-end", ["profileCount": loaded.0.profiles.count])
          return loaded
        } catch { timeline?.record("load-error"); throw error }
      },
      success: { [weak self] loaded in
        guard let self else { return }
        self.settings = loaded.0
        self.loginEnabled = loaded.1
        self.populate()
      })
    readingEnvironment.start()
  }
  func applicationWillTerminate(_ notification: Notification) {
    readingIntent += 1
    cancelPendingCrossProjectTransition()
    nativeSessionOriginProfileID = nil
    readingEnvironment.dispose()
    session.dispose()
    activeNativeReadCancel = nil
    nativeWindow?.dispose(); offlineWindow?.dispose()
  }
  func networkChanged(_ available: Bool) { session.networkChanged(available: available) }
  func powerChanged(_ constrained: Bool) { session.setConstrainedPower(constrained) }
  func sleepChanged(_ sleeping: Bool) {
    if sleeping { readingIntent += 1 }
    session.setSleeping(sleeping)
  }
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
    showWindow()
    return true
  }
  func buildMenu() {
    let menu = makeStatusMenu()
    statusItem?.menu = menu
    let main = NSMenu()
    let app = NSMenuItem()
    app.submenu = menu.copy() as? NSMenu
    main.addItem(app)
    let editItem = NSMenuItem()
    let edit = NSMenu(title: "Edit")
    for (title, action, key) in [
      ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"),
      ("Select All", "selectAll:", "a"),
    ] {
      edit.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
    }
    edit.addItem(NSMenuItem.separator())
    let findItem = NSMenuItem(title: "Find", action: nil, keyEquivalent: "")
    let findMenu = NSMenu(title: "Find")
    for (title, key, modifiers, action) in [
      ("Find…", "f", NSEvent.ModifierFlags.command, NSTextFinder.Action.showFindInterface),
      ("Find Next", "g", NSEvent.ModifierFlags.command, NSTextFinder.Action.nextMatch),
      ("Find Previous", "g", NSEvent.ModifierFlags([.command, .shift]), NSTextFinder.Action.previousMatch),
    ] {
      let item = NSMenuItem(
        title: title,
        action: #selector(NSResponder.performTextFinderAction(_:)),
        keyEquivalent: key)
      item.keyEquivalentModifierMask = modifiers
      item.tag = action.rawValue
      item.target = nil
      findMenu.addItem(item)
    }
    findItem.submenu = findMenu
    edit.addItem(findItem)
    editItem.submenu = edit
    main.addItem(editItem)
    let windowItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
    let windowMenu = NSMenu(title: "Window")
    windowMenu.addItem(withTitle: "창 닫기", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
    windowItem.submenu = windowMenu
    main.addItem(windowItem)
    NSApp.windowsMenu = windowMenu
    NSApp.mainMenu = main
  }
  func button(_ title: String, _ selector: Selector) -> NSButton {
    let result = NativeDesignButton(title: title, target: self, action: selector)
    if selector == #selector(openPreview) || selector == #selector(save) { result.designRole = .primary }
    controls[selector] = result
    return result
  }
  private func iconButton(symbol: String, label: String, identifier: String, selector: Selector,
                          size: CGFloat = 32) -> NativeDesignButton {
    let result = NativeDesignButton(title: "", target: self, action: selector)
    configureIcon(result, symbol: symbol, label: label, identifier: identifier, selector: selector, size: size)
    controls[selector] = result
    return result
  }
  private func configureIcon(_ button: NativeDesignButton, symbol: String, label: String,
                             identifier: String, selector: Selector, size: CGFloat = 32) {
    button.title = ""
    button.target = self; button.action = selector
    button.designRole = .ghost
    button.setSymbol(symbol, label: label)
    button.imagePosition = .imageOnly
    button.imageScaling = .scaleProportionallyDown
    button.identifier = NSUserInterfaceItemIdentifier(identifier)
    button.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([button.widthAnchor.constraint(equalToConstant: size),
                                 button.heightAnchor.constraint(equalToConstant: size)])
  }
  func buildWindow() {
    window = NativeReaderEditingWindow(
      contentRect: NSRect(x: 0, y: 0, width: 452, height: 228),
      styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
    NativeChrome.install(on: window)
    window.title = LagrangianIdentity.appName
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    // contentRect includes a title-bar conversion; Home's compact size is the
    // outer window frame, including before the first session snapshot arrives.
    window.setFrame(NSRect(origin: window.frame.origin, size: NSSize(width: 452, height: 228)), display: false)
    (window as? NativeReaderEditingWindow)?.fixtureMode = fixtureMode
    window.isReleasedWhenClosed = false
    window.center()

    let content = window.contentView!
    let header = NSView()
    header.translatesAutoresizingMaskIntoConstraints = false
    content.addSubview(header)
    brandMark.identifier = NSUserInterfaceItemIdentifier("home.brandMark")
    brandMark.translatesAutoresizingMaskIntoConstraints = false
    header.addSubview(brandMark)
    let add = iconButton(symbol: "plus", label: "프로젝트 추가", identifier: "home.addProject", selector: #selector(addProject), size: 28)
    let gear = iconButton(symbol: "gearshape", label: "프로젝트 설정 (⌘,)", identifier: "home.openSettings", selector: #selector(showSettings), size: 28)
    let actions = NSStackView(views: [add, gear])
    actions.spacing = 4; actions.translatesAutoresizingMaskIntoConstraints = false
    header.addSubview(actions)

    let card = NativeDesignSurface()
    card.identifier = NSUserInterfaceItemIdentifier("home.noteCard")
    card.translatesAutoresizingMaskIntoConstraints = false
    content.addSubview(card)
    picker.target = self; picker.action = #selector(selectProfile)
    picker.identifier = NSUserInterfaceItemIdentifier("home.projectPicker")
    picker.setAccessibilityLabel("프로젝트 선택")
    (picker.cell as? NSPopUpButtonCell)?.lineBreakMode = .byTruncatingTail
    picker.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    let read = button("읽기", #selector(openPreview)) as! NativeDesignButton
    read.identifier = NSUserInterfaceItemIdentifier("home.read")
    read.setSymbol("book", label: "읽기")
    read.imagePosition = .imageLeading
    read.keyEquivalent = "\r"
    read.widthAnchor.constraint(equalToConstant: 104).isActive = true
    let firstRow = NSStackView(views: [picker, read])
    firstRow.alignment = .centerY; firstRow.spacing = 12
    firstRow.translatesAutoresizingMaskIntoConstraints = false
    card.addSubview(firstRow)

    let divider = NSBox()
    divider.boxType = .separator
    divider.identifier = NSUserInterfaceItemIdentifier("home.divider")
    divider.translatesAutoresizingMaskIntoConstraints = false
    card.addSubview(divider)
    configureIcon(serviceToggleButton, symbol: "play.fill", label: "미리보기 시작", identifier: "home.serviceToggle", selector: #selector(start))
    let external = iconButton(symbol: "globe", label: "웹 브라우저에서 열기", identifier: "home.external", selector: #selector(openExternalPreview))
    let copy = iconButton(symbol: "link", label: "미리보기 주소 복사", identifier: "home.copyAddress", selector: #selector(copyPreviewAddress))
    let offline = iconButton(symbol: "doc.text", label: "오프라인 문서 열기", identifier: "home.offline", selector: #selector(openOffline))
    let dock = NSStackView(views: [serviceToggleButton, external, copy, offline])
    dock.spacing = 8; dock.translatesAutoresizingMaskIntoConstraints = false
    dock.identifier = NSUserInterfaceItemIdentifier("home.iconDock")
    card.addSubview(dock)
    configureIcon(overflowButton, symbol: "ellipsis", label: "더 보기", identifier: "home.overflow", selector: #selector(showOverflowMenu(_:)))
    card.addSubview(overflowButton)

    activity.style = .spinning; activity.controlSize = .small
    activity.translatesAutoresizingMaskIntoConstraints = false
    activity.widthAnchor.constraint(equalToConstant: 16).isActive = true
    activity.heightAnchor.constraint(equalToConstant: 16).isActive = true
    feedbackIcon.image = NSImage(systemSymbolName: "exclamationmark.circle.fill", accessibilityDescription: "오류")
    feedbackIcon.translatesAutoresizingMaskIntoConstraints = false
    feedbackIcon.widthAnchor.constraint(equalToConstant: 16).isActive = true
    feedbackIcon.heightAnchor.constraint(equalToConstant: 16).isActive = true
    status.identifier = NSUserInterfaceItemIdentifier("home.status")
    status.font = NativeAppDesign.Typography.font(.caption)
    status.maximumNumberOfLines = 1; status.usesSingleLineMode = true
    status.lineBreakMode = .byTruncatingTail
    status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    let logs = iconButton(symbol: "doc.plaintext", label: "로그 보기", identifier: "home.errorLogs", selector: #selector(openLogs))
    [activity, feedbackIcon, status, logs].forEach { feedbackStack.addArrangedSubview($0) }
    feedbackStack.orientation = .horizontal; feedbackStack.alignment = .centerY; feedbackStack.spacing = 8
    feedbackStack.identifier = NSUserInterfaceItemIdentifier("home.banner")
    feedbackStack.isHidden = true
    feedbackStack.translatesAutoresizingMaskIntoConstraints = false
    content.addSubview(feedbackStack)
    let bannerHeight = feedbackStack.heightAnchor.constraint(equalToConstant: 0)
    feedbackHeight = bannerHeight
    NSLayoutConstraint.activate([
      header.topAnchor.constraint(equalTo: content.topAnchor, constant: 42),
      header.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
      header.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
      header.heightAnchor.constraint(equalToConstant: 44),
      brandMark.centerXAnchor.constraint(equalTo: header.centerXAnchor),
      brandMark.centerYAnchor.constraint(equalTo: header.centerYAnchor),
      brandMark.widthAnchor.constraint(equalToConstant: 44), brandMark.heightAnchor.constraint(equalToConstant: 41),
      actions.trailingAnchor.constraint(equalTo: header.trailingAnchor), actions.centerYAnchor.constraint(equalTo: header.centerYAnchor),
      card.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 16),
      card.leadingAnchor.constraint(equalTo: header.leadingAnchor), card.trailingAnchor.constraint(equalTo: header.trailingAnchor),
      card.heightAnchor.constraint(equalToConstant: 108),
      firstRow.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
      firstRow.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
      firstRow.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16), firstRow.heightAnchor.constraint(equalToConstant: 36),
      divider.topAnchor.constraint(equalTo: firstRow.bottomAnchor, constant: 7),
      divider.leadingAnchor.constraint(equalTo: firstRow.leadingAnchor), divider.trailingAnchor.constraint(equalTo: firstRow.trailingAnchor),
      divider.heightAnchor.constraint(equalToConstant: 1),
      dock.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 8), dock.leadingAnchor.constraint(equalTo: firstRow.leadingAnchor),
      overflowButton.trailingAnchor.constraint(equalTo: firstRow.trailingAnchor), overflowButton.centerYAnchor.constraint(equalTo: dock.centerYAnchor),
      feedbackStack.topAnchor.constraint(equalTo: card.bottomAnchor, constant: 12),
      feedbackStack.leadingAnchor.constraint(equalTo: card.leadingAnchor), feedbackStack.trailingAnchor.constraint(equalTo: card.trailingAnchor), bannerHeight,
    ])
    buildSettingsWindow()
    NativeChrome.apply(to: content)
    appearanceObservation?.invalidate()
    appearanceObservation = window.observe(\.effectiveAppearance, options: []) { [weak self] _, _ in
      if Thread.isMainThread { self?.refreshAppearanceColors() }
      else { DispatchQueue.main.async { self?.refreshAppearanceColors() } }
    }
    if accessibilityObservation == nil {
      accessibilityObservation = NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
      ) { [weak self] _ in self?.refreshAppearanceColors() }
    }
    refreshAppearanceColors()
    updateControls()
  }
  private func buildSettingsWindow() {
    let sheet = NativeReaderEditingWindow(
      contentRect: NSRect(x: 0, y: 0, width: 580, height: 480),
      styleMask: [.titled, .closable], backing: .buffered, defer: false)
    sheet.minSize = NSSize(width: 500, height: 440)
    NativeChrome.install(on: sheet)
    sheet.title = "프로젝트 설정"
    sheet.identifier = NSUserInterfaceItemIdentifier("settings.window")
    sheet.fixtureMode = fixtureMode
    sheet.isReleasedWhenClosed = false
    settingsWindow = sheet

    let container = NSStackView()
    container.orientation = .vertical
    container.alignment = .leading
    container.spacing = 14
    container.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 20, right: 24)
    container.translatesAutoresizingMaskIntoConstraints = false
    sheet.contentView!.addSubview(container)
    NSLayoutConstraint.activate([
      container.leadingAnchor.constraint(equalTo: sheet.contentView!.leadingAnchor),
      container.trailingAnchor.constraint(equalTo: sheet.contentView!.trailingAnchor),
      container.topAnchor.constraint(equalTo: sheet.contentView!.topAnchor),
      container.bottomAnchor.constraint(lessThanOrEqualTo: sheet.contentView!.bottomAnchor),
    ])

    let heading = NSTextField(labelWithString: "프로젝트 설정")
    heading.font = NativeAppDesign.Typography.font(.heading)
    settingsProjectLabel.font = NativeAppDesign.Typography.font(.caption)
    settingsProjectLabel.lineBreakMode = .byTruncatingMiddle
    settingsProjectLabel.maximumNumberOfLines = 1
    settingsProjectLabel.usesSingleLineMode = true
    settingsProjectLabel.cell?.truncatesLastVisibleLine = true
    settingsProjectLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    settingsEntryLabel.font = NativeAppDesign.Typography.font(.caption)
    settingsEntryLabel.lineBreakMode = .byTruncatingHead
    settingsEntryLabel.maximumNumberOfLines = 1
    settingsEntryLabel.usesSingleLineMode = true
    settingsEntryLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    settingsProjectLabel.identifier = NSUserInterfaceItemIdentifier("settings.projectName")
    settingsEntryLabel.identifier = NSUserInterfaceItemIdentifier("settings.entryPath")
    let headerStack = NSStackView(views: [heading, settingsProjectLabel, settingsEntryLabel])
    headerStack.orientation = .vertical
    headerStack.alignment = .leading
    headerStack.spacing = 4
    container.addArrangedSubview(headerStack)
    headerStack.widthAnchor.constraint(equalTo: container.widthAnchor, constant: -48).isActive = true
    settingsProjectLabel.widthAnchor.constraint(equalTo: headerStack.widthAnchor).isActive = true
    settingsEntryLabel.widthAnchor.constraint(equalTo: headerStack.widthAnchor).isActive = true

    let definitions = [
      ("name", "프로젝트 이름"), ("root", "프로젝트 폴더"), ("entry", "진입 파일"), ("fonts", "글꼴 폴더 ( ; 구분)"),
      ("packages", "로컬 패키지 폴더"), ("port", "로컬 포트"), ("publicURL", "HTTPS 주소 (선택)"),
    ]
    let browseButton = button("찾아보기…", #selector(browseRoot))
    browseButton.identifier = NSUserInterfaceItemIdentifier("settings.browseRoot")
    browseButton.setAccessibilityLabel("프로젝트 폴더 찾아보기")
    browseButton.setContentHuggingPriority(.required, for: .horizontal)
    browseButton.setContentCompressionResistancePriority(.required, for: .horizontal)

    let grid = NSGridView(
      views: definitions.map { key, label in
        let field = NSTextField()
        field.setAccessibilityLabel(label)
        field.identifier = NSUserInterfaceItemIdentifier("settings.field.\(key)")
        field.font = NativeAppDesign.Typography.font(.control)
        field.maximumNumberOfLines = 1
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        if key == "root" || key == "packages" {
          field.lineBreakMode = .byTruncatingMiddle
        }
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        fields[key] = field
        let titleLabel = NSTextField(labelWithString: label)
        titleLabel.font = NativeAppDesign.Typography.font(.control)
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        if key == "root" {
          let row = NSStackView(views: [field, browseButton])
          row.orientation = .horizontal
          row.alignment = .centerY
          row.spacing = NativeAppDesign.Spacing.small
          field.widthAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true
          return [titleLabel, row]
        }
        field.widthAnchor.constraint(greaterThanOrEqualToConstant: 330).isActive = true
        return [titleLabel, field]
      })
    grid.rowSpacing = 10
    grid.columnSpacing = 12
    grid.xPlacement = .leading
    for row in 0..<grid.numberOfRows {
      grid.cell(atColumnIndex: 1, rowIndex: row).xPlacement = .fill
    }
    container.addArrangedSubview(grid)
    grid.widthAnchor.constraint(equalTo: container.widthAnchor, constant: -48).isActive = true

    settingsHintLabel.font = NativeAppDesign.Typography.font(.caption)
    settingsHintLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    container.addArrangedSubview(settingsHintLabel)
    settingsHintLabel.widthAnchor.constraint(equalTo: container.widthAnchor, constant: -48).isActive = true

    settingsStatus.font = NativeAppDesign.Typography.font(.caption)
    settingsStatus.maximumNumberOfLines = 3
    settingsStatus.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    settingsStatus.identifier = NSUserInterfaceItemIdentifier("settings.status")
    settingsStatus.setAccessibilityLabel("설정 저장 상태")
    settingsStatus.isHidden = true
    container.addArrangedSubview(settingsStatus)
    settingsStatus.widthAnchor.constraint(equalTo: container.widthAnchor, constant: -48).isActive = true

    let revealButton = button("설정 파일 보기", #selector(revealSettings))
    revealButton.identifier = NSUserInterfaceItemIdentifier("settings.revealFile")
    revealButton.setAccessibilityLabel("설정 파일 보기")
    let actionSpacer = NSView()
    actionSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    actionSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    let closeButton = button("닫기", #selector(closeSettings))
    closeButton.keyEquivalent = "\u{1b}"
    closeButton.identifier = NSUserInterfaceItemIdentifier("settings.close")
    closeButton.setAccessibilityLabel("닫기")
    let saveButton = button("설정 저장", #selector(save))
    saveButton.keyEquivalent = "\r"
    saveButton.identifier = NSUserInterfaceItemIdentifier("settings.save")
    saveButton.setAccessibilityLabel("설정 저장")

    let buttonsRow = NSStackView(views: [revealButton, actionSpacer, closeButton, saveButton])
    buttonsRow.orientation = .horizontal
    buttonsRow.alignment = .centerY
    buttonsRow.spacing = NativeAppDesign.Spacing.small
    container.addArrangedSubview(buttonsRow)
    buttonsRow.widthAnchor.constraint(equalTo: container.widthAnchor, constant: -48).isActive = true

    NativeChrome.apply(to: sheet.contentView!)
    refreshSettingsHeader()
  }
  private func refreshSettingsHeader() {
    settingsProjectLabel.stringValue = active?.name ?? "프로젝트를 추가해 시작하세요"
    settingsProjectLabel.toolTip = active?.name
    settingsEntryLabel.stringValue = active.map { $0.path($0.entry) } ?? ""
    settingsEntryLabel.toolTip = settingsEntryLabel.stringValue
  }
  func populate() {
    picker.removeAllItems()
    // NSPopUpButton.addItems collapses identical titles. Profile names are not
    // unique IDs; preserve every validated profile and its selection index.
    for profile in settings.profiles {
      picker.menu?.addItem(NSMenuItem(title: profile.name, action: nil, keyEquivalent: ""))
    }
    if let index = settings.profiles.firstIndex(where: { $0.id == settings.selectedID }) {
      picker.selectItem(at: index)
    } else if let first = settings.profiles.first {
      settings.selectedID = first.id
      picker.selectItem(at: 0)
    }
    session.select(active)
    picker.toolTip = active.map { "\($0.name)\n\($0.path($0.entry))" } ?? "프로젝트 추가 버튼으로 시작하세요"
    if active == nil { picker.addItem(withTitle: "프로젝트를 추가하세요") }
    copyConfirmation?.cancel(); copyConfirmation = nil
    (controls[#selector(copyPreviewAddress)] as? NativeDesignButton)?.setSymbol("link", label: "미리보기 주소 복사")
    syncFieldsFromActive()
    updateControls()
  }
  private var isServiceRunning: Bool {
    guard active != nil, let snapshot else { return false }
    return snapshot.pid != nil || snapshot.phase == .running || snapshot.phase == .ready
  }
  var homeBrandPhase: NativeBrandMark.Phase {
    guard let snapshot else { return .idle }
    if snapshot.phase == .failed { return .error }
    if snapshot.phase == .sleeping { return .held }
    if snapshot.phase == .running { return .reconnecting }
    if snapshot.isBusy { return .busy }
    if active == nil { return .idle }
    return isServiceRunning || snapshot.phase == .painted ? .completed : .offline
  }
  private func renderHomeState() {
    let phase = homeBrandPhase
    brandMark.phase = phase
    brandMark.showsRunningIndicator = isServiceRunning
    let hint: String
    switch phase {
    case .error: hint = "오류"
    case .busy, .reconnecting: hint = "준비 중"
    default: hint = active == nil ? "프로젝트 없음" : (isServiceRunning ? "미리보기 실행 중" : "미리보기 중지됨")
    }
    brandMark.toolTip = "Lagrangian · " + hint
    brandMark.setAccessibilityLabel(brandMark.toolTip)
    statusItem?.button?.title = ""
    statusItem?.button?.image = NativeBrandMark.statusImage(phase: phase == .completed && !isServiceRunning ? .offline : phase)
    statusItem?.button?.toolTip = brandMark.toolTip
    statusItem?.button?.setAccessibilityLabel(brandMark.toolTip)
    serviceToggleButton.action = isServiceRunning ? #selector(stop) : #selector(start)
    let serviceHint = isServiceRunning ? "미리보기 중지" : "미리보기 시작"
    let preparing = phase == .busy || phase == .reconnecting
    let serviceSymbol = phase == .error ? "exclamationmark.triangle.fill" :
      (preparing ? "arrow.triangle.2.circlepath" : (isServiceRunning ? "stop.fill" : "play.fill"))
    serviceToggleButton.setSymbol(serviceSymbol, label: preparing ? "미리보기 준비 중" : serviceHint)
    serviceToggleButton.showsRunningIndicator = isServiceRunning
  }
  func render(_ snapshot: ReadingSessionSnapshot) {
    let previousMessage = status.stringValue
    self.snapshot = snapshot
    // Only controlled Korean copy reaches Home. Diagnostic details remain in the session/logs.
    status.stringValue = snapshot.phase == .failed ? "작업을 완료하지 못했습니다. 로그를 확인해 주세요." :
      (snapshot.isBusy ? (snapshot.message == "프로젝트 설정을 불러오는 중…" ? "프로젝트 설정을 불러오는 중…" :
        (mutating ? "프로젝트 설정을 적용하는 중…" : "문서를 준비하는 중…")) : "")
    let showFeedback = snapshot.isBusy || snapshot.phase == .failed
    feedbackStack.isHidden = !showFeedback
    feedbackHeight?.constant = showFeedback ? 32 : 0
    feedbackIcon.isHidden = snapshot.phase != .failed
    activity.isHidden = !snapshot.isBusy
    controls[#selector(openLogs)]?.isHidden = snapshot.phase != .failed
    if snapshot.isBusy { activity.startAnimation(nil) } else { activity.stopAnimation(nil) }
    if let window {
      let height: CGFloat = showFeedback ? 272 : 228
      if window.frame.height != height {
        var frame = window.frame
        frame.origin.y += frame.height - height; frame.size = NSSize(width: 452, height: height)
        window.setFrame(frame, display: false)
      }
    }
    let retry = snapshot.phase == .failed
    let read = controls[#selector(openPreview)] as? NativeDesignButton
    read?.title = retry ? "다시 읽기" : "읽기"
    read?.setSymbol(retry ? "arrow.clockwise" : "book", label: retry ? "다시 읽기" : "읽기")
    updateControls()
    if previousMessage != status.stringValue { NSAccessibility.post(element: status, notification: .valueChanged) }
  }
  func enabled(_ action: Selector?) -> Bool {
    guard let action else { return true }
    if fixtureMode && [#selector(connectEditor), #selector(disconnectEditor), #selector(addProject),
        #selector(openLogs), #selector(revealSettings), #selector(browseRoot), #selector(guide), #selector(about)].contains(action) { return false }
    if isolated && action == #selector(toggleLogin) { return false }
    if isolated && !devIsolatedServicePreview && [#selector(start), #selector(stop),
                    #selector(restart), #selector(openExternalPreview)].contains(action) { return false }
    if [#selector(addProject), #selector(toggleLogin)].contains(action) {
      return !mutating && snapshot?.isBusy != true
    }
    if [#selector(openExternalPreview), #selector(copyPreviewAddress)].contains(action) {
      return isServiceRunning && !mutating && snapshot?.isBusy != true
    }
    if [#selector(openPreview), #selector(start), #selector(restart), #selector(save)].contains(
      action)
    {
      return active != nil && !mutating && snapshot?.isBusy != true
    }
    if action == #selector(browseRoot) { return active != nil && !mutating }
    if action == #selector(stop) { return active != nil && !mutating }
    if action == #selector(closeSettings) { return !mutating }
    if [#selector(openOffline), #selector(showSettings), #selector(connectEditor), #selector(disconnectEditor)].contains(action) { return active != nil }
    if action == #selector(revealSettings) { return !mutating }
    return true
  }
  func refreshStatusColor() {
    let appearance = window?.effectiveAppearance ?? status.effectiveAppearance
    let palette = NativeAppDesign.palette(.current(appearance: appearance))
    status.textColor = snapshot?.phase == .failed ? palette.error : palette.secondaryInk
    feedbackIcon.contentTintColor = palette.error
    settingsProjectLabel.textColor = palette.ink
    settingsEntryLabel.textColor = palette.secondaryInk
    settingsHintLabel.textColor = palette.secondaryInk
    settingsStatus.textColor = settingsStatus.isHidden ? palette.secondaryInk : palette.error
  }
  func refreshAppearanceColors() {
    refreshStatusColor()
    brandMark.needsDisplay = true
    serviceToggleButton.needsDisplay = true
  }
  func updateControls() {
    renderHomeState()
    picker.isEnabled = active != nil && !mutating
    for field in fields.values { field.isEnabled = active != nil && !mutating }
    for (action, control) in controls { control.isEnabled = enabled(action) }
    serviceToggleButton.isEnabled = enabled(serviceToggleButton.action) && snapshot?.isBusy != true && homeBrandPhase != .reconnecting
    overflowButton.isEnabled = !mutating
    refreshStatusColor()
    refreshMenu()
  }
  private var editorMenuAction: Selector {
    guard let profile = active else { return #selector(connectEditor) }
    let readerConsent = readerEditorConsent.map { $0.window === nativeWindow && $0.profileID == profile.id && $0.editor.consentID != nil } == true
    return consentedEditors[profile.id]?.consentID != nil || readerConsent ? #selector(disconnectEditor) : #selector(connectEditor)
  }
  private func addMenuItem(_ menu: NSMenu, _ title: String, _ action: Selector, key: String = "") {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
    item.target = self
    if action == #selector(toggleLogin) { item.state = loginEnabled ? .on : .off }
    menu.addItem(item)
  }
  func overflowMenu() -> NSMenu {
    let menu = NSMenu(title: "더 보기")
    addMenuItem(menu, "미리보기 재시작", #selector(restart))
    addMenuItem(menu, "미리보기 주소 복사", #selector(copyPreviewAddress))
    addMenuItem(menu, "로그 보기", #selector(openLogs))
    menu.addItem(.separator())
    addMenuItem(menu, editorMenuAction == #selector(connectEditor) ? "에디터 연결…" : "에디터 연결 해제", editorMenuAction)
    menu.addItem(.separator())
    addMenuItem(menu, "설정 파일 보기", #selector(revealSettings))
    addMenuItem(menu, "사용·업데이트·복구 안내", #selector(guide))
    return menu
  }
  private func makeStatusMenu() -> NSMenu {
    let menu = NSMenu(title: LagrangianIdentity.appName)
    let summary = active.map { "\($0.name) · " + (isServiceRunning ? "실행 중" : "중지됨") } ?? "프로젝트 없음"
    let statusLine = NSMenuItem(title: summary, action: nil, keyEquivalent: "")
    statusLine.isEnabled = false
    menu.addItem(statusLine); menu.addItem(.separator())
    addMenuItem(menu, "홈 열기", #selector(showWindow), key: "0")
    addMenuItem(menu, "읽기 시작", #selector(openPreview), key: "o")
    addMenuItem(menu, "웹 브라우저에서 열기", #selector(openExternalPreview))
    addMenuItem(menu, "오프라인 문서 열기", #selector(openOffline))
    menu.addItem(.separator())
    addMenuItem(menu, isServiceRunning ? "미리보기 중지" : "미리보기 시작", isServiceRunning ? #selector(stop) : #selector(start))
    addMenuItem(menu, "미리보기 재시작", #selector(restart))
    addMenuItem(menu, editorMenuAction == #selector(connectEditor) ? "에디터 연결…" : "에디터 연결 해제", editorMenuAction)
    addMenuItem(menu, "미리보기 주소 복사", #selector(copyPreviewAddress))
    addMenuItem(menu, "로그 보기", #selector(openLogs))
    menu.addItem(.separator())
    addMenuItem(menu, "프로젝트 설정…", #selector(showSettings), key: ",")
    addMenuItem(menu, "로그인 시 자동 실행", #selector(toggleLogin))
    addMenuItem(menu, "사용·업데이트·복구 안내", #selector(guide))
    addMenuItem(menu, "Lagrangian 정보", #selector(about))
    menu.addItem(.separator())
    addMenuItem(menu, "Lagrangian 종료 (미리보기 유지)", #selector(quit), key: "q")
    return menu
  }
  private func refreshMenu() {
    statusItem?.menu = makeStatusMenu()
    NSApp.mainMenu?.items.first?.submenu = makeStatusMenu()
  }
  @objc func showOverflowMenu(_ sender: NSButton) {
    let y: CGFloat = sender.isFlipped ? sender.bounds.height + 4 : -4
    overflowMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: y), in: sender)
  }
  @objc func browseRoot() {
    guard !fixtureMode, !mutating, active != nil else { return }
    let panel = NSOpenPanel()
    panel.title = "프로젝트 폴더 선택"
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let url = panel.url else { return }
    fields["root"]?.stringValue = url.path
  }
  func validateMenuItem(_ menuItem: NSMenuItem) -> Bool { enabled(menuItem.action) }
  func mutate<T>(
    _ message: String, reportFailureToSession: Bool = true, onFailure: ((Error) -> Void)? = nil,
    work: @escaping () throws -> T, success: @escaping (T) -> Void
  ) {
    guard !mutating else { return }
    mutating = true
    updateControls()
    let timeline = startupTimeline
    let finish: (Result<T, Error>) -> Void = { [weak self] result in
      timeline?.record("completion-owner", ["weakOwnerPresent": self != nil])
      guard let self else { return }
      self.mutating = false
      switch result {
      case .success(let value): success(value)
      case .failure(let error):
        if let index = self.settings.profiles.firstIndex(where: {
          $0.id == self.settings.selectedID
        }) {
          self.picker.selectItem(at: index)
        }
        self.session.select(self.active)
        if reportFailureToSession {
          self.session.reportFailure(error)
        } else {
          onFailure?(error)
        }
      }
      self.updateControls()
      let selectedHash = SHA256.hash(data: Data(self.settings.selectedID.utf8)).map { String(format: "%02x", $0) }.joined()
      timeline?.record("settings-adopted", ["profileCount": self.settings.profiles.count,
        "selectedIDHash": selectedHash, "readEnabled": self.controls[#selector(FlowApp.openPreview)]?.isEnabled ?? false])
    }
    if reportFailureToSession {
      session.performMutation(message: message, work: work, completion: finish)
    } else {
      session.performMutation(
        message: message,
        work: { () -> Result<T, Error> in
          do { return .success(try work()) } catch { return .failure(error) }
        },
        completion: { outer in
          switch outer {
          case .success(let inner): finish(inner)
          case .failure(let error): finish(.failure(error))
          }
        })
    }
  }
  @objc func showWindow() {
    guard NSApp.activationPolicy() != .prohibited else { return }
    if noActivate { window?.orderFrontRegardless() }
    else { window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
  }
  @MainActor @objc func selectProfile() {
    guard !mutating, picker.indexOfSelectedItem >= 0 else { return }
    let id = settings.profiles[picker.indexOfSelectedItem].id
    readingIntent += 1
    cancelPendingCrossProjectTransition()
    crossProjectNavigationStack = CrossProjectNavigationStack()
    nativeSessionOriginProfileID = nil
    let previous = settings
    let service = projectService
    // Invalidate a pending browser opening as soon as another project is selected.
    session.select(nil)
    mutate(
      "프로젝트를 전환하는 중…",
      work: {
        try service.selectProfile(id, in: previous)
      },
      success: { [weak self] next in
        self?.settings = next
        self?.populate()
      })
  }
  @MainActor @objc func addProject() {
    guard !fixtureMode, !mutating else { return }
    let panel = NSOpenPanel()
    panel.title = "프로젝트 폴더 또는 Typst 파일 선택"
    panel.canChooseDirectories = true
    panel.canChooseFiles = true
    panel.allowedContentTypes = [UTType(filenameExtension: "typ")!]
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let url = panel.url else { return }
    registerProjectSelection(at: url)
  }
  @MainActor func registerProjectSelection(at url: URL, chooseEntry: ((URL, [String]) -> String?)? = nil) {
    guard !fixtureMode, !mutating else { return }
    let previous = settings
    let service = projectService
    let home = environment.userHome
    var isDirectory: ObjCBool = false
    let directory = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    var selectedEntry: String?
    var detectedKey: String?
    if directory {
      let candidates: [String]
      do { candidates = try service.discoverProjectEntryCandidates(in: url) }
      catch { session.reportFailure(error); return }
      if candidates.first == "main.typ" || candidates.count == 1 {
        selectedEntry = candidates[0]
      } else {
        guard let selection = (chooseEntry ?? self.chooseProjectEntry)(url, candidates) else { return }
        selectedEntry = selection
      }
      if let catalog = crossProjectCatalog(for: active) {
        var probe = Profile(
          id: "probe", name: url.lastPathComponent, root: url.path, entry: "entry.typ",
          fonts: [], packages: "", port: 23625, publicURL: "", label: "project.probe")
        let matches = catalog.projects.keys.filter { catalog.matchProfile(for: $0, in: [probe]) != nil }
        if matches.count == 1 {
          probe.projectRefKey = matches[0]
          if (try? probe.validate()) != nil { detectedKey = matches[0] }
        }
      }
    }
    let entry = selectedEntry
    let key = detectedKey
    mutate(
      "프로젝트를 추가하는 중…",
      work: {
        if directory {
          return try service.addProjectDirectory(at: url, entry: entry, projectRefKey: key, in: previous, userHome: home)
        }
        return try service.addProject(at: url, in: previous, userHome: home)
      },
      success: { [weak self] next in
        self?.settings = next
        self?.populate()
      })
  }
  private func chooseProjectEntry(in directory: URL, candidates: [String]) -> String? {
    let alert = NSAlert()
    alert.messageText = "진입 파일 선택"
    alert.informativeText = directory.lastPathComponent
    let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 320, height: 26))
    picker.addItems(withTitles: candidates)
    alert.accessoryView = picker
    alert.addButton(withTitle: "추가")
    alert.addButton(withTitle: "취소")
    return alert.runModal() == .alertFirstButtonReturn ? picker.titleOfSelectedItem : nil
  }
  func editedProfile() throws -> Profile {
    guard var updated = active else { throw FlowError(message: "프로젝트를 추가해 시작하세요.") }
    func value(_ key: String) -> String {
      fields[key]!.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    guard let port = Int(value("port")) else { throw FlowError(message: "포트를 숫자로 입력하세요.") }
    updated.name = value("name")
    updated.root = fields["root"]!.stringValue
    updated.entry = value("entry")
    updated.fonts = value("fonts").split(separator: ";").map {
      $0.trimmingCharacters(in: .whitespaces)
    }.filter { !$0.isEmpty }
    updated.packages = value("packages")
    updated.port = port
    updated.publicURL = value("publicURL")
    return updated
  }
  private func showSettingsError(_ error: Error) {
    settingsStatus.stringValue = error.localizedDescription
    settingsStatus.isHidden = false
    refreshStatusColor()
  }
  func saveProfile(readAfterSaving: Bool, external: Bool = false) {
    guard !(fixtureMode && external), !mutating else { return }
    let intent = readingIntent
    do {
      let updated = try editedProfile()
      if updated == active {
        if readAfterSaving { external ? session.readExternally() : session.read() }
        else {
          clearSettingsStatus()
          settingsSaved = true
          closeSettings()
        }
        return
      }
      let previous = settings
      let service = projectService
      mutate(
        "설정을 확인하고 저장하는 중…",
        reportFailureToSession: readAfterSaving,
        onFailure: readAfterSaving ? nil : { [weak self] error in
          self?.showSettingsError(error)
        },
        work: {
          try service.updateProfile(updated, in: previous)
        },
        success: { [weak self] next in
          guard let self else { return }
          self.settings = next
          self.populate()
          if !readAfterSaving {
            self.clearSettingsStatus()
            self.settingsSaved = true
            self.closeSettings()
          }
          if readAfterSaving && self.readingIntent == intent {
            external ? self.session.readExternally() : self.session.read()
          }
        })
    } catch {
      if readAfterSaving {
        session.reportFailure(error)
      } else {
        showSettingsError(error)
      }
    }
  }
  @objc func save() { saveProfile(readAfterSaving: false) }
  func perform(_ action: String) {
    guard !mutating, (!isolated || devIsolatedServicePreview) else { return }
    readingIntent += 1
    session.control(action)
  }
  @objc func start() { perform("start") }
  @objc func stop() { perform("stop") }
  @objc func restart() { perform("restart") }
  @objc func openPreview() {
    guard enabled(#selector(openPreview)) else { return }
    readingIntent += 1
    saveProfile(readAfterSaving: true)
  }
  @objc func openExternalPreview() {
    guard enabled(#selector(openExternalPreview)) else { return }
    readingIntent += 1
    saveProfile(readAfterSaving: true, external: true)
  }
  @objc func copyPreviewAddress() {
    guard enabled(#selector(copyPreviewAddress)), let p = active, copyText(p.url) else { return }
    copyConfirmation?.cancel()
    let control = controls[#selector(copyPreviewAddress)] as? NativeDesignButton
    control?.setSymbol("checkmark", label: "미리보기 주소 복사됨")
    let reset = DispatchWorkItem { [weak control] in control?.setSymbol("link", label: "미리보기 주소 복사") }
    copyConfirmation = reset
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: reset)
  }
  @objc func copyURL() {
    guard let profile = active else { return }
    _ = copyText(profile.url)
  }
  @objc func openLogs() {
    guard !fixtureMode else { return }
    let file = active.map { environment.logRoot.appendingPathComponent("\($0.id).err.log") } ?? environment.logRoot
    if FileManager.default.fileExists(atPath: file.path) {
      _ = openExternalURL(file)
    } else {
      _ = openExternalURL(environment.logRoot)
    }
  }
  @objc func revealSettings() {
    guard !fixtureMode else { return }
    revealExternalFiles([
      environment.support.appendingPathComponent("profiles.json")
    ])
  }
  @objc func toggleLogin() {
    guard !isolated else { return }
    guard enabled(#selector(toggleLogin)) else { return }
    let desired = !loginEnabled
    let agents = launchAgents
    mutate(
      "로그인 시 실행 설정을 저장하는 중…",
      work: {
        try agents.setLogin(desired)
        return agents.loginEnabled()
      },
      success: { [weak self] enabled in
        self?.loginEnabled = enabled
        self?.refreshMenu()
        self?.session.refresh()
      })
  }
  @objc func about() {
    guard !fixtureMode else { return }
    NSApp.orderFrontStandardAboutPanel(options: [
      .applicationName: LagrangianIdentity.appName,
      .credits: NSAttributedString(
        string:
          "Personal Typst workspace. Powered by Tinymist and Typst. Apache License 2.0.\nInstalled releases and recovery: see the bundled User Guide."
      ),
    ])
  }
  @objc func guide() {
    guard !fixtureMode else { return }
    if let url = Bundle.main.url(forResource: "UserGuide", withExtension: "pdf") {
      _ = openExternalURL(url)
    }
  }
  @objc func quit() { NSApp.terminate(nil) }
}

/// In-memory service simulator for isolated dogfood previews; never touches launchd.
final class SimulatedIsolatedProjectController: ProjectControlling {
  private let lock = NSLock()
  private var pids: [String: Int] = [:]

  func jobPID(_ label: String) -> Int? {
    lock.lock()
    defer { lock.unlock() }
    return pids[label]
  }

  func control(_ action: String, _ profile: Profile) throws {
    lock.lock()
    defer { lock.unlock() }
    switch action {
    case "start":
      if pids[profile.label] == nil {
        pids[profile.label] = 90001
      }
    case "stop":
      pids[profile.label] = nil
    case "restart":
      pids[profile.label] = (pids[profile.label] ?? 90000) + 1
    default:
      throw FlowError(message: "지원하지 않는 서비스 동작입니다: \(action)")
    }
  }
}
