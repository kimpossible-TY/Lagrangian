import Foundation

private enum FixtureError: Error {
  case save, start, stop
}

private final class Events {
  var values: [String] = []
}

private final class TestStore: SettingsPersisting {
  let events: Events
  var saveCount = 0
  var failFirstSave = false
  var savedSettings: Settings?

  init(events: Events) { self.events = events }

  func save(_ settings: Settings) throws {
    saveCount += 1
    savedSettings = settings
    events.values.append("save:\(settings.profiles[0].name)")
    if failFirstSave && saveCount == 1 { throw FixtureError.save }
  }
}

private final class TestAgents: ProjectControlling {
  let events: Events
  var running = true
  var failStart = false
  var failStop = false

  init(events: Events) { self.events = events }

  func jobPID(_ label: String) -> Int? {
    events.values.append("pid")
    return running ? 123 : nil
  }

  func control(_ action: String, _ profile: Profile) throws {
    events.values.append("\(action):\(profile.name)")
    if action == "stop" && failStop { throw FixtureError.stop }
    if action == "start" && profile.name == "updated" && failStart { throw FixtureError.start }
  }
}

private func expectFailure(_ expected: FixtureError, _ operation: () throws -> Void) throws {
  do {
    try operation()
  } catch let error as FixtureError {
    try require(error == expected, "Unexpected failure: \(error)")
    return
  }
  throw FlowError(message: "Expected \(expected) failure")
}

private func settingsData(_ settings: Settings) throws -> Data {
  let encoder = JSONEncoder()
  encoder.outputFormatting = .sortedKeys
  return try encoder.encode(settings)
}

private func expectFlowError(_ operation: () throws -> Void) throws {
  do {
    try operation()
  } catch is FlowError { return }
  throw FlowError(message: "Expected FlowError")
}

private func testReferenceKey(_ profile: Profile) throws {
  let encoded = try JSONEncoder().encode(profile)
  var legacy = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
  legacy.removeValue(forKey: "projectRefKey")
  let decoded = try JSONDecoder().decode(Profile.self, from: JSONSerialization.data(withJSONObject: legacy))
  try require(decoded == profile && decoded.projectRefKey == nil, "Legacy profile must decode unchanged")
  legacy["projectRefKey"] = NSNull()
  try require(try JSONDecoder().decode(Profile.self, from: JSONSerialization.data(withJSONObject: legacy)).projectRefKey == nil,
              "Null reference key is unconfigured")
  for key in ["", "a", "project-1", String(repeating: "a", count: 64)] {
    var candidate = profile
    candidate.projectRefKey = key
    try candidate.validate()
    let copy = try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(candidate))
    try require(copy == candidate, "Reference key must round trip")
  }
  for key in ["A", "-project", "a_b", "a b", "a/b", " a", "a\n", "a\r", "a\r\n",
              "a\u{0085}", "a\u{2028}", "a\u{2029}", "\na", "a\nb", "한글",
              String(repeating: "a", count: 65)] {
    var candidate = profile
    candidate.projectRefKey = key
    try expectFlowError { try candidate.validate() }
  }
  var candidate = profile
  candidate.projectRefKey = "valid"
  candidate.port = 1
  try expectFlowError { try candidate.validate() }
}

private func testTrailingNewlineValidation(_ profile: Profile) throws {
  var candidate = profile
  candidate.projectRefKey = "a\n"
  try expectFlowError { try candidate.validate() }
  let decoded = try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(candidate))
  try expectFlowError { try decoded.validate() }
  candidate = profile
  candidate.id = "a\n"
  try expectFlowError { try candidate.validate() }
  candidate = profile
  candidate.label = "ab\n"
  try expectFlowError { try candidate.validate() }
}

private func testDirectoryDiscovery(_ service: ProjectService, _ root: URL) throws {
  let fm = FileManager.default
  for path in ["z.typ", "a.typ", "one/nested.typ", "one/two/deep.typ", "one/two/three/ignored.typ",
               ".hidden/ignored.typ", "one/.hidden/ignored.typ", "not.typ/no.txt"] {
    let file = root.appendingPathComponent(path)
    try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data().write(to: file)
  }
  let outside = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try fm.createDirectory(at: outside, withIntermediateDirectories: true)
  defer { try? fm.removeItem(at: outside) }
  try Data().write(to: outside.appendingPathComponent("external.typ"))
  try fm.createSymbolicLink(at: root.appendingPathComponent("linked"), withDestinationURL: outside)
  let expected = ["main.typ", "a.typ", "one/nested.typ", "one/two/deep.typ", "z.typ"]
  try require(try service.discoverProjectEntryCandidates(in: root) == expected,
              "Discovery must be deterministic, depth bounded and exclude hidden/symlink directories")
  try require(try service.discoverProjectEntryCandidates(in: root) == expected, "Repeated discovery must be stable")
  let empty = root.appendingPathComponent("empty")
  try fm.createDirectory(at: empty, withIntermediateDirectories: true)
  try expectFlowError { _ = try service.discoverProjectEntryCandidates(in: empty) }
}

