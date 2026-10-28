import Darwin
import Foundation

struct LaunchAgentService: ProjectControlling {
  let environment: AppEnvironment
  var commands = CommandRunner()
  var fileManager: FileManager = .default
  var userID = getuid()
  var shutdownTimeout: TimeInterval = 10
  var processExists: (Int) -> Bool = { pid in
    kill(pid_t(pid), 0) == 0 || errno == EPERM
  }

  func jobPID(_ label: String) -> Int? {
    let result = try? commands.run("/bin/launchctl", ["print", "gui/\(userID)/\(label)"])
    guard let result,
      let range = result.range(of: "(?m)^\\s*pid = [0-9]+$", options: .regularExpression)
    else { return nil }
    return Int(result[range].split(separator: "=").last!.trimmingCharacters(in: .whitespaces))
  }

  func managedByApp(_ profile: Profile) -> Bool {
    let file = environment.agents.appendingPathComponent("\(profile.label).plist")
    guard let data = try? Data(contentsOf: file),
      let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
        as? [String: Any],
      let arguments = plist["ProgramArguments"] as? [String]
    else { return false }
    return arguments == programArguments(for: profile)
  }

  private func programArguments(for profile: Profile) -> [String] {
    [environment.executable.path, "--serve", profile.id]
  }

  func agent(_ profile: Profile) -> [String: Any] {
    [
      "Label": profile.label,
      "ProgramArguments": programArguments(for: profile),
      "AssociatedBundleIdentifiers": [LagrangianIdentity.bundleID],
      "RunAtLoad": true,
      "KeepAlive": true,
      "ThrottleInterval": 10,
      "ProcessType": "Interactive",
      "WorkingDirectory": environment.support.path,
      "EnvironmentVariables": EngineLaunch(environment: environment).variables(for: profile),
      "StandardOutPath": environment.logRoot.appendingPathComponent("\(profile.id).out.log").path,
      "StandardErrorPath": environment.logRoot.appendingPathComponent("\(profile.id).err.log").path,
    ]
  }

  private func withControlLock<T>(_ body: () throws -> T) throws -> T {
    try fileManager.createDirectory(at: environment.support, withIntermediateDirectories: true)
    let file = environment.support.appendingPathComponent("control.lock")
    let descriptor = open(file.path, O_CREAT | O_RDWR, 0o600)
    try require(descriptor >= 0, "제어 잠금을 열 수 없습니다.")
    defer {
      flock(descriptor, LOCK_UN)
      close(descriptor)
    }
    try require(flock(descriptor, LOCK_EX | LOCK_NB) == 0, "다른 서비스 작업이 진행 중입니다.")
    return try body()
  }

  /// bootout may return before its process exits. Keep stop/start and restart ordered,
  /// including the interval after launchd forgets the job but the old PID is still alive.
  private func waitForExit(_ profile: Profile, previousPID: Int?) throws {
    let deadline = Date().addingTimeInterval(shutdownTimeout)
    while true {
      let registeredPID = jobPID(profile.label)
      let previousStillRunning = previousPID.map(processExists) ?? false
      if registeredPID == nil && !previousStillRunning { return }
      try require(Date() < deadline, "이전 프리뷰가 아직 종료되지 않았습니다. 잠시 후 다시 시도하세요.")
      Thread.sleep(forTimeInterval: min(0.1, max(0, deadline.timeIntervalSinceNow)))
    }
  }

  func control(_ action: String, _ profile: Profile) throws {
    try withControlLock {
      let target = "gui/\(userID)/\(profile.label)"
      if action == "stop" {
        let pid = jobPID(profile.label)
        try commands.run("/bin/launchctl", ["disable", target])
        try commands.run("/bin/launchctl", ["bootout", target], allowFailure: true)
        try waitForExit(profile, previousPID: pid)
        return
      }
      try require(action == "start" || action == "restart", "지원하지 않는 작업입니다.")
      try profile.validate(checkFiles: true, fileManager: fileManager)
      let owners =
        (try? commands.run(
          "/usr/sbin/lsof", ["-nP", "-iTCP:\(profile.port)", "-sTCP:LISTEN", "-t"],
          allowFailure: true
        )) ?? ""
      let ownerIDs = Set(owners.split(separator: "\n").compactMap { Int($0) })
      let pid = jobPID(profile.label)
      try require(
        ownerIDs.isEmpty || ownerIDs == Set([pid].compactMap { $0 }),
        "포트 \(profile.port)를 다른 프로세스가 사용 중입니다."
      )
      if action == "start" && pid != nil { return }
      try fileManager.createDirectory(at: environment.logRoot, withIntermediateDirectories: true)
      try fileManager.createDirectory(
        at: environment.support.appendingPathComponent("focus"), withIntermediateDirectories: true)
      try fileManager.createDirectory(at: environment.agents, withIntermediateDirectories: true)
      let plist = environment.agents.appendingPathComponent("\(profile.label).plist")
      let data = try PropertyListSerialization.data(
        fromPropertyList: agent(profile), format: .xml, options: 0)
      try data.write(to: plist, options: .atomic)
      try commands.run("/bin/launchctl", ["bootout", target], allowFailure: true)
      try waitForExit(profile, previousPID: pid)
      try commands.run("/bin/launchctl", ["enable", target])
      var lastError: Error?
      for _ in 0..<5 {
        do {
          try commands.run("/bin/launchctl", ["bootstrap", "gui/\(userID)", plist.path])
          return
        } catch {
          lastError = error
          Thread.sleep(forTimeInterval: 0.3)
        }
      }
      throw lastError!
    }
  }

  func loginEnabled() -> Bool {
    fileManager.fileExists(atPath: environment.agents
      .appendingPathComponent("\(LagrangianIdentity.legacyLoginAgentLabel).plist").path)
      || fileManager.fileExists(atPath: environment.agents
        .appendingPathComponent("\(LagrangianIdentity.bundleID).login.plist").path)
  }

  func setLogin(_ enabled: Bool) throws {
    let legacyLabel = LagrangianIdentity.legacyLoginAgentLabel
    let currentLabel = "\(LagrangianIdentity.bundleID).login"
    let legacyFile = environment.agents.appendingPathComponent("\(legacyLabel).plist")
    let label = enabled && fileManager.fileExists(atPath: legacyFile.path) ? legacyLabel : currentLabel
    let file = environment.agents.appendingPathComponent("\(label).plist")
    if enabled {
      try fileManager.createDirectory(at: environment.agents, withIntermediateDirectories: true)
      let job: [String: Any] = [
        "Label": label,
        "ProgramArguments": [environment.executable.path, "--background"],
        "RunAtLoad": true,
        "AssociatedBundleIdentifiers": [LagrangianIdentity.bundleID],
      ]
      try PropertyListSerialization.data(fromPropertyList: job, format: .xml, options: 0).write(
        to: file, options: .atomic)
      try commands.run("/bin/launchctl", ["enable", "gui/\(userID)/\(label)"])
    } else {
      try commands.run("/bin/launchctl", ["disable", "gui/\(userID)/\(label)"])
      if fileManager.fileExists(atPath: file.path) { try fileManager.removeItem(at: file) }
      let otherLabel = label == legacyLabel ? currentLabel : legacyLabel
      let otherFile = environment.agents.appendingPathComponent("\(otherLabel).plist")
      try commands.run("/bin/launchctl", ["disable", "gui/\(userID)/\(otherLabel)"])
      if fileManager.fileExists(atPath: otherFile.path) { try fileManager.removeItem(at: otherFile) }
    }
  }
}
