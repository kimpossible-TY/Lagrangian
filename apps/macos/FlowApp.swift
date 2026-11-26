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
  var managedResolver: NativeReaderManagedResolver?
  var nativeWindow: NativeReaderWindowController?
  var crossProjectNavigationStack = CrossProjectNavigationStack()
  var nativeWindowControllerFactory: ((Profile) -> NativeReaderWindowController?)?
  var crossProjectDocumentLoader: ((Profile) async throws -> NativeReaderDocument)?
  private var pendingCrossProjectWindow: NativeReaderWindowController?
  private var pendingCrossProjectCancel: (() -> Void)?
  private var crossProjectNavigationSerial = 0
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
      guard let self, self.nativeProfile == self.active, let window = self.nativeWindow else { return false }
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

  @MainActor func makeNativeReaderWindowController(for profile: Profile) -> NativeReaderWindowController? {
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
      let client = NativeReaderManagedClient(resolver: resolver, root: profile.root, entry: profile.entry,
                                             editor: consentedEditors.removeValue(forKey: profile.id))
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
      guard let self, let entry = self.crossProjectNavigationStack.peek() else { return false }
      let matches = self.settings.profiles.filter { $0.id == entry.profileID }
      guard matches.count == 1 else { return false }
      return self.beginCrossProjectTransition(to: matches[0], targetLocation: entry, pushOnSuccess: nil, popOnSuccess: true)
    }
  }

  @MainActor @discardableResult func beginCrossProjectTransition(to targetProfile: Profile, targetLocation: CrossProjectNavigationEntry,
      pushOnSuccess: CrossProjectNavigationEntry?, popOnSuccess: Bool) -> Bool {
    cancelPendingCrossProjectTransition()
    guard let candidate = makeNativeReaderWindowController(for: targetProfile) else { return false }
    candidate.pendingCrossProjectTarget = targetLocation
    crossProjectNavigationSerial += 1
    let serial = crossProjectNavigationSerial
    pendingCrossProjectWindow = candidate
    var committed = false
    let cancel = candidate.open(targetProfile) { [weak self, weak candidate] progress in
      guard let self, let candidate, self.crossProjectNavigationSerial == serial,
            self.pendingCrossProjectWindow === candidate, !committed else { return }
      switch progress {
      case .windowInitialized:
        committed = true
        self.pendingCrossProjectWindow = nil; self.pendingCrossProjectCancel = nil
        if let entry = pushOnSuccess { self.crossProjectNavigationStack.push(entry) }
        if popOnSuccess { _ = self.crossProjectNavigationStack.pop() }
        self.nativeWindow?.dispose()
        self.nativeWindow = candidate; self.nativeProfile = targetProfile
        candidate.hostWindow.updateNavigation()
      case .failed:
        self.pendingCrossProjectWindow = nil; self.pendingCrossProjectCancel = nil
        candidate.dispose()
      default: break
      }
    }
    if pendingCrossProjectWindow === candidate { pendingCrossProjectCancel = cancel }
    return true
  }

  @MainActor func cancelPendingCrossProjectTransition() {
    crossProjectNavigationSerial += 1
    let cancel = pendingCrossProjectCancel
    let candidate = pendingCrossProjectWindow
    pendingCrossProjectCancel = nil; pendingCrossProjectWindow = nil
    cancel?(); candidate?.dispose()
  }

  @MainActor func readNative(_ profile: Profile, progress: @escaping (NativeReadProgress) -> Void) -> () -> Void {
    cancelPendingCrossProjectTransition()
    if let read = nativeReadOverride { return read(profile, progress) }
    if nativeProfile != profile || nativeWindow?.session.hasRecoveryCopy == true {
      nativeWindow?.dispose(); nativeWindow = nil; nativeProfile = profile
    }
    if nativeWindow == nil { nativeWindow = makeNativeReaderWindowController(for: profile) }
    guard let window = nativeWindow else {
      progress(.failed("네이티브 문서 서비스가 아직 연결되지 않았습니다. 명시적으로 구성된 Reader manager가 필요합니다."))
      return {}
    }
    return window.open(profile, progress: progress)
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
    nativeWindow?.dispose(); nativeWindow = nil
    if let resolver = managedResolver,
       !(await resolver.retryEditorCleanup(root: profile.root, entry: profile.entry)) {
      throw NativeReaderOperationFailure.unavailable
    }
    guard active == profile else { throw NativeReaderContractError.wrongTarget }
    consentedEditors[profile.id] = editor
    return true
  }
  @MainActor @objc func disconnectEditor() {
    guard !fixtureMode else { return }
    guard let profile = active else { return }
    consentedEditors.removeValue(forKey: profile.id)
    nativeWindow?.dispose(); nativeWindow = nil
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
  let pathCaption = NSTextField(labelWithString: "")
  let status = NSTextField(labelWithString: "프로젝트를 선택하세요")
  let detail = NSTextField(wrappingLabelWithString: "")
  let activity = NSProgressIndicator()
  private let feedbackStack = NSStackView()
  private let serviceStatusDot = ServiceStatusDotView()
  let serviceStatusLabel = NSTextField(labelWithString: "프리뷰 서비스 · 중지됨")
  let serviceAddressLabel = NSTextField(labelWithString: "")
  let serviceAddressLink = NativeLinkButton(title: "", target: nil, action: nil)
  let projectOverflowButton = NativeDesignButton(title: "•••", target: nil, action: nil)
  let serviceOverflowButton = NativeDesignButton(title: "•••", target: nil, action: nil)
  let settingsFooterButton = NativeLinkButton(title: "프로젝트 설정…", target: nil, action: nil)
  private let settingsProjectLabel = NSTextField(labelWithString: "")
  private let settingsHintLabel = NSTextField(wrappingLabelWithString: "글꼴 경로는 프로젝트 기준이며, HTTPS 주소는 선택 사항입니다.")
  let settingsStatus = NSTextField(wrappingLabelWithString: "")
  var controls: [Selector: NSButton] = [:]
  var fields: [String: NSTextField] = [:]
  let login: NSButton = NativeCheckboxButton(checkboxTitle: "로그인 시 앱 열기")
  private var appearanceObservation: NSKeyValueObservation?
  private var accessibilityObservation: NSObjectProtocol?
  var active: Profile? { settings.profiles.first { $0.id == settings.selectedID } }
  deinit {
    appearanceObservation?.invalidate()
    if let accessibilityObservation {
      NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObservation)
    }
  }
  func applicationDidFinishLaunching(_ note: Notification) {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.button?.image = NSImage(
      systemSymbolName: "wind", accessibilityDescription: "Lagrangian")
    statusItem.button?.title = " Flow"
    statusItem.button?.imagePosition = .imageLeading
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
        self.login.state = loaded.1 ? .on : .off
        self.populate()
      })
    readingEnvironment.start()
  }
  func applicationWillTerminate(_ notification: Notification) {
    readingIntent += 1
    cancelPendingCrossProjectTransition()
    readingEnvironment.dispose()
    session.dispose()
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
    let menu = NSMenu()
    for (title, selector, key) in [
      ("Lagrangian 열기…", #selector(showWindow), ","),
      ("읽기 시작", #selector(openPreview), "o"),
      ("외부 Reader 열기", #selector(openExternalPreview), ""),
      ("오프라인 문서 열기", #selector(openOffline), ""),
      ("Connect Editor…", #selector(connectEditor), ""),
      ("Disconnect Editor", #selector(disconnectEditor), ""),
      ("프로젝트 설정", #selector(showSettings), ""),
      ("선택한 프로젝트 서비스 시작", #selector(start), ""),
      ("선택한 프로젝트 서비스 중지", #selector(stop), ""),
      ("선택한 프로젝트 서비스 재시작", #selector(restart), ""),
      ("로그 보기", #selector(openLogs), ""),
      ("사용·업데이트·복구 안내", #selector(guide), ""),
      ("앱 정보", #selector(about), ""),
      ("앱 종료 (프리뷰 계속 실행)", #selector(quit), "q"),
    ] {
      let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
      item.target = self
      menu.addItem(item)
    }
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
    NSApp.mainMenu = main
  }
  func button(_ title: String, _ selector: Selector) -> NSButton {
    let result = NativeDesignButton(title: title, target: self, action: selector)
    if selector == #selector(openPreview) || selector == #selector(save) { result.designRole = .primary }
    controls[selector] = result
    return result
  }
  private func iconButton(symbol: String, label: String, identifier: String, selector: Selector) -> NativeDesignButton {
    let result = NativeDesignButton(title: "", target: self, action: selector)
    let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
    image?.isTemplate = true
    result.image = image
    result.imagePosition = .imageOnly
    result.imageScaling = .scaleProportionallyDown
    result.toolTip = label
    result.identifier = NSUserInterfaceItemIdentifier(identifier)
    result.setAccessibilityLabel(label)
    result.widthAnchor.constraint(equalToConstant: 36).isActive = true
    result.heightAnchor.constraint(equalToConstant: 32).isActive = true
    controls[selector] = result
    return result
  }
  private func configureOverflowButton(_ button: NativeDesignButton, label: String, identifier: String, selector: Selector) {
    button.title = "•••"
    button.target = self
    button.action = selector
    button.identifier = NSUserInterfaceItemIdentifier(identifier)
    button.setAccessibilityLabel(label)
    button.toolTip = label
    button.setContentHuggingPriority(.required, for: .horizontal)
    button.setContentCompressionResistancePriority(.required, for: .horizontal)
  }
  func buildWindow() {
    window = NativeReaderEditingWindow(
      contentRect: NSRect(x: 0, y: 0, width: 660, height: 460),
      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
    window.minSize = NSSize(width: 560, height: 390)
    NativeChrome.install(on: window)
    window.title = LagrangianIdentity.appName
    (window as? NativeReaderEditingWindow)?.fixtureMode = fixtureMode
    window.isReleasedWhenClosed = false
    window.center()

    let root = NSStackView()
    root.orientation = .vertical
    root.alignment = .leading
    root.spacing = NativeAppDesign.Spacing.section
    root.edgeInsets = NSEdgeInsets(top: 24, left: 28, bottom: 20, right: 28)
    root.translatesAutoresizingMaskIntoConstraints = false
    window.contentView!.addSubview(root)
    NSLayoutConstraint.activate([
      root.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
      root.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
      root.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
      root.bottomAnchor.constraint(lessThanOrEqualTo: window.contentView!.bottomAnchor),
    ])

    // 1. Minimal header: centered NativeBrandMark + title, top-right + and ⚙ only.
    let headerBar = NSView()
    headerBar.translatesAutoresizingMaskIntoConstraints = false
    let icon = NativeBrandMarkView()
    icon.identifier = NSUserInterfaceItemIdentifier("home.brandMark")
    icon.widthAnchor.constraint(equalToConstant: 44).isActive = true
    icon.heightAnchor.constraint(equalToConstant: 41).isActive = true
    let title = NSTextField(labelWithString: LagrangianIdentity.appName)
    title.font = NativeAppDesign.Typography.font(.brandTitle)
    title.identifier = NSUserInterfaceItemIdentifier("home.brandTitle")
    let brandGroup = NSStackView(views: [icon, title])
    brandGroup.orientation = .horizontal
    brandGroup.alignment = .centerY
    brandGroup.spacing = 10
    brandGroup.translatesAutoresizingMaskIntoConstraints = false
    let addButton = iconButton(symbol: "plus", label: "프로젝트 추가", identifier: "home.addProject", selector: #selector(addProject))
    let gearButton = iconButton(symbol: "gearshape", label: "프로젝트 설정", identifier: "home.openSettings", selector: #selector(showSettings))
    let headerActions = NSStackView(views: [addButton, gearButton])
    headerActions.orientation = .horizontal
    headerActions.alignment = .centerY
    headerActions.spacing = NativeAppDesign.Spacing.small
    headerActions.translatesAutoresizingMaskIntoConstraints = false
    headerBar.addSubview(brandGroup)
    headerBar.addSubview(headerActions)
    root.addArrangedSubview(headerBar)
    NSLayoutConstraint.activate([
      headerBar.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -56),
      headerBar.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
      brandGroup.centerXAnchor.constraint(equalTo: headerBar.centerXAnchor),
      brandGroup.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),
      brandGroup.topAnchor.constraint(greaterThanOrEqualTo: headerBar.topAnchor),
      brandGroup.bottomAnchor.constraint(lessThanOrEqualTo: headerBar.bottomAnchor),
      brandGroup.leadingAnchor.constraint(greaterThanOrEqualTo: headerBar.leadingAnchor),
      headerActions.trailingAnchor.constraint(equalTo: headerBar.trailingAnchor),
      headerActions.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),
      headerActions.leadingAnchor.constraint(greaterThanOrEqualTo: brandGroup.trailingAnchor, constant: 12),
    ])

    // 2. Center project card.
    let projectCard = NativeDesignSurface()
    projectCard.role = .panel
    projectCard.identifier = NSUserInterfaceItemIdentifier("home.projectCard")
    projectCard.translatesAutoresizingMaskIntoConstraints = false
    let projectContent = NSStackView()
    projectContent.orientation = .vertical
    projectContent.alignment = .leading
    projectContent.spacing = NativeAppDesign.Spacing.control
    projectContent.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
    projectContent.translatesAutoresizingMaskIntoConstraints = false
    projectCard.addSubview(projectContent)
    NSLayoutConstraint.activate([
      projectContent.leadingAnchor.constraint(equalTo: projectCard.leadingAnchor),
      projectContent.trailingAnchor.constraint(equalTo: projectCard.trailingAnchor),
      projectContent.topAnchor.constraint(equalTo: projectCard.topAnchor),
      projectContent.bottomAnchor.constraint(equalTo: projectCard.bottomAnchor),
    ])

    picker.target = self
    picker.action = #selector(selectProfile)
    picker.identifier = NSUserInterfaceItemIdentifier("home.projectPicker")
    picker.setAccessibilityLabel("프로젝트 선택")
    picker.setContentHuggingPriority(.defaultLow, for: .horizontal)
    picker.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    picker.heightAnchor.constraint(greaterThanOrEqualToConstant: NativeAppDesign.Shape.minimumControlHeight).isActive = true

    pathCaption.font = NativeAppDesign.Typography.font(.caption)
    pathCaption.lineBreakMode = .byTruncatingHead
    pathCaption.maximumNumberOfLines = 1
    pathCaption.cell?.usesSingleLineMode = true
    pathCaption.cell?.wraps = false
    pathCaption.cell?.truncatesLastVisibleLine = true
    pathCaption.identifier = NSUserInterfaceItemIdentifier("home.projectPath")
    pathCaption.setAccessibilityLabel("프로젝트 진입 파일 경로")
    pathCaption.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    let selectorBlock = NSStackView(views: [picker, pathCaption])
    selectorBlock.orientation = .vertical
    selectorBlock.alignment = .leading
    selectorBlock.spacing = 6
    projectContent.addArrangedSubview(selectorBlock)
    selectorBlock.widthAnchor.constraint(equalTo: projectContent.widthAnchor, constant: -40).isActive = true
    picker.widthAnchor.constraint(equalTo: selectorBlock.widthAnchor).isActive = true
    pathCaption.widthAnchor.constraint(equalTo: selectorBlock.widthAnchor).isActive = true

    status.font = NativeAppDesign.Typography.font(.control)
    status.identifier = NSUserInterfaceItemIdentifier("home.status")
    status.setAccessibilityLabel("읽기 상태")
    status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    activity.style = .spinning
    activity.controlSize = .small
    activity.isDisplayedWhenStopped = false
    let statusRow = NSStackView(views: [activity, status])
    statusRow.orientation = .horizontal
    statusRow.alignment = .centerY
    statusRow.spacing = NativeAppDesign.Spacing.small

    detail.font = NativeAppDesign.Typography.font(.caption)
    detail.maximumNumberOfLines = 4
    detail.identifier = NSUserInterfaceItemIdentifier("home.detail")
    detail.setAccessibilityLabel("읽기 상태 설명")
    detail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    feedbackStack.orientation = .vertical
    feedbackStack.alignment = .leading
    feedbackStack.spacing = 4
    feedbackStack.addArrangedSubview(statusRow)
    feedbackStack.addArrangedSubview(detail)
    feedbackStack.isHidden = true
    projectContent.addArrangedSubview(feedbackStack)
    feedbackStack.widthAnchor.constraint(equalTo: projectContent.widthAnchor, constant: -40).isActive = true
    detail.widthAnchor.constraint(equalTo: feedbackStack.widthAnchor).isActive = true

    let readButton = button("읽기 시작", #selector(openPreview))
    readButton.keyEquivalent = "\r"
    readButton.identifier = NSUserInterfaceItemIdentifier("home.read")
    readButton.setAccessibilityLabel("읽기 시작")
    let offlineButton = button("오프라인 문서", #selector(openOffline))
    offlineButton.identifier = NSUserInterfaceItemIdentifier("home.offline")
    offlineButton.setAccessibilityLabel("오프라인 문서")
    configureOverflowButton(projectOverflowButton, label: "프로젝트 추가 작업", identifier: "home.projectOverflow", selector: #selector(showProjectMenu(_:)))
    let projectActions = NSStackView(views: [readButton, offlineButton, projectOverflowButton])
    projectActions.orientation = .horizontal
    projectActions.alignment = .centerY
    projectActions.spacing = NativeAppDesign.Spacing.small
    projectContent.addArrangedSubview(projectActions)

    root.addArrangedSubview(projectCard)
    projectCard.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -56).isActive = true

    // 3. Bottom status-linked single-line preview service card.
    let serviceCard = NativeDesignSurface()
    serviceCard.role = .panel
    serviceCard.identifier = NSUserInterfaceItemIdentifier("home.serviceCard")
    serviceCard.translatesAutoresizingMaskIntoConstraints = false
    let serviceRow = NSStackView()
    serviceRow.orientation = .horizontal
    serviceRow.alignment = .centerY
    serviceRow.spacing = NativeAppDesign.Spacing.control
    serviceRow.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
    serviceRow.translatesAutoresizingMaskIntoConstraints = false
    serviceCard.addSubview(serviceRow)
    NSLayoutConstraint.activate([
      serviceRow.leadingAnchor.constraint(equalTo: serviceCard.leadingAnchor),
      serviceRow.trailingAnchor.constraint(equalTo: serviceCard.trailingAnchor),
      serviceRow.topAnchor.constraint(equalTo: serviceCard.topAnchor),
      serviceRow.bottomAnchor.constraint(equalTo: serviceCard.bottomAnchor),
    ])

    serviceStatusDot.translatesAutoresizingMaskIntoConstraints = false
    serviceStatusDot.widthAnchor.constraint(equalToConstant: 10).isActive = true
    serviceStatusDot.heightAnchor.constraint(equalToConstant: 10).isActive = true
    serviceStatusLabel.font = NativeAppDesign.Typography.font(.control)
    serviceStatusLabel.identifier = NSUserInterfaceItemIdentifier("home.serviceStatus")
    serviceStatusLabel.setAccessibilityLabel("프리뷰 서비스 상태")
    let serviceStatusRow = NSStackView(views: [serviceStatusDot, serviceStatusLabel])
    serviceStatusRow.orientation = .horizontal
    serviceStatusRow.alignment = .centerY
    serviceStatusRow.spacing = NativeAppDesign.Spacing.small

    serviceAddressLabel.font = NativeAppDesign.Typography.font(.caption)
    serviceAddressLabel.lineBreakMode = .byTruncatingMiddle
    serviceAddressLabel.maximumNumberOfLines = 1
    serviceAddressLabel.cell?.usesSingleLineMode = true
    serviceAddressLabel.identifier = NSUserInterfaceItemIdentifier("home.serviceAddress")
    serviceAddressLabel.setAccessibilityLabel("프리뷰 서비스 주소")
    serviceAddressLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    serviceAddressLink.linkFont = NativeAppDesign.Typography.font(.caption)
    serviceAddressLink.underlineAlways = true
    serviceAddressLink.target = self
    serviceAddressLink.action = #selector(openAddressLink)
    serviceAddressLink.identifier = NSUserInterfaceItemIdentifier("home.serviceAddressLink")
    serviceAddressLink.setAccessibilityLabel("프리뷰 주소 열기")
    serviceAddressLink.setAccessibilityRole(.link)
    serviceAddressLink.isHidden = true
    serviceAddressLink.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    let serviceInfoColumn = NSStackView(views: [serviceStatusRow, serviceAddressLabel, serviceAddressLink])
    serviceInfoColumn.orientation = .vertical
    serviceInfoColumn.alignment = .leading
    serviceInfoColumn.spacing = 4
    serviceInfoColumn.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    let serviceSpacer = NSView()
    serviceSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    serviceSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    let startButton = button("시작", #selector(start))
    startButton.identifier = NSUserInterfaceItemIdentifier("home.serviceStart")
    startButton.setAccessibilityLabel("서비스 시작")
    let logsButton = button("로그", #selector(openLogs))
    logsButton.identifier = NSUserInterfaceItemIdentifier("home.serviceLogs")
    logsButton.setAccessibilityLabel("서비스 로그 보기")
    let externalButton = button("외부 Reader", #selector(openExternalPreview))
    externalButton.identifier = NSUserInterfaceItemIdentifier("home.serviceExternalReader")
    externalButton.setAccessibilityLabel("외부 Reader")
    let stopButton = button("중지", #selector(stop))
    stopButton.identifier = NSUserInterfaceItemIdentifier("home.serviceStop")
    stopButton.setAccessibilityLabel("서비스 중지")
    configureOverflowButton(serviceOverflowButton, label: "프리뷰 서비스 추가 작업", identifier: "home.serviceOverflow", selector: #selector(showServiceMenu(_:)))
    for item in [startButton, logsButton, externalButton, stopButton] {
      item.setContentHuggingPriority(.required, for: .horizontal)
      item.setContentCompressionResistancePriority(.required, for: .horizontal)
    }
    externalButton.isHidden = true
    stopButton.isHidden = true
    serviceOverflowButton.isHidden = true

    let serviceActions = NSStackView(views: [startButton, logsButton, externalButton, stopButton, serviceOverflowButton])
    serviceActions.orientation = .horizontal
    serviceActions.alignment = .centerY
    serviceActions.spacing = NativeAppDesign.Spacing.small
    serviceActions.setContentHuggingPriority(.required, for: .horizontal)
    serviceActions.setContentCompressionResistancePriority(.required, for: .horizontal)

    serviceRow.addArrangedSubview(serviceInfoColumn)
    serviceRow.addArrangedSubview(serviceSpacer)
    serviceRow.addArrangedSubview(serviceActions)
    root.addArrangedSubview(serviceCard)
    serviceCard.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -56).isActive = true

    // 4. Bottom-most bar: login checkbox (left) + project settings link (right).
    login.target = self
    login.action = #selector(toggleLogin)
    login.identifier = NSUserInterfaceItemIdentifier("home.loginLaunch")
    login.setAccessibilityLabel("로그인 시 앱 열기")

    let footerSpacer = NSView()
    footerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    footerSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    settingsFooterButton.linkFont = NativeAppDesign.Typography.font(.control)
    settingsFooterButton.underlineAlways = false
    settingsFooterButton.target = self
    settingsFooterButton.action = #selector(showSettings)
    settingsFooterButton.identifier = NSUserInterfaceItemIdentifier("home.openSettingsFooter")
    settingsFooterButton.setAccessibilityLabel("프로젝트 설정")

    let footerBar = NSStackView(views: [login, footerSpacer, settingsFooterButton])
    footerBar.orientation = .horizontal
    footerBar.alignment = .centerY
    footerBar.spacing = NativeAppDesign.Spacing.control
    root.addArrangedSubview(footerBar)
    footerBar.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -56).isActive = true

    buildSettingsWindow()

    NativeChrome.apply(to: window.contentView!)
    (login as? NativeCheckboxButton)?.onAppearanceChange = { [weak self] in
      self?.refreshAppearanceColors()
    }
    appearanceObservation?.invalidate()
    appearanceObservation = window.observe(\.effectiveAppearance, options: []) { [weak self] _, _ in
      if Thread.isMainThread { self?.refreshAppearanceColors() }
      else { DispatchQueue.main.async { self?.refreshAppearanceColors() } }
    }
    if accessibilityObservation == nil {
      accessibilityObservation = NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        self?.refreshAppearanceColors()
      }
    }
    refreshAppearanceColors()
    renderServiceCard()
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
    let headerStack = NSStackView(views: [heading, settingsProjectLabel])
    headerStack.orientation = .vertical
    headerStack.alignment = .leading
    headerStack.spacing = 4
    container.addArrangedSubview(headerStack)
    headerStack.widthAnchor.constraint(equalTo: container.widthAnchor, constant: -48).isActive = true
    settingsProjectLabel.widthAnchor.constraint(equalTo: headerStack.widthAnchor).isActive = true

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
    settingsProjectLabel.stringValue = active.map { "\($0.name) · \($0.path($0.entry))" } ?? "프로젝트를 추가해 시작하세요"
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
    guard let p = active else {
      pathCaption.stringValue = "프로젝트를 추가해 시작하세요"
      pathCaption.toolTip = nil
      syncFieldsFromActive()
      updateControls()
      renderServiceCard()
      return
    }
    let fullPath = p.path(p.entry)
    pathCaption.stringValue = fullPath
    pathCaption.toolTip = fullPath
    syncFieldsFromActive()
    updateControls()
    renderServiceCard()
  }
  private var isServiceRunning: Bool {
    guard active != nil, let snapshot else { return false }
    return snapshot.pid != nil || snapshot.phase == .running || snapshot.phase == .ready
  }
  private func displayAddress(for profile: Profile) -> String {
    profile.publicURL.isEmpty ? "127.0.0.1:\(profile.port)" : profile.publicURL
  }
  private func renderServiceCard() {
    let running = isServiceRunning
    serviceStatusDot.running = running
    if let p = active {
      let addr = displayAddress(for: p)
      serviceStatusLabel.stringValue = running ? "프리뷰 서비스 · 실행 중" : "프리뷰 서비스 · 중지됨"
      serviceAddressLabel.stringValue = addr
      serviceAddressLink.title = addr
      serviceAddressLink.toolTip = p.url
      serviceAddressLink.refreshAppearance()
    } else {
      serviceStatusLabel.stringValue = "프리뷰 서비스 · 프로젝트 없음"
      serviceAddressLabel.stringValue = "프로젝트를 추가해 시작하세요"
      serviceAddressLink.title = ""
      serviceAddressLink.toolTip = nil
    }
    serviceAddressLabel.isHidden = running
    serviceAddressLink.isHidden = !running
    controls[#selector(start)]?.isHidden = running
    controls[#selector(openLogs)]?.isHidden = running
    controls[#selector(openExternalPreview)]?.isHidden = !running
    controls[#selector(stop)]?.isHidden = !running
    serviceOverflowButton.isHidden = !running
  }
  func render(_ snapshot: ReadingSessionSnapshot) {
    let previousMessage = self.snapshot?.message
    self.snapshot = snapshot
    status.stringValue = snapshot.message
    detail.stringValue = snapshot.detail
    detail.toolTip = snapshot.detail
    let showFeedback = mutating || snapshot.isBusy || snapshot.phase == .failed || snapshot.phase == .painted || snapshot.phase == .sleeping || snapshot.phase == .idle || active == nil
    feedbackStack.isHidden = !showFeedback
    let showDetail = !snapshot.detail.isEmpty && (snapshot.phase == .failed || snapshot.detail != active?.url)
    detail.isHidden = !showDetail
    refreshStatusColor()
    if snapshot.isBusy { activity.startAnimation(nil) } else { activity.stopAnimation(nil) }
    let readTitle = snapshot.phase == .failed ? "다시 읽기" : "읽기 시작"
    controls[#selector(openPreview)]?.title = readTitle
    controls[#selector(openPreview)]?.setAccessibilityLabel(readTitle)
    renderServiceCard()
    updateControls()
    if previousMessage != snapshot.message {
      NSAccessibility.post(element: status, notification: .valueChanged)
    }
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
    if [#selector(openPreview), #selector(openExternalPreview), #selector(start), #selector(restart), #selector(save)].contains(
      action)
    {
      return active != nil && !mutating && snapshot?.isBusy != true
    }
    if action == #selector(browseRoot) { return active != nil && !mutating }
    if action == #selector(stop) { return active != nil && !mutating }
    if action == #selector(closeSettings) { return !mutating }
    if [#selector(copyURL), #selector(openLogs), #selector(openOffline), #selector(showSettings)].contains(action) { return active != nil }
    return true
  }
  func refreshStatusColor() {
    let appearance = status.window != nil ? status.effectiveAppearance : (window?.effectiveAppearance ?? status.effectiveAppearance)
    let palette = NativeAppDesign.palette(.current(appearance: appearance))
    status.textColor = snapshot?.phase == .failed ? palette.error : palette.ink
    detail.textColor = snapshot?.phase == .failed ? palette.error : palette.secondaryInk
    pathCaption.textColor = palette.secondaryInk
    serviceStatusLabel.textColor = palette.ink
    serviceAddressLabel.textColor = palette.secondaryInk
    settingsProjectLabel.textColor = palette.secondaryInk
    settingsHintLabel.textColor = palette.secondaryInk
    settingsStatus.textColor = (!settingsStatus.isHidden && !settingsStatus.stringValue.isEmpty) ? palette.error : palette.secondaryInk
    for selector in [#selector(addProject), #selector(showSettings)] {
      if let btn = controls[selector] {
        btn.contentTintColor = btn.isEnabled ? palette.ink : palette.disabledInk
      }
    }
  }
  func refreshAppearanceColors() {
    refreshLoginTitle()
    refreshStatusColor()
    serviceAddressLink.refreshAppearance()
    settingsFooterButton.refreshAppearance()
    serviceStatusDot.needsDisplay = true
  }
  func refreshLoginTitle() {
    let appearance = login.window != nil ? login.effectiveAppearance : (window?.effectiveAppearance ?? login.effectiveAppearance)
    let palette = NativeAppDesign.palette(.current(appearance: appearance))
    let foreground = login.isEnabled ? palette.ink : palette.secondaryInk
    let title = login.title.isEmpty ? "로그인 시 앱 열기" : login.title
    let font = login.font ?? NativeAppDesign.Typography.font(.control)
    login.attributedTitle = NSAttributedString(
      string: title,
      attributes: [.foregroundColor: foreground, .font: font]
    )
    login.needsDisplay = true
  }
  func updateControls() {
    picker.isEnabled = !mutating
    login.isEnabled = enabled(#selector(toggleLogin))
    refreshLoginTitle()
    for field in fields.values { field.isEnabled = active != nil && !mutating }
    for (action, control) in controls { control.isEnabled = enabled(action) }
    projectOverflowButton.isEnabled = !mutating
    serviceOverflowButton.isEnabled = active != nil && !mutating
    serviceAddressLink.isEnabled = !fixtureMode && (!isolated || devIsolatedServicePreview) && active != nil
    settingsFooterButton.isEnabled = enabled(#selector(showSettings))
    refreshStatusColor()
  }
  func projectOverflowMenu() -> NSMenu {
    let menu = NSMenu(title: "프로젝트 작업")
    menu.autoenablesItems = true
    for (title, action) in [
      ("주소 복사", #selector(copyURL)),
      ("설정 파일 보기", #selector(revealSettings)),
      ("프로젝트 추가…", #selector(addProject)),
    ] {
      let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
      item.target = self
      menu.addItem(item)
    }
    menu.addItem(NSMenuItem.separator())
    for (title, action) in [
      ("Connect Editor…", #selector(connectEditor)),
      ("Disconnect Editor", #selector(disconnectEditor)),
      ("사용·업데이트·복구 안내", #selector(guide)),
    ] {
      let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
      item.target = self
      menu.addItem(item)
    }
    return menu
  }
  func serviceOverflowMenu() -> NSMenu {
    let menu = NSMenu(title: "프리뷰 서비스 작업")
    menu.autoenablesItems = true
    for (title, action) in [
      ("재시작", #selector(restart)),
      ("주소 복사", #selector(copyURL)),
      ("로그 보기", #selector(openLogs)),
    ] {
      let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
      item.target = self
      menu.addItem(item)
    }
    return menu
  }
  @objc func showProjectMenu(_ sender: NSButton) {
    let y: CGFloat = sender.isFlipped ? sender.bounds.height + 4 : -4
    projectOverflowMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: y), in: sender)
  }
  @objc func showServiceMenu(_ sender: NSButton) {
    let y: CGFloat = sender.isFlipped ? sender.bounds.height + 4 : -4
    serviceOverflowMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: y), in: sender)
  }
  @objc func openAddressLink() {
    guard !fixtureMode, (!isolated || devIsolatedServicePreview), let p = active, let url = URL(string: p.url) else { return }
    _ = openExternalURL(url)
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
  @objc func selectProfile() {
    guard !mutating, picker.indexOfSelectedItem >= 0 else { return }
    let id = settings.profiles[picker.indexOfSelectedItem].id
    readingIntent += 1
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
  @objc func copyURL() {
    if let p = active {
      _ = copyText(p.url)
    }
  }
  @objc func openLogs() {
    guard !fixtureMode, let p = active else { return }
    let file = environment.logRoot.appendingPathComponent("\(p.id).err.log")
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
    let desired = login.state == .on
    login.state = loginEnabled ? .on : .off
    let agents = launchAgents
    mutate(
      "로그인 시 실행 설정을 저장하는 중…",
      work: {
        try agents.setLogin(desired)
        return agents.loginEnabled()
      },
      success: { [weak self] enabled in
        self?.loginEnabled = enabled
        self?.login.state = enabled ? .on : .off
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

private final class NativeCheckboxButton: NSButton {
  var onAppearanceChange: (() -> Void)?
  override class var cellClass: AnyClass? {
    get { NativeCheckboxCell.self }
    set {}
  }
  convenience init(checkboxTitle: String) {
    self.init(frame: .zero)
    setButtonType(.switch)
    title = checkboxTitle
  }
  override init(frame: NSRect) {
    super.init(frame: frame)
    setButtonType(.switch)
  }
  required init?(coder: NSCoder) { nil }
  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    onAppearanceChange?()
  }
}

private final class NativeCheckboxCell: NSButtonCell {
  override func drawTitle(_ title: NSAttributedString, withFrame frame: NSRect, in controlView: NSView) -> NSRect {
    let text = NSMutableAttributedString(attributedString: title)
    if let explicit = (controlView as? NSButton)?.attributedTitle, explicit.length > 0,
       let color = explicit.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor {
      text.addAttribute(.foregroundColor, value: color, range: NSRange(location: 0, length: text.length))
    }
    return super.drawTitle(text, withFrame: frame, in: controlView)
  }
}

private final class ServiceStatusDotView: NSView {
  var running = false { didSet { needsDisplay = true } }
  override var intrinsicContentSize: NSSize { NSSize(width: 10, height: 10) }
  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    needsDisplay = true
  }
  override func draw(_ dirtyRect: NSRect) {
    let preferences = NativeAppDesign.Preferences.current(appearance: effectiveAppearance)
    let palette = NativeAppDesign.palette(preferences)
    let dark = preferences.theme == .dark
    let color: NSColor = running
      ? NativeAppDesign.color(dark ? 0x5BD28B : 0x217A4B)
      : NativeAppDesign.color(dark ? 0xA59D90 : 0x6E6960)
    let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1))
    color.setFill()
    circle.fill()
    if preferences.increasedContrast {
      palette.boundary.setStroke()
      circle.lineWidth = 1
      circle.stroke()
    }
  }
}

final class NativeLinkButton: NSButton {
  var linkFont: NSFont = NativeAppDesign.Typography.font(.control) { didSet { refreshAppearance() } }
  var underlineAlways = false { didSet { refreshAppearance() } }
  private var isHovered = false
  private var hoverArea: NSTrackingArea?
  private var observation: NativeDesignObservation?

  convenience init(title: String, target: AnyObject?, action: Selector?) {
    self.init(frame: .zero)
    self.title = title
    self.target = target
    self.action = action
  }
  override init(frame: NSRect) {
    super.init(frame: frame)
    configure()
  }
  required init?(coder: NSCoder) {
    super.init(coder: coder)
    configure()
  }
  private func configure() {
    setButtonType(.momentaryChange)
    isBordered = false
    focusRingType = .exterior
    observation = NativeDesignObservation(view: self)
  }
  override var title: String {
    didSet { refreshAppearance() }
  }
  override var isEnabled: Bool {
    didSet {
      if !isEnabled { isHovered = false }
      refreshAppearance()
    }
  }
  override var intrinsicContentSize: NSSize {
    let size = super.intrinsicContentSize
    return NSSize(width: size.width + 4, height: max(24, size.height + 4))
  }
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let hoverArea { removeTrackingArea(hoverArea) }
    let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
    addTrackingArea(area)
    hoverArea = area
  }
  override func mouseEntered(with event: NSEvent) {
    isHovered = isEnabled
    refreshAppearance()
  }
  override func mouseExited(with event: NSEvent) {
    isHovered = false
    refreshAppearance()
  }
  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    refreshAppearance()
  }
  override var focusRingMaskBounds: NSRect { bounds }
  override func drawFocusRingMask() {
    NSBezierPath(roundedRect: bounds, xRadius: NativeAppDesign.Shape.controlRadius, yRadius: NativeAppDesign.Shape.controlRadius).fill()
  }
  func refreshAppearance() {
    let appearance = window != nil ? effectiveAppearance : NSApp.effectiveAppearance
    let palette = NativeAppDesign.palette(.current(appearance: appearance))
    let color = isEnabled ? palette.accent : palette.disabledInk
    var attributes: [NSAttributedString.Key: Any] = [
      .foregroundColor: color,
      .font: linkFont,
    ]
    if underlineAlways || isHovered {
      attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
    }
    attributedTitle = NSAttributedString(string: title, attributes: attributes)
    needsDisplay = true
  }
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
