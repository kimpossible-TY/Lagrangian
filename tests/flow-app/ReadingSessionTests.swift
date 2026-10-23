import Foundation

private final class TestAgents: ProjectControlling {
  private let lock = NSLock()
  private var process: Int?
  private var recorded: [String] = []
  var blockStart: DispatchSemaphore?
  var failure: Error?
  var delayedStop = false
  var pid: Int? {
    get {
      lock.lock()
      defer { lock.unlock() }
      return process
    }
    set {
      lock.lock()
      process = newValue
      lock.unlock()
    }
  }
  var events: [String] {
    lock.lock()
    defer { lock.unlock() }
    return recorded
  }
  func jobPID(_ label: String) -> Int? {
    precondition(!Thread.isMainThread, "PID lookup must leave the UI thread")
    return pid
  }
  func control(_ action: String, _ profile: Profile) throws {
    precondition(!Thread.isMainThread, "Service control must leave the UI thread")
    lock.lock()
    recorded.append("\(action):\(profile.id)")
    lock.unlock()
    if action == "start" { blockStart?.wait() }
    if let failure { throw failure }
    if action != "stop" || !delayedStop { pid = action == "stop" ? nil : 41 }
  }
}

private func spin(until condition: () -> Bool, timeout: TimeInterval = 2) throws {
  let end = Date().addingTimeInterval(timeout)
  while !condition(), Date() < end {
    RunLoop.main.run(until: Date().addingTimeInterval(0.002))
  }
  try require(condition(), "Timed out waiting for test condition")
}

private func drain(_ interval: TimeInterval = 0.025) {
  RunLoop.main.run(until: Date().addingTimeInterval(interval))
}

private final class Fixture {
  let agents = TestAgents()
  let profile: Profile
  var changes: [ReadingSessionSnapshot] = []
  var opens: [URL] = []
  var probes: [(PreviewReadiness) -> Void] = []
  var cancelled: [Int] = []
  var controller: ReadingSessionController!
  var browserSucceeds = true
  var onChange: ((ReadingSessionSnapshot) -> Void)?

  init(root: URL, timeout: TimeInterval = 0.2) {
    profile = Profile(
      id: "fixture", name: "Fixture", root: root.path, entry: "main.typ", fonts: [],
      packages: "", port: 24650, publicURL: "", label: "com.example.fixture")
    controller = ReadingSessionController(
      launchAgents: agents,
      onChange: { [unowned self] in
        precondition(Thread.isMainThread, "UI state must arrive on main")
        self.changes.append($0)
        self.onChange?($0)
      },
      openBrowser: { [unowned self] url in
        precondition(Thread.isMainThread, "Browser opening must occur on main")
        self.opens.append(url)
        return self.browserSucceeds
      },
      probe: { [unowned self] _, completion in
        let index = self.probes.count
        self.probes.append(completion)
        return { [weak self] in self?.cancelled.append(index) }
      },
      validate: {
        precondition(!Thread.isMainThread, "Validation must leave the UI thread")
        try $0.validate(checkFiles: true)
      }, startupTimeout: timeout, retryInterval: 0.005)
    controller.select(profile)
  }

  func begin() throws {
    controller.read()
    try spin { !probes.isEmpty }
  }

  func finish() { controller.dispose() }
}

@main
enum ReadingSessionTests {
  static func main() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data("Fixture".utf8).write(to: root.appendingPathComponent("main.typ"))
    let scenario = CommandLine.arguments[1]
    let fixture = Fixture(root: root)
    let controller = fixture.controller!
    defer { fixture.finish() }

