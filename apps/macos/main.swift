import AppKit

do {
  let configuration = try FlowRuntimeConfiguration(
    arguments: Array(CommandLine.arguments.dropFirst()),
    variables: ProcessInfo.processInfo.environment,
    userHome: FileManager.default.homeDirectoryForCurrentUser,
    executable: Bundle.main.executableURL!)
  let arguments = configuration.arguments
  try configuration.environment.prepareFixtureDirectories()
  if arguments.first != "--version" {
    try AppDataMigration.migrateDefaults(
      home: configuration.environment.userHome, variables: configuration.variables)
  }
  if !arguments.isEmpty && arguments.first != "--background" {
    try FlowCLI(environment: configuration.environment).run(arguments)
  } else {
    let bundled = configuration.fixture == nil ? try configuration.environment.nativeReaderBundle() : nil
    let math = configuration.fixture == nil ? nil : try configuration.environment.nativeMathBundle()
    let defaultRuntime = math.map { NativeReaderRuntime(node: $0.node, helper: $0.helper, runtime: $0.runtime) }
      ?? bundled.map { NativeReaderRuntime(node: $0.node, helper: $0.helper, runtime: $0.runtime) }
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = FlowApp(environment: configuration.environment,
                           isolated: configuration.isolated, fixture: configuration.fixture,
                           noActivate: configuration.noActivate,
                           startupTimeline: configuration.isolated ? NativeStartupTimeline(root: configuration.environment.userHome.deletingLastPathComponent()) : nil,
                           nativeRuntime: configuration.nativeRuntimePaths.map {
                             NativeReaderRuntime(node: URL(fileURLWithPath: $0[0]), helper: URL(fileURLWithPath: $0[1]), runtime: URL(fileURLWithPath: $0[2]))
                           } ?? defaultRuntime, nativeManager: configuration.nativeManager.map { URL(fileURLWithPath: $0) } ?? bundled?.manager)
    app.delegate = delegate
    app.run()
  }
} catch {
  FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
  exit(1)
}
