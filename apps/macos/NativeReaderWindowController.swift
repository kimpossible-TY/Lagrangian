import AppKit

/// Explicit offline runtime inputs. No PATH, scratch install or checkout discovery.
struct NativeReaderRuntime {
  let node: URL
  let helper: URL
  let runtime: URL
  var record: @Sendable (NativeMathExecution) -> Void = { _ in }
  func worker() throws -> NativeMathWorker {
    guard [node, helper, runtime].allSatisfy({ $0.isFileURL && $0.path.hasPrefix("/") }),
          FileManager.default.isExecutableFile(atPath: node.path),
          FileManager.default.fileExists(atPath: helper.path),
          FileManager.default.fileExists(atPath: runtime.appendingPathComponent("node_modules/@mathjax/src/package.json").path)
    else { throw NativeObjectError.unsupported("math-runtime-not-delivered") }
    return NativeMathWorker(node: node, helper: helper, runtime: runtime, record: record)
  }
}

/// One window, one store, one session. Heavy preparation never publishes a snapshot.
@MainActor final class NativeReaderWindowController {
  typealias Target = (Profile) async throws -> NativeDocumentIdentity
  typealias Assets = (NativeReaderDocument, NativeReaderRequestContext) async throws -> [String: Data]
  let store = NativeReaderDocumentStore()
  lazy var textView = NativeReaderTextView(store: store)
  private(set) var session: NativeReaderSession!
  private(set) var acceptedPaintKey: NativeReaderTextRenderKey?
  private(set) var preparingKey: NativeReaderTextRenderKey?
  private(set) var paintedKey: NativeReaderTextRenderKey?
  private(set) var diagnostic: String?
  private var cache: (key: NativeReaderTextRenderKey, objects: [String: NativeReaderPreparedTextObject])?
  private var profile: Profile?
  private let provider: NativeReaderDocumentProviding
  private let target: Target
  private let assets: Assets
  private let actions: (() async throws -> NativeReaderActions)?
  private let invalidate: () async -> Void
  private let show: Bool
  private let avoidActivation: Bool
  private var progress: ((NativeReadProgress) -> Void)?
  private var requestTicket = ReadingOperationTicket()
  private var actionTasks = [UUID: Task<Void, Never>]()
  private var selectionTask: Task<Void, Never>?
  private var disposed = false
  private var layoutObserver: NSObjectProtocol?
  private var reflowTask: Task<Void, Never>?
  var runtime: NativeReaderRuntime?
  var copyText: (String) -> Bool = { _ in false }
  var openHomepage: ((URL) -> Void)?
  private(set) var chatView: NativeReaderChatView?
  lazy var hostWindow = NativeReaderHostWindow(reader: textView, show: show, avoidActivation: avoidActivation)

