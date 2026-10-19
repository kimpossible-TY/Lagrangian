import Foundation

protocol ProjectControlling {
  func jobPID(_ label: String) -> Int?
  func control(_ action: String, _ profile: Profile) throws
}

/// Coordinates profile replacement, including restoration after persistence or startup failure.
struct ProjectService {
  let store: SettingsPersisting
  let launchAgents: ProjectControlling

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
