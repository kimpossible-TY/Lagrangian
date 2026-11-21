import Darwin
import Foundation

/// Cancellation signals only this owned subprocess; the polling runner performs
/// bounded TERM/KILL and waits for its actual exit before returning.
final class CommandCancellation {
  private let lock = NSLock()
  private var value = false
  func cancel() { lock.lock(); value = true; lock.unlock() }
  var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
}

struct CommandRunner {
  var execute: (String, [String], Bool) throws -> String

  init(timeout: TimeInterval = 15, cancellation: CommandCancellation? = nil, environment: [String: String]? = nil) {
    execute = { path, arguments, allowFailure in
      try Self.executeProcess(path, arguments, allowFailure: allowFailure, timeout: timeout, cancellation: cancellation, environment: environment)
    }
  }

  private static func executeProcess(
    _ path: String, _ arguments: [String], allowFailure: Bool, timeout: TimeInterval, cancellation: CommandCancellation?, environment: [String: String]?
  ) throws -> String {
    if cancellation?.isCancelled == true { throw CancellationError() }
    let task = Process()
    task.executableURL = URL(fileURLWithPath: path)
    task.arguments = arguments
    task.environment = environment
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
      if Date() >= deadline || cancellation?.isCancelled == true {
        if task.isRunning {
          task.terminate()
          let grace = Date().addingTimeInterval(0.2)
          while task.isRunning && Date() < grace { Thread.sleep(forTimeInterval: 0.005) }
          if task.isRunning { kill(task.processIdentifier, SIGKILL) }
        }
        task.waitUntilExit()
        if cancellation?.isCancelled == true { throw CancellationError() }
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

  /// Native attach retains a 10s caller budget: 6.5s manager preparation,
  /// 7s process ceiling, then <=2.5s exact cleanup. Ordinary callers stay at10s.
  static func nativeReaderManager(_ path: String, _ arguments: [String]) async throws -> Data {
    let cancellation = CommandCancellation()
    let cleanup = arguments.first == "--release-native-editor-operation"
    let query = arguments.first == "--native-editor-scope"
    var timeout: TimeInterval = query ? 1 : cleanup ? 2.5 : arguments.contains("--native-editor-operation") ? 7 : 10
    if let index = arguments.firstIndex(of: "--native-editor-deadline"), index + 1 < arguments.count,
       let deadline = TimeInterval(arguments[index + 1]), deadline.isFinite {
      // Reserve TERM/KILL grace on cleanup; attach gets <=0.5s past its
      // manager deadline to report failure. The resolver reserves cleanup too.
      timeout = min(timeout, deadline - Date().timeIntervalSince1970 + (cleanup || query ? -0.2 : 0.5))
    }
    guard timeout > 0 else { throw NativeReaderOperationFailure.unavailable }
    return try await withTaskCancellationHandler(operation: {
      try await Task.detached {
        Data(try CommandRunner(timeout: timeout, cancellation: cancellation).run(path, arguments).utf8)
      }.value
    }, onCancel: { cancellation.cancel() })
  }

  @discardableResult
  func run(_ path: String, _ arguments: [String], allowFailure: Bool = false) throws -> String {
    try execute(path, arguments, allowFailure)
  }
}
