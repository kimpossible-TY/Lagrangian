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
    return try saveNewProject(root: root, entry: file.lastPathComponent, projectRefKey: nil,
                              in: settings, userHome: userHome, fileManager: fileManager)
  }

  /// Relative Typst paths at the root and in at most two directory levels.
  func discoverProjectEntryCandidates(
    in directory: URL, fileManager: FileManager = .default
  ) throws -> [String] {
    var candidates: [String] = []
    func scan(_ folder: URL, prefix: String, depth: Int) throws {
      let children = try fileManager.contentsOfDirectory(
        at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .isHiddenKey])
      for child in children {
        let values = try child.resourceValues(
          forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .isHiddenKey])
        let relative = prefix + child.lastPathComponent
        if values.isDirectory == true {
          if depth < 2 && values.isHidden != true && values.isSymbolicLink != true {
            try scan(child, prefix: relative + "/", depth: depth + 1)
          }
        } else if values.isRegularFile == true && child.pathExtension == "typ" {
          candidates.append(relative)
        }
      }
    }
    try scan(directory, prefix: "", depth: 0)
    try require(!candidates.isEmpty, "프로젝트 폴더에서 .typ 파일을 찾을 수 없습니다.")
    return candidates.sorted {
      if $0 == "main.typ" { return $1 != "main.typ" }
      if $1 == "main.typ" { return false }
      return $0 < $1
    }
  }

  func addProjectDirectory(
    at directory: URL, entry: String? = nil, projectRefKey: String? = nil,
    in settings: Settings, userHome: URL, fileManager: FileManager = .default
  ) throws -> Settings {
    let root = directory.standardizedFileURL
    var isDirectory: ObjCBool = false
    try require(
      fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory) && isDirectory.boolValue,
      "프로젝트 폴더를 찾을 수 없습니다.")
    let selectedEntry: String
    if let entry {
      selectedEntry = entry
    } else {
      let candidates = try discoverProjectEntryCandidates(in: root, fileManager: fileManager)
      try require(candidates.first == "main.typ" || candidates.count == 1,
                  "진입 파일이 여러 개입니다. .typ 파일을 선택하세요.")
      selectedEntry = candidates[0]
    }
    let file = root.appendingPathComponent(selectedEntry).standardizedFileURL
    let resolvedRoot = root.resolvingSymlinksInPath().path
    try require(
      !selectedEntry.hasPrefix("/") && pathIsInside(file.path, directory: root.path)
        && pathIsInside(file.resolvingSymlinksInPath().path, directory: resolvedRoot)
        && file.pathExtension == "typ"
        && (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
      "진입 파일은 프로젝트 폴더 안의 .typ 파일이어야 합니다.")
    return try saveNewProject(root: root, entry: selectedEntry, projectRefKey: projectRefKey,
                              in: settings, userHome: userHome, fileManager: fileManager)
  }

  private func saveNewProject(
    root: URL, entry: String, projectRefKey: String?, in settings: Settings,
    userHome: URL, fileManager: FileManager
  ) throws -> Settings {
    let ports = Set(settings.profiles.map(\.port))
    guard let port = (23625...65535).first(where: { !ports.contains($0) }) else {
      throw FlowError(message: "사용 가능한 프로젝트 포트가 없습니다.")
    }
    let id = "project-" + UUID().uuidString.prefix(8).lowercased()
    let profile = Profile(
      id: id, name: root.lastPathComponent, root: root.path, entry: entry,
      fonts: fileManager.fileExists(atPath: root.appendingPathComponent("fonts").path) ? ["fonts"] : [],
      packages: userHome.appendingPathComponent("Library/Application Support/typst/packages").path,
      port: port, publicURL: "", label: LagrangianIdentity.bundleID + ".preview." + id,
      projectRefKey: projectRefKey)
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
