import Darwin
import Foundation

struct EngineLaunch {
  let environment: AppEnvironment
  var fileManager: FileManager = .default

  func arguments(for profile: Profile) -> [String] {
    var arguments = [
      "preview", profile.path(profile.entry), "--root", profile.root,
      "--data-plane-host=127.0.0.1:\(profile.port)", "--control-plane-host=127.0.0.1:0",
      "--no-open", "--partial-rendering=true", "--preview-mode=document", "--follow-system-theme",
    ]
    for font in profile.fonts { arguments += ["--font-path", profile.path(font)] }
    if !profile.packages.isEmpty { arguments += ["--package-path", profile.packages] }
    return arguments
  }

  func variables(for profile: Profile) -> [String: String] {
    var variables = [
      "TINYMIST_PREVIEW_FOCUS_FILE": environment.focusFile(for: profile).path,
      "TINYMIST_PREVIEW_CHANGE_FILE": environment.changeFile(for: profile).path,
    ]
    if !profile.publicURL.isEmpty {
      variables["TINYMIST_ALLOWED_ORIGINS"] = profile.publicURL.trimmingCharacters(
        in: CharacterSet(charactersIn: "/"))
    }
    return variables
  }

  func serve(_ profile: Profile) throws -> Never {
    try profile.validate(checkFiles: true, fileManager: fileManager)
    try require(fileManager.isExecutableFile(atPath: environment.engine.path), "앱에 포함된 엔진이 없습니다.")
    try fileManager.createDirectory(
      at: environment.support.appendingPathComponent("focus"), withIntermediateDirectories: true)
    unsetenv("TINYMIST_ALLOWED_ORIGINS")
    unsetenv("TINYMIST_PREVIEW_FOCUS_FILE")
    for (key, value) in variables(for: profile) { setenv(key, value, 1) }
    let arguments = ([environment.engine.path] + arguments(for: profile)).map { strdup($0) } + [nil]
    arguments.withUnsafeBufferPointer { _ = execv(environment.engine.path, $0.baseAddress!) }
    throw FlowError(message: "엔진 실행 실패: \(String(cString: strerror(errno)))")
  }
}