  init(provider: NativeReaderDocumentProviding, target: @escaping Target,
       assets: @escaping Assets = { document, _ in
         guard document.assets.isEmpty else { throw NativeObjectError.unsupported("asset-provider-unavailable") }
         return [:]
       }, runtime: NativeReaderRuntime? = nil,
       actions: (() async throws -> NativeReaderActions)? = nil,
       invalidate: @escaping () async -> Void = {}, show: Bool = true, avoidActivation: Bool = false) {
    self.provider = provider; self.target = target; self.assets = assets; self.runtime = runtime
    self.actions = actions; self.invalidate = invalidate; self.show = show; self.avoidActivation = avoidActivation
    session = NativeReaderSession(store: store, provider: provider, target: { [weak self] in
      guard let self, let profile = self.profile else { throw NativeReaderOperationFailure.unavailable }
      return try await self.target(profile)
    }, invalidate: invalidate, prepare: { [weak self] document, context in
      guard let self else { throw NativeReaderContractError.disposed }
      return try await self.prepare(document, context: context)
    })
    session.onChange = { [weak self] in self?.sessionChanged() }
    session.onSelection = { [weak self] selection, context in self?.selectionChanged(selection, context: context) }
    textView.cachedObject = { [weak self] node, key in
      guard let cache = self?.cache, cache.key == key else { return nil }
      return cache.objects[node.id]
    }
    textView.callbacks.selectionChanged = { [weak self] selection in
      guard let self, let selection else { return }
      do { try self.session.hold(selection) } catch { self.report(error) }
    }
    // Only NA02's explicit user release enters this callback. Source/network ack never does.
    textView.callbacks.selectionReleased = { [weak self] in self?.session.acknowledge(ticket: $0) }
    textView.callbacks.painted = { [weak self] key in
      guard let self, !self.disposed, !self.requestTicket.isCancelled,
            self.acceptedPaintKey == key, self.textView.renderKey == key,
            self.session.context == self.textView.context, self.store.document?.identity == key.identity,
            self.store.document?.generation == key.documentGeneration else { return }
      self.paintedKey = key; self.progress?(.painted)
    }
    textView.callbacks.copyText = { [weak self] in self?.copyText($0) ?? false }
    textView.callbacks.sourceRequested = { [weak self] in self?.source($0) }
    textView.callbacks.chatRequested = { [weak self] command, context in self?.chat(command, context: context) }
    textView.callbacks.statusChanged = { [weak self] message in
      guard let self else { return }
      self.diagnostic = message
      self.layoutChanged()
    }
    textView.postsFrameChangedNotifications = true
    layoutObserver = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: textView, queue: .main) { [weak self] _ in
      Task { @MainActor in self?.layoutChanged() }
    }
    hostWindow.onClose = { [weak self] in self?.cancel() }
  }

  func open(_ profile: Profile, progress: @escaping (NativeReadProgress) -> Void) -> () -> Void {
    guard !disposed else { progress(.failed("Reader disposed")); return {} }
    guard self.profile == nil || self.profile == profile else {
      progress(.failed("Create a new view for another profile")); return {}
    }
    self.profile = profile; self.progress = progress
    requestTicket.cancel(); let ticket = ReadingOperationTicket(); requestTicket = ticket
    acceptedPaintKey = nil; paintedKey = nil; diagnostic = nil
    hostWindow.initialize()
    session.refresh()
    return { [weak self] in
      ticket.cancel()
      Task { @MainActor in
        guard let self, self.requestTicket === ticket else { return }; self.cancel()
      }
    }
  }

  func refresh() { acceptedPaintKey = nil; paintedKey = nil; session.refresh() }

  private func prepare(_ document: NativeReaderDocument, context: NativeReaderRequestContext, reflowOnly: Bool = false) async throws -> NativeReaderSession.PreparedAdoption {
    let ticket = requestTicket
    let key = try textView.preparationKey(for: document, context: context)
    let descriptors = try await assets(document, context)
    try Task.checkCancellation()
    let hasObjects = document.blocks.flatMap(\.orderedNodes).contains { [.math, .equation, .table, .figure, .image].contains($0.kind) }
    var objects = [String: NativeReaderPreparedTextObject]()
    if hasObjects {
      let needsMath = document.blocks.flatMap(\.orderedNodes).contains { $0.kind == .math }
      let worker: NativeMathWorker?
      if needsMath {
        guard let runtime else {
          diagnostic = "math-runtime-not-delivered (exit 2): prior accepted view retained"
          throw NativeObjectError.unsupported("math-runtime-not-delivered")
        }
        worker = try runtime.worker()
      } else { worker = nil }
      let objectContext = NativeObjectContext(identity: document.identity, snapshotGeneration: document.generation,
        generation: key.layoutGeneration, width: Double(key.width), fontSize: Double(key.appearance.effectiveSize),
        fontName: "system", theme: key.appearance.theme == .dark ? .dark : .light, mode: .reflow, pageHeight: 1000)
      preparingKey = key
      defer { if preparingKey == key { preparingKey = nil } }
      let job = Task.detached(priority: .userInitiated) {
        precondition(!Thread.isMainThread, "Object preparation must leave the UI thread")
        return try await NativeReaderPagedLayout.layout(document: document, context: objectContext, assets: descriptors,
          math: { node, width in
            guard let worker, let math = node.math else { throw NativeObjectError.unsupported("math-runtime-not-delivered") }
            return try await worker.calculate(math, context: objectContext, width: width)
          }, cancelled: { ticket.isCancelled })
      }
      let plan = try await withTaskCancellationHandler(operation: { try await job.value }, onCancel: { job.cancel() })
      try Task.checkCancellation()
      guard plan.diagnostics.isEmpty else { throw NativeObjectError.unsupported(plan.diagnostics.joined(separator: ";")) }
      for node in document.blocks.flatMap(\.orderedNodes) where [.math, .equation, .table, .figure, .image].contains(node.kind) {
        guard let region = plan.regions.first(where: { $0.node.id == node.id }) else { throw NativeReaderTextFailure.unsupportedObject(node.id) }
        let bounds = region.frames.reduce(CGRect.null) { $0.union($1) }
        guard !bounds.isNull, bounds.width > 0, bounds.height > 0, bounds.width <= key.width else { throw NativeObjectError.invalidGeometry }
        let ids = Set(node.orderedNodes.map(\.id))
        let subplan = NativeObjectPlan(context: plan.context, items: plan.items.filter { ids.contains($0.nodeID) },
          regions: plan.regions.filter { ids.contains($0.node.id) }, size: bounds.size, pageCount: 1, diagnostics: [], cost: plan.cost)
        var prepared = NativeReaderPreparedTextObject(key: key, size: bounds.size,
          baseline: min(bounds.height, CGFloat(objectContext.fontSize) * 0.2),
          accessibilityLabel: node.alt ?? node.math?.normalizedText ?? (node.displayText.isEmpty ? node.kind.rawValue : node.displayText),
          draw: { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return }
            context.saveGState(); context.clip(to: rect)
            context.translateBy(x: rect.minX - bounds.minX, y: rect.minY - bounds.minY)
            NativeReaderObjectRenderer.draw(subplan, in: context); context.restoreGState()
          })
        prepared.hitNode = { subplan.hit(CGPoint(x: $0.x + bounds.minX, y: $0.y + bounds.minY))?.node.id }
        prepared.accessibilityLabelForNode = { id in subplan.regions.first { $0.node.id == id }.map { $0.node.alt ?? $0.node.math?.normalizedText ?? $0.node.displayText } }
        objects[node.id] = prepared
      }
    }
    let preparedObjects = objects
    return .init(isCurrent: { [weak self] in
      guard let self, !self.disposed, !ticket.isCancelled else { return false }
      return try self.textView.preparationKey(for: document, context: context) == key
    }, adopt: { [weak self] in
      guard let self, !self.disposed, !ticket.isCancelled,
            try self.textView.preparationKey(for: document, context: context) == key else { throw NativeObjectError.stale }
      let previous = self.cache
      self.cache = (key, preparedObjects)
      do {
        if reflowOnly {
          guard self.store.document == document else { throw NativeObjectError.stale }
          try self.textView.refreshPreparedObjects(for: key)
        } else { try self.textView.adopt(document, context: context) }
      }
      catch { self.cache = previous; throw error }
      self.acceptedPaintKey = key; self.paintedKey = nil; self.diagnostic = nil
    })
  }

  /// Reprepare only the latest layout key. Session retains incoming candidates;
  /// an accepted snapshot reflow never adopts/releases selection or changes service state.
  private func layoutChanged() {
    guard !disposed, !requestTicket.isCancelled else { return }
    session.preparationChanged()
    guard let document = store.document, let context = session.context,
          store.generation == document.generation, context == textView.context,
          let key = textView.requestedRenderKey, key != cache?.key else { return }
    reflowTask?.cancel()
    acceptedPaintKey = nil; paintedKey = nil
    reflowTask = Task { [weak self] in
      guard let self else { return }
      do {
        // Let AppKit finish this layout pass before reading its final width.
        await Task.yield()
        let prepared = try await self.prepare(document, context: context, reflowOnly: true)
        try Task.checkCancellation()
        guard try prepared.isCurrent() else { return }
        try prepared.adopt()
      } catch { if !Task.isCancelled { self.report(error) } }
    }
  }

  private func sessionChanged() {
    guard !disposed, !requestTicket.isCancelled else { return }
    if let failure = session.failure {
      let message = diagnostic ?? failure
      hostWindow.notice.stringValue = message
      progress?(.failed(message)); return
    }
    guard session.state == .reading || session.state == .offline,
          let key = acceptedPaintKey, textView.renderKey == key, session.context == textView.context else { return }
    progress?(.accepted); progress?(.windowInitialized)
    hostWindow.present()
  }

  private func report(_ error: Error) {
    diagnostic = String(describing: error)
    hostWindow.notice.stringValue = diagnostic ?? "Reader unavailable"
  }

  private func selectionChanged(_ selection: NativeReaderSelection?, context: NativeReaderRequestContext) {
    let previous = selectionTask
    previous?.cancel()
    guard let actions else { return }
    selectionTask = Task {
      await previous?.value
      do { try Task.checkCancellation(); let owner = try await actions(); try Task.checkCancellation(); try await owner.updateSelection(selection, context: context) }
      catch { if !Task.isCancelled { report(error) } }
    }
  }
  private func source(_ request: NativeReaderSourceRequest) {
    guard let actions else { report(NativeReaderOperationFailure.unavailable); return }
    let selection = selectionTask
    guard actionTasks.count < 8 else { report(NativeReaderOperationFailure.unavailable); return }
    let id = UUID()
    actionTasks[id] = Task {
      defer { actionTasks.removeValue(forKey: id) }
      do {
        await selection?.value
        try session.authorize(request.context, selection: request.selection.ticket)
        let owner = try await actions()
        let result = try await owner.perform(request)
        try Task.checkCancellation()
        try session.authorize(request.context, selection: request.selection.ticket)
        _ = textView.acceptSourceResult(result, for: request)
      } catch { if !Task.isCancelled { report(error) } }
    }
  }
  private func chat(_ command: NativeReaderChatCommand, context: NativeReaderRequestContext) {
    guard let actions else { report(NativeReaderOperationFailure.unavailable); return }
    let selection = selectionTask
    guard actionTasks.count < 8 else { report(NativeReaderOperationFailure.unavailable); return }
    let id = UUID()
    actionTasks[id] = Task {
      defer { actionTasks.removeValue(forKey: id) }
      do {
        await selection?.value
        try session.authorize(context)
        let owner = try await actions()
        let state = try await owner.perform(command, context: context)
        try Task.checkCancellation(); try session.authorize(context)
        guard let conversation = await owner.conversation(state.conversationID) else { throw NativeReaderOperationFailure.unavailable }
        chatView?.dispose(); chatView?.removeFromSuperview()
        let chat = NativeReaderChatView(actions: owner, context: context, authorize: { [weak self = self] in
          guard let self else { throw NativeReaderContractError.disposed }; try self.session.authorize(context)
        })
        // nativeMath consumes TeX; the MathML helper is deliberately not passed here.
        chat.openHomepage = { [weak self = self] in self?.openHomepage?($0) }
        chat.present(conversation); chatView = chat; hostWindow.attachChat(chat)
        chat.presentAccount(try await owner.account(context: context))
      } catch { if !Task.isCancelled { report(error) } }
    }
  }

  func cancel() {
    preparingKey = nil
    reflowTask?.cancel(); reflowTask = nil
    requestTicket.cancel(); progress = nil; acceptedPaintKey = nil; paintedKey = nil
    selectionTask?.cancel(); selectionTask = nil
    actionTasks.values.forEach { $0.cancel() }; actionTasks.removeAll()
    chatView?.dispose(); session.cancel()
  }
  func dispose() {
    if let observer = layoutObserver { NotificationCenter.default.removeObserver(observer); layoutObserver = nil }
    cancel(); disposed = true; session.event(.dispose); textView.dispose(); hostWindow.window?.close() }
}