private func testDirectoryRegistration(
  _ service: ProjectService, _ settings: Settings, _ root: URL, _ store: TestStore, _ events: Events
) throws {
  let fm = FileManager.default
  let before = try settingsData(settings)
  let directory = root.appendingPathComponent("directory")
  try fm.createDirectory(at: directory.appendingPathComponent("fonts"), withIntermediateDirectories: true)
  try Data().write(to: directory.appendingPathComponent("main.typ"))
  try Data().write(to: directory.appendingPathComponent("other.typ"))
  let added = try service.addProjectDirectory(at: directory, projectRefKey: "book", in: settings, userHome: root)
  let created = added.profiles.last!
  try require(created.root == directory.path && created.name == "directory" && created.entry == "main.typ"
                && created.projectRefKey == "book" && created.fonts == ["fonts"] && created.port == 23625,
              "Root main and supplied reference key must preserve project defaults")
  try require(created.packages == root.appendingPathComponent("Library/Application Support/typst/packages").path
                && created.publicURL.isEmpty && created.label == LagrangianIdentity.bundleID + ".preview." + created.id,
              "Directory creation must preserve home, public URL and launch identity defaults")
  try require(added.selectedID == created.id && added.profiles.dropLast() == settings.profiles[...],
              "Directory registration selects only the new project")
  try require(try settingsData(store.savedSettings!) == settingsData(added), "Returned settings equal saved settings")
  try require(events.values == ["save:original"], "Directory registration must save once without service control")
  try fm.removeItem(at: directory.appendingPathComponent("main.typ"))
  let sole = try service.addProjectDirectory(at: directory, in: settings, userHome: root)
  try require(sole.profiles.last?.entry == "other.typ", "The sole candidate must be selected")
  try fm.createDirectory(at: directory.appendingPathComponent("chapters"), withIntermediateDirectories: true)
  try Data().write(to: directory.appendingPathComponent("chapters/book.typ"))
  let saves = store.saveCount
  try expectFlowError { _ = try service.addProjectDirectory(at: directory, in: settings, userHome: root) }
  try require(store.saveCount == saves, "Ambiguous entry must not save")
  var occupied = settings
  occupied.profiles[0].port = 23625
  let explicit = try service.addProjectDirectory(
    at: directory, entry: "chapters/book.typ", in: occupied, userHome: root)
  try require(explicit.profiles.last?.entry == "chapters/book.typ" && explicit.profiles.last?.port == 23626,
              "Explicit nested entry and first unused port must be retained")
  try require(try settingsData(settings) == before, "Directory registration must not mutate caller settings")
  let absoluteEntry = root.appendingPathComponent("main.typ").path
  let rootProject = try service.addProjectDirectory(
    at: URL(fileURLWithPath: "/"), entry: String(absoluteEntry.dropFirst()), in: settings, userHome: root)
  try require(rootProject.profiles.last?.root == "/", "Filesystem root must accept contained entries")
  var rootProfile = settings.profiles[0]
  rootProfile.root = "/"
  rootProfile.entry = String(absoluteEntry.dropFirst())
  try rootProfile.validate(checkFiles: true)
}

private func testDirectoryFailures(
  _ service: ProjectService, _ settings: Settings, _ root: URL, _ store: TestStore, _ events: Events
) throws {
  let directory = root.appendingPathComponent("empty")
  let fm = FileManager.default
  try fm.createDirectory(at: directory, withIntermediateDirectories: true)
  try expectFlowError { _ = try service.addProjectDirectory(at: directory, in: settings, userHome: root) }
  try expectFlowError { _ = try service.addProjectDirectory(at: root.appendingPathComponent("missing"), in: settings, userHome: root) }
  try expectFlowError { _ = try service.addProjectDirectory(at: root.appendingPathComponent("main.typ"), in: settings, userHome: root) }
  try Data().write(to: directory.appendingPathComponent("book.typ"))
  try fm.createDirectory(at: directory.appendingPathComponent("fake.typ"), withIntermediateDirectories: true)
  try fm.createSymbolicLink(at: directory.appendingPathComponent("linked.typ"), withDestinationURL: root.appendingPathComponent("main.typ"))
  for entry in ["../main.typ", "missing.typ", "fake.typ", "linked.typ", "book.txt", root.appendingPathComponent("main.typ").path, ""] {
    try expectFlowError { _ = try service.addProjectDirectory(at: directory, entry: entry, in: settings, userHome: root) }
  }
  try expectFlowError {
    _ = try service.addProjectDirectory(at: directory, entry: "book.typ", projectRefKey: "Bad Key", in: settings, userHome: root)
  }
  try require(events.values.isEmpty, "Invalid directory input must never reach store or services")
  store.failFirstSave = true
  let before = try settingsData(settings)
  try expectFailure(.save) {
    _ = try service.addProjectDirectory(at: directory, entry: "book.typ", in: settings, userHome: root)
  }
  try require(try settingsData(settings) == before && events.values == ["save:original"],
              "Save failure must preserve caller settings without service effects")
}

