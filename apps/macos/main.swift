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
                           isolated: configuration.isolated, fixture: configuration.fixture,
                           noActivate: configuration.noActivate,
                           nativeRuntime: configuration.nativeRuntimePaths.map {
                             NativeReaderRuntime(node: URL(fileURLWithPath: $0[0]), helper: URL(fileURLWithPath: $0[1]), runtime: URL(fileURLWithPath: $0[2]))
                           }, nativeManager: configuration.nativeManager.map { URL(fileURLWithPath: $0) })
    app.delegate = delegate
    app.run()
  }
} catch {
  FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
  exit(1)
}
