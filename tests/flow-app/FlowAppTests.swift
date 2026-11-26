import AppKit
import Foundation

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
  if !condition() { fatalError(message) }
}

private func waitUntil(_ message: String, _ predicate: () -> Bool) {
  let deadline = Date().addingTimeInterval(5)
  while !predicate() && Date() < deadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.005))
  }
  check(predicate(), message)
}

private final class Services: ProjectControlling {
  private let lock = NSLock()
  private var running: [String: Int] = [:]
  private var commands: [String] = []
  func jobPID(_ label: String) -> Int? {
    check(!Thread.isMainThread, "PID observation blocked the UI thread")
    lock.lock()
    defer { lock.unlock() }
    return running[label]
  }
  func control(_ action: String, _ profile: Profile) throws {
    check(!Thread.isMainThread, "service command blocked the UI thread")
    lock.lock()
    defer { lock.unlock() }
    commands.append(action)
    running[profile.label] = action == "stop" ? nil : 712
  }
  var actions: [String] {
    lock.lock()
    defer { lock.unlock() }
    return commands
  }
}

private final class BlockingStore: SettingsPersisting {
  let store: SettingsStore
  let entered = DispatchSemaphore(value: 0)
  let release = DispatchSemaphore(value: 0)
  var blocked = false
  init(_ store: SettingsStore) { self.store = store }
  func save(_ settings: Settings) throws {
    if blocked {
      entered.signal()
      _ = release.wait(timeout: .now() + 5)
    }
    try store.save(settings)
  }
}

private func allDescendants(of view: NSView) -> [NSView] {
  [view] + view.subviews.flatMap { allDescendants(of: $0) }
}

