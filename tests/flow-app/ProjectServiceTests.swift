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

  init(events: Events) { self.events = events }

  func save(_ settings: Settings) throws {
    saveCount += 1
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
