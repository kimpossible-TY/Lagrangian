import Foundation
import Darwin

protocol SettingsPersisting {
  func save(_ settings: Settings) throws
}

struct SettingsStore: SettingsPersisting {
  let directory: URL
  var fileManager: FileManager = .default
  var localReplacement = false
  var file: URL { directory.appendingPathComponent("profiles.json") }

  func load() throws -> Settings {
    let data: Data
    if localReplacement {
      let fd = open(file.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
      if fd < 0, errno == ENOENT { return Settings() }
      try require(fd >= 0, "Cannot read private settings")
      let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
      defer { try? handle.close() }
      var info = stat()
      try require(fstat(fd, &info) == 0 && info.st_mode & S_IFMT == S_IFREG, "Private settings must be a regular file")
      data = try handle.readToEnd() ?? Data()
    } else {
      guard fileManager.fileExists(atPath: file.path) else { return Settings() }
      data = try Data(contentsOf: file)
    }
    let settings = try JSONDecoder().decode(Settings.self, from: data)
    try settings.validate()
    return settings
  }

  func save(_ settings: Settings) throws {
    try settings.validate()
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(settings)
    if localReplacement {
      // Fixture writes cannot ask Foundation for a volume/platform replacement
      // directory. Keep the private temporary file beside its owned destination.
      let temporary = directory.appendingPathComponent(".profiles-" + UUID().uuidString)
      let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
      try require(fd >= 0, "Cannot create private settings replacement")
      let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
      defer { try? handle.close(); unlink(temporary.path) }
      try handle.write(contentsOf: data); try handle.synchronize()
      try require(rename(temporary.path, file.path) == 0, "Cannot replace private settings")
    } else {
      try data.write(to: file, options: .atomic)
    }
    try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
  }
}
