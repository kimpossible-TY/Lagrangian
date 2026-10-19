import Foundation

private func jsonOut(_ object: Any) throws {
  let data = try JSONSerialization.data(
    withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed])
  print(String(data: data, encoding: .utf8)!)
}

struct FlowCLI {
  let store: SettingsStore
  let launchAgents: LaunchAgentService
  let engine: EngineLaunch

  init(environment: AppEnvironment) {
    store = SettingsStore(directory: environment.support)
    launchAgents = LaunchAgentService(environment: environment)
    engine = EngineLaunch(environment: environment)
  }

  func run(_ arguments: [String]) throws {
    if arguments.first == "--version" {
      print(
        "tinymist-flow \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "dev")"
      )
      return
    }
    let settings = try store.load()
    switch arguments.first {
    case "--check-config":
      try settings.validate()
      print("ok")
    case "--profiles":
      let data = try JSONEncoder().encode(settings)
      print(String(data: data, encoding: .utf8)!)
    case "--control":
      try require(arguments.count == 3, "--control start|stop|restart PROJECT_ID")
      try launchAgents.control(arguments[1], settings.profile(arguments[2]))
    case "--serve":
      try require(arguments.count == 2, "--serve PROJECT_ID")
      try engine.serve(settings.profile(arguments[1]))
    case "--status":
      try require(arguments.count == 2, "--status PROJECT_ID")
      let profile = try settings.profile(arguments[1])
      let pid = launchAgents.jobPID(profile.label)
      try jsonOut([
        "id": profile.id, "running": pid != nil, "pid": pid as Any? ?? NSNull(), "url": profile.url,
        "focusFile": engine.environment.focusFile(for: profile).path, "label": profile.label,
        "managedByApp": launchAgents.managedByApp(profile),
      ])
    case "--launch-plan":
      try require(arguments.count == 2, "--launch-plan PROJECT_ID")
      let profile = try settings.profile(arguments[1])
      try jsonOut([
        "arguments": engine.arguments(for: profile), "environment": engine.variables(for: profile),
        "agent": launchAgents.agent(profile),
      ])
    case "--agent-plist":
      try require(arguments.count == 2, "--agent-plist PROJECT_ID")
      let data = try PropertyListSerialization.data(
        fromPropertyList: launchAgents.agent(settings.profile(arguments[1])), format: .xml,
        options: 0
      )
      FileHandle.standardOutput.write(data)
    case "--login":
      try require(arguments.count == 2 && ["on", "off"].contains(arguments[1]), "--login on|off")
      try launchAgents.setLogin(arguments[1] == "on")
    default:
      throw FlowError(
        message:
          "명령: --version, --profiles, --check-config, --control, --status, --launch-plan, --agent-plist, --login"
      )
    }
  }
}