@MainActor final class NativeReaderHostWindow: NSWindowController, NSWindowDelegate {
  let reader: NativeReaderTextView
  let notice = NSTextField(wrappingLabelWithString: "Native Reader · reflow only; paged/runtime delivery pending")
  var onClose: (() -> Void)?
  private let show: Bool
  private let avoidActivation: Bool
  private let stack = NSStackView()
  init(reader: NativeReaderTextView, show: Bool, avoidActivation: Bool) {
    self.reader = reader; self.show = show; self.avoidActivation = avoidActivation
    super.init(window: nil)
  }
  required init?(coder: NSCoder) { nil }
  func initialize() { if window == nil { loadWindow() } }
  override func loadWindow() {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 840, height: 720),
      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.delegate = self; window.title = "Lagrangian · Native Reader"
    stack.orientation = .vertical; stack.alignment = .width
    let controls = NSStackView()
    for (title, action) in [("Copy", #selector(copySelected)), ("Source", #selector(sourceSelected)),
                             ("Highlight", #selector(highlightSelected)), ("Ask", #selector(askSelected))] {
      controls.addArrangedSubview(NSButton(title: title, target: self, action: action))
    }
    stack.addArrangedSubview(notice); stack.addArrangedSubview(controls); stack.addArrangedSubview(reader)
    stack.translatesAutoresizingMaskIntoConstraints = false; window.contentView!.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 16),
      stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -16),
      stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 16),
      stack.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor, constant: -16),
      reader.heightAnchor.constraint(greaterThanOrEqualToConstant: 220)])
    self.window = window
  }
  func present() {
    guard show, NSApp.activationPolicy() != .prohibited else { return }
    if avoidActivation { window?.orderFrontRegardless() } else { showWindow(nil) }
  }
  func attachChat(_ chat: NativeReaderChatView) { stack.addArrangedSubview(chat) }
  @objc func copySelected() { _ = reader.copyPlainText() }
  @objc func sourceSelected() { _ = reader.requestSource(.excerpt) }
  @objc func highlightSelected() { _ = reader.requestSource(.highlight) }
  @objc func askSelected() { reader.openChat() }
  func windowWillClose(_ notification: Notification) { onClose?() }
}

/// Explicit fixture-only adapter; never impersonates service/source acceptance.
struct NativeReaderFixtureProvider: NativeReaderDocumentProviding {
  let url: URL
  func load() async throws -> NativeReaderDocument {
    try await Task.detached {
      let document = try NativeReaderDocument.decode(Data(contentsOf: self.url))
      guard document.identity.scope == .fixture else { throw NativeReaderContractError.wrongTarget }
      return document
    }.value
  }
  func document(for context: NativeReaderRequestContext) async throws -> NativeReaderDocument {
    let value = try await load()
    guard value.identity == context.target else { throw NativeReaderContractError.wrongTarget }
    return value.rebinding(generation: context.generation)
  }
}
