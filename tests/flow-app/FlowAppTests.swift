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

private func verifyOverflow(_ app: FlowApp) {
  let items = app.overflowMenu().items
  check(items.map(\.title) == ["미리보기 재시작", "미리보기 주소 복사", "로그 보기", "", "에디터 연결…", "", "설정 파일 보기", "사용·업데이트·복구 안내"], "unified overflow grouping")
  check(items.compactMap(\.action) == [#selector(FlowApp.restart), #selector(FlowApp.copyPreviewAddress), #selector(FlowApp.openLogs), #selector(FlowApp.connectEditor), #selector(FlowApp.revealSettings), #selector(FlowApp.guide)], "overflow actions")
  check(items.filter { $0.action != nil }.allSatisfy { $0.target === app }, "overflow target wiring")
}

private func verifyStatusMenu(_ app: FlowApp) {
  let items = app.statusItem.menu!.items
  check(items.first?.title == (app.active.map { "\($0.name) · " + (app.snapshot?.pid != nil ? "실행 중" : "중지됨") } ?? "프로젝트 없음"), "menu status summary")
  check(items.first?.isEnabled == false && items.first?.action == nil, "status line must be disabled")
  check(items.filter(\.isSeparatorItem).count == 4, "menu groups")
  check(items.dropFirst().map(\.title) == [
    "", "홈 열기", "읽기 시작", "웹 브라우저에서 열기", "오프라인 문서 열기", "",
    app.snapshot?.pid != nil ? "미리보기 중지" : "미리보기 시작", "미리보기 재시작", "에디터 연결…", "미리보기 주소 복사", "로그 보기", "",
    "프로젝트 설정…", "로그인 시 자동 실행", "사용·업데이트·복구 안내", "Lagrangian 정보", "", "Lagrangian 종료 (미리보기 유지)",
  ], "Korean status menu order")
  for (selector, key) in [(#selector(FlowApp.showWindow), "0"), (#selector(FlowApp.openPreview), "o"), (#selector(FlowApp.showSettings), ","), (#selector(FlowApp.quit), "q")] {
    let item = items.first { $0.action == selector }
    check(item?.keyEquivalent == key && item?.target === app, "menu shortcut/target")
  }
  let login = items.first { $0.action == #selector(FlowApp.toggleLogin) }!
  check(login.title == "로그인 시 자동 실행" && login.state == (app.loginEnabled ? .on : .off), "login menu state")
  check(app.validateMenuItem(login) == app.enabled(#selector(FlowApp.toggleLogin)), "login menu permission")
}

private func verifyMinimalHome(_ app: FlowApp, profile: Profile) {
  let root = app.window.contentView!
  root.layoutSubtreeIfNeeded()
  let views = allDescendants(of: root)
  check(app.window.titleVisibility == .hidden && app.window.titlebarAppearsTransparent, "Home chrome")
  check(app.window.frame.size == NSSize(width: 452, height: 228), "compact Home geometry")
  let cards = views.compactMap { $0 as? NativeDesignSurface }.filter { $0.role == .panel }
  check(cards.count == 1 && cards[0].identifier?.rawValue == "home.noteCard", "Home needs one Note Card")
  check(!views.contains { $0 is NSTabView }, "legacy tabs")
  let labels = views.compactMap { $0 as? NSTextField }.filter { !$0.isHiddenOrHasHiddenAncestor }.map(\.stringValue)
  check(!labels.contains { $0.contains(profile.root) || $0.contains(profile.url) || $0.contains("127.0.0.1") || $0.contains("https://") }, "raw Home path/address")
  check(app.picker.toolTip == "\(profile.name)\n\(profile.path(profile.entry))", "project tooltip")
  let buttons = views.compactMap { $0 as? NSButton }.filter { !($0 is NSPopUpButton) && !$0.isHiddenOrHasHiddenAncestor }
  check(buttons.filter { !$0.title.isEmpty }.map(\.title) == ["읽기"], "only primary action has a text label")
  let read = app.controls[#selector(FlowApp.openPreview)] as! NativeDesignButton
  check(read.keyEquivalent == "\r" && read.symbolName == "book", "primary icon/Return")
  check(allDescendants(of: cards[0]).filter { $0 is NSPopUpButton }.count == 1, "one popup")
  for (selector, size, symbol, tooltip) in [
    (#selector(FlowApp.addProject), CGFloat(28), "plus", "프로젝트 추가"),
    (#selector(FlowApp.showSettings), 28, "gearshape", "프로젝트 설정 (⌘,)"),
    (#selector(FlowApp.openExternalPreview), 32, "globe", "웹 브라우저에서 열기"),
    (#selector(FlowApp.copyPreviewAddress), 32, "link", "미리보기 주소 복사"),
    (#selector(FlowApp.openOffline), 32, "doc.text", "오프라인 문서 열기"),
  ] {
    let button = app.controls[selector] as! NativeDesignButton
    check(button.frame.size == NSSize(width: size, height: size), "icon target dimensions")
    check(button.designRole == .ghost && button.symbolName == symbol, "ghost SF Symbol")
    check(button.toolTip == tooltip && button.accessibilityLabel() == tooltip, "Korean tooltip/AX")
    check(button.target === app && button.action == selector, "icon target/action")
    button.preferencesOverride = .init(theme: .light)
    check(button.paint.edge.alphaComponent == 0 && button.paint.fill.alphaComponent == 0, "ghost rest paint")
    button.mouseEntered(with: NSEvent())
    check(button.paint.fill.alphaComponent > 0 || !button.isEnabled, "hover tint")
    button.mouseExited(with: NSEvent())
    button.preferencesOverride = .init(theme: .light, increasedContrast: true)
    check(button.paint.edge.alphaComponent == 1 && button.paint.lineWidth == 1, "Increase Contrast hairline")
    button.preferencesOverride = nil
  }
  check(app.overflowButton.symbolName == "ellipsis" && app.overflowButton.toolTip == "더 보기", "single overflow")
  verifyOverflow(app)
  for button in buttons {
    check(root.bounds.contains(button.convert(button.bounds, to: root)), "clipped compact control")
    for other in buttons where other !== button {
      check(!button.convert(button.bounds, to: root).intersects(other.convert(other.bounds, to: root)), "overlapping compact controls")
    }
  }
  let markFrame = app.brandMark.convert(app.brandMark.bounds, to: root)
  check(abs(markFrame.midX - root.bounds.midX) < 0.5, "centered brand mark")
}

@main
struct FlowAppTests {
  static func main() throws {
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
    check(delegate.window.frame.size == NSSize(width: 452, height: 228), "initial Home frame before session snapshot")
    check(delegate.status.isHiddenOrHasHiddenAncestor, "initial Home banner must be collapsed")
    delegate.populate()
    defer {
      delegate.session.dispose()
      delegate.settingsWindow?.close()
      delegate.window.close()
    }
    waitUntil("initial stopped status") { delegate.snapshot?.phase == .stopped }

    switch CommandLine.arguments[1] {
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
      check(!delegate.serviceToggleButton.isEnabled && delegate.serviceToggleButton.symbolName == "arrow.triangle.2.circlepath", "busy service slot must be disabled")
      check(delegate.picker.isEnabled, "project switch unavailable while reading")
      probes[0](.ready)
      waitUntil("browser opened after readiness") { opens.count == 1 }
      check(delegate.brandMark.phase == .completed && delegate.status.isHiddenOrHasHiddenAncestor,
            "ready state must use brand status and collapse the banner")
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
      check(delegate.snapshot!.detail.contains("포트"), "failure cause missing")
      check(delegate.controls[#selector(FlowApp.openPreview)]!.title == "다시 읽기", "retry missing")
      check(services.actions.isEmpty, "invalid settings changed service")
      delegate.fields["port"]!.stringValue = String(profile.port)
      delegate.openPreview()
      waitUntil("retry requested document") { !probes.isEmpty }
      probes.last?(.failed("컴파일 실패 테스트"))
      waitUntil("compile failure visible") { delegate.snapshot?.phase == .failed }
      check(delegate.snapshot!.detail.contains("컴파일 실패"), "compile failure cause lost")
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
      verifyMinimalHome(delegate, profile: profile)
      delegate.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
      defer { NSStatusBar.system.removeStatusItem(delegate.statusItem) }
      delegate.buildMenu()
      delegate.render(delegate.snapshot!)
      check(delegate.statusItem.button?.title == "", "menu bar title must be empty")
      check(delegate.statusItem.button?.image?.isTemplate == true, "menu bar must use template brand image")
      check(delegate.statusItem.button?.image?.size == NSSize(width: 18, height: 18), "menu bar image size")
      verifyStatusMenu(delegate)
      let close = NSApp.windowsMenu?.items.first { $0.action == #selector(NSWindow.performClose(_:)) }
      check(close?.title == "창 닫기" && close?.keyEquivalent == "w", "standard Window close shortcut missing")
      let original = delegate.snapshot!
      let states: [(ReadingSessionPhase, Bool, Int?, NativeBrandMark.Phase, String)] = [
        (.idle, false, nil, .offline, "미리보기 중지됨"),
        (.requested, true, nil, .busy, "준비 중"),
        (.running, true, 712, .reconnecting, "준비 중"),
        (.ready, false, 712, .completed, "미리보기 실행 중"),
        (.failed, false, 712, .error, "오류"),
        (.sleeping, false, nil, .held, "미리보기 중지됨"),
      ]
      var images = Set<Data>()
      for (phase, busy, pid, brand, tooltip) in states {
        delegate.render(ReadingSessionSnapshot(profileID: profile.id, phase: phase,
          message: "raw English exception /private/project https://private.invalid", detail: profile.url, pid: pid, isBusy: busy))
        check(delegate.brandMark.phase == brand, "brand phase transition")
        check(delegate.brandMark.showsRunningIndicator == (pid != nil), "brand running indicator")
        check(delegate.brandMark.toolTip == "Lagrangian · " + tooltip, "brand tooltip transition")
        check(delegate.statusItem.button?.image?.isTemplate == true, "dynamic menu bar image lost template")
        images.insert(delegate.statusItem.button!.image!.tiffRepresentation!)
        verifyStatusMenu(delegate)
        let showBanner = busy || phase == .failed
        check(delegate.window.frame.size == NSSize(width: 452, height: showBanner ? 272 : 228), "banner-only window expansion")
        check(delegate.status.isHiddenOrHasHiddenAncestor != showBanner, "banner visibility")
        check(!delegate.status.stringValue.contains("raw English") && !delegate.status.stringValue.contains(profile.url), "Home leaked diagnostic text")
        check(delegate.controls[#selector(FlowApp.openLogs)]!.isHidden == (phase != .failed), "inline log action only on error")
      }
      check(images.count >= 4, "menu bar status cues must produce different images")
      delegate.render(original)
      delegate.settings = Settings(); delegate.populate()
      check(delegate.brandMark.phase == .idle && delegate.brandMark.toolTip == "Lagrangian · 프로젝트 없음", "empty project identity")
      verifyStatusMenu(delegate)
    case "service-card-states":
      let slot = delegate.serviceToggleButton
      let external = delegate.controls[#selector(FlowApp.openExternalPreview)]!
      let copy = delegate.controls[#selector(FlowApp.copyPreviewAddress)] as! NativeDesignButton
      check(slot.action == #selector(FlowApp.start) && slot.symbolName == "play.fill" && slot.isEnabled, "stopped slot")
      check(!external.isEnabled && !copy.isEnabled && !delegate.overflowButton.isHidden, "stopped dock availability")
      let stoppedCopy = FlowApp(environment: environment, isolated: true, fixture: root.appendingPathComponent("fixture.json"))
      stoppedCopy.settings = delegate.settings
      check(NSApp.sendAction(#selector(FlowApp.copyURL), to: stoppedCopy, from: nil), "copyURL selector")
      check(NSPasteboard(name: FlowApp.isolatedCopyBoard(home: environment.userHome)).string(forType: .string) == profile.url, "stopped fixture copies to isolated board")
      slot.performClick(nil)
      waitUntil("service started probe") { probes.count == 1 }
      check(!slot.isEnabled && slot.symbolName == "arrow.triangle.2.circlepath", "busy slot")
      probes[0](.ready)
      waitUntil("service running settled") { delegate.snapshot?.phase == .ready && !delegate.snapshot!.isBusy }
      check(slot.action == #selector(FlowApp.stop) && slot.symbolName == "stop.fill" && slot.showsRunningIndicator, "running slot")
      check(external.isEnabled && copy.isEnabled, "running dock availability")
      check(delegate.brandMark.phase == .completed && delegate.brandMark.showsRunningIndicator, "running header")
      verifyOverflow(delegate)
      let isolatedCopy = FlowApp(environment: environment, isolated: true, devIsolatedServicePreview: true)
      isolatedCopy.settings = delegate.settings; isolatedCopy.buildWindow(); isolatedCopy.populate()
      defer { isolatedCopy.session.dispose(); isolatedCopy.settingsWindow?.close(); isolatedCopy.window.close() }
      isolatedCopy.render(delegate.snapshot!)
      let privateCopy = isolatedCopy.controls[#selector(FlowApp.copyPreviewAddress)] as! NativeDesignButton
      privateCopy.performClick(nil)
      check(privateCopy.symbolName == "checkmark" && privateCopy.toolTip == "미리보기 주소 복사됨", "copy confirmation missing")
      check(NSPasteboard(name: FlowApp.isolatedCopyBoard(home: environment.userHome)).string(forType: .string) == profile.url, "copy address effect")
      waitUntil("copy confirmation resets") { privateCopy.symbolName == "link" }
      check(privateCopy.toolTip == "미리보기 주소 복사", "copy tooltip did not reset")
      slot.performClick(nil)
      waitUntil("service returned to stopped") { delegate.snapshot?.phase == .stopped }
      check(slot.action == #selector(FlowApp.start) && slot.symbolName == "play.fill" && !slot.showsRunningIndicator, "stop restores slot")
      check(!external.isEnabled && !copy.isEnabled && !delegate.overflowButton.isHidden, "stopped dock remains visible")
      check(services.actions == ["start", "stop"], "dock actions changed lifecycle")
      fallthrough
    case "editor-consent-menu":
      delegate.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
      defer { NSStatusBar.system.removeStatusItem(delegate.statusItem); delegate.nativeWindow?.dispose() }
      delegate.buildMenu()
      let control = root.appendingPathComponent("editor-control")
      let descriptor = root.appendingPathComponent("editor.json")
      try Data().write(to: control)
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: control.path)
      let value: [String: Any] = ["address": "fixture", "executable": "/bin/sh", "ownerPID": ProcessInfo.processInfo.processIdentifier, "controlFile": control.path]
      try JSONSerialization.data(withJSONObject: value).write(to: descriptor)
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: descriptor.path)
      var finished = false
      var connected = false
      Task { @MainActor in
        connected = (try? await delegate.connectEditor(descriptor: descriptor, for: profile, consent: { true })) == true
        finished = true
      }
      waitUntil("editor consent") { finished }
      check(connected, "editor consent accepted")
      var scopeRequests = 0
      var attachRequests: [[String]] = []
      delegate.managedResolver = NativeReaderManagedResolver(attach: { args in
        if args.contains("--native-editor-scope") {
          await MainActor.run { scopeRequests += 1 }
        }
        if args.contains("--attach") {
          await MainActor.run { attachRequests.append(args) }
        }
        throw NativeReaderOperationFailure.unavailable
      }, network: .urlSession())
      func checkEditorMenu(_ action: Selector, _ title: String) {
        check(delegate.overflowMenu().items.contains { $0.action == action && $0.title == title }, "overflow consent state")
        check(delegate.statusItem.menu!.items.contains { $0.action == action && $0.title == title }, "menubar consent state")
      }
      checkEditorMenu(#selector(FlowApp.disconnectEditor), "에디터 연결 해제")
      for cancelled in [false, true] {
        if cancelled {
          // This resolver deliberately fails every scope request; reconnect the
          // local consent before restoring it for the second close path.
          let failingResolver = delegate.managedResolver
          delegate.managedResolver = nil
          finished = false; connected = false
          Task { @MainActor in
            connected = (try? await delegate.connectEditor(descriptor: descriptor, for: profile, consent: { true })) == true
            finished = true
          }
          waitUntil("renewed editor consent") { finished }
          check(connected, "renewed editor consent accepted")
          delegate.managedResolver = failingResolver
        }
        let beforeRead = scopeRequests
        let cancelRead = delegate.readNative(profile, progress: { _ in })
        checkEditorMenu(#selector(FlowApp.disconnectEditor), "에디터 연결 해제")
        waitUntil("editor resolution") { scopeRequests > beforeRead }
        if cancelled { cancelRead() }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        let beforeClose = scopeRequests
        delegate.nativeWindow!.hostWindow.window!.close()
        waitUntil("reader consent revoked") {
          scopeRequests > beforeClose && delegate.statusItem.menu!.items.contains { $0.action == #selector(FlowApp.connectEditor) }
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        check(scopeRequests == beforeClose + 1, "reader close revoked editor consent more than once")
        checkEditorMenu(#selector(FlowApp.connectEditor), "에디터 연결…")
        let beforeReopen = attachRequests.count
        let reopen = delegate.readNative(profile, progress: { _ in })
        waitUntil("reader reopens without editor consent") { attachRequests.count > beforeReopen }
        check(!attachRequests.last!.contains("--native-editor-consent") && !attachRequests.last!.contains("--editor-server"), "closed reader retained editor authority")
        checkEditorMenu(#selector(FlowApp.connectEditor), "에디터 연결…")
        reopen()
      }
    case "separated-settings-sheet":
      check(!delegate.isSettingsPresented, "settings sheet should start closed")
      check(delegate.enabled(#selector(FlowApp.showSettings)), "showSettings should be enabled with active project")
      let saveButton = delegate.controls[#selector(FlowApp.save)]!
      let revealButton = delegate.controls[#selector(FlowApp.revealSettings)]!
      let closeButton = delegate.controls[#selector(FlowApp.closeSettings)]!
      let browseButton = delegate.controls[#selector(FlowApp.browseRoot)]!
      guard let sheetRoot = delegate.settingsWindow?.contentView else { fatalError("settings window missing") }
      let sheetViews = allDescendants(of: sheetRoot)
      let nameLabel = sheetViews.first { $0.identifier?.rawValue == "settings.projectName" } as! NSTextField
      let pathLabel = sheetViews.first { $0.identifier?.rawValue == "settings.entryPath" } as! NSTextField
      check(nameLabel.stringValue == profile.name && pathLabel.stringValue == profile.path(profile.entry), "separate Settings header fields")
      check(pathLabel.lineBreakMode == .byTruncatingHead, "Settings path truncation")
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
      delegate.settings.profiles[0].name = String(repeating: "긴 프로젝트 이름 ", count: 30)
      delegate.populate()
      delegate.showSettings()
      check(delegate.isSettingsPresented, "reopening settings sheet failed")
      delegate.settingsStatus.stringValue = "1줄 오류 메시지: 경로 확인 필요\n2줄 오류 메시지: 프로젝트 설정을 다시 확인하세요\n3줄 오류 메시지: 포트와 진입 파일을 확인하세요"
      delegate.settingsStatus.isHidden = false
      sheetRoot.layoutSubtreeIfNeeded()
      let nameFrame = nameLabel.convert(nameLabel.bounds, to: sheetRoot)
      let pathFrame = pathLabel.convert(pathLabel.bounds, to: sheetRoot)
      check(sheetRoot.bounds.contains(nameFrame) && sheetRoot.bounds.contains(pathFrame), "long Settings header clipped")
      check(!nameFrame.intersects(pathFrame), "Settings name and entry path collide")
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
