import Foundation

private enum FixtureError: Error {
  case save, start, stop
}

private final class Events {
  var values: [String] = []
}

private final class TestStore: SettingsPersisting {
  let events: Events
  var saveCount = 0
  var failFirstSave = false
  var savedSettings: Settings?

  init(events: Events) { self.events = events }

  func save(_ settings: Settings) throws {
    saveCount += 1
    savedSettings = settings
    events.values.append("save:\(settings.profiles[0].name)")
    if failFirstSave && saveCount == 1 { throw FixtureError.save }
  }
}

private final class TestAgents: ProjectControlling {
  let events: Events
  var running = true
  var failStart = false
  var failStop = false

  init(events: Events) { self.events = events }

  func jobPID(_ label: String) -> Int? {
    events.values.append("pid")
    return running ? 123 : nil
  }

  func control(_ action: String, _ profile: Profile) throws {
    events.values.append("\(action):\(profile.name)")
    if action == "stop" && failStop { throw FixtureError.stop }
    if action == "start" && profile.name == "updated" && failStart { throw FixtureError.start }
  }
}

private func expectFailure(_ expected: FixtureError, _ operation: () throws -> Void) throws {
  do {
    try operation()
  } catch let error as FixtureError {
    try require(error == expected, "Unexpected failure: \(error)")
    return
  }
  throw FlowError(message: "Expected \(expected) failure")
}

private func settingsData(_ settings: Settings) throws -> Data {
  let encoder = JSONEncoder()
  encoder.outputFormatting = .sortedKeys
  return try encoder.encode(settings)
}

@main
enum ProjectServiceTests {
  static func main() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data("Fixture".utf8).write(to: root.appendingPathComponent("main.typ"))
    let profile = Profile(
      id: "fixture", name: "original", root: root.path, entry: "main.typ", fonts: [],
      packages: "", port: 24650, publicURL: "", label: "com.example.fixture"
    )
    var settings = Settings(selectedID: profile.id, profiles: [profile])
    var updated = profile
    updated.name = "updated"
    let events = Events()
    let store = TestStore(events: events)
    let agents = TestAgents(events: events)
    let service = ProjectService(store: store, launchAgents: agents)

