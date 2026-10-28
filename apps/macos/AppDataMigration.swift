import Foundation

/// Moves default app-owned directories while keeping legacy absolute paths usable
/// by existing LaunchAgents and integrations until they are updated by the user.
enum AppDataMigration {
  static let legacySupportPath = "Library/Application Support/tinymist-flow"
  static let legacyLogPath = "Library/Logs/tinymist-flow"

  static func migrateDefaults(
    home: URL,
    variables: [String: String],
    fileManager: FileManager = .default
  ) throws {
    var directories: [(source: URL, destination: URL)] = []
    if variables["FLOW_DATA_DIR"] == nil {
      directories.append((
        source: home.appendingPathComponent(legacySupportPath),
        destination: home.appendingPathComponent("Library/Application Support/Lagrangian")))
    }
    if variables["FLOW_LOG_DIR"] == nil {
      directories.append((
        source: home.appendingPathComponent(legacyLogPath),
        destination: home.appendingPathComponent("Library/Logs/Lagrangian")))
    }
    for (source, destination) in directories {
      try validateMigration(from: source, to: destination, fileManager: fileManager)
    }
    for (source, destination) in directories {
      try migrateDirectory(from: source, to: destination, fileManager: fileManager)
    }
  }

  private static func validateMigration(
    from source: URL,
    to destination: URL,
    fileManager: FileManager
  ) throws {
    let sourceType = try itemType(at: source, fileManager: fileManager)
    if sourceType == .typeSymbolicLink {
      let target = try fileManager.destinationOfSymbolicLink(atPath: source.path)
      let resolvedTarget = URL(fileURLWithPath: target, relativeTo: source.deletingLastPathComponent())
        .standardizedFileURL
      guard resolvedTarget.path == destination.standardizedFileURL.path else {
        throw FlowError(message: "Legacy data path is a symbolic link to an unexpected location: \(source.path)")
      }
      return
    }
    guard let sourceType else { return }
    guard sourceType == .typeDirectory else {
      throw FlowError(message: "Legacy data path is not a directory: \(source.path)")
    }
    guard try itemType(at: destination, fileManager: fileManager) == nil else {
      throw FlowError(
        message: "Both legacy and Lagrangian data directories exist; no data was changed. Resolve these paths manually: \(source.path) and \(destination.path)")
    }
  }

  private static func migrateDirectory(
    from source: URL,
    to destination: URL,
    fileManager: FileManager
  ) throws {
    let sourceType = try itemType(at: source, fileManager: fileManager)
    if sourceType == .typeSymbolicLink { return }
    guard sourceType != nil else { return }

    try fileManager.createDirectory(
      at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
    try fileManager.moveItem(at: source, to: destination)
    do {
      try fileManager.createSymbolicLink(at: source, withDestinationURL: destination)
    } catch {
      // Restore the original path if compatibility-link creation failed.
      if (try? itemType(at: source, fileManager: fileManager)) == nil {
        try? fileManager.moveItem(at: destination, to: source)
      }
      throw error
    }
  }

  private static func itemType(
    at url: URL,
    fileManager: FileManager
  ) throws -> FileAttributeType? {
    guard fileManager.fileExists(atPath: url.path) else { return nil }
    return try fileManager.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType
  }
}
