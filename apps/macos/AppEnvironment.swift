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
  let fixtureRoot: URL?
  var engine: URL { executable.deletingLastPathComponent().appendingPathComponent("flow-engine") }

  init(
    variables: [String: String] = ProcessInfo.processInfo.environment,
    userHome: URL = FileManager.default.homeDirectoryForCurrentUser,
    executable: URL = Bundle.main.executableURL!, fixtureRoot: URL? = nil
  ) {
    self.userHome = userHome
    self.executable = executable
    self.fixtureRoot = fixtureRoot
    support =
      variables["FLOW_DATA_DIR"].map { URL(fileURLWithPath: $0) }
      ?? userHome.appendingPathComponent("Library/Application Support/Lagrangian")
    logRoot =
      variables["FLOW_LOG_DIR"].map { URL(fileURLWithPath: $0) }
      ?? userHome.appendingPathComponent("Library/Logs/Lagrangian")
    agents = userHome.appendingPathComponent("Library/LaunchAgents")
  }

  func nativeReaderBundle() throws -> NativeReaderBundleEnvironment? {
    try require(fixtureRoot == nil, "Fixture mode does not connect a Reader manager")
    return try NativeReaderBundleEnvironment.load(executable: executable)
  }

  /// Explicit child environment, independent of the launching shell. Math keeps
  /// its existing PATH-only, write/network-denying worker environment.
  var fixtureChildEnvironment: [String: String]? {
    guard let root = fixtureRoot else { return nil }
    return ["HOME": userHome.path, "CFFIXED_USER_HOME": userHome.path,
      "TMPDIR": root.appendingPathComponent("tmp").path + "/",
      "XDG_CACHE_HOME": root.appendingPathComponent("cache").path,
      "FLOW_READER_DATA_DIR": root.appendingPathComponent("reader-data").path,
      "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "PYTHONNOUSERSITE": "1", "PYTHONDONTWRITEBYTECODE": "1"]
  }

  func prepareFixtureDirectories() throws {
    guard let root = fixtureRoot, let environment = fixtureChildEnvironment else { return }
    for key in ["HOME", "TMPDIR", "XDG_CACHE_HOME", "FLOW_READER_DATA_DIR"] {
      let directory = URL(fileURLWithPath: environment[key]!).standardizedFileURL
      var component = directory
      while component.path.hasPrefix(root.path + "/") || component.path == root.path {
        try require((try? FileManager.default.destinationOfSymbolicLink(atPath: component.path)) == nil,
                    "Fixture child path contains a symbolic link")
        component.deleteLastPathComponent()
      }
      try require(directory.resolvingSymlinksInPath().path.hasPrefix(root.path + "/"), "Fixture child path escapes dev root")
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: 0o700])
    }
  }

  func nativeMathBundle() throws -> NativeReaderBundleEnvironment.Math? {
    try require(fixtureRoot != nil, "Fixture math requires a dev root")
    try prepareFixtureDirectories()
    return try NativeReaderBundleEnvironment.loadMath(executable: executable,
      runner: CommandRunner(timeout: 60, environment: fixtureChildEnvironment))
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
