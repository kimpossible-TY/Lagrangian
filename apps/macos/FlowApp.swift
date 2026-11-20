import AppKit
import CryptoKit
import UniformTypeIdentifiers

final class FlowApp: NSObject, NSApplicationDelegate, NSMenuItemValidation {
  let startupTimeline: NativeStartupTimeline?
  let isolated: Bool
  let fixture: URL?
  var fixtureMode: Bool { isolated && fixture != nil }
  var openExternalURL: (URL) -> Bool = { NSWorkspace.shared.open($0) }
  var revealExternalFiles: ([URL]) -> Void = { NSWorkspace.shared.activateFileViewerSelecting($0) }
  let noActivate: Bool
  let showNativeWindow: Bool
  let nativeRuntime: NativeReaderRuntime?
  let copyText: (String) -> Bool
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
  var offlineWindow: NativeReaderWindowController?
  var nativeReadOverride: ReadingSessionController.NativeRead?
  let environment: AppEnvironment
  let store: SettingsStore
  let launchAgents: LaunchAgentService
  let projectService: ProjectService
  var settings = Settings()
  lazy var session = ReadingSessionController(
    launchAgents: isolated ? IsolatedProjectController() : launchAgents,
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
    }
  )
  /// The same production composition is called by Read and isolated offscreen
  /// tests; service inventory and window visibility remain explicit inputs.
  @MainActor func readNative(_ profile: Profile, progress: @escaping (NativeReadProgress) -> Void) -> () -> Void {
      if let read = self.nativeReadOverride { return read(profile, progress) }
      if self.nativeProfile != profile || self.nativeWindow?.session.hasRecoveryCopy == true {
        self.nativeWindow?.dispose(); self.nativeWindow = nil; self.nativeProfile = profile
      }
      if self.nativeWindow == nil {
        if let fixture = self.fixture, self.isolated {
          let provider = NativeReaderFixtureProvider(url: fixture)
          self.nativeWindow = NativeReaderWindowController(provider: provider, target: { _ in try await provider.load().identity },
            assets: { document, _ in
              try await Task.detached {
                var bytes = [String: Data]()
                for asset in document.assets {
                  bytes[asset.id] = try Data(contentsOf: fixture.deletingLastPathComponent().appendingPathComponent("assets").appendingPathComponent(asset.id))
                }
                return bytes
              }.value
            }, runtime: self.nativeRuntime, show: self.showNativeWindow, avoidActivation: self.noActivate, fixtureMode: self.fixtureMode,
               offlineStorage: NativeReaderOfflineStorage(owner: NativeReaderRecoveryStore(root: self.environment.nativeRecoveryRoot(for: profile))))
        } else {
          guard let resolver = self.managedResolver else {
            progress(.failed("네이티브 문서 서비스가 아직 연결되지 않았습니다. 명시적으로 구성된 Reader manager가 필요합니다."))
            return {}
          }
          let client = NativeReaderManagedClient(resolver: resolver, root: profile.root, entry: profile.entry,
                                                 editor: self.consentedEditors.removeValue(forKey: profile.id))
          self.nativeWindow = NativeReaderWindowController(provider: client, target: { _ in try await client.target() },
            assets: { document, context in
              let actions = try await client.currentActions()
              var assets = [String: Data]()
              for asset in document.assets { assets[asset.id] = try await actions.transport.asset(asset, context: context) }
              return assets
            }, runtime: self.nativeRuntime, actions: { try await client.currentActions() },
            invalidate: { await client.invalidate() }, show: self.showNativeWindow, avoidActivation: self.noActivate, fixtureMode: self.fixtureMode,
               offlineStorage: NativeReaderOfflineStorage(owner: NativeReaderRecoveryStore(root: self.environment.nativeRecoveryRoot(for: profile))))
        }
        self.nativeWindow?.copyText = self.copyText
        self.nativeWindow?.openHomepage = { [weak self] url in
          guard let self, !self.fixtureMode else { return }
          _ = self.openExternalURL(url)
        }
      }
      return self.nativeWindow!.open(profile, progress: progress)
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
       isolated: Bool = false, fixture: URL? = nil,
       noActivate: Bool = false, startupTimeline: NativeStartupTimeline? = nil, nativeRuntime: NativeReaderRuntime? = nil, nativeManager: URL? = nil, showNativeWindow: Bool = true) {
    self.startupTimeline = startupTimeline
    self.noActivate = noActivate
    self.showNativeWindow = showNativeWindow
    self.nativeRuntime = nativeRuntime
    self.isolated = isolated
    self.fixture = fixture
    self.environment = environment
    let privateBoard = isolated ? NSPasteboard(name: Self.isolatedCopyBoard(home: environment.userHome)) : nil
    copyText = { text in
      let board = privateBoard ?? NSPasteboard.general
      board.clearContents()
      return board.setString(text, forType: .string)
    }
    store = SettingsStore(directory: environment.support, localReplacement: environment.fixtureRoot != nil)
    launchAgents = LaunchAgentService(environment: environment)
    self.projectService = projectService ?? ProjectService(store: store, launchAgents: isolated ? IsolatedProjectController() : launchAgents)
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
  var settingsTabs: NSTabView?
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
  @objc func showSettings() { showWindow(); settingsTabs?.selectTabViewItem(at: 1) }
  var statusItem: NSStatusItem!
  var window: NSWindow!
  let picker = NSPopUpButton()
  let status = NSTextField(labelWithString: "프로젝트를 선택하세요")
  let detail = NSTextField(wrappingLabelWithString: "")
  let homeSummary = NSTextField(wrappingLabelWithString: "")
  let activity = NSProgressIndicator()
  var controls: [Selector: NSButton] = [:]
  var fields: [String: NSTextField] = [:]
  let login: NSButton = NativeCheckboxButton(checkboxTitle: "로그인 시 Lagrangian 앱 열기")
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
    statusItem.menu = menu
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
    editItem.submenu = edit
    main.addItem(editItem)
    NSApp.mainMenu = main
  }
  func button(_ title: String, _ selector: Selector) -> NSButton {
    let result = NativeDesignButton(title: title, target: self, action: selector)
    if selector == #selector(openPreview) { result.designRole = .primary }
    controls[selector] = result
    return result
  }
  func buildWindow() {
    window = NativeReaderEditingWindow(
      contentRect: NSRect(x: 0, y: 0, width: 760, height: 900),
      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
    window.minSize = NSSize(width: 720, height: 860)
    NativeChrome.install(on: window)
    window.title = LagrangianIdentity.appName
    (window as? NativeReaderEditingWindow)?.fixtureMode = fixtureMode
    window.isReleasedWhenClosed = false
    window.center()
    let content = NSStackView()
    content.orientation = .vertical
    content.alignment = .leading
    content.spacing = 14
    content.edgeInsets = NSEdgeInsets(top: 24, left: 28, bottom: 24, right: 28)
    content.translatesAutoresizingMaskIntoConstraints = false
    window.contentView!.addSubview(content)
    NSLayoutConstraint.activate([
      content.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
      content.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
      content.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
    ])
    let icon = NativeBrandMarkView()
    icon.widthAnchor.constraint(equalToConstant: 64).isActive = true
    icon.heightAnchor.constraint(equalToConstant: 59).isActive = true
    let title = NSTextField(labelWithString: LagrangianIdentity.appName)
    title.font = NativeAppDesign.Typography.font(.brandTitle)
    let sub = NSTextField(labelWithString: "문서에서 프리뷰까지, 한 흐름으로.")
    sub.textColor = .secondaryLabelColor
    let heading = NSStackView(views: [title, sub])
    heading.orientation = .vertical
    heading.alignment = .leading
    content.addArrangedSubview(NSStackView(views: [icon, heading]))
    picker.target = self
    picker.action = #selector(selectProfile)
    picker.widthAnchor.constraint(equalToConstant: 400).isActive = true
    content.addArrangedSubview(
      NSStackView(views: [picker, button("프로젝트 추가…", #selector(addProject))]))
    status.font = .systemFont(ofSize: 14, weight: .medium)
    status.setAccessibilityLabel("읽기 상태")
    activity.style = .spinning
    activity.controlSize = .small
    activity.isDisplayedWhenStopped = false
    content.addArrangedSubview(NSStackView(views: [activity, status]))
    detail.textColor = .secondaryLabelColor
    detail.font = .systemFont(ofSize: 12)
    detail.widthAnchor.constraint(equalToConstant: 630).isActive = true
    detail.maximumNumberOfLines = 4
    detail.setAccessibilityLabel("읽기 상태 설명")
    content.addArrangedSubview(detail)
    content.addArrangedSubview(
      NSStackView(views: [
        button("읽기 시작", #selector(openPreview)), button("외부 Reader", #selector(openExternalPreview)),
        button("주소 복사", #selector(copyURL)), button("오프라인 문서", #selector(openOffline)),
      ]))
    content.addArrangedSubview(
      NSStackView(views: [
        button("서비스 시작", #selector(start)), button("서비스 중지", #selector(stop)),
        button("서비스 재시작", #selector(restart)), button("로그", #selector(openLogs)),
      ]))
    controls[#selector(openPreview)]?.keyEquivalent = "\r"
    let definitions = [
      ("name", "프로젝트 이름"), ("root", "프로젝트 폴더"), ("entry", "진입 파일"), ("fonts", "글꼴 폴더 ( ; 구분)"),
      ("packages", "로컬 패키지 폴더"), ("port", "로컬 포트"), ("publicURL", "HTTPS 주소 (선택)"),
    ]
    let grid = NSGridView(
      views: definitions.map { key, label in
        let field = NSTextField()
        field.setAccessibilityLabel(label)
        if key == "root" {
          field.widthAnchor.constraint(greaterThanOrEqualToConstant: 440).isActive = true
          field.maximumNumberOfLines = 1
          field.lineBreakMode = .byTruncatingMiddle
          field.cell?.usesSingleLineMode = true
          field.cell?.wraps = false
        } else { field.widthAnchor.constraint(equalToConstant: 440).isActive = true }
        fields[key] = field
        return [NSTextField(labelWithString: label), field]
      })
    grid.rowSpacing = 10
    grid.columnSpacing = 12
    grid.xPlacement = .leading
    grid.cell(atColumnIndex: 1, rowIndex: 1).xPlacement = .fill
    let settingsPanel = NSStackView(views: [grid])
    settingsPanel.orientation = .vertical
    settingsPanel.alignment = .leading
    grid.widthAnchor.constraint(equalTo: settingsPanel.widthAnchor).isActive = true
    let tabs = NSTabView()
    tabs.tabViewType = .topTabsBezelBorder
    let home = NSTabViewItem(identifier: "home")
    home.label = "홈"
    home.view = homeSummary
    let project = NSTabViewItem(identifier: "settings")
    project.label = "프로젝트 설정"
    project.view = settingsPanel
    tabs.addTabViewItem(home)
    tabs.addTabViewItem(project)
    tabs.heightAnchor.constraint(equalToConstant: 290).isActive = true
    settingsTabs = tabs
    content.addArrangedSubview(tabs)
    tabs.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -56).isActive = true
    content.addArrangedSubview(
      NSStackView(views: [
        button("설정 저장", #selector(save)), button("설정 파일 보기", #selector(revealSettings)),
      ]))
    let hint = NSTextField(
      wrappingLabelWithString:
        "읽기 시작은 설정을 확인하고 네이티브 문서를 요청합니다. 외부 Reader 열기는 기존 브라우저 프리뷰를 엽니다. 변경한 설정은 먼저 저장됩니다. 글꼴 경로는 프로젝트 기준이며, HTTPS 주소는 Tail Hosting에서 연결하세요."
    )
    hint.font = .systemFont(ofSize: 11)
    hint.textColor = .secondaryLabelColor
    hint.widthAnchor.constraint(equalToConstant: 630).isActive = true
    content.addArrangedSubview(hint)
    login.target = self
    login.action = #selector(toggleLogin)
    content.addArrangedSubview(login)
    let footer = NSTextField(labelWithString: "프리뷰는 시작 후 로그인 시에도 실행됩니다. 중지하면 자동 실행도 해제됩니다.")
    footer.font = .systemFont(ofSize: 11)
    footer.textColor = .secondaryLabelColor
    content.addArrangedSubview(footer)
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
      for field in fields.values { field.stringValue = "" }
      updateControls()
      return
    }
    for (key, value) in [
      "name": p.name, "root": p.root, "entry": p.entry, "fonts": p.fonts.joined(separator: "; "),
      "packages": p.packages, "port": String(p.port), "publicURL": p.publicURL,
    ] { fields[key]?.stringValue = value }
    updateControls()
  }
  func render(_ snapshot: ReadingSessionSnapshot) {
    let previousMessage = self.snapshot?.message
    self.snapshot = snapshot
    status.stringValue = snapshot.message
    detail.stringValue = snapshot.detail
    detail.toolTip = snapshot.detail
    refreshStatusColor()
    if snapshot.isBusy { activity.startAnimation(nil) } else { activity.stopAnimation(nil) }
    controls[#selector(openPreview)]?.title = snapshot.phase == .failed ? "다시 읽기" : "읽기 시작"
    updateControls()
    if previousMessage != snapshot.message {
      NSAccessibility.post(element: status, notification: .valueChanged)
    }
  }
  func enabled(_ action: Selector?) -> Bool {
    guard let action else { return true }
    if fixtureMode && [#selector(connectEditor), #selector(disconnectEditor), #selector(addProject),
        #selector(openLogs), #selector(revealSettings), #selector(guide), #selector(about)].contains(action) { return false }
    if isolated && [#selector(toggleLogin), #selector(start), #selector(stop),
                    #selector(restart), #selector(openExternalPreview)].contains(action) { return false }
    if [#selector(addProject), #selector(toggleLogin)].contains(action) {
      return !mutating && snapshot?.isBusy != true
    }
    if [#selector(openPreview), #selector(openExternalPreview), #selector(start), #selector(restart), #selector(save)].contains(
      action)
    {
      return active != nil && !mutating && snapshot?.isBusy != true
    }
    if action == #selector(stop) { return active != nil && !mutating }
    if [#selector(copyURL), #selector(openLogs), #selector(openOffline)].contains(action) { return active != nil }
    return true
  }
  func refreshStatusColor() {
    let appearance = status.window != nil ? status.effectiveAppearance : (window?.effectiveAppearance ?? status.effectiveAppearance)
    let palette = NativeAppDesign.palette(.current(appearance: appearance))
    status.textColor = snapshot?.phase == .failed ? palette.error : palette.ink
  }
  func refreshAppearanceColors() {
    refreshLoginTitle()
    refreshStatusColor()
  }
  func refreshLoginTitle() {
    let appearance = login.window != nil ? login.effectiveAppearance : (window?.effectiveAppearance ?? login.effectiveAppearance)
    let palette = NativeAppDesign.palette(.current(appearance: appearance))
    let foreground = login.isEnabled ? palette.ink : palette.secondaryInk
    let title = login.title.isEmpty ? "로그인 시 Lagrangian 앱 열기" : login.title
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
    if mutating {
      homeSummary.stringValue = settings.profiles.isEmpty
        ? "프로젝트 설정을 불러오는 중입니다. 준비가 끝나면 프로젝트를 선택하고 읽기를 시작할 수 있습니다. 이 상태가 계속되면 앱을 닫았다가 다시 여세요."
        : "프로젝트 설정을 확인하고 저장하는 중입니다. 작업이 끝날 때까지 기다려 주세요. 이 상태가 계속되면 앱을 닫았다가 다시 여세요."
    } else if snapshot?.phase == .failed {
      homeSummary.stringValue = active == nil
        ? "설정을 확인하는 중 오류가 발생했습니다. 위의 오류 내용을 확인하세요. 이 상태가 계속되면 앱을 닫았다가 다시 여세요."
        : "위의 오류와 프로젝트 설정을 확인한 뒤 다시 읽기를 시작할 수 있습니다. 이 상태가 계속되면 앱을 닫았다가 다시 여세요."
    } else if snapshot?.isBusy == true {
      homeSummary.stringValue = "문서를 준비하고 있습니다. 준비가 끝날 때까지 기다려 주세요."
    } else if active == nil {
      homeSummary.stringValue = "프로젝트를 추가하면 읽기를 시작할 수 있습니다. 프로젝트 추가에서 문서를 선택하세요."
    } else {
      homeSummary.stringValue = "프로젝트를 선택하고 읽기를 시작하세요. 문서 창은 앱 안에서 열립니다. 외부 Reader는 기존 프리뷰를 엽니다. 서비스 제어는 읽기 시작과 별도입니다."
    }
  }
  func validateMenuItem(_ menuItem: NSMenuItem) -> Bool { enabled(menuItem.action) }
  func mutate<T>(
    _ message: String, work: @escaping () throws -> T, success: @escaping (T) -> Void
  ) {
    guard !mutating else { return }
    mutating = true
    updateControls()
    let timeline = startupTimeline
    session.performMutation(message: message, work: work) { [weak self] result in
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
        self.session.reportFailure(error)
      }
      self.updateControls()
      let selectedHash = SHA256.hash(data: Data(self.settings.selectedID.utf8)).map { String(format: "%02x", $0) }.joined()
      timeline?.record("settings-adopted", ["profileCount": self.settings.profiles.count,
        "selectedIDHash": selectedHash, "readEnabled": self.controls[#selector(FlowApp.openPreview)]?.isEnabled ?? false])
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
  @objc func addProject() {
    guard !fixtureMode, !mutating else { return }
    let panel = NSOpenPanel()
    panel.title = "Typst 진입 파일 선택"
    panel.allowedContentTypes = [UTType(filenameExtension: "typ")!]
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let file = panel.url else { return }
    let previous = settings
    let service = projectService
    let home = environment.userHome
    mutate(
      "프로젝트를 추가하는 중…",
      work: {
        try service.addProject(at: file, in: previous, userHome: home)
      },
      success: { [weak self] next in
        self?.settings = next
        self?.populate()
      })
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
  func saveProfile(readAfterSaving: Bool, external: Bool = false) {
    guard !(fixtureMode && external), !mutating else { return }
    let intent = readingIntent
    do {
      let updated = try editedProfile()
      if updated == active {
        if readAfterSaving { external ? session.readExternally() : session.read() }
        return
      }
      let previous = settings
      let service = projectService
      mutate(
        "설정을 확인하고 저장하는 중…",
        work: {
          try service.updateProfile(updated, in: previous)
        },
        success: { [weak self] next in
          guard let self else { return }
          self.settings = next
          self.populate()
          if readAfterSaving && self.readingIntent == intent {
            external ? self.session.readExternally() : self.session.read()
          }
        })
    } catch { session.reportFailure(error) }
  }
  @objc func save() { saveProfile(readAfterSaving: false) }
  func perform(_ action: String) {
    guard !mutating, !isolated else { return }
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
