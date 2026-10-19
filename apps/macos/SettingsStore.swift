import Foundation

protocol SettingsPersisting {
  func save(_ settings: Settings) throws
}

struct SettingsStore: SettingsPersisting {
  let directory: URL
  var fileManager: FileManager = .default
  var file: URL { directory.appendingPathComponent("profiles.json") }

  func load() throws -> Settings {
    guard fileManager.fileExists(atPath: file.path) else { return Settings() }
    let settings = try JSONDecoder().decode(Settings.self, from: Data(contentsOf: file))
    try settings.validate()
    return settings
  }

  func save(_ settings: Settings) throws {
    try settings.validate()
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try encoder.encode(settings).write(to: file, options: .atomic)
    try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
  }
}
