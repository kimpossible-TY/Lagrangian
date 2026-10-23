import Foundation

enum ReadingSessionPhase {
  case idle, validating, requested, running, ready, stopped, sleeping, failed
}

struct ReadingSessionSnapshot {
  var profileID: String?
  var phase: ReadingSessionPhase = .idle
  var message = "프로젝트를 추가해 시작하세요"
  var detail = ""
  var pid: Int?
  var isBusy = false
}

private final class ReadingOperationTicket {
  private let lock = NSLock()
  private var cancelled = false
  var isCancelled: Bool {
    lock.lock()
    defer { lock.unlock() }
    return cancelled
  }
  func cancel() {
    lock.lock()
    cancelled = true
    lock.unlock()
  }
}

/// Main-thread session policy; blocking storage and launchd work share one serial worker.
/// Platform sleep/network/power events are supplied by the AppKit composition.
final class ReadingSessionController {
  typealias Probe = (Profile, @escaping (PreviewReadiness) -> Void) -> () -> Void
  private let launchAgents: ProjectControlling
  private let probe: Probe
  private let validate: (Profile) throws -> Void
  private let openBrowser: (URL) -> Bool
  private let onChange: (ReadingSessionSnapshot) -> Void
  private let worker = DispatchQueue(label: "app.tinymist.flow.session", qos: .userInitiated)
  private let startupTimeout: TimeInterval
  private let retryInterval: TimeInterval
  private var profile: Profile?
  private var generation = 0
  private var operation = ReadingOperationTicket()
  private var probeGeneration = 0
  private var cancelProbe: (() -> Void)?
  private var probing = false
  private var timer: DispatchWorkItem?
  private var deadlineTimer: DispatchWorkItem?
  private var deadline: Date?
  private var openWhenReady = false
  private var commandRunning = false
  private var storageMutationRunning = false
  private var stopping = false
  private var verifiedPID: Int?
  private var verifiedAt: Date?
  private var sleeping = false
  private var constrainedPower = false
  private var disposed = false
  private var lastWaitReason = "엔진이 아직 실행되지 않았습니다."
  private(set) var snapshot = ReadingSessionSnapshot()

  var idleProbeInterval: TimeInterval { constrainedPower ? 30 : 8 }

  init(
    launchAgents: ProjectControlling,
    onChange: @escaping (ReadingSessionSnapshot) -> Void,
    openBrowser: @escaping (URL) -> Bool,
    probe: @escaping Probe = PreviewReadinessProbe.start,
    validate: @escaping (Profile) throws -> Void = { try $0.validate(checkFiles: true) },
    startupTimeout: TimeInterval = 30,
    retryInterval: TimeInterval = 0.5
  ) {
    self.launchAgents = launchAgents
    self.onChange = onChange
    self.openBrowser = openBrowser
    self.probe = probe
    self.validate = validate
    self.startupTimeout = startupTimeout
    self.retryInterval = retryInterval
  }

  func select(_ profile: Profile?) {
    guard !disposed else { return }
    invalidate()
    self.profile = profile
    snapshot = ReadingSessionSnapshot(profileID: profile?.id)
    if sleeping {
      publish(.sleeping, "잠자기 중 · 깨어나면 연결을 확인합니다")
    } else {
      if profile != nil { publish(.idle, "프로젝트 상태를 확인하는 중…") }
      refresh()
    }
  }

  func read() {
    guard !disposed, !sleeping, !commandRunning, deadline == nil, let profile else { return }
    beginCommand("start", profile: profile, open: true)
  }

  func control(_ action: String) {
    guard !disposed, !sleeping, let profile else { return }
    guard action == "stop" || (!commandRunning && deadline == nil) else { return }
    beginCommand(action, profile: profile, open: false)
  }

