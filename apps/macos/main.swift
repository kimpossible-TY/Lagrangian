import AppKit

do {
  let configuration = try FlowRuntimeConfiguration(
    arguments: Array(CommandLine.arguments.dropFirst()),
    variables: ProcessInfo.processInfo.environment,
    userHome: FileManager.default.homeDirectoryForCurrentUser,
    executable: Bundle.main.executableURL!)
  let arguments = configuration.arguments
  if arguments.first != "--version" {
    try AppDataMigration.migrateDefaults(
      home: configuration.environment.userHome, variables: configuration.variables)
  }
  if !arguments.isEmpty && arguments.first != "--background" {
    try FlowCLI(environment: configuration.environment).run(arguments)
  } else {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = FlowApp(environment: configuration.environment,
                           isolated: configuration.isolated, fixture: configuration.fixture)
    app.delegate = delegate
    app.run()
  }
} catch {
  FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
  exit(1)
}
