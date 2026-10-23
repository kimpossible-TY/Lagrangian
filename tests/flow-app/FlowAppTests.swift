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
    delegate.populate()
    defer {
      delegate.session.dispose()
      delegate.window.close()
    }
    waitUntil("initial stopped status") { delegate.snapshot?.phase == .stopped }

    switch CommandLine.arguments[1] {
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
        onNetwork: {}, onPower: { powerEvents.append($0) })
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