private func testCatalog(_ root: URL, _ profile: Profile) throws {
  let source = #"""
  {"schema":1,"projects":{
    "book":{"title":"Book","pdf_url":"https://example.test/book.pdf","references":{
      "theorem":{"page":3,"text":"Theorem 1","x":0.2,"y":0.4},
      "other":{"page":3,"text":"Lemma 2"},"duplicate":{"page":4,"text":"Theorem 2"}},
      "ambiguous_labels":["duplicate","omitted"]},
    "second":{"title":"Second","pdf_url":"https://example.test/second.pdf",
      "references":{"copy":{"page":2,"text":"Theorem 1"}},"ambiguous_labels":[]}}}
  """#
  let file = root.appendingPathComponent("projects.json")
  try Data(source.utf8).write(to: file)
  let catalog = try CrossProjectCatalog.load(from: file)
  guard case .unique(let target) = catalog.resolve(projectKey: "book", label: "theorem") else {
    throw FlowError(message: "Explicit identity must resolve")
  }
  try require(target.projectKey == "book" && target.label == "theorem" && target.entry.page == 3
                && target.entry.x == 0.2 && target.entry.y == 0.4 && target.project.title == "Book",
              "Resolved target must retain catalog identity and coordinates")
  try require(catalog.resolve(projectKey: "book", label: "duplicate") == .ambiguous([])
                && catalog.resolve(projectKey: "book", label: "omitted") == .ambiguous([]),
              "Duplicate labels remain ambiguous, even without published entries")
  try require(catalog.resolve(projectKey: "missing", label: "theorem") == .unresolved
                && catalog.resolve(projectKey: "book", label: "missing") == .unresolved,
              "Missing keys and labels remain unresolved")
  let url = "https://example.test/book.pdf#page=3"
  for text in ["Theorem 1", "Theorem 1 of Book"] {
    try require(catalog.resolve(url: url, linkText: text) == .unique(target), "Fallback must filter display text")
  }
  guard case .ambiguous(let matches) = catalog.resolve(url: url, linkText: nil) else {
    throw FlowError(message: "Page-only fallback must retain all candidates")
  }
  try require(matches.count == 2, "Two references on a page remain ambiguous")
  guard case .ambiguous = catalog.resolve(url: "https://example.test/book.pdf#page=4", linkText: "Theorem 2") else {
    throw FlowError(message: "Fallback cannot hide an ambiguous label")
  }
  for invalid in ["https://example.test/book.pdf", "https://example.test/book.pdf#page=0",
                  "https://example.test/book.pdf#page=-1", "https://example.test/book.pdf#page=abc",
                  "https://example.test/book.pdf#page=3&other=1", "https://example.test/book.pdf#page=2",
                  "https://other.test/book.pdf#page=3"] {
    try require(catalog.resolve(url: invalid, linkText: "Theorem 1") == .unresolved, "Invalid URL/page must not resolve")
  }
  try require(catalog.resolve(url: url, linkText: "wrong") == .unresolved, "Incorrect display text must not resolve")
  var shared = catalog.projects
  shared["copy"] = shared["book"]
  guard case .ambiguous(let duplicates) = CrossProjectCatalog(projects: shared).resolve(url: url, linkText: "Theorem 1") else {
    throw FlowError(message: "Shared PDF identity must retain ambiguity")
  }
  try require(duplicates.map(\.projectKey) == ["book", "copy"], "Ambiguous matches must be deterministic")
  try require(try CrossProjectCatalog.load(from: file, maxBytes: source.utf8.count) == catalog, "Exact byte limit accepted")
  try expectFlowError { _ = try CrossProjectCatalog.load(from: file, maxBytes: source.utf8.count - 1) }
  try expectFlowError { _ = try CrossProjectCatalog.load(from: file, maxBytes: 0) }
  for schema in [0, 2] {
    try Data(source.replacingOccurrences(of: #""schema":1"#, with: "\"schema\":\(schema)").utf8).write(to: file)
    try expectFlowError { _ = try CrossProjectCatalog.load(from: file) }
  }
  try Data(source.replacingOccurrences(of: #""page":3"#, with: #""page":0"#).utf8).write(to: file)
  try expectFlowError { _ = try CrossProjectCatalog.load(from: file) }
  try Data("{invalid".utf8).write(to: file)
  do { _ = try CrossProjectCatalog.load(from: file); throw FixtureError.start } catch is DecodingError {}

  var fallback = profile
  fallback.root = root.appendingPathComponent("  My_Book ").path
  var explicit = profile
  explicit.id = "explicit"
  explicit.projectRefKey = "my-book"
  try require(catalog.matchProfile(for: "my-book", in: [fallback, explicit]) == explicit, "Explicit key wins")
  try require(catalog.matchProfile(for: "MY-BOOK", in: [fallback]) == fallback, "Folder normalization ignores case")
  fallback.root = root.path
  fallback.name = "My Book"
  try require(catalog.matchProfile(for: "my-book", in: [fallback]) == fallback, "Name normalization ignores separators")
  try require(catalog.matchProfile(for: "my-book", in: [fallback, fallback]) == nil
                && catalog.matchProfile(for: "my-book", in: [explicit, explicit]) == nil,
              "Duplicate local matches must not guess")
  explicit.projectRefKey = "other"
  explicit.name = "my-book"
  try require(catalog.matchProfile(for: "my-book", in: [explicit]) == nil, "Configured identity is authoritative")
  try require(catalog.matchProfile(for: "missing", in: [profile]) == nil, "Missing profile remains unavailable")
  explicit.projectRefKey = ""
  explicit.name = ""
  try require(catalog.matchProfile(for: "", in: [explicit]) == nil
                && catalog.matchProfile(for: "  ", in: [explicit]) == nil,
              "Empty catalog keys must never match unconfigured profiles")
}

private struct CrossProjectFixture: Decodable {
  struct Catalog: Decodable { let projects: [String: CrossProjectCatalogProject] }
  struct LocalProfile: Decodable {
    let id, name, root: String
    let projectRefKey: String?
    var profile: Profile {
      Profile(id: id, name: name, root: root, entry: "main.typ", fonts: [], packages: "",
              port: 24650, publicURL: "", label: "fixture", projectRefKey: projectRefKey)
    }
  }
  struct Query: Decodable {
    let project_key, label, href, link_text: String?
  }
  struct ExpectedTarget: Decodable {
    let status: String
    let projectKey, label, profileID: String?
  }
  struct Resolution: Decodable {
    let name: String
    let catalog: Catalog
    let profiles: [LocalProfile]
    let query: Query
    let expected: ExpectedTarget
  }
  struct Node: Decodable {
    let id, sectionID, canonicalText, displayText: String
    let kind: NativeReaderNode.Kind
    let anchors: [String]
    let children: [Node]
    var native: NativeReaderNode {
      NativeReaderNode(id: id, sectionID: sectionID, kind: kind, canonicalText: canonicalText,
        displayText: displayText, rangeUTF16: [0, canonicalText.utf16.count], offsets: NativeTextOffsets(canonicalText),
        children: children.map(\.native), anchors: anchors, annotationTargets: [], visible: true, mapping: .unmapped,
        passageKey: nil, direction: nil, language: nil, headingLevel: nil, math: nil, cell: nil, link: nil, assetID: nil, alt: nil)
    }
  }
  struct Snippet: Decodable {
    struct Expected: Decodable { let text: String; let truncated: Bool }
    let name: String
    let blocks: [Node]
    let label, reference_text: String?
    let max_chars, max_blocks: Int?
    let expected: Expected?
  }
  let resolution: [Resolution]
  let snippets: [Snippet]
}

private func testSharedCrossProjectFixture(_ file: URL) throws {
  let fixture = try JSONDecoder().decode(CrossProjectFixture.self, from: Data(contentsOf: file))
  for item in fixture.resolution {
    let catalog = CrossProjectCatalog(projects: item.catalog.projects)
    let query = item.query
    let resolution: CrossProjectResolution
    if let key = query.project_key, let label = query.label {
      resolution = catalog.resolve(projectKey: key, label: label)
    } else {
      resolution = catalog.resolve(url: query.href ?? "", linkText: query.link_text)
    }
    var status: String
    var key: String?, label: String?, profileID: String?
    switch resolution {
    case .unique(let target):
      status = "unique"; key = target.projectKey; label = target.label
      profileID = catalog.matchProfile(for: target.projectKey, in: item.profiles.map(\.profile))?.id
    case .ambiguous: status = "ambiguous"
    case .unresolved: status = "unresolved"
    }
    try require(status == item.expected.status && key == item.expected.projectKey && label == item.expected.label
                  && profileID == item.expected.profileID, "Shared resolution: \(item.name)")
  }
  for item in fixture.snippets {
    let document = NativeReaderDocument(schemaVersion: 1,
      identity: NativeDocumentIdentity(documentID: "doc", serviceID: "service", revision: "r1", scope: .fixture),
      generation: 0, requiredCapabilities: ["semantic-tree-v1"], blocks: item.blocks.map(\.native), assets: [], diagnostics: [])
    let result = CrossProjectSnippetExtractor.extract(from: document, label: item.label, referenceText: item.reference_text,
      maxChars: item.max_chars ?? 600, maxBlocks: item.max_blocks ?? 4)
    let expected = item.expected.map { CrossProjectSnippetResult(text: $0.text, truncated: $0.truncated) }
    try require(result == expected, "Shared snippet: \(item.name)")
  }
}

private func testNavigationStack() throws {
  var stack = CrossProjectNavigationStack()
  try require(stack.maxDepth == 64 && !stack.canGoBack && stack.backLabel == nil
                && stack.peek() == nil && stack.pop() == nil, "Empty stack semantics")
  func location(_ number: Int) -> CrossProjectNavigationEntry {
    CrossProjectNavigationEntry(profileID: "p\(number)", documentTitle: "Document \(number)",
                                anchor: "label-\(number)", blockID: "block-\(number)", scrollOffset: Double(number) / 10)
  }
  for index in 0..<70 { stack.push(location(index)) }
  try require(stack.peek() == location(69) && stack.backLabel == "Document 69" && stack.canGoBack,
              "Peek and back metadata reflect last location")
  let copy = stack
  try require(stack.peek() == copy.peek() && stack == copy, "Peek must not mutate stack")
  for index in stride(from: 69, through: 6, by: -1) {
    try require(stack.pop() == location(index), "Bounded stack must retain all location fields in LIFO order")
  }
  try require(!stack.canGoBack && stack.pop() == nil, "Oldest entries must be evicted at depth 64")
  stack.maxDepth = 2
  stack.push(location(1)); stack.push(location(2)); stack.push(location(3))
  try require(stack.pop() == location(3) && stack.pop() == location(2) && stack.pop() == nil, "Custom capacity")
  stack.push(location(1)); stack.push(location(2)); stack.maxDepth = 1
  try require(stack.pop() == location(2) && stack.pop() == nil, "Capacity reduction trims immediately")
  stack.maxDepth = 0; stack.push(location(1))
  try require(stack.peek() == nil, "Zero depth disables history")
  stack.maxDepth = -1; stack.push(location(1))
  try require(stack.peek() == nil, "Negative depth disables history")
}

@main
enum ProjectServiceTests {
  static func main() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data("Fixture".utf8).write(to: root.appendingPathComponent("main.typ"))
    let profile = Profile(
      id: "fixture", name: "original", root: root.path, entry: "main.typ", fonts: [],
      packages: "", port: 24650, publicURL: "", label: "com.example.fixture"
    )
    var settings = Settings(selectedID: profile.id, profiles: [profile])
    var updated = profile
    updated.name = "updated"
    let events = Events()
    let store = TestStore(events: events)
    let agents = TestAgents(events: events)
    let service = ProjectService(store: store, launchAgents: agents)

    switch CommandLine.arguments[1] {
    case "reference-key": try testReferenceKey(profile)
    case "trailing-newline-validation": try testTrailingNewlineValidation(profile)
    case "directory-discovery": try testDirectoryDiscovery(service, root)
    case "directory-registration": try testDirectoryRegistration(service, settings, root, store, events)
    case "directory-failures": try testDirectoryFailures(service, settings, root, store, events)
    case "cross-project-catalog": try testCatalog(root, profile)
    case "cross-project-shared-fixture": try testSharedCrossProjectFixture(URL(fileURLWithPath: CommandLine.arguments[2]))
    case "cross-project-stack": try testNavigationStack()
    case "select-profile", "select-invalid-profile", "select-save-failure":
      var second = profile
      second.id = "second"
      second.label = "com.example.second"
      second.port = 24651
      settings.profiles.append(second)
      let before = try settingsData(settings)
      switch CommandLine.arguments[1] {
      case "select-profile":
        let result = try service.selectProfile(second.id, in: settings)
        var expected = settings
        expected.selectedID = second.id
        try require(
          try settingsData(result) == settingsData(expected),
          "Selection must preserve profiles and change only the selected ID")
        try require(
          try settingsData(store.savedSettings!) == settingsData(result),
          "Returned settings must match the persisted selection")
        try require(
          events.values == ["save:original"],
          "Selection must save once without controlling services")
      case "select-invalid-profile":
        do {
          _ = try service.selectProfile("missing", in: settings)
          throw FixtureError.start
        } catch is FlowError {}
        try require(
          events.values.isEmpty, "Unknown profiles must not reach storage or services")
      default:
        store.failFirstSave = true
        var callerSettings = settings
        try expectFailure(.save) {
          callerSettings = try service.selectProfile(second.id, in: callerSettings)
        }
        try require(
          try settingsData(callerSettings) == before,
          "Failed selection must preserve the caller's prior profiles and selected ID")
        try require(
          events.values == ["save:original"],
          "Failed selection must not control or recover services")
      }
      try require(try settingsData(settings) == before, "Selection must not mutate input settings")
    case "create-project", "create-fonts-and-used-ports":
      let withFonts = CommandLine.arguments[1] == "create-fonts-and-used-ports"
      if withFonts {
        try FileManager.default.createDirectory(
          at: root.appendingPathComponent("fonts"), withIntermediateDirectories: true)
        settings.profiles[0].port = 23625
        var second = profile
        second.id = "second"
        second.label = "com.example.second"
        second.port = 23627
        settings.profiles.append(second)
      }
      let before = try settingsData(settings)
      let home = root.appendingPathComponent("home")
      let result = try service.addProject(
        at: root.appendingPathComponent("main.typ"), in: settings, userHome: home)
      let created = result.profiles.last!
      try require(
        created.id.range(of: "^project-[0-9a-f]{8}$", options: .regularExpression) != nil,
        "New projects must retain the UUID-based ID format")
      try require(
        created.label == LagrangianIdentity.bundleID + ".preview." + created.id,
        "LaunchAgent labels must retain the app and project identity")
      try require(
        created.name == root.lastPathComponent && created.root == root.path
          && created.entry == "main.typ", "The selected file must determine project paths and name")
      try require(
        created.fonts == (withFonts ? ["fonts"] : []),
        "Only an existing project fonts path is included by default")
      try require(
        created.packages
          == home.appendingPathComponent(
            "Library/Application Support/typst/packages"
          ).path,
        "Packages must use the supplied home")
      try require(
        created.port == (withFonts ? 23626 : 23625) && created.publicURL.isEmpty,
        "Creation must choose the first unused default port and no public URL")
      try require(result.selectedID == created.id, "The new project must be selected")
      var previous = result
      previous.profiles.removeLast()
      previous.selectedID = settings.selectedID
      try require(try settingsData(previous) == before, "Existing profiles must remain unchanged")
      try require(try settingsData(settings) == before, "Creation must not mutate input settings")
      try require(
        try settingsData(store.savedSettings!) == settingsData(result),
        "Returned settings must match the saved settings")
      try require(
        events.values == ["save:original"], "Creation must save once without controlling services")
    case "create-invalid-project":
      let before = try settingsData(settings)
      do {
        _ = try service.addProject(
          at: root.appendingPathComponent("invalid.txt"), in: settings, userHome: root)
        throw FixtureError.start
      } catch is FlowError {}
      try require(
        events.values.isEmpty, "Invalid project settings must not reach storage or services")
      try require(try settingsData(settings) == before, "Failed validation must preserve settings")
    case "create-save-failure":
      store.failFirstSave = true
      let before = try settingsData(settings)
      var callerSettings = settings
      try expectFailure(.save) {
        callerSettings = try service.addProject(
          at: root.appendingPathComponent("main.typ"), in: callerSettings, userHome: root)
      }
      try require(
        try settingsData(callerSettings) == before,
        "The caller must keep its prior profiles and selection when saving fails")
      try require(
        events.values == ["save:original"], "Failed creation must not control or recover services")
    case "agent-update-delayed-exit", "agent-restart-delayed-exit", "agent-shutdown-timeout":
      let environment = AppEnvironment(
        variables: ["FLOW_DATA_DIR": root.appendingPathComponent("data").path],
        userHome: root, executable: root.appendingPathComponent("Lagrangian"))
      var launchAgents = LaunchAgentService(environment: environment)
      let timesOut = CommandLine.arguments[1] == "agent-shutdown-timeout"
      launchAgents.shutdownTimeout = timesOut ? 0.02 : 1
      var running = true
      var retiring = false
      var exitPolls = 0
      var bootstraps = 0
      launchAgents.processExists = { _ in running }
      launchAgents.commands.execute = { path, arguments, _ in
        if path == "/usr/sbin/lsof" { return "" }
        switch arguments[0] {
        case "print":
          if retiring && !timesOut {
            exitPolls += 1
            if exitPolls >= 3 {
              running = false
              retiring = false
            }
            // launchd can forget the job one poll before the actual process has exited.
            if exitPolls >= 2 { return "" }
          }
          return running ? "    pid = 123\n" : ""
        case "bootout":
          if running {
            retiring = true
            exitPolls = 0
          }
        case "bootstrap":
          try require(
            !running && exitPolls >= 3,
            "New service must bootstrap only after confirmed previous process exit")
          bootstraps += 1
          running = true
        default: break
        }
        return ""
      }
      if timesOut {
        do {
          try launchAgents.control("restart", profile)
          throw FixtureError.start
        } catch let error as FlowError {
          try require(error.message.contains("종료"), "Shutdown timeout must explain its cause")
        }
        try require(bootstraps == 0, "Timed-out shutdown must never bootstrap a replacement")
      } else {
        updated.publicURL = "https://updated.example"
        if CommandLine.arguments[1] == "agent-update-delayed-exit" {
          let project = ProjectService(store: store, launchAgents: launchAgents)
          let saved = try project.updateProfile(updated, in: settings)
          try require(
            saved.profiles[0].publicURL == updated.publicURL,
            "Profile replacement must retain the saved settings")
        } else {
          try launchAgents.control("restart", updated)
        }
        try require(
          bootstraps == 1 && running,
          "Delayed shutdown must lead to one actual bootstrap instead of a skipped start")
        let plist = environment.agents.appendingPathComponent("\(profile.label).plist")
        let job =
          try PropertyListSerialization.propertyList(
            from: Data(contentsOf: plist), format: nil) as! [String: Any]
        let variables = job["EnvironmentVariables"] as! [String: String]
        try require(
          variables["TINYMIST_ALLOWED_ORIGINS"] == updated.publicURL,
          "The replacement must launch with the updated environment")
      }
    case "agent-ownership":
      let environment = AppEnvironment(
        variables: ["FLOW_DATA_DIR": root.appendingPathComponent("data").path],
        userHome: root, executable: root.appendingPathComponent("Lagrangian"))
      let launchAgents = LaunchAgentService(environment: environment)
      let plist = environment.agents.appendingPathComponent("\(profile.label).plist")
      try require(!launchAgents.managedByApp(profile), "A missing job must not be app-owned")
      try FileManager.default.createDirectory(
        at: environment.agents, withIntermediateDirectories: true)
      var job = launchAgents.agent(profile)
      let arguments = job["ProgramArguments"] as! [String]
      try require(
        arguments == [environment.executable.path, "--serve", profile.id],
        "Generated jobs must preserve the app serve invocation")
      func writeJob() throws {
        try PropertyListSerialization.data(fromPropertyList: job, format: .xml, options: 0)
          .write(to: plist)
      }
      try writeJob()
      try require(
        launchAgents.managedByApp(profile), "Generated jobs must be recognized as app-owned")
      for other in [
        [root.appendingPathComponent("other-app").path, "--serve", profile.id],
        [environment.executable.path, "--serve", "other-project"],
        [environment.executable.path, "--background", profile.id],
        arguments + ["extra"],
      ] {
        job["ProgramArguments"] = other
        try writeJob()
        try require(
          !launchAgents.managedByApp(profile), "Foreign invocations must not be app-owned")
      }
      job.removeValue(forKey: "ProgramArguments")
      try writeJob()
      try require(
        !launchAgents.managedByApp(profile), "Jobs without an invocation must not be app-owned")
      try Data("invalid plist".utf8).write(to: plist)
      try require(!launchAgents.managedByApp(profile), "Malformed jobs must not be app-owned")
    case "invalid-profile":
      updated.entry = "missing.typ"
      do {
        _ = try service.updateProfile(updated, in: settings)
        throw FixtureError.start
      } catch is FlowError {}
      try require(events.values.isEmpty, "Validation must happen before service or storage access")
    case "duplicate-port":
      var second = profile
      second.id = "second"
      second.label = "com.example.second"
      second.port = 24651
      settings.profiles.append(second)
      updated.port = second.port
      do {
        _ = try service.updateProfile(updated, in: settings)
        throw FixtureError.start
      } catch is FlowError {}
      try require(
        events.values.isEmpty, "Whole-settings validation must happen before stopping a service")
    case "stopped":
      agents.running = false
      let result = try service.updateProfile(updated, in: settings)
      try require(result.profiles[0].name == "updated", "Updated settings must be returned")
      try require(result.selectedID == settings.selectedID, "Selection must be preserved")
      try require(
        events.values == ["pid", "save:updated"], "A stopped service must remain stopped")
    case "running":
      _ = try service.updateProfile(updated, in: settings)
      try require(
        events.values == ["pid", "stop:original", "save:updated", "start:updated"],
        "Unexpected update order")
    case "save-failure":
      store.failFirstSave = true
      try expectFailure(.save) { _ = try service.updateProfile(updated, in: settings) }
      try require(
        events.values == [
          "pid", "stop:original", "save:updated", "save:original", "start:original",
        ], "Save failure must restore the previous configuration and service")
    case "start-failure":
      agents.failStart = true
      try expectFailure(.start) { _ = try service.updateProfile(updated, in: settings) }
      try require(
        events.values == [
          "pid", "stop:original", "save:updated", "start:updated", "save:original",
          "start:original",
        ], "Start failure must restore the previous configuration and service")
    case "stop-failure":
      agents.failStop = true
      try expectFailure(.stop) { _ = try service.updateProfile(updated, in: settings) }
      try require(
        events.values == ["pid", "stop:original"], "Failed stop must leave settings unchanged")
    case "settings-store":
      let environment = AppEnvironment(
        variables: [
          "FLOW_DATA_DIR": root.appendingPathComponent("data").path,
          "FLOW_LOG_DIR": root.appendingPathComponent("logs").path,
        ],
        userHome: root, executable: root.appendingPathComponent("Lagrangian")
      )
      let disk = SettingsStore(directory: environment.support)
      try require(try disk.load().profiles.isEmpty, "Missing settings must start empty")
      try disk.save(settings)
      let loaded = try disk.load()
      try require(
        loaded.profiles[0].id == profile.id && loaded.selectedID == profile.id,
        "Settings must round-trip")
      let attributes = try FileManager.default.attributesOfItem(atPath: disk.file.path)
      try require(
        (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600,
        "Settings must remain private")
      try require(
        environment.agents == root.appendingPathComponent("Library/LaunchAgents"),
        "LaunchAgents must use the supplied home")
    case "data-migration":
      let home = root.appendingPathComponent("migration-home")
      let oldSupport = home.appendingPathComponent(AppDataMigration.legacySupportPath)
      let newSupport = home.appendingPathComponent("Library/Application Support/Lagrangian")
      let oldLogs = home.appendingPathComponent(AppDataMigration.legacyLogPath)
      let newLogs = home.appendingPathComponent("Library/Logs/Lagrangian")
      try FileManager.default.createDirectory(at: oldSupport, withIntermediateDirectories: true)
      try FileManager.default.createDirectory(at: oldLogs, withIntermediateDirectories: true)
      try Data("profiles".utf8).write(to: oldSupport.appendingPathComponent("profiles.json"))
      try Data("log".utf8).write(to: oldLogs.appendingPathComponent("service.log"))

      try AppDataMigration.migrateDefaults(home: home, variables: [:])
      try require(
        try String(contentsOf: newSupport.appendingPathComponent("profiles.json"), encoding: .utf8)
          == "profiles",
        "Support files must move intact")
      try require(
        try String(contentsOf: newLogs.appendingPathComponent("service.log"), encoding: .utf8)
          == "log",
        "Log files must move intact")
      try require(
        try FileManager.default.destinationOfSymbolicLink(atPath: oldSupport.path)
          == newSupport.path,
        "The legacy support path must remain a compatibility symlink")
      try require(
        try FileManager.default.destinationOfSymbolicLink(atPath: oldLogs.path) == newLogs.path,
        "The legacy log path must remain a compatibility symlink")
      try AppDataMigration.migrateDefaults(home: home, variables: [:])

      let overrideHome = root.appendingPathComponent("override-home")
      let overrideLegacy = overrideHome.appendingPathComponent(AppDataMigration.legacySupportPath)
      try FileManager.default.createDirectory(at: overrideLegacy, withIntermediateDirectories: true)
      try AppDataMigration.migrateDefaults(
        home: overrideHome, variables: ["FLOW_DATA_DIR": root.appendingPathComponent("custom").path])
      try require(
        FileManager.default.fileExists(atPath: overrideLegacy.path),
        "Explicit data overrides must leave the default directory untouched")

      let collisionHome = root.appendingPathComponent("collision-home")
      let collisionOld = collisionHome.appendingPathComponent(AppDataMigration.legacySupportPath)
      let collisionNew = collisionHome.appendingPathComponent("Library/Application Support/Lagrangian")
      let collisionOldLogs = collisionHome.appendingPathComponent(AppDataMigration.legacyLogPath)
      let collisionNewLogs = collisionHome.appendingPathComponent("Library/Logs/Lagrangian")
      try FileManager.default.createDirectory(at: collisionOld, withIntermediateDirectories: true)
      try FileManager.default.createDirectory(at: collisionNew, withIntermediateDirectories: true)
      try FileManager.default.createDirectory(at: collisionOldLogs, withIntermediateDirectories: true)
      try FileManager.default.createDirectory(at: collisionNewLogs, withIntermediateDirectories: true)
      try Data("old".utf8).write(to: collisionOld.appendingPathComponent("old.txt"))
      try Data("new".utf8).write(to: collisionNew.appendingPathComponent("new.txt"))
      try Data("old log".utf8).write(to: collisionOldLogs.appendingPathComponent("old.log"))
      try Data("new log".utf8).write(to: collisionNewLogs.appendingPathComponent("new.log"))
      var collisionError: FlowError?
      do {
        try AppDataMigration.migrateDefaults(home: collisionHome, variables: [:])
      } catch let error as FlowError {
        collisionError = error
      }
      try require(collisionError != nil, "Conflicting data directories must fail")
      try require(
        collisionError!.message.contains(collisionOld.path)
          && collisionError!.message.contains(collisionNew.path),
        "The collision error must identify both paths")
      try require(
        FileManager.default.fileExists(atPath: collisionOld.appendingPathComponent("old.txt").path)
          && FileManager.default.fileExists(atPath: collisionNew.appendingPathComponent("new.txt").path)
          && FileManager.default.fileExists(atPath: collisionOldLogs.appendingPathComponent("old.log").path)
          && FileManager.default.fileExists(atPath: collisionNewLogs.appendingPathComponent("new.log").path),
        "A collision must leave both directories unchanged")
    default:
      throw FlowError(message: "Unknown test scenario")
    }
  }
}
