import Darwin
import Foundation

struct CommandRunner {
  var execute: (String, [String], Bool) throws -> String

  init(timeout: TimeInterval = 15) {
    execute = { path, arguments, allowFailure in
      try Self.executeProcess(path, arguments, allowFailure: allowFailure, timeout: timeout)
    }
  }

  private static func executeProcess(
    _ path: String, _ arguments: [String], allowFailure: Bool, timeout: TimeInterval
  ) throws -> String {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: path)
    task.arguments = arguments
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe
    try task.run()
    pipe.fileHandleForWriting.closeFile()
    defer { pipe.fileHandleForReading.closeFile() }
    let descriptor = pipe.fileHandleForReading.fileDescriptor
    let flags = fcntl(descriptor, F_GETFL)
    _ = fcntl(descriptor, F_SETFL, flags | O_NONBLOCK)
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 8192)
    let deadline = Date().addingTimeInterval(timeout)
    var ended = false
    var truncated = false
    while !ended || task.isRunning {
      // Drain while the child runs: waiting first can deadlock when its output fills the pipe.
      let count = read(descriptor, &buffer, buffer.count)
      if count > 0 {
        let kept = min(count, max(0, 1024 * 1024 - data.count))
        data.append(contentsOf: buffer.prefix(kept))
        truncated = truncated || kept != count
      } else if count == 0 {
        ended = true
      }
      if Date() >= deadline {
        if task.isRunning {
          task.terminate()
          let grace = Date().addingTimeInterval(0.2)
          while task.isRunning && Date() < grace { Thread.sleep(forTimeInterval: 0.005) }
          if task.isRunning { kill(task.processIdentifier, SIGKILL) }
        }
        task.waitUntilExit()
        throw FlowError(message: "\(path): 명령 실행 시간이 초과되었습니다. 다시 시도하세요.")
      }
      if count <= 0 && (!ended || task.isRunning) {
        var pollDescriptor = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
        _ = poll(&pollDescriptor, 1, 20)
        if ended { Thread.sleep(forTimeInterval: 0.002) }
      }
    }
    task.waitUntilExit()
    let output =
      (String(data: data, encoding: .utf8) ?? "")
      + (truncated ? "\n[출력이 1 MiB에서 잘렸습니다.]" : "")
    try require(
      allowFailure || task.terminationStatus == 0,
      "\(path): \(output.trimmingCharacters(in: .whitespacesAndNewlines))"
    )
    return output
  }

  @discardableResult
  func run(_ path: String, _ arguments: [String], allowFailure: Bool = false) throws -> String {
    try execute(path, arguments, allowFailure)
  }
}
