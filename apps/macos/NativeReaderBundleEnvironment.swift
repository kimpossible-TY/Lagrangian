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

  static func load(executable: URL, runner: CommandRunner = CommandRunner(timeout: 60)) throws -> Self? {
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
    return try Self(root: root, node: entry("node"), helper: entry("helper"), runtime: entry("runtime"),
                    manager: entry("manager"), sourceRevision: revision)
  }
}