  private func beginCommand(_ action: String, profile: Profile, open: Bool) {
    invalidate()
    let current = generation
    let ticket = operation
    commandRunning = true
    stopping = action == "stop"
    openWhenReady = open
    deadline = Date().addingTimeInterval(startupTimeout)
    let timeout = DispatchWorkItem { [weak self] in
      guard let self, self.isCurrent(current) else { return }
      self.fail(
        "\(self.stopping ? "종료 확인" : "읽기 준비") 시간이 초과되었습니다. \(self.lastWaitReason) 로그를 확인한 뒤 다시 시도하세요."
      )
    }
    deadlineTimer = timeout
    DispatchQueue.main.asyncAfter(deadline: .now() + startupTimeout, execute: timeout)
    publish(.validating, action == "stop" ? "중지를 요청하는 중…" : "설정을 확인하는 중…")
    worker.async {
      guard !ticket.isCancelled else { return }
      do {
        if action != "stop" { try self.validate(profile) }
        guard !ticket.isCancelled else { return }
        DispatchQueue.main.async {
          guard self.isCurrent(current), !self.sleeping else { return }
          self.publish(.requested, action == "stop" ? "중지 요청을 보냈습니다" : "시작 요청을 보냈습니다")
        }
        try self.launchAgents.control(action, profile)
        DispatchQueue.main.async {
          guard self.isCurrent(current) else { return }
          self.commandRunning = false
          if action == "stop" {
            self.publish(.requested, "중지 요청 완료 · 종료를 확인하는 중…")
            self.refresh()
          } else {
            self.publish(.requested, "시작 요청 완료 · 엔진 실행을 확인하는 중…")
            self.refresh()
          }
        }
      } catch {
        DispatchQueue.main.async {
          guard self.isCurrent(current) else { return }
          self.fail(error.localizedDescription)
        }
      }
    }
  }

  /// Settings, project and login mutations use the same worker as service control.
  func performMutation<T>(
    message: String, work: @escaping () throws -> T,
    completion: @escaping (Result<T, Error>) -> Void
  ) {
    guard !disposed, !storageMutationRunning else {
      completion(.failure(FlowError(message: "다른 설정 작업이 진행 중이거나 앱이 종료되었습니다. 다시 시도하세요.")))
      return
    }
    invalidate()
    let current = generation
    commandRunning = true
    storageMutationRunning = true
    publish(.validating, message)
    worker.async {
      let result = Result { try work() }
      DispatchQueue.main.async {
        guard self.isCurrent(current) else { return }
        self.commandRunning = false
        self.storageMutationRunning = false
        if case .failure(let error) = result { self.fail(error.localizedDescription) }
        completion(result)
        if case .success = result, self.isCurrent(current), !self.sleeping { self.refresh() }
      }
    }
  }

  func refresh() { refresh(forceDocument: true) }

  private func refresh(forceDocument: Bool) {
    guard !disposed, !sleeping, !commandRunning else { return }
    guard let profile else {
      publish(.idle, "프로젝트를 추가해 시작하세요")
      return
    }
    guard !probing else { return }
    if let deadline, Date() >= deadline {
      fail("\(stopping ? "종료 확인" : "읽기 준비") 시간이 초과되었습니다. \(lastWaitReason) 로그를 확인한 뒤 다시 시도하세요.")
      return
    }
    timer?.cancel()
    timer = nil
    probing = true
    let current = generation
    let currentProbe = probeGeneration
    worker.async {
      let pid = self.launchAgents.jobPID(profile.label)
      DispatchQueue.main.async {
        guard self.isCurrent(current), self.probeGeneration == currentProbe, !self.sleeping else {
          return
        }
        guard let pid else {
          self.probing = false
          self.verifiedPID = nil
          self.snapshot.pid = nil
          self.lastWaitReason = "엔진이 아직 실행되지 않았습니다."
          if self.stopping {
            self.stopping = false
            self.deadline = nil
            self.deadlineTimer?.cancel()
            self.deadlineTimer = nil
          }
          self.publish(
            self.deadline == nil ? .stopped : .requested,
            self.deadline == nil ? "중지됨" : "시작 요청 완료 · 엔진 실행을 기다리는 중…")
          self.scheduleProbe()
          return
        }
        self.snapshot.pid = pid
        if self.stopping {
          self.probing = false
          self.lastWaitReason = "엔진이 아직 종료되지 않았습니다."
          self.publish(.requested, "중지 요청 완료 · 엔진 종료를 기다리는 중…")
          self.scheduleProbe()
          return
        }
        let verificationAge = self.verifiedAt.map { Date().timeIntervalSince($0) } ?? .infinity
        if !forceDocument && self.verifiedPID == pid
          && verificationAge < (self.constrainedPower ? 120 : 60)
        {
          self.probing = false
          self.scheduleProbe()
          return
        }
        if self.verifiedPID != pid || self.snapshot.phase != .ready {
          self.publish(.running, "엔진 실행 중 · 읽을 문서를 확인하는 중…")
        }
        self.cancelProbe = self.probe(profile) { result in
          DispatchQueue.main.async {
            guard self.isCurrent(current), self.probeGeneration == currentProbe, !self.sleeping
            else { return }
            // A full document from a process that exited during the probe is stale.
            self.worker.async {
              let latestPID = self.launchAgents.jobPID(profile.label)
              DispatchQueue.main.async {
                guard self.isCurrent(current), self.probeGeneration == currentProbe, !self.sleeping
                else { return }
                self.probing = false
                self.cancelProbe = nil
                self.probeGeneration += 1
                guard latestPID == pid else {
                  self.verifiedPID = nil
                  self.snapshot.pid = latestPID
                  self.lastWaitReason = "엔진이 재시작되어 문서를 다시 확인합니다."
                  self.publish(latestPID == nil ? .requested : .running, self.lastWaitReason)
                  self.scheduleProbe()
                  return
                }
                self.accept(result, pid: pid, profile: profile)
              }
            }
          }
        }
      }
    }
  }

