import Foundation

protocol ProjectControlling {
  func jobPID(_ label: String) -> Int?
  func control(_ action: String, _ profile: Profile) throws
}

/// Owns project creation, selection and profile replacement, including update failure recovery.
struct ProjectService {
  let store: SettingsPersisting
  let launchAgents: ProjectControlling

  func selectProfile(_ id: String, in settings: Settings) throws -> Settings {
    _ = try settings.profile(id)
    var next = settings
    next.selectedID = id
    try next.validate()
    try store.save(next)
    return next
  }

  func addProject(
    at file: URL, in settings: Settings, userHome: URL,
    fileManager: FileManager = .default
  ) throws -> Settings {
    let root = file.deletingLastPathComponent()
    let ports = Set(settings.profiles.map(\.port))
    let port = (23625...65535).first { !ports.contains($0) }!
    let id = "project-" + UUID().uuidString.prefix(8).lowercased()
    let profile = Profile(
      id: id, name: root.lastPathComponent, root: root.path, entry: file.lastPathComponent,
      fonts: fileManager.fileExists(atPath: root.appendingPathComponent("fonts").path)
        ? ["fonts"] : [],
      packages: userHome.appendingPathComponent("Library/Application Support/typst/packages").path,
      port: port, publicURL: "", label: FlowIdentity.bundleID + ".preview." + id)
    var next = settings
    next.profiles.append(profile)
    next.selectedID = id
    try next.validate()
    try store.save(next)
    return next
  }

  func updateProfile(_ updated: Profile, in settings: Settings) throws -> Settings {
    let old = try settings.profile(updated.id)
    let index = settings.profiles.firstIndex(where: { $0.id == updated.id })!
    try updated.validate(checkFiles: true)
    var next = settings
    next.profiles[index] = updated
    try next.validate()

    let running = launchAgents.jobPID(old.label) != nil
    if running { try launchAgents.control("stop", old) }
    do {
      try store.save(next)
      if running { try launchAgents.control("start", updated) }
    } catch {
      try? store.save(settings)
      if running { try? launchAgents.control("start", old) }
      throw error
    }
    return next
  }
}
