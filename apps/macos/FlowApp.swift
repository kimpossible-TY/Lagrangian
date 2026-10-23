import AppKit
import UniformTypeIdentifiers

final class FlowApp: NSObject, NSApplicationDelegate, NSMenuItemValidation {
  let environment: AppEnvironment
  let store: SettingsStore
  let launchAgents: LaunchAgentService
  let projectService: ProjectService
  var settings = Settings()
  lazy var session = ReadingSessionController(
    launchAgents: launchAgents,
    onChange: { [weak self] snapshot in self?.render(snapshot) },
    openBrowser: { NSWorkspace.shared.open($0) }
  )
  lazy var readingEnvironment = NativeReadingEnvironment(
    onSleep: { [weak self] in self?.sleepChanged($0) },
    onNetwork: { [weak self] in self?.session.networkChanged() },
    onPower: { [weak self] in self?.session.setConstrainedPower($0) }
  )
  var snapshot: ReadingSessionSnapshot?
  var mutating = false
  var loginEnabled = false
  var readingIntent = 0

  init(environment: AppEnvironment, projectService: ProjectService? = nil) {
    self.environment = environment
    store = SettingsStore(directory: environment.support)
    launchAgents = LaunchAgentService(environment: environment)
    self.projectService = projectService ?? ProjectService(store: store, launchAgents: launchAgents)
    super.init()
  }
  var statusItem: NSStatusItem!
  var window: NSWindow!
  let picker = NSPopUpButton()
  let status = NSTextField(labelWithString: "프로젝트를 선택하세요")
  let detail = NSTextField(wrappingLabelWithString: "")
  let activity = NSProgressIndicator()
  var controls: [Selector: NSButton] = [:]
  var fields: [String: NSTextField] = [:]
  let login = NSButton(checkboxWithTitle: "로그인 시 tinymist-flow 앱 열기", target: nil, action: nil)
  var active: Profile? { settings.profiles.first { $0.id == settings.selectedID } }
  func applicationDidFinishLaunching(_ note: Notification) {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.button?.image = NSImage(
      systemSymbolName: "wind", accessibilityDescription: "tinymist-flow")
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
        (try store.load(), agents.loginEnabled())
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
  }
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
      ("tinymist-flow 열기…", #selector(showWindow), ","),
      ("읽기 시작", #selector(openPreview), "o"),
      ("선택한 프로젝트 시작", #selector(start), ""),
      ("선택한 프로젝트 중지", #selector(stop), ""),
      ("선택한 프로젝트 재시작", #selector(restart), ""),
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
    let result = NSButton(title: title, target: self, action: selector)
    controls[selector] = result
    return result
  }
  func buildWindow() {
    window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 700, height: 720),
      styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
    window.title = FlowIdentity.appName
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
    let icon = NSImageView()
    icon.image = NSImage(named: NSImage.applicationIconName)
    icon.widthAnchor.constraint(equalToConstant: 64).isActive = true
    icon.heightAnchor.constraint(equalToConstant: 64).isActive = true
    let title = NSTextField(labelWithString: "tinymist-flow")
    title.font = .systemFont(ofSize: 26, weight: .semibold)
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
        button("읽기 시작", #selector(openPreview)), button("주소 복사", #selector(copyURL)),
        button("시작", #selector(start)), button("중지", #selector(stop)),
        button("재시작", #selector(restart)), button("로그", #selector(openLogs)),
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
        field.widthAnchor.constraint(equalToConstant: 440).isActive = true
        fields[key] = field
        return [NSTextField(labelWithString: label), field]
      })
    grid.rowSpacing = 10
    grid.columnSpacing = 12
    grid.xPlacement = .leading
    content.addArrangedSubview(grid)
    let hint = NSTextField(
      wrappingLabelWithString:
        "읽기 시작은 설정을 확인하고 문서가 준비되면 브라우저를 엽니다. 변경한 설정은 먼저 저장됩니다. 글꼴 경로는 프로젝트 기준이며, HTTPS 주소는 Tail Hosting에서 연결하세요."
    )
    hint.font = .systemFont(ofSize: 11)
    hint.textColor = .secondaryLabelColor
    hint.widthAnchor.constraint(equalToConstant: 630).isActive = true
    content.addArrangedSubview(hint)
    content.addArrangedSubview(
      NSStackView(views: [
        button("설정 저장", #selector(save)), button("설정 파일 보기", #selector(revealSettings)),
      ]))
    login.target = self
    login.action = #selector(toggleLogin)
    content.addArrangedSubview(login)
    let footer = NSTextField(labelWithString: "프리뷰는 시작 후 로그인 시에도 실행됩니다. 중지하면 자동 실행도 해제됩니다.")
    footer.font = .systemFont(ofSize: 11)
    footer.textColor = .secondaryLabelColor
    content.addArrangedSubview(footer)
  }
  func populate() {
    picker.removeAllItems()
    picker.addItems(withTitles: settings.profiles.map(\.name))
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
    status.textColor = snapshot.phase == .failed ? .systemRed : .labelColor
    if snapshot.isBusy { activity.startAnimation(nil) } else { activity.stopAnimation(nil) }
    controls[#selector(openPreview)]?.title = snapshot.phase == .failed ? "다시 읽기" : "읽기 시작"
    updateControls()
    if previousMessage != snapshot.message {
      NSAccessibility.post(element: status, notification: .valueChanged)
    }
  }
  func enabled(_ action: Selector?) -> Bool {
    guard let action else { return true }
    if [#selector(addProject), #selector(toggleLogin)].contains(action) {
      return !mutating && snapshot?.isBusy != true
    }
    if [#selector(openPreview), #selector(start), #selector(restart), #selector(save)].contains(
      action)
    {
      return active != nil && !mutating && snapshot?.isBusy != true
    }
    if action == #selector(stop) { return active != nil && !mutating }
    if [#selector(copyURL), #selector(openLogs)].contains(action) { return active != nil }
    return true
  }
  func updateControls() {
    picker.isEnabled = !mutating
    login.isEnabled = enabled(#selector(toggleLogin))
    for field in fields.values { field.isEnabled = active != nil && !mutating }
    for (action, control) in controls { control.isEnabled = enabled(action) }
  }
  func validateMenuItem(_ menuItem: NSMenuItem) -> Bool { enabled(menuItem.action) }
  func mutate<T>(
    _ message: String, work: @escaping () throws -> T, success: @escaping (T) -> Void
  ) {
    guard !mutating else { return }
    mutating = true
    updateControls()
    session.performMutation(message: message, work: work) { [weak self] result in
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
    }
  }
  @objc func showWindow() {
    window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
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
    guard !mutating else { return }
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
    updated.root = value("root")
    updated.entry = value("entry")
    updated.fonts = value("fonts").split(separator: ";").map {
      $0.trimmingCharacters(in: .whitespaces)
    }.filter { !$0.isEmpty }
    updated.packages = value("packages")
    updated.port = port
    updated.publicURL = value("publicURL")
    return updated
  }
  func saveProfile(readAfterSaving: Bool) {
    guard !mutating else { return }
    let intent = readingIntent
    do {
      let updated = try editedProfile()
      if updated == active {
        if readAfterSaving { session.read() }
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
          if readAfterSaving && self.readingIntent == intent { self.session.read() }
        })
    } catch { session.reportFailure(error) }
  }
  @objc func save() { saveProfile(readAfterSaving: false) }
  func perform(_ action: String) {
    guard !mutating else { return }
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
  @objc func copyURL() {
    if let p = active {
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(p.url, forType: .string)
    }
  }
  @objc func openLogs() {
    guard let p = active else { return }
    let file = environment.logRoot.appendingPathComponent("\(p.id).err.log")
    if FileManager.default.fileExists(atPath: file.path) {
      NSWorkspace.shared.open(file)
    } else {
      NSWorkspace.shared.open(environment.logRoot)
    }
  }
  @objc func revealSettings() {
    NSWorkspace.shared.activateFileViewerSelecting([
      environment.support.appendingPathComponent("profiles.json")
    ])
  }
  @objc func toggleLogin() {
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
    NSApp.orderFrontStandardAboutPanel(options: [
      .applicationName: FlowIdentity.appName,
      .credits: NSAttributedString(
        string:
          "Personal Typst workspace. Powered by Tinymist and Typst. Apache License 2.0.\nInstalled releases and recovery: see the bundled User Guide."
      ),
    ])
  }
  @objc func guide() {
    if let url = Bundle.main.url(forResource: "UserGuide", withExtension: "pdf") {
      NSWorkspace.shared.open(url)
    }
  }
  @objc func quit() { NSApp.terminate(nil) }
}
