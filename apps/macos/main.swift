import AppKit

do {
  let arguments = Array(CommandLine.arguments.dropFirst())
  if arguments.first != "--version" {
    try AppDataMigration.migrateDefaults(
      home: FileManager.default.homeDirectoryForCurrentUser,
      variables: ProcessInfo.processInfo.environment)
  }
} catch {
  FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
  exit(1)
}

let environment = AppEnvironment()
if CommandLine.arguments.count > 1 && CommandLine.arguments[1] != "--background" {
  do {
    try FlowCLI(environment: environment).run(Array(CommandLine.arguments.dropFirst()))
  } catch {
    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
    exit(1)
  }
} else {
  let app = NSApplication.shared
  app.setActivationPolicy(.accessory)
  let delegate = FlowApp(environment: environment)
  app.delegate = delegate
  app.run()
}