@main
struct FlowAppTests {
  @MainActor static func main() throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.prohibited)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data("Hello".utf8).write(to: root.appendingPathComponent("main.typ"))
    let profile = Profile(
      id: "test", name: "Reading fixture", root: root.path, entry: "main.typ",
      fonts: [], packages: "", port: 23625, publicURL: "", label: "test.reading")
    var other = profile
    other.id = "other"
    other.name = "Other project"
    other.port = 23626
    other.label = "test.other"
    let environment = AppEnvironment(
      variables: ["FLOW_DATA_DIR": root.appendingPathComponent("data").path],
      userHome: root, executable: root.appendingPathComponent("flow"))
    let store = SettingsStore(directory: environment.support)
    let storage = BlockingStore(store)
    let services = Services()
    let delegate = FlowApp(
      environment: environment,
      projectService: ProjectService(store: storage, launchAgents: services))
    var opens: [URL] = []
    var probes: [(PreviewReadiness) -> Void] = []
    delegate.session = ReadingSessionController(
      launchAgents: services,
      onChange: { [weak delegate] in delegate?.render($0) },
      openBrowser: {
        opens.append($0)
        return true
      },
      probe: { _, completion in
        probes.append(completion)
        return {}
      },
      startupTimeout: 2, retryInterval: 0.01)
    delegate.settings = Settings(selectedID: profile.id, profiles: [profile, other])
    try store.save(delegate.settings)
    delegate.buildWindow()
    delegate.populate()
    defer {
      delegate.session.dispose()
      delegate.settingsWindow?.close()
      delegate.window.close()
    }
    waitUntil("initial stopped status") { delegate.snapshot?.phase == .stopped }

    switch CommandLine.arguments[1] {
    case "ide-directory-add":
      let manager = FileManager.default
      let packages = root.appendingPathComponent("custom-packages")
      let catalog = packages.appendingPathComponent("local/project-references/0.1.0/projects.json")
      try manager.createDirectory(at: catalog.deletingLastPathComponent(), withIntermediateDirectories: true)
      let catalogJSON = """
        {"schema":1,"projects":{
          "my-book":{"title":"Book","pdf_url":"https://example.test/book.pdf","references":{},"ambiguous_labels":[]},
          "ambiguous-book":{"title":"Book","pdf_url":"https://example.test/book.pdf","references":{},"ambiguous_labels":[]},
          "ambiguous_book":{"title":"Book","pdf_url":"https://example.test/book.pdf","references":{},"ambiguous_labels":[]}
        }}
        """
      try Data(catalogJSON.utf8).write(to: catalog)
      delegate.settings.profiles[0].packages = packages.path
      let mainDirectory = root.appendingPathComponent("My_Book")
      try manager.createDirectory(at: mainDirectory, withIntermediateDirectories: true)
      try Data().write(to: mainDirectory.appendingPathComponent("main.typ"))
      try Data().write(to: mainDirectory.appendingPathComponent("other.typ"))
      delegate.registerProjectSelection(at: mainDirectory, chooseEntry: { _, _ in fatalError("main.typ prompted") })
      waitUntil("main directory registered") { !delegate.mutating && delegate.active?.root == mainDirectory.path }
      check(delegate.active?.entry == "main.typ" && delegate.active?.projectRefKey == "my-book", "main entry or key missing")
      let savedMain = try store.load()
      let savedMainProfile = try savedMain.profile(delegate.settings.selectedID)
      check(savedMainProfile.projectRefKey == "my-book", "key not persisted")

      let ambiguous = root.appendingPathComponent("Ambiguous Book")
      try manager.createDirectory(at: ambiguous, withIntermediateDirectories: true)
      try Data().write(to: ambiguous.appendingPathComponent("a.typ"))
      try Data().write(to: ambiguous.appendingPathComponent("b.typ"))
      // Use the custom catalog again after the newly created profile becomes active.
      delegate.settings.profiles[delegate.settings.profiles.count - 1].packages = packages.path
      var pickerCalled = false
      delegate.registerProjectSelection(at: ambiguous, chooseEntry: { directory, candidates in
        pickerCalled = true
        check(directory == ambiguous && candidates == ["a.typ", "b.typ"], "incorrect picker inputs")
        return "b.typ"
      })
      waitUntil("selected directory registered") { !delegate.mutating && delegate.active?.root == ambiguous.path }
      check(pickerCalled && delegate.active?.entry == "b.typ" && delegate.active?.projectRefKey == nil, "selection or ambiguous key incorrect")
      let beforeCancel = try store.load()
      func sameSettings(_ lhs: Settings, _ rhs: Settings) -> Bool {
        lhs.selectedID == rhs.selectedID && lhs.profiles == rhs.profiles
      }
      delegate.registerProjectSelection(at: ambiguous, chooseEntry: { _, _ in nil })
      let afterCancel = try store.load()
      check(!delegate.mutating && sameSettings(delegate.settings, beforeCancel), "cancel changed settings")
      check(sameSettings(afterCancel, beforeCancel), "cancel persisted settings")

      let empty = root.appendingPathComponent("empty")
      try manager.createDirectory(at: empty, withIntermediateDirectories: true)
      delegate.registerProjectSelection(at: empty)
      check(delegate.snapshot?.phase == .failed && delegate.detail.stringValue.contains(".typ"), "empty directory failure missing")
      let afterEmpty = try store.load()
      check(sameSettings(afterEmpty, beforeCancel) && sameSettings(delegate.settings, beforeCancel), "empty directory changed settings")

      let sole = root.appendingPathComponent("sole")
      try manager.createDirectory(at: sole, withIntermediateDirectories: true)
      let soleFile = sole.appendingPathComponent("only.typ")
      try Data().write(to: soleFile)
      delegate.registerProjectSelection(at: sole, chooseEntry: { _, _ in fatalError("sole entry prompted") })
      waitUntil("sole directory registered") { !delegate.mutating && delegate.active?.root == sole.path }
      check(delegate.active?.entry == "only.typ", "sole entry missing")
      let fileDirectory = root.appendingPathComponent("file-project")
      try manager.createDirectory(at: fileDirectory, withIntermediateDirectories: true)
      let file = fileDirectory.appendingPathComponent("document.typ")
      try Data().write(to: file)
      delegate.registerProjectSelection(at: file)
      waitUntil("file registered") { !delegate.mutating && delegate.active?.root == fileDirectory.path }
      check(delegate.active?.entry == "document.typ" && delegate.active?.projectRefKey == nil, "file registration changed")
      let savedFile = try store.load()
      check(sameSettings(savedFile, delegate.settings), "file registration not persisted")
    case "timeline-owner":
      let timeline = NativeStartupTimeline(root: root)
      var owner: NSObject? = NSObject()
      timeline.owner = owner
      owner = nil
      check(timeline.owner == nil, "timeline retained its weak owner")
      timeline.record("released-owner")
    case "duplicate-names":
      delegate.settings.profiles[1].name = profile.name
      delegate.populate()
      check(delegate.picker.numberOfItems == 2, "duplicate labels dropped a valid profile")
      delegate.picker.selectItem(at: 1)
      check(NSApp.sendAction(delegate.picker.action!, to: delegate.picker.target, from: delegate.picker), "profile target/action")
      waitUntil("same-name profile selected by exact index") { !delegate.mutating && delegate.active?.id == other.id }
    case "read":
      delegate.controls[#selector(FlowApp.openPreview)]!.performClick(nil)
      waitUntil("read requested a document") { probes.count == 1 }
      check(opens.isEmpty, "browser opened before document was ready")
      check(!delegate.controls[#selector(FlowApp.openPreview)]!.isEnabled, "duplicate read enabled")
      check(delegate.controls[#selector(FlowApp.stop)]!.isEnabled, "stop unavailable while reading")
      check(delegate.picker.isEnabled, "project switch unavailable while reading")
      probes[0](.ready)
      waitUntil("browser opened after readiness") { opens.count == 1 }
      check(delegate.status.stringValue.contains("준비"), "missing ready state")
      check(services.actions == ["start"], "read created duplicate commands")
    case "switch":
      delegate.openPreview()
      waitUntil("first probe") { probes.count == 1 }
      delegate.picker.selectItem(at: 1)
      delegate.selectProfile()
      probes[0](.ready)
      waitUntil("selection saved asynchronously") {
        !delegate.mutating && delegate.active?.id == other.id
      }
      check(opens.isEmpty, "old project opened a browser")
      let saved = try store.load()
      check(saved.selectedID == other.id, "new selection was not persisted")
    case "save-and-read":
      delegate.fields["name"]!.stringValue = "Edited reading fixture"
      delegate.openPreview()
      waitUntil("settings then read") { !probes.isEmpty }
      check(delegate.active?.name == "Edited reading fixture", "Read ignored edited settings")
      let saved = try store.load()
      check(saved.profiles[0].name == "Edited reading fixture", "settings not persisted")
      probes.last?(.ready)
      waitUntil("ready opens saved project") { opens.count == 1 }
    case "failure":
      delegate.fields["port"]!.stringValue = "invalid"
      delegate.openPreview()
      check(delegate.snapshot?.phase == .failed, "invalid configuration not shown inline")
      check(delegate.detail.stringValue.contains("포트"), "failure cause missing")
      check(delegate.controls[#selector(FlowApp.openPreview)]!.title == "다시 읽기", "retry missing")
      check(services.actions.isEmpty, "invalid settings changed service")
      delegate.fields["port"]!.stringValue = String(profile.port)
      delegate.openPreview()
      waitUntil("retry requested document") { !probes.isEmpty }
      probes.last?(.failed("컴파일 실패 테스트"))
      waitUntil("compile failure visible") { delegate.snapshot?.phase == .failed }
      check(delegate.detail.stringValue.contains("컴파일 실패"), "compile failure cause lost")
      check(opens.isEmpty, "failed document opened")
    case "sleep-save":
      storage.blocked = true
      delegate.fields["name"]!.stringValue = "Saved through sleep"
      delegate.openPreview()
      var entered = false
      waitUntil("settings save started") {
        if !entered { entered = storage.entered.wait(timeout: .now()) == .success }
        return entered
      }
      delegate.sleepChanged(true)
      delegate.sleepChanged(false)
      storage.release.signal()
      waitUntil("settings completion delivered after wake") { !delegate.mutating }
      check(delegate.active?.name == "Saved through sleep", "saved settings lost on wake")
      check(services.actions.isEmpty, "sleep revived an earlier read intention")
      check(opens.isEmpty, "sleep during save opened a browser after wake")
    case "environment":
      var sleepEvents: [Bool] = []
      var powerEvents: [Bool] = []
      let monitor = NativeReadingEnvironment(
        onSleep: { sleepEvents.append($0) },
        onNetwork: { _ in }, onPower: { powerEvents.append($0) })
      monitor.start()
      NSWorkspace.shared.notificationCenter.post(
        name: NSWorkspace.willSleepNotification, object: nil)
      NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
      waitUntil("native wake/sleep delivery") { sleepEvents == [true, false] }
      check(!powerEvents.isEmpty, "power policy not initialized")
      monitor.dispose()
      NSWorkspace.shared.notificationCenter.post(
        name: NSWorkspace.willSleepNotification, object: nil)
      RunLoop.current.run(until: Date().addingTimeInterval(0.02))
      check(sleepEvents == [true, false], "disposed lifecycle observer fired")
    case "minimal-home-layout":
      let homeRoot = delegate.window.contentView!
      let views = allDescendants(of: homeRoot)
      check(!views.contains { $0 is NSTabView }, "legacy NSTabView still present on home")
      check(views.contains { $0 is NativeBrandMarkView }, "brand mark missing on home")
      let labels = views.compactMap { ($0 as? NSTextField)?.stringValue }
      check(labels.contains(LagrangianIdentity.appName), "Lagrangian title missing on home")
      check(!labels.contains { $0.contains("한 흐름으로") }, "legacy subtitle still present on home")
      let buttonTitles = views.compactMap { ($0 as? NSButton)?.title }
      check(!buttonTitles.contains("설정 저장"), "save button must not exist on home")
      check(!buttonTitles.contains("설정 파일 보기"), "reveal settings button must not exist on home")
      check(views.contains { $0.identifier?.rawValue == "home.addProject" }, "top-right add button missing")
      check(views.contains { $0.identifier?.rawValue == "home.openSettings" }, "top-right gear button missing")
      check(delegate.pathCaption.lineBreakMode == .byTruncatingHead, "path caption must truncate head")
      check(delegate.pathCaption.stringValue == profile.path(profile.entry), "path caption mismatch")
      check(delegate.login.title == "로그인 시 앱 열기", "bottom-left login label mismatch")
      check(delegate.settingsFooterButton.title == "프로젝트 설정…", "bottom-right settings link mismatch")
      let projectCard = views.first { $0.identifier?.rawValue == "home.projectCard" }!
      let cardButtons = allDescendants(of: projectCard).compactMap { ($0 is NSPopUpButton) ? nil : ($0 as? NSButton) }.map(\.title)
      check(cardButtons == ["읽기 시작", "오프라인 문서", "•••"], "project card must have exactly 3 action controls")
      check(allDescendants(of: projectCard).compactMap { $0 as? NSPopUpButton }.count == 1, "project card must have one project selector")
      let projectMenu = delegate.projectOverflowMenu()
      let projectMenuSelectors = projectMenu.items.compactMap(\.action)
      check(projectMenuSelectors.contains(#selector(FlowApp.copyURL)), "project overflow missing copyURL")
      check(projectMenuSelectors.contains(#selector(FlowApp.revealSettings)), "project overflow missing revealSettings")
      check(projectMenuSelectors.contains(#selector(FlowApp.addProject)), "project overflow missing addProject")
      delegate.window.setContentSize(NSSize(width: 640, height: 480))
      homeRoot.layoutSubtreeIfNeeded()
      let visibleButtons = views.compactMap { $0 as? NSButton }.filter { !$0.isHidden }
      for button in visibleButtons {
        let frame = button.convert(button.bounds, to: homeRoot)
        check(homeRoot.bounds.contains(frame), "control clipped at 640px width: \(button.identifier?.rawValue ?? button.title)")
      }
      for i in 0..<visibleButtons.count {
        for j in (i + 1)..<visibleButtons.count {
          let a = visibleButtons[i].convert(visibleButtons[i].bounds, to: homeRoot)
          let b = visibleButtons[j].convert(visibleButtons[j].bounds, to: homeRoot)
          check(!a.intersects(b), "controls overlap at 640px width")
        }
      }
    case "service-card-states":
      var openedLinks: [URL] = []
      delegate.openExternalURL = { url in openedLinks.append(url); return true }
      let startBtn = delegate.controls[#selector(FlowApp.start)]!
      let logsBtn = delegate.controls[#selector(FlowApp.openLogs)]!
      let extBtn = delegate.controls[#selector(FlowApp.openExternalPreview)]!
      let stopBtn = delegate.controls[#selector(FlowApp.stop)]!
      check(delegate.serviceStatusLabel.stringValue == "프리뷰 서비스 · 중지됨", "stopped status label mismatch")
      check(!delegate.serviceAddressLabel.isHidden && delegate.serviceAddressLabel.stringValue == "127.0.0.1:23625", "stopped address text mismatch")
      check(delegate.serviceAddressLink.isHidden, "stopped state must not show clickable address link")
      check(!startBtn.isHidden && !logsBtn.isHidden, "stopped state must show start and logs")
      check(extBtn.isHidden && stopBtn.isHidden && delegate.serviceOverflowButton.isHidden, "stopped state must hide running-only controls")

      startBtn.performClick(nil)
      waitUntil("service started probe") { probes.count == 1 }
      probes[0](.ready)
      waitUntil("service running settled") { delegate.snapshot?.phase == .ready && !delegate.snapshot!.isBusy }
      check(delegate.serviceStatusLabel.stringValue == "프리뷰 서비스 · 실행 중", "running status label mismatch")
      check(delegate.serviceAddressLabel.isHidden, "running state must hide static address label")
      check(!delegate.serviceAddressLink.isHidden && delegate.serviceAddressLink.title == "127.0.0.1:23625", "running address link mismatch")
      check(startBtn.isHidden && logsBtn.isHidden, "running state must hide stopped-only controls")
      check(!extBtn.isHidden && !stopBtn.isHidden && !delegate.serviceOverflowButton.isHidden, "running state must show external reader, stop, and overflow")
      let serviceMenu = delegate.serviceOverflowMenu()
      let serviceSelectors = serviceMenu.items.compactMap(\.action)
      check(serviceSelectors == [#selector(FlowApp.restart), #selector(FlowApp.copyURL), #selector(FlowApp.openLogs)], "service overflow menu mismatch")
      delegate.serviceAddressLink.performClick(nil)
      check(openedLinks.map(\.absoluteString) == [profile.url], "address link did not open project URL")

      stopBtn.performClick(nil)
      waitUntil("service returned to stopped") { delegate.snapshot?.phase == .stopped }
      check(!startBtn.isHidden && !logsBtn.isHidden && extBtn.isHidden && stopBtn.isHidden && delegate.serviceOverflowButton.isHidden, "stop did not restore stopped card state")
    case "separated-settings-sheet":
      check(!delegate.isSettingsPresented, "settings sheet should start closed")
      check(delegate.enabled(#selector(FlowApp.showSettings)), "showSettings should be enabled with active project")
      let saveButton = delegate.controls[#selector(FlowApp.save)]!
      let revealButton = delegate.controls[#selector(FlowApp.revealSettings)]!
      let closeButton = delegate.controls[#selector(FlowApp.closeSettings)]!
      let browseButton = delegate.controls[#selector(FlowApp.browseRoot)]!
      guard let sheetRoot = delegate.settingsWindow?.contentView else { fatalError("settings window missing") }
      let sheetViews = allDescendants(of: sheetRoot)
      let homeViews = allDescendants(of: delegate.window.contentView!)
      check(!homeViews.contains(saveButton), "save button must live only in settings sheet")
      check(sheetViews.contains(saveButton) && sheetViews.contains(revealButton) && sheetViews.contains(closeButton) && sheetViews.contains(browseButton), "settings sheet controls missing")
      check(["name", "root", "entry", "fonts", "packages", "port", "publicURL"].allSatisfy { key in
        delegate.fields[key].map { sheetViews.contains($0) } == true
      }, "all 7 profile fields must live in settings sheet")

      check(NSApp.sendAction(#selector(FlowApp.showSettings), to: delegate, from: nil), "showSettings action failed")
      check(delegate.isSettingsPresented, "showSettings did not open settings sheet")
      check(!delegate.window.isVisible && NSApp.activationPolicy() == .prohibited, "showSettings violated offscreen policy")

      let homePhaseBeforeSettingsError = delegate.snapshot?.phase
      delegate.fields["port"]!.stringValue = "bad-port"
      saveButton.performClick(nil)
      check(delegate.isSettingsPresented, "invalid save should keep settings sheet open")
      check(!delegate.settingsStatus.isHidden && delegate.settingsStatus.stringValue.contains("포트"), "settings sheet inline error missing")
      check(delegate.snapshot?.phase == homePhaseBeforeSettingsError && delegate.snapshot?.phase != .failed,
            "settings sheet validation error polluted Home snapshot.phase")

      delegate.fields["port"]!.stringValue = String(profile.port)
      delegate.fields["entry"]!.stringValue = "missing-entry.typ"
      saveButton.performClick(nil)
      waitUntil("async settings validation failure") { !delegate.mutating && !delegate.settingsStatus.isHidden }
      check(delegate.isSettingsPresented, "async save error should keep settings sheet open")
      check(delegate.settingsStatus.stringValue.contains("진입 파일"), "async settings error missing")
      waitUntil("home snapshot restored without failure") { delegate.snapshot?.phase == .stopped }
      check(delegate.snapshot?.phase != .failed, "async settings mutation error polluted Home snapshot.phase")

      delegate.fields["name"]!.stringValue = "Cancelled unsaved name"
      closeButton.performClick(nil)
      check(!delegate.isSettingsPresented, "close button should dismiss settings sheet after error")
      check(delegate.fields["name"]!.stringValue == profile.name, "cancelled name edit was not discarded")
      check(delegate.fields["entry"]!.stringValue == profile.entry, "cancelled entry edit was not discarded")
      check(delegate.settingsStatus.isHidden && delegate.settingsStatus.stringValue.isEmpty, "settingsStatus not cleared on cancel")

      delegate.openPreview()
      waitUntil("openPreview after cancelled settings") { probes.count == 1 }
      check(delegate.active?.name == profile.name, "cancelled settings edit leaked into openPreview")
      probes[0](.ready)
      waitUntil("openPreview ready after cancelled settings") { opens.count == 1 }
      delegate.stop()
      waitUntil("stopped after cancelled settings check") { delegate.snapshot?.phase == .stopped }
      probes.removeAll()
      opens.removeAll()

      delegate.showSettings()
      delegate.fields["port"]!.stringValue = String(profile.port)
      delegate.fields["name"]!.stringValue = "Sheet updated"
      saveButton.performClick(nil)
      waitUntil("settings saved from sheet") { !delegate.mutating && delegate.active?.name == "Sheet updated" }
      let saved = try store.load()
      check(saved.profiles[0].name == "Sheet updated", "sheet save did not persist")
      check(!delegate.isSettingsPresented, "successful save should close settings sheet")

      let longDir = root.appendingPathComponent(String(repeating: "very-long-segment-", count: 7))
      try FileManager.default.createDirectory(at: longDir, withIntermediateDirectories: true)
      try Data("Hello".utf8).write(to: longDir.appendingPathComponent("main.typ"))
      delegate.settings.profiles[0].root = longDir.path
      delegate.populate()
      delegate.showSettings()
      check(delegate.isSettingsPresented, "reopening settings sheet failed")
      delegate.settingsStatus.stringValue = "1줄 오류 메시지: 경로 확인 필요\n2줄 오류 메시지: 프로젝트 설정을 다시 확인하세요\n3줄 오류 메시지: 포트와 진입 파일을 확인하세요"
      delegate.settingsStatus.isHidden = false
      sheetRoot.layoutSubtreeIfNeeded()
      check(delegate.settingsWindow!.frame.width <= 580, "settings sheet width blew up: \(delegate.settingsWindow!.frame.width)")
      check(sheetRoot.bounds.width <= 580, "settings sheet content width blew up: \(sheetRoot.bounds.width)")
      let statusFrame = delegate.settingsStatus.convert(delegate.settingsStatus.bounds, to: sheetRoot)
      for button in [revealButton, closeButton, saveButton] {
        let frame = button.convert(button.bounds, to: sheetRoot)
        check(sheetRoot.bounds.contains(frame), "settings button clipped: \(button.identifier?.rawValue ?? button.title)")
        check(!frame.intersects(statusFrame), "settings button overlapped 3-line status")
      }
      closeButton.performClick(nil)
      check(!delegate.isSettingsPresented, "close button did not dismiss settings sheet")

      delegate.settings = Settings(selectedID: "", profiles: [])
      delegate.populate()
      check(!delegate.enabled(#selector(FlowApp.showSettings)), "showSettings must be disabled when active == nil")
      delegate.showSettings()
      check(!delegate.isSettingsPresented, "showSettings must not open when active == nil")
    case "render":
      delegate.session.reportFailure(
        FlowError(
          message:
            "문서 컴파일에 실패했습니다. 진입 파일과 로그를 확인한 뒤 다시 읽기를 시작하세요."))
      let view = delegate.window.contentView!
      view.layoutSubtreeIfNeeded()
      let image = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
      view.cacheDisplay(in: view.bounds, to: image)
      try image.representation(using: .png, properties: [:])!.write(
        to: URL(fileURLWithPath: CommandLine.arguments[2]))
    default: fatalError("Unknown scenario")
    }
    print("passed")
  }
}
