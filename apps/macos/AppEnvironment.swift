import Foundation

enum FlowIdentity {
  static let bundleID = "io.github.kimpossible-ty.tinymist-flow"
  static let appName = "tinymist-flow"
}

/// Paths are captured once and can be replaced for isolated service tests.
struct AppEnvironment {
  let userHome: URL
  let support: URL
  let logRoot: URL
  let agents: URL
  let executable: URL
  var engine: URL { executable.deletingLastPathComponent().appendingPathComponent("flow-engine") }

  init(
    variables: [String: String] = ProcessInfo.processInfo.environment,
    userHome: URL = FileManager.default.homeDirectoryForCurrentUser,
    executable: URL = Bundle.main.executableURL!
  ) {
    self.userHome = userHome
    self.executable = executable
    support =
      variables["FLOW_DATA_DIR"].map { URL(fileURLWithPath: $0) }
      ?? userHome.appendingPathComponent("Library/Application Support/tinymist-flow")
    logRoot =
      variables["FLOW_LOG_DIR"].map { URL(fileURLWithPath: $0) }
      ?? userHome.appendingPathComponent("Library/Logs/tinymist-flow")
    agents = userHome.appendingPathComponent("Library/LaunchAgents")
  }

  func focusFile(for profile: Profile) -> URL {
    support.appendingPathComponent("focus/\(profile.id).json")
  }

  func changeFile(for profile: Profile) -> URL {
    support.appendingPathComponent("changes/\(profile.id).json")
  }
}
