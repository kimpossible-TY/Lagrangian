import Foundation

struct CrossProjectCatalogEntry: Codable, Equatable {
  var page: Int
  var text: String
  var x: Double? = nil
  var y: Double? = nil
}

struct CrossProjectCatalogProject: Codable, Equatable {
  var title: String
  var pdfURL: String
  var references: [String: CrossProjectCatalogEntry]
  var ambiguousLabels: [String]

  enum CodingKeys: String, CodingKey {
    case title, references
    case pdfURL = "pdf_url"
    case ambiguousLabels = "ambiguous_labels"
  }
}

struct CrossProjectTarget: Equatable {
  let projectKey: String
  let label: String
  let project: CrossProjectCatalogProject
  let entry: CrossProjectCatalogEntry
}

enum CrossProjectResolution: Equatable {
  case unique(CrossProjectTarget)
  /// May be empty when the producer reports a duplicate label without publishing its entries.
  case ambiguous([CrossProjectTarget])
  case unresolved
}

/// Read-only catalog policy. Loading never fetches PDFs or starts another project's service.
struct CrossProjectCatalog: Equatable {
  let projects: [String: CrossProjectCatalogProject]

  private struct Document: Decodable {
    let schema: Int
    let projects: [String: CrossProjectCatalogProject]
  }

  static func load(from url: URL, maxBytes: Int = 16 * 1024 * 1024) throws -> CrossProjectCatalog {
    try require(maxBytes > 0 && maxBytes < Int.max, "프로젝트 참조 목록 크기 제한이 올바르지 않습니다.")
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    let data = try handle.read(upToCount: maxBytes + 1) ?? Data()
    try require(data.count <= maxBytes, "프로젝트 참조 목록이 크기 제한을 초과합니다.")
    let document = try JSONDecoder().decode(Document.self, from: data)
    try require(document.schema == 1, "지원하지 않는 프로젝트 참조 목록 버전입니다.")
    for project in document.projects.values {
      for entry in project.references.values {
        try require(entry.page > 0 && entry.x?.isFinite != false && entry.y?.isFinite != false,
                    "프로젝트 참조 위치가 올바르지 않습니다.")
      }
    }
    return CrossProjectCatalog(projects: document.projects)
  }

  func resolve(projectKey: String, label: String) -> CrossProjectResolution {
    guard let project = projects[projectKey] else { return .unresolved }
    if project.ambiguousLabels.contains(label) { return .ambiguous([]) }
    guard let entry = project.references[label] else { return .unresolved }
    return .unique(CrossProjectTarget(projectKey: projectKey, label: label, project: project, entry: entry))
  }

  func resolve(url: String, linkText: String?) -> CrossProjectResolution {
    guard var components = URLComponents(string: url),
          let fragment = components.fragment, fragment.hasPrefix("page="),
          let page = Int(fragment.dropFirst(5)), page > 0 else { return .unresolved }
    components.fragment = nil
    guard let pdfURL = components.string else { return .unresolved }
    var targets: [CrossProjectTarget] = []
    var hasAmbiguousLabel = false
    for key in projects.keys.sorted() {
      let project = projects[key]!
      guard project.pdfURL == pdfURL else { continue }
      for label in project.references.keys.sorted() {
        let entry = project.references[label]!
        guard entry.page == page else { continue }
        if let linkText,
           linkText != entry.text && linkText != entry.text + " of " + project.title { continue }
        targets.append(CrossProjectTarget(projectKey: key, label: label, project: project, entry: entry))
        hasAmbiguousLabel = hasAmbiguousLabel || project.ambiguousLabels.contains(label)
      }
    }
    if targets.isEmpty { return .unresolved }
    if targets.count == 1 && !hasAmbiguousLabel { return .unique(targets[0]) }
    return .ambiguous(targets)
  }

  func matchProfile(for projectKey: String, in profiles: [Profile]) -> Profile? {
    guard !Self.normalized(projectKey).isEmpty else { return nil }
    let explicit = profiles.filter { $0.projectRefKey == projectKey && $0.projectRefKey?.isEmpty == false }
    if !explicit.isEmpty { return explicit.count == 1 ? explicit[0] : nil }
    let key = Self.normalized(projectKey)
    let fallback = profiles.filter {
      // A configured key is authoritative, even if this folder happens to resemble another key.
      ($0.projectRefKey == nil || $0.projectRefKey == "")
        && (Self.normalized($0.name) == key
          || Self.normalized(URL(fileURLWithPath: $0.root).lastPathComponent) == key)
    }
    return fallback.count == 1 ? fallback[0] : nil
  }

  private static func normalized(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      .split(whereSeparator: { $0.isWhitespace || $0 == "_" || $0 == "-" })
      .joined(separator: "-")
  }
}

struct CrossProjectNavigationEntry: Equatable {
  var profileID: String
  var documentTitle: String
  var anchor: String?
  var blockID: String?
  var scrollOffset: Double
}

struct CrossProjectNavigationStack: Equatable {
  var maxDepth: Int = 64 {
    didSet { trim() }
  }
  private var entries: [CrossProjectNavigationEntry] = []
  var canGoBack: Bool { !entries.isEmpty }
  var backLabel: String? { entries.last?.documentTitle }

  mutating func push(_ entry: CrossProjectNavigationEntry) {
    entries.append(entry)
    trim()
  }

  mutating func pop() -> CrossProjectNavigationEntry? { entries.popLast() }
  func peek() -> CrossProjectNavigationEntry? { entries.last }

  private mutating func trim() {
    let excess = entries.count - max(0, maxDepth)
    if excess > 0 { entries.removeFirst(excess) }
  }
}