    switch scenario {
    case "read-once":
      try fixture.begin()
      controller.read()
      for _ in 0..<10 { controller.refresh() }
      try require(fixture.probes.count == 1, "Repeated requests must coalesce")
      try require(fixture.opens.isEmpty, "PID alone must not open browser")
      fixture.probes[0](.ready)
      try spin { fixture.opens.count == 1 }
      fixture.probes[0](.ready)
      drain()
      try require(fixture.opens.count == 1, "One read intent must open exactly once")
      try require(
        fixture.agents.events == ["start:fixture"], "Double Read must not restart services")
      let phases = fixture.changes.map(\.phase)
      try require(
        phases.contains(.validating) && phases.contains(.requested)
          && phases.contains(.running) && phases.contains(.ready),
        "All readiness stages must be observable")
      try require(!controller.snapshot.isBusy, "Completed reads must release busy state")
    case "responsive-and-serialized-stop":
      let gate = DispatchSemaphore(value: 0)
      fixture.agents.blockStart = gate
      controller.read()
      try spin { fixture.agents.events.count == 1 }
      var mainResponded = false
      DispatchQueue.main.async { mainResponded = true }
      try spin { mainResponded }
      controller.control("stop")
      drain()
      try require(
        fixture.agents.events.count == 1, "Stop must wait for the running service operation")
      gate.signal()
      try spin { fixture.agents.events.count == 2 && controller.snapshot.phase == .stopped }
      try require(fixture.opens.isEmpty, "Superseded read must never open browser")
    case "switch-stale":
      try fixture.begin()
      var changed = fixture.profile
      changed.entry = "other.typ"
      // Even the same profile ID with changed configuration must invalidate the old callback.
      controller.select(changed)
      try spin { fixture.probes.count == 2 }
      fixture.probes[0](.ready)
      drain()
      try require(
        fixture.opens.isEmpty && controller.snapshot.phase != .ready,
        "Old profile configuration must not open or overwrite the new state")
      fixture.probes[1](.ready)
      try spin { controller.snapshot.phase == .ready }
      try require(fixture.opens.isEmpty, "Selection alone must not open a tab")
    case "stop-stale":
      try fixture.begin()
      controller.control("stop")
      fixture.probes[0](.ready)
      try spin { controller.snapshot.phase == .stopped && !controller.snapshot.isBusy }
      try require(fixture.opens.isEmpty, "Stop must cancel delayed readiness")
    case "stop-confirmation":
      fixture.agents.pid = 41
      fixture.agents.delayedStop = true
      controller.control("stop")
      try spin { fixture.agents.events.count == 1 && controller.snapshot.pid == 41 }
      try require(
        controller.snapshot.phase == .requested && controller.snapshot.isBusy,
        "Stop command completion must not claim the process has exited")
      fixture.agents.pid = nil
      try spin { controller.snapshot.phase == .stopped && !controller.snapshot.isBusy }
      try require(fixture.probes.isEmpty, "Stopping must only verify process exit")
    case "process-replaced":
      try fixture.begin()
      fixture.agents.pid = 99
      fixture.probes[0](.ready)
      try spin { fixture.probes.count == 2 }
      try require(fixture.opens.isEmpty, "A replaced process must invalidate document proof")
      fixture.probes[1](.ready)
      try spin { fixture.opens.count == 1 }
      try require(controller.snapshot.pid == 99, "Ready state must refer to the new process")
    case "sleep-wake-power":
      try fixture.begin()
      controller.setConstrainedPower(true)
      try require(controller.idleProbeInterval == 30, "Constrained power must reduce idle polling")
      controller.setSleeping(true)
      fixture.probes[0](.ready)
      controller.networkChanged()
      drain()
      try require(
        controller.snapshot.phase == .sleeping && fixture.probes.count == 1,
        "Sleep must suspend probes and invalidate old document results")
      controller.setSleeping(false)
      try spin { fixture.probes.count == 2 }
      fixture.probes[1](.ready)
      try spin { controller.snapshot.phase == .ready }
      try require(fixture.opens.isEmpty, "Wake must recover status without reopening tabs")
      try require(
        fixture.agents.events == ["start:fixture"], "Sleep and power policy must not stop services")
      controller.setConstrainedPower(false)
      try require(
        controller.idleProbeInterval == 8, "Normal power must restore normal idle polling")
      controller.networkChanged()
      try spin { fixture.probes.count == 3 }
    case "timeout":
      try fixture.begin()
      var handled = 0
      try spin(until: {
        while handled < fixture.probes.count {
          fixture.probes[handled](.waiting("fixture document pending"))
          handled += 1
        }
        return controller.snapshot.phase == .failed
      })
      try require(
        controller.snapshot.detail.contains("fixture document pending"),
        "Readiness timeout must preserve the last cause")
      let count = fixture.probes.count
      drain(0.05)
      try require(
        fixture.probes.count == count && fixture.opens.isEmpty,
        "Failure must remain visible without implicit retry or browser opening")
    case "validation-failure":
      var missing = fixture.profile
      missing.entry = "missing.typ"
      controller.select(missing)
      controller.read()
      try spin { controller.snapshot.phase == .failed }
      try require(
        fixture.agents.events.isEmpty && fixture.opens.isEmpty,
        "Invalid files must fail before service mutation")
      try require(controller.snapshot.detail.contains("진입 파일"), "Validation cause must be inline")
    case "compile-failure", "browser-failure":
      try fixture.begin()
      fixture.browserSucceeds = false
      fixture.probes[0](scenario == "compile-failure" ? .failed("fixture compile error") : .ready)
      try spin { controller.snapshot.phase == .failed }
      try require(
        controller.snapshot.detail.contains(
          scenario == "compile-failure" ? "compile error" : "브라우저"),
        "Failures must explain their cause")
    case "mutation-sleep":
      let gate = DispatchSemaphore(value: 0)
      var completed = false
      controller.performMutation(
        message: "Saving",
        work: {
          precondition(!Thread.isMainThread)
          gate.wait()
          return 7
        },
        completion: { result in
          precondition(Thread.isMainThread)
          if case .success(7) = result { completed = true }
        })
      controller.setSleeping(true)
      gate.signal()
      try spin { completed }
      try require(
        controller.snapshot.phase == .sleeping, "Storage completion must preserve sleeping state")
    case "mutation-failure":
      var completed = false
      controller.performMutation(
        message: "Saving",
        work: { () throws -> Int in
          precondition(!Thread.isMainThread)
          throw FlowError(message: "fixture storage failure")
        }, completion: { _ in completed = true })
      try spin { completed }
      try require(
        controller.snapshot.phase == .failed
          && controller.snapshot.detail.contains("storage failure"),
        "Storage failures must remain inline")
    case "mutation-supersedes-read":
      let gate = DispatchSemaphore(value: 0)
      fixture.agents.blockStart = gate
      controller.read()
      try spin { fixture.agents.events.count == 1 }
      var saved = false
      controller.performMutation(
        message: "Saving", work: { 7 },
        completion: { result in
          if case .success(7) = result { saved = true }
        })
      drain()
      try require(!saved, "Storage mutation must wait for current service control")
      gate.signal()
      try spin { saved }
      try require(fixture.opens.isEmpty, "Superseded read must never open a browser")
    case "reentrant-ready":
      try fixture.begin()
      fixture.onChange = { state in if state.phase == .ready { controller.select(nil) } }
      fixture.probes[0](.ready)
      try spin { controller.snapshot.phase == .idle }
      try require(
        fixture.opens.isEmpty, "Reentrant selection must cancel opening after ready notification")
    case "command-deadline":
      let gate = DispatchSemaphore(value: 0)
      fixture.agents.blockStart = gate
      controller.read()
      try spin { fixture.agents.events.count == 1 }
      try spin { controller.snapshot.phase == .failed }
      gate.signal()
      drain()
      try require(
        controller.snapshot.phase == .failed && fixture.opens.isEmpty && fixture.probes.isEmpty,
        "The startup deadline must include command execution and reject late completion")
    case "command-timeout":
      let runner = CommandRunner(timeout: 0.05)
      let started = Date()
      do {
        _ = try runner.run("/bin/sleep", ["10"])
        throw FlowError(message: "Expected timeout")
      } catch {
        try require(
          error.localizedDescription.contains("시간이 초과"), "Command timeout must be actionable")
      }
      try require(Date().timeIntervalSince(started) < 1, "Command timeout must be bounded")
    case "command-output":
      let runner = CommandRunner(timeout: 2)
      let output = try runner.run("/usr/bin/head", ["-c", "2097152", "/dev/zero"])
      try require(
        output.contains("1 MiB"), "Large output must drain without deadlock and remain bounded")
      let failure = try runner.run("/usr/bin/false", [], allowFailure: true)
      try require(failure.isEmpty, "Allow-failure must preserve its prior contract")
    case "dispose-stale":
      try fixture.begin()
      controller.dispose()
      let changes = fixture.changes.count
      fixture.probes[0](.ready)
      drain()
      try require(
        fixture.opens.isEmpty && fixture.changes.count == changes,
        "Disposed owners must ignore callbacks")
    case "wire":
      var profile = fixture.profile
      profile.port = Int(CommandLine.arguments[2])!
      var output: String?
      let probe = PreviewReadinessProbe(profile: profile, timeout: 0.3) { result in
        DispatchQueue.main.async {
          switch result {
          case .ready: output = "ready"
          case .waiting: output = "waiting"
          case .failed: output = "failed"
          }
        }
      }
      defer { probe.cancel() }
      try spin { output != nil }
      print(output!)
    default:
      throw FlowError(message: "Unknown scenario: \(scenario)")
    }
  }
}
