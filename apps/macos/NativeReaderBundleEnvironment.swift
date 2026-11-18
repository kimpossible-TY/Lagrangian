import Foundation
import CryptoKit

/// Delivery composition only. ReaderManager and native consumers retain their policies.
struct NativeReaderBundleEnvironment {
  let root: URL
  let node: URL
  let helper: URL
  let runtime: URL
  let manager: URL
  let sourceRevision: String

  struct Math {
    let node: URL
    let helper: URL
    let runtime: URL
    let sourceRevision: String
  }

  static func load(executable: URL, runner: CommandRunner = CommandRunner(timeout: 60)) throws -> Self? {
    guard let manifest = try verified(executable: executable, runner: runner) else { return nil }
    return try Self(root: manifest.root, node: manifest.entry("node"), helper: manifest.entry("helper"),
                    runtime: manifest.entry("runtime"), manager: manifest.entry("manager"), sourceRevision: manifest.revision)
  }

  static func loadMath(executable: URL, runner: CommandRunner) throws -> Math? {
    guard let manifest = try verified(executable: executable, runner: runner) else { return nil }
    return try Math(node: manifest.entry("node"), helper: manifest.entry("helper"),
                    runtime: manifest.entry("runtime"), sourceRevision: manifest.revision)
  }

  private struct Verified {
    let root: URL
    let entries: [String: String]
    let revision: String
    func entry(_ key: String) throws -> URL {
      guard let value = entries[key], !value.hasPrefix("/"), !value.contains("\\"),
            value.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
        throw FlowError(message: "잘못된 Reader 배송 경로: \(key)")
      }
      let url = root.appendingPathComponent(value).resolvingSymlinksInPath()
      guard url.path.hasPrefix(root.resolvingSymlinksInPath().path + "/"), FileManager.default.fileExists(atPath: url.path) else {
        throw FlowError(message: "Reader 배송 파일이 없거나 외부를 가리킵니다: \(key)")
      }
      return url
    }
  }

  private static func verified(executable: URL, runner: CommandRunner) throws -> Verified? {
    let contents = executable.deletingLastPathComponent().deletingLastPathComponent()
    let root = contents.appendingPathComponent("Resources/native-reader", isDirectory: true)
    let file = root.appendingPathComponent("delivery-manifest.json")
    guard FileManager.default.fileExists(atPath: file.path) else { return nil }
    // Verify the outer seal before reading executable URLs or invoking any payload.
    try runner.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", contents.deletingLastPathComponent().path])
    let bytes = try Data(contentsOf: file)
    guard bytes.count <= 16 * 1024 * 1024,
          let manifest = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
          manifest["schema"] as? Int == 1,
          let revision = manifest["sourceRevision"] as? String,
          let entries = manifest["entrypoints"] as? [String: String],
          let release = try JSONSerialization.jsonObject(with: Data(contentsOf: contents.appendingPathComponent("Resources/release.json"))) as? [String: Any],
          release["sourceRevision"] as? String == revision,
          release["nativeDeliverySHA256"] as? String == SHA256.hash(data: bytes).map({ String(format: "%02x", $0) }).joined() else {
      throw FlowError(message: "네이티브 Reader 배송 manifest가 앱과 일치하지 않습니다.")
    }
    return Verified(root: root, entries: entries, revision: revision)
  }
}
