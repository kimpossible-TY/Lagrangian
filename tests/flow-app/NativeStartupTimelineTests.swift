import Foundation
import Darwin

@main struct StartupTimelineTests {
  static func require(_ value: Bool, _ message: String) throws {
    if !value { throw NSError(domain: message, code: 1) }
  }
  static func run(_ scenario: String, _ root: URL) throws {
    let entered = DispatchSemaphore(value: 0), gate = DispatchSemaphore(value: 0), done = DispatchSemaphore(value: 0)
    let opened = DispatchSemaphore(value: 0)
    if scenario == "normal" || scenario == "guards" {
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      let file = root.appendingPathComponent("startup-timeline.jsonl")
      let canary = root.appendingPathComponent("canary")
      if scenario == "guards" {
        try Data("canary".utf8).write(to: canary)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: canary)
      }
      var io = NativeStartupTimeline.IO.live
      let close = io.closeDirectory
      io.closeDirectory = { close($0); done.signal() }
      var timeline: NativeStartupTimeline? = NativeStartupTimeline(root: root, io: io)
      timeline!.record("normal-record", ["value": 7]); timeline = nil
      try require(done.wait(timeout: .now()+2) == .success, "normal queue completion")
      if scenario == "guards" {
        try require(try Data(contentsOf: canary) == Data("canary".utf8), "nofollow canary unchanged")
        try FileManager.default.removeItem(at: file)
        try Data("private guard".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        var guarded: NativeStartupTimeline? = NativeStartupTimeline(root: root, io: io)
        guarded!.record("must-not-append"); guarded = nil
        try require(done.wait(timeout: .now()+2) == .success, "private guard completion")
        try require(try String(contentsOf: file, encoding: .utf8) == "private guard", "unsafe permissions unchanged")
      } else {
        let rows = try String(contentsOf: file, encoding: .utf8).split(separator: "\n")
        let row = try JSONSerialization.jsonObject(with: Data(rows[0].utf8)) as! [String: Any]
        try require(rows.count == 1 && row["event"] as? String == "normal-record" && row["value"] as? Int == 7, "normal records")
        let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as! NSNumber
        try require(mode.intValue == 0o600, "private mode")
      }
      return
    }
    var writes = 0
    let io = NativeStartupTimeline.IO(openDirectory: { _ in
      opened.signal()
      if scenario == "slow-open" { entered.signal(); _ = gate.wait(timeout: .now()+2) }
      if scenario == "failed-open" { done.signal(); return -1 }
      return 42
    }, append: { _, _ in
      writes += 1
      if scenario == "slow-write" { entered.signal(); _ = gate.wait(timeout: .now()+2) }
      if scenario == "failed-write" { throw NSError(domain:"Injected diagnostic write failure",code:5) }
    }, closeDirectory: { _ in done.signal() })
    let begin = ProcessInfo.processInfo.systemUptime
    var timeline: NativeStartupTimeline? = NativeStartupTimeline(root: root, io: io)
    weak var weakTimeline = timeline
    try require(ProcessInfo.processInfo.systemUptime - begin < 0.2, "init blocked by IO")
    timeline!.record("event")
    try require(opened.wait(timeout: .now()+1) == .success, "queued open executed")
    if scenario.hasPrefix("slow-") { try require(entered.wait(timeout: .now()+1) == .success, "IO gate entered") }
    let end = ProcessInfo.processInfo.systemUptime
    timeline = nil
    try require(weakTimeline == nil && ProcessInfo.processInfo.systemUptime - end < 0.2, "deinit blocked/retained by IO")
    weakTimeline = nil
    gate.signal()
    try require(done.wait(timeout: .now()+2) == .success, "owned IO cleanup")
    if scenario != "failed-open" { try require(writes == 1, "write attempted without blocking caller") }
  }
  static func main() {
    do { try run(CommandLine.arguments[1], URL(fileURLWithPath: CommandLine.arguments[2])); print("STARTUP-1 passed: \(CommandLine.arguments[1])") }
    catch { FileHandle.standardError.write(Data("\(error)\n".utf8)); exit(1) }
  }
}
