import Foundation

struct CommandRunner {
  var execute: (String, [String], Bool) throws -> String = { path, arguments, allowFailure in
    let task = Process()
    task.executableURL = URL(fileURLWithPath: path)
    task.arguments = arguments
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe
    try task.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    task.waitUntilExit()
    let output = String(data: data, encoding: .utf8) ?? ""
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
