import Foundation
import CryptoKit

enum LagrangianIdentity {
  static let bundleID = "io.github.kimpossible-ty.lagrangian"
  static let appName = "Lagrangian"
  static let legacyLoginAgentLabel = "io.github.kimpossible-ty.tinymist-flow.login"
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
      ?? userHome.appendingPathComponent("Library/Application Support/Lagrangian")
    logRoot =
      variables["FLOW_LOG_DIR"].map { URL(fileURLWithPath: $0) }
      ?? userHome.appendingPathComponent("Library/Logs/Lagrangian")
    agents = userHome.appendingPathComponent("Library/LaunchAgents")
  }

  func nativeReaderBundle() throws -> NativeReaderBundleEnvironment? {
    try NativeReaderBundleEnvironment.load(executable: executable)
  }

  /// Profile/target namespace is independent of service PID/revision. Typed
  /// entries still validate their complete document identity when opened.
  func nativeRecoveryRoot(for profile: Profile) -> URL {
    let target = [profile.id, URL(fileURLWithPath: profile.root).standardizedFileURL.path, profile.entry]
    let bytes = (try? JSONEncoder().encode(target)) ?? Data()
    let key = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    return support.appendingPathComponent("native-reader/" + key, isDirectory: true)
  }

  func focusFile(for profile: Profile) -> URL {
    support.appendingPathComponent("focus/\(profile.id).json")
  }

  func changeFile(for profile: Profile) -> URL {
    support.appendingPathComponent("changes/\(profile.id).json")
  }
}
