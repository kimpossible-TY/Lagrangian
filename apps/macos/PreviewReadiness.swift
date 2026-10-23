import Foundation

enum PreviewReadiness {
  case ready
  case waiting(String)
  case failed(String)
}

/// A temporary viewer verifies an accepted document using the existing data-plane protocol.
/// HTTP success and compile success alone do not establish document availability.
final class PreviewReadinessProbe {
  private let session: URLSession
  private let socket: URLSessionWebSocketTask
  private let queue = DispatchQueue(label: "app.tinymist.flow.readiness")
  private var completion: ((PreviewReadiness) -> Void)?
  private var compileFailed = false

  init(profile: Profile, timeout: TimeInterval, completion: @escaping (PreviewReadiness) -> Void) {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = timeout
    session = URLSession(configuration: configuration)
    var request = URLRequest(url: URL(string: "ws://127.0.0.1:\(profile.port)/")!)
    request.setValue("http://127.0.0.1:\(profile.port)", forHTTPHeaderField: "Origin")
    socket = session.webSocketTask(with: request)
    socket.maximumMessageSize = 256 * 1024 * 1024
    self.completion = completion
    socket.resume()
    socket.send(.string("current")) { [weak self] error in
      guard let self, let error else { return }
      self.queue.async { self.finish(.waiting("문서 연결을 기다리는 중입니다: \(error.localizedDescription)")) }
    }
    receive()
    queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
      guard let self else { return }
      self.finish(
        self.compileFailed
          ? .failed("문서 컴파일에 실패했습니다. 진입 파일과 로그를 확인한 뒤 다시 읽기를 시작하세요.")
          : .waiting("엔진은 실행 중이지만 아직 읽을 문서를 전달하지 않았습니다."))
    }
  }

  func cancel() {
    queue.async {
      self.completion = nil
      self.socket.cancel(with: .goingAway, reason: nil)
      self.session.invalidateAndCancel()
    }
  }

  private func finish(_ result: PreviewReadiness) {
    guard let callback = completion else { return }
    completion = nil
    socket.cancel(with: .normalClosure, reason: nil)
    session.invalidateAndCancel()
    callback(result)
  }

  private func receive() {
    socket.receive { [weak self] result in
      guard let self else { return }
      self.queue.async {
        guard self.completion != nil else { return }
        switch result {
        case .failure(let error):
          self.finish(
            self.compileFailed
              ? .failed("문서 컴파일에 실패했습니다. 진입 파일과 로그를 확인하세요.")
              : .waiting("문서 연결을 기다리는 중입니다: \(error.localizedDescription)"))
        case .success(let message):
          if case .data(let data) = message {
            if data.starts(with: Data("new,".utf8)) && data.count > 4 {
              self.finish(
                self.compileFailed
                  ? .failed("문서 컴파일에 실패했습니다. 브라우저의 이전 문서는 유지됩니다. 진입 파일과 로그를 확인한 뒤 다시 읽기를 시작하세요.")
                  : .ready)
              return
            }
            if data == Data("compile-status,error".utf8) { self.compileFailed = true }
            if data == Data("compile-status,success".utf8) { self.compileFailed = false }
          }
          self.receive()
        }
      }
    }
  }

  static func start(
    _ profile: Profile, completion: @escaping (PreviewReadiness) -> Void
  ) -> () -> Void {
    let probe = PreviewReadinessProbe(profile: profile, timeout: 3, completion: completion)
    return { probe.cancel() }
  }
}