    switch CommandLine.arguments[1] {
    case "select-profile", "select-invalid-profile", "select-save-failure":
      var second = profile
      second.id = "second"
      second.label = "com.example.second"
      second.port = 24651
      settings.profiles.append(second)
      let before = try settingsData(settings)
      switch CommandLine.arguments[1] {
      case "select-profile":
        let result = try service.selectProfile(second.id, in: settings)
        var expected = settings
        expected.selectedID = second.id
        try require(
          try settingsData(result) == settingsData(expected),
          "Selection must preserve profiles and change only the selected ID")
        try require(
          try settingsData(store.savedSettings!) == settingsData(result),
          "Returned settings must match the persisted selection")
        try require(
          events.values == ["save:original"],
          "Selection must save once without controlling services")
      case "select-invalid-profile":
        do {
          _ = try service.selectProfile("missing", in: settings)
          throw FixtureError.start
        } catch is FlowError {}
        try require(
          events.values.isEmpty, "Unknown profiles must not reach storage or services")
      default:
        store.failFirstSave = true
        var callerSettings = settings
        try expectFailure(.save) {
          callerSettings = try service.selectProfile(second.id, in: callerSettings)
        }
        try require(
          try settingsData(callerSettings) == before,
          "Failed selection must preserve the caller's prior profiles and selected ID")
        try require(
          events.values == ["save:original"],
          "Failed selection must not control or recover services")
      }
      try require(try settingsData(settings) == before, "Selection must not mutate input settings")
    case "create-project", "create-fonts-and-used-ports":
      let withFonts = CommandLine.arguments[1] == "create-fonts-and-used-ports"
      if withFonts {
        try FileManager.default.createDirectory(
          at: root.appendingPathComponent("fonts"), withIntermediateDirectories: true)
        settings.profiles[0].port = 23625
        var second = profile
        second.id = "second"
        second.label = "com.example.second"
        second.port = 23627
        settings.profiles.append(second)
      }
      let before = try settingsData(settings)
      let home = root.appendingPathComponent("home")
      let result = try service.addProject(
        at: root.appendingPathComponent("main.typ"), in: settings, userHome: home)
      let created = result.profiles.last!
      try require(
        created.id.range(of: "^project-[0-9a-f]{8}$", options: .regularExpression) != nil,
        "New projects must retain the UUID-based ID format")
      try require(
        created.label == FlowIdentity.bundleID + ".preview." + created.id,
        "LaunchAgent labels must retain the app and project identity")
      try require(
        created.name == root.lastPathComponent && created.root == root.path
          && created.entry == "main.typ", "The selected file must determine project paths and name")
      try require(
        created.fonts == (withFonts ? ["fonts"] : []),
        "Only an existing project fonts path is included by default")
      try require(
        created.packages
          == home.appendingPathComponent(
            "Library/Application Support/typst/packages"
          ).path,
        "Packages must use the supplied home")
      try require(
        created.port == (withFonts ? 23626 : 23625) && created.publicURL.isEmpty,
        "Creation must choose the first unused default port and no public URL")
      try require(result.selectedID == created.id, "The new project must be selected")
      var previous = result
      previous.profiles.removeLast()
      previous.selectedID = settings.selectedID
      try require(try settingsData(previous) == before, "Existing profiles must remain unchanged")
      try require(try settingsData(settings) == before, "Creation must not mutate input settings")
      try require(
        try settingsData(store.savedSettings!) == settingsData(result),
        "Returned settings must match the saved settings")
      try require(
        events.values == ["save:original"], "Creation must save once without controlling services")
    case "create-invalid-project":
      let before = try settingsData(settings)
      do {
        _ = try service.addProject(
          at: root.appendingPathComponent("invalid.txt"), in: settings, userHome: root)
        throw FixtureError.start
      } catch is FlowError {}
      try require(
        events.values.isEmpty, "Invalid project settings must not reach storage or services")
      try require(try settingsData(settings) == before, "Failed validation must preserve settings")
    case "create-save-failure":
      store.failFirstSave = true
      let before = try settingsData(settings)
      var callerSettings = settings
      try expectFailure(.save) {
        callerSettings = try service.addProject(
          at: root.appendingPathComponent("main.typ"), in: callerSettings, userHome: root)
      }
      try require(
        try settingsData(callerSettings) == before,
        "The caller must keep its prior profiles and selection when saving fails")
      try require(
        events.values == ["save:original"], "Failed creation must not control or recover services")
    case "agent-update-delayed-exit", "agent-restart-delayed-exit", "agent-shutdown-timeout":
      let environment = AppEnvironment(
        variables: ["FLOW_DATA_DIR": root.appendingPathComponent("data").path],
        userHome: root, executable: root.appendingPathComponent("tinymist-flow"))
      var launchAgents = LaunchAgentService(environment: environment)
      let timesOut = CommandLine.arguments[1] == "agent-shutdown-timeout"
      launchAgents.shutdownTimeout = timesOut ? 0.02 : 1
      var running = true
      var retiring = false
      var exitPolls = 0
      var bootstraps = 0
      launchAgents.processExists = { _ in running }
      launchAgents.commands.execute = { path, arguments, _ in
        if path == "/usr/sbin/lsof" { return "" }
        switch arguments[0] {
        case "print":
          if retiring && !timesOut {
            exitPolls += 1
            if exitPolls >= 3 {
              running = false
              retiring = false
            }
            // launchd can forget the job one poll before the actual process has exited.
            if exitPolls >= 2 { return "" }
          }
          return running ? "    pid = 123\n" : ""
        case "bootout":
          if running {
            retiring = true
            exitPolls = 0
          }
        case "bootstrap":
          try require(
            !running && exitPolls >= 3,
            "New service must bootstrap only after confirmed previous process exit")
          bootstraps += 1
          running = true
        default: break
        }
        return ""
      }
      if timesOut {
        do {
          try launchAgents.control("restart", profile)
          throw FixtureError.start
        } catch let error as FlowError {
          try require(error.message.contains("종료"), "Shutdown timeout must explain its cause")
        }
        try require(bootstraps == 0, "Timed-out shutdown must never bootstrap a replacement")
      } else {
        updated.publicURL = "https://updated.example"
        if CommandLine.arguments[1] == "agent-update-delayed-exit" {
          let project = ProjectService(store: store, launchAgents: launchAgents)
          let saved = try project.updateProfile(updated, in: settings)
          try require(
            saved.profiles[0].publicURL == updated.publicURL,
            "Profile replacement must retain the saved settings")
        } else {
          try launchAgents.control("restart", updated)
        }
        try require(
          bootstraps == 1 && running,
          "Delayed shutdown must lead to one actual bootstrap instead of a skipped start")
        let plist = environment.agents.appendingPathComponent("\(profile.label).plist")
        let job =
          try PropertyListSerialization.propertyList(
            from: Data(contentsOf: plist), format: nil) as! [String: Any]
        let variables = job["EnvironmentVariables"] as! [String: String]
        try require(
          variables["TINYMIST_ALLOWED_ORIGINS"] == updated.publicURL,
          "The replacement must launch with the updated environment")
      }
    case "agent-ownership":
      let environment = AppEnvironment(
        variables: ["FLOW_DATA_DIR": root.appendingPathComponent("data").path],
        userHome: root, executable: root.appendingPathComponent("tinymist-flow"))
      let launchAgents = LaunchAgentService(environment: environment)
      let plist = environment.agents.appendingPathComponent("\(profile.label).plist")
      try require(!launchAgents.managedByApp(profile), "A missing job must not be app-owned")
      try FileManager.default.createDirectory(
        at: environment.agents, withIntermediateDirectories: true)
      var job = launchAgents.agent(profile)
      let arguments = job["ProgramArguments"] as! [String]
      try require(
        arguments == [environment.executable.path, "--serve", profile.id],
        "Generated jobs must preserve the app serve invocation")
      func writeJob() throws {
        try PropertyListSerialization.data(fromPropertyList: job, format: .xml, options: 0)
          .write(to: plist)
      }
      try writeJob()
      try require(
        launchAgents.managedByApp(profile), "Generated jobs must be recognized as app-owned")
      for other in [
        [root.appendingPathComponent("other-app").path, "--serve", profile.id],
        [environment.executable.path, "--serve", "other-project"],
        [environment.executable.path, "--background", profile.id],
        arguments + ["extra"],
      ] {
        job["ProgramArguments"] = other
        try writeJob()
        try require(
          !launchAgents.managedByApp(profile), "Foreign invocations must not be app-owned")
      }
      job.removeValue(forKey: "ProgramArguments")
      try writeJob()
      try require(
        !launchAgents.managedByApp(profile), "Jobs without an invocation must not be app-owned")
      try Data("invalid plist".utf8).write(to: plist)
      try require(!launchAgents.managedByApp(profile), "Malformed jobs must not be app-owned")
    case "invalid-profile":
      updated.entry = "missing.typ"
      do {
        _ = try service.updateProfile(updated, in: settings)
        throw FixtureError.start
      } catch is FlowError {}
      try require(events.values.isEmpty, "Validation must happen before service or storage access")
    case "duplicate-port":
      var second = profile
      second.id = "second"
      second.label = "com.example.second"
      second.port = 24651
      settings.profiles.append(second)
      updated.port = second.port
      do {
        _ = try service.updateProfile(updated, in: settings)
        throw FixtureError.start
      } catch is FlowError {}
      try require(
        events.values.isEmpty, "Whole-settings validation must happen before stopping a service")
    case "stopped":
      agents.running = false
      let result = try service.updateProfile(updated, in: settings)
      try require(result.profiles[0].name == "updated", "Updated settings must be returned")
      try require(result.selectedID == settings.selectedID, "Selection must be preserved")
      try require(
        events.values == ["pid", "save:updated"], "A stopped service must remain stopped")
    case "running":
      _ = try service.updateProfile(updated, in: settings)
      try require(
        events.values == ["pid", "stop:original", "save:updated", "start:updated"],
        "Unexpected update order")
    case "save-failure":
      store.failFirstSave = true
      try expectFailure(.save) { _ = try service.updateProfile(updated, in: settings) }
      try require(
        events.values == [
          "pid", "stop:original", "save:updated", "save:original", "start:original",
        ], "Save failure must restore the previous configuration and service")
    case "start-failure":
      agents.failStart = true
      try expectFailure(.start) { _ = try service.updateProfile(updated, in: settings) }
      try require(
        events.values == [
          "pid", "stop:original", "save:updated", "start:updated", "save:original",
          "start:original",
        ], "Start failure must restore the previous configuration and service")
    case "stop-failure":
      agents.failStop = true
      try expectFailure(.stop) { _ = try service.updateProfile(updated, in: settings) }
      try require(
        events.values == ["pid", "stop:original"], "Failed stop must leave settings unchanged")
    case "settings-store":
      let environment = AppEnvironment(
        variables: [
          "FLOW_DATA_DIR": root.appendingPathComponent("data").path,
          "FLOW_LOG_DIR": root.appendingPathComponent("logs").path,
        ],
        userHome: root, executable: root.appendingPathComponent("tinymist-flow")
      )
      let disk = SettingsStore(directory: environment.support)
      try require(try disk.load().profiles.isEmpty, "Missing settings must start empty")
      try disk.save(settings)
      let loaded = try disk.load()
      try require(
        loaded.profiles[0].id == profile.id && loaded.selectedID == profile.id,
        "Settings must round-trip")
      let attributes = try FileManager.default.attributesOfItem(atPath: disk.file.path)
      try require(
        (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600,
        "Settings must remain private")
      try require(
        environment.agents == root.appendingPathComponent("Library/LaunchAgents"),
        "LaunchAgents must use the supplied home")
    default:
      throw FlowError(message: "Unknown test scenario")
    }
  }
}
