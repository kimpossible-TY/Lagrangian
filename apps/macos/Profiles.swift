import Foundation

struct FlowError: LocalizedError {
  let message: String
  var errorDescription: String? { message }
}

func require(_ condition: Bool, _ message: String) throws {
  if !condition { throw FlowError(message: message) }
}

private func matches(_ value: String, _ pattern: String) -> Bool {
  value.range(of: pattern, options: .regularExpression) != nil
}

struct Profile: Codable {
  var id: String
  var name: String
  var root: String
  var entry: String
  var fonts: [String]
  var packages: String
  var port: Int
  var publicURL: String
  var label: String

  var url: String { publicURL.isEmpty ? "http://127.0.0.1:\(port)/" : publicURL }

  func path(_ relative: String) -> String {
    let url =
      relative.hasPrefix("/")
      ? URL(fileURLWithPath: relative)
      : URL(fileURLWithPath: root).appendingPathComponent(relative)
    return url.standardizedFileURL.path
  }

  func validate(checkFiles: Bool = false, fileManager: FileManager = .default) throws {
    try require(matches(id, "^[a-z0-9][a-z0-9-]{0,63}$"), "프로젝트 ID가 올바르지 않습니다.")
    try require(!name.trimmingCharacters(in: .whitespaces).isEmpty, "프로젝트 이름을 입력하세요.")
    try require(root.hasPrefix("/") && !entry.isEmpty, "프로젝트 폴더와 진입 파일을 지정하세요.")
    let rootURL = URL(fileURLWithPath: root).standardizedFileURL.path
    let entryPath = path(entry)
    try require(
      entryPath.hasPrefix(rootURL + "/") && entryPath.hasSuffix(".typ"),
      "진입 파일은 프로젝트 폴더 안의 .typ 파일이어야 합니다.")
    try require((1024...65535).contains(port), "포트는 1024–65535 범위여야 합니다.")
    try require(matches(label, "^[a-zA-Z0-9][a-zA-Z0-9.-]+$"), "LaunchAgent 이름이 올바르지 않습니다.")
    if !publicURL.isEmpty {
      guard let url = URLComponents(string: publicURL) else {
        throw FlowError(message: "HTTPS 주소가 올바르지 않습니다.")
      }
      try require(
        url.scheme == "https" && url.host != nil && url.user == nil && url.password == nil
          && url.query == nil && url.fragment == nil && (url.path == "" || url.path == "/"),
        "공개 주소에는 HTTPS 호스트와 포트만 입력하세요."
      )
    }
    if checkFiles {
      try require(fileManager.fileExists(atPath: entryPath), "진입 파일을 읽을 수 없습니다: \(entryPath)")
      for font in fonts {
        try require(fileManager.fileExists(atPath: path(font)), "글꼴 폴더를 찾을 수 없습니다: \(path(font))")
      }
      if !packages.isEmpty {
        try require(fileManager.fileExists(atPath: packages), "패키지 폴더를 찾을 수 없습니다.")
      }
    }
  }
}

struct Settings: Codable {
  var schemaVersion = 1
  var selectedID: String = ""
  var profiles: [Profile] = []

  func validate() throws {
    try require(schemaVersion == 1, "지원하지 않는 설정 버전입니다.")
    try require(Set(profiles.map(\.id)).count == profiles.count, "프로젝트 ID가 중복됩니다.")
    try require(Set(profiles.map(\.port)).count == profiles.count, "프로젝트 포트가 중복됩니다.")
    try require(Set(profiles.map(\.label)).count == profiles.count, "LaunchAgent 이름이 중복됩니다.")
    for profile in profiles { try profile.validate() }
  }

  func profile(_ id: String) throws -> Profile {
    guard let profile = profiles.first(where: { $0.id == id }) else {
      throw FlowError(message: "프로젝트를 찾을 수 없습니다: \(id)")
    }
    return profile
  }
}