  private func accept(_ result: PreviewReadiness, pid: Int, profile: Profile) {
    switch result {
    case .ready:
      verifiedPID = pid
      verifiedAt = Date()
      deadline = nil
      deadlineTimer?.cancel()
      deadlineTimer = nil
      let shouldOpen = openWhenReady
      openWhenReady = false
      let current = generation
      publish(.ready, "읽을 문서 준비됨 · PID \(pid)")
      guard isCurrent(current), !sleeping else { return }
      if shouldOpen {
        guard let url = URL(string: profile.url), openBrowser(url) else {
          fail("문서는 준비되었지만 브라우저를 열지 못했습니다. 주소를 복사해 브라우저에서 열어 주세요.")
          return
        }
      }
      guard isCurrent(current), !sleeping else { return }
      scheduleProbe()
    case .waiting(let reason):
      verifiedPID = nil
      lastWaitReason = reason
      publish(.running, "엔진 실행 중 · 문서 준비를 기다리는 중…", detail: reason)
      scheduleProbe()
    case .failed(let reason):
      fail(reason)
    }
  }

  private func scheduleProbe() {
    guard !disposed, !sleeping else { return }
    timer?.cancel()
    let remaining = deadline.map { max(0, $0.timeIntervalSinceNow) }
    let delay = remaining.map { min(retryInterval, $0) } ?? idleProbeInterval
    let task = DispatchWorkItem { [weak self] in self?.refresh(forceDocument: false) }
    timer = task
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
  }

  func setSleeping(_ sleeping: Bool) {
    guard !disposed, self.sleeping != sleeping else { return }
    self.sleeping = sleeping
    if storageMutationRunning {
      cancelCurrentProbe()
      openWhenReady = false
      deadline = nil
    } else {
      invalidate()
    }
    if sleeping { publish(.sleeping, "잠자기 중 · 깨어나면 연결을 확인합니다") } else { refresh() }
  }

  func networkChanged() {
    guard !disposed, !sleeping, !commandRunning else { return }
    cancelCurrentProbe()
    verifiedPID = nil
    refresh()
  }

  func setConstrainedPower(_ constrained: Bool) {
    guard !disposed, constrainedPower != constrained else { return }
    constrainedPower = constrained
    if !probing && !commandRunning && snapshot.phase != .failed { scheduleProbe() }
  }

  func dispose() {
    invalidate()
    disposed = true
  }

  func reportFailure(_ error: Error) {
    guard !disposed else { return }
    invalidate()
    fail(error.localizedDescription)
  }

  private func cancelCurrentProbe() {
    probeGeneration += 1
    cancelProbe?()
    cancelProbe = nil
    probing = false
    timer?.cancel()
    timer = nil
  }

  private func invalidate() {
    generation += 1
    operation.cancel()
    operation = ReadingOperationTicket()
    cancelCurrentProbe()
    deadline = nil
    deadlineTimer?.cancel()
    deadlineTimer = nil
    openWhenReady = false
    commandRunning = false
    storageMutationRunning = false
    stopping = false
    verifiedPID = nil
    verifiedAt = nil
    lastWaitReason = "엔진이 아직 실행되지 않았습니다."
  }

  private func isCurrent(_ value: Int) -> Bool { !disposed && generation == value }

  private func fail(_ reason: String) {
    invalidate()
    publish(.failed, "작업을 완료하지 못했습니다", detail: reason)
  }

  private func publish(_ phase: ReadingSessionPhase, _ message: String, detail: String? = nil) {
    snapshot.profileID = profile?.id
    snapshot.phase = phase
    snapshot.message = message
    snapshot.detail = detail ?? profile?.url ?? ""
    snapshot.isBusy = commandRunning || deadline != nil
    onChange(snapshot)
  }
}
