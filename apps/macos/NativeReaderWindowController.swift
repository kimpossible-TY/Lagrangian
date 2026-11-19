import AppKit
import UniformTypeIdentifiers

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

/// Concrete typed disk operations are composed once per profile. Injection is
/// for owned storage/cancellation tests; validation remains in RecoveryStore.
struct NativeReaderOfflineStorage {
  let save: (NativeReaderRecoverySnapshot) async throws -> Void
  let list: () async throws -> [NativeReaderRecoveryStore.Entry]
  let load: (NativeDocumentIdentity) async throws -> NativeReaderRecoverySnapshot
  init(owner: NativeReaderRecoveryStore) {
    save = { try await owner.save($0) }; list = { try await owner.list() }
    load = { try await owner.load(identity: $0) }
  }
  init(save: @escaping (NativeReaderRecoverySnapshot) async throws -> Void,
       list: @escaping () async throws -> [NativeReaderRecoveryStore.Entry],
       load: @escaping (NativeDocumentIdentity) async throws -> NativeReaderRecoverySnapshot) {
    self.save = save; self.list = list; self.load = load
  }
}

/// An offline library has no live document operation. It cannot impersonate a
/// managed attachment or acquire source/chat authority.
struct NativeReaderOfflineProvider: NativeReaderDocumentProviding {
  func document(for context: NativeReaderRequestContext) async throws -> NativeReaderDocument { throw NativeReaderOperationFailure.unavailable }
}

/// One window, one store, one session. Heavy preparation never publishes a snapshot.
@MainActor final class NativeReaderWindowController {
  typealias Target = (Profile) async throws -> NativeDocumentIdentity
  typealias Assets = (NativeReaderDocument, NativeReaderRequestContext) async throws -> [String: Data]
  enum Mode { case nativeReflow, originalPages }
  private(set) var mode: Mode = .nativeReflow
  private(set) var visibleMode: Mode = .nativeReflow
  let store = NativeReaderDocumentStore()
  lazy var originalPageView = NativeReaderOriginalPageView(viewID: store.viewID)
  private var acceptedPageDelivery: NativeOriginalPageDelivery?
  private let pagePreparer = NativeOriginalPagePreparer()
  private var pageProvider: ((NativeReaderRequestContext) async throws -> NativeOriginalPageDelivery)?
  lazy var textView = NativeReaderTextView(store: store)
  private(set) var session: NativeReaderSession!
  private(set) var acceptedPaintKey: NativeReaderTextRenderKey?
  private(set) var preparingKey: NativeReaderTextRenderKey?
  private(set) var paintedKey: NativeReaderTextRenderKey?
  private(set) var diagnostic: String?
  private var cache: (key: NativeReaderTextRenderKey, objects: [String: NativeReaderPreparedTextObject])?
  private var acceptedAssets: (document: NativeReaderDocument, bytes: [String: Data])?
  private var chatWorker: (node: URL, helper: URL, runtime: URL, worker: NativeMathWorker)?
  private var profile: Profile?
  let localReview = NativeReaderLocalReview()
  private let offlineStorage: NativeReaderOfflineStorage?
  private var storageTask: Task<Void, Never>?
  private var storageEpoch = 0
  private var storageIsOpening = false
  private var exportTask: Task<Void, Never>?
  private var exportEpoch = 0
  private var recoveredDrafts = [NativeReaderRecoveredDraft]()
  private var recoveredDraftIdentity: NativeDocumentIdentity?
  private var currentDrafts = [UUID: NativeReaderRecoveredDraft]()
  private var currentDraftIdentity: NativeDocumentIdentity?
  private var pendingPresentation: (NativeReaderDocument, NativeReaderRestoration)?

  private let provider: NativeReaderDocumentProviding
  private let target: Target
  private let assets: Assets
  private let actions: (() async throws -> NativeReaderActions)?
  private let invalidate: () async -> Void
  private let show: Bool
  private let avoidActivation: Bool
  private let fixtureMode: Bool
  private var progress: ((NativeReadProgress) -> Void)?
  private var requestTicket = ReadingOperationTicket()
  private var actionTasks = [UUID: Task<Void, Never>]()
  private var selectionTask: Task<Void, Never>?
  private var disposed = false
  private var layoutObserver: NSObjectProtocol?
  private var capsuleScrollObserver: NSObjectProtocol?
  private var dismissedCapsule: NativeFloatingCapsule.Binding?
  private var capsuleCapabilities: (NativeFloatingCapsule.Binding, [NativeFloatingCapsule.Action: String])?
  private weak var capsuleFocusReturn: NSResponder?
  private var reflowTask: Task<Void, Never>?
  var runtime: NativeReaderRuntime?
  var copyText: (String) -> Bool = { _ in false }
  var openHomepage: ((URL) -> Void)?
  var choosePDFDestination: (NSWindow) async -> URL? = { window in
    await withCheckedContinuation { continuation in
      let panel = NSSavePanel(); panel.allowedContentTypes = [.pdf]; panel.nameFieldStringValue = "Document.pdf"
      panel.beginSheetModal(for: window) { response in continuation.resume(returning: response == .OK ? panel.url : nil) }
    }
  }
  var stagePDFExport: @Sendable (NativeOriginalPageRecovery, NativeReaderDocument, URL) throws -> NativeReaderRecoveryStore.StagedPDF = {
    try NativeReaderRecoveryStore.stageOriginalPDF($0, document: $1, to: $2)
  }
  private var chatContext: NativeReaderRequestContext?
  // Bounded display associations alongside the existing draft owner. Never
  // evidence for Send authorization, and never persisted across Reader lifetime.
  private struct ChatPresentation {
    let context: NativeReaderRequestContext
    let selection: NativeReaderSelection
    let conversationID: UUID
  }
  private struct ChatConversationPresentation {
    let conversation: NativeReaderConversation
    let models: [String]
  }
  private var retainedChatPresentations = [ChatPresentation]()
  private var retainedChatConversations = [UUID: ChatConversationPresentation]()
  private var editorRequest: NativeReaderSourceRequest?
  private var editorBusy = false
  private let revokeEditorConsent: () async -> Void
  private(set) var chatView: NativeReaderChatView?
  lazy var hostWindow = NativeReaderHostWindow(reader: textView, show: show, avoidActivation: avoidActivation, fixtureMode: fixtureMode)

  init(provider: NativeReaderDocumentProviding, target: @escaping Target,
       assets: @escaping Assets = { document, _ in
         guard document.assets.isEmpty else { throw NativeObjectError.unsupported("asset-provider-unavailable") }
         return [:]
       }, runtime: NativeReaderRuntime? = nil,
       actions: (() async throws -> NativeReaderActions)? = nil,
       originalPages: ((NativeReaderRequestContext) async throws -> NativeOriginalPageDelivery)? = nil,
       invalidate: @escaping () async -> Void = {}, show: Bool = true, avoidActivation: Bool = false, fixtureMode: Bool = false,
       offlineStorage: NativeReaderOfflineStorage? = nil) {
    self.provider = provider; self.target = target; self.assets = assets; self.runtime = runtime
    self.actions = actions; self.invalidate = invalidate; self.show = show; self.avoidActivation = avoidActivation
    if let managed = provider as? NativeReaderManagedClient {
      revokeEditorConsent = { await managed.revokeEditorConsent() }
    } else { revokeEditorConsent = {} }
    self.fixtureMode = fixtureMode
    self.offlineStorage = offlineStorage
    self.pageProvider = originalPages
    if self.pageProvider == nil, let managed = provider as? NativeReaderManagedClient {
      self.pageProvider = { try await managed.originalPages(for: $0) }
    }
    session = NativeReaderSession(store: store, provider: provider, target: { [weak self] in
      guard let self, let profile = self.profile else { throw NativeReaderOperationFailure.unavailable }
      return try await self.target(profile)
    }, invalidate: invalidate, prepare: { [weak self] document, context in
      guard let self else { throw NativeReaderContractError.disposed }
      do { return try await self.prepare(document, context: context) }
      catch { self.report(error); throw error }
    })
    session.onChange = { [weak self] in self?.sessionChanged() }
    session.onSelection = { [weak self] selection, context in self?.selectionChanged(selection, context: context) }
    hostWindow.onRefresh = { [weak self] in
      guard let self, !self.session.hasRecoveryCopy else { return }
      self.refresh()
    }
    hostWindow.onCancelRecovery = { [weak self] in
      guard let self, self.session.hasPendingRecovery else { return }
      if self.storageIsOpening { self.cancelStorage() } else { self.session.cancel() }
      self.hostWindow.notice.stringValue = "복원을 취소했습니다. 저장 목록에서 문서를 다시 열 수 있습니다."
    }
    hostWindow.capsule.onAction = { [weak self] in self?.capsuleAction($0, $1) }
    hostWindow.capsule.onDismiss = { [weak self] binding in
      guard let self, self.hostWindow.capsule.binding == binding else { return }
      self.dismissedCapsule = binding; self.hostWindow.hideCapsule(); self.returnCapsuleFocus()
    }
    hostWindow.onRetryRecovery = { [weak self] in
      guard let self, self.session.hasPendingRecovery, self.session.failure != nil else { return }
      self.session.preparationChanged()
    }
    hostWindow.onShowCapsule = { [weak self] in self?.updateCapsule(reopen: true, focus: true) }
    hostWindow.onCapsuleLayout = { [weak self] in self?.updateCapsule() }
    hostWindow.onEditorReceipt = { [weak self] in self?.checkEditorReceipt() }
    textView.cachedObject = { [weak self] node, key in
      guard let cache = self?.cache, cache.key == key else { return nil }
      return cache.objects[node.id]
    }
    textView.callbacks.selectionChanged = { [weak self] selection in
      guard let self, self.visibleMode == .nativeReflow, let selection else { return }
      do { try self.session.hold(selection); self.updatePresentation() } catch { self.report(error) }
    }
    // Only NA02's explicit user release enters this callback. Source/network ack never does.
    textView.callbacks.selectionReleased = { [weak self] in self?.session.acknowledge(ticket: $0) }
    textView.callbacks.painted = { [weak self] key in
      guard let self, !self.disposed, !self.requestTicket.isCancelled,
            self.mode == .nativeReflow, self.visibleMode == .nativeReflow, !self.textView.isHidden,
            self.acceptedPaintKey == key, self.textView.renderKey == key,
            self.session.context == self.textView.context, self.store.document?.identity == key.identity,
            self.store.document?.generation == key.documentGeneration else { return }
      self.paintedKey = key; self.progress?(.painted)
    }
    textView.callbacks.copyText = { [weak self] text in
      guard let self, self.visibleMode == .nativeReflow else { return false }; return self.copyText(text)
    }
    textView.callbacks.sourceRequested = { [weak self] in self?.source($0) }
    textView.callbacks.chatRequested = { [weak self] command, context in self?.chat(command, context: context) }
    textView.callbacks.statusChanged = { [weak self] message in
      guard let self else { return }
      self.diagnostic = message
      self.layoutChanged()
    }
    originalPageView.onHold = { [weak self] held in self?.session.holdOriginalPageSelection(held); self?.updatePresentation() }
    originalPageView.onFailure = { [weak self] in self?.report($0) }
    originalPageView.copyText = { [weak self] in self?.copyText($0) ?? false }
    originalPageView.openURI = { [weak self] in self?.openHomepage?($0) }
    originalPageView.onPaint = { [weak self] receipt in
      guard let self, !self.disposed, !self.requestTicket.isCancelled, self.mode == .originalPages, self.visibleMode == .originalPages,
            !self.originalPageView.isHidden, let binding = self.originalPageView.store.accepted?.binding,
            receipt.snapshotID == self.originalPageView.store.accepted?.id,
            (self.session.state == .reading || self.session.state == .offline), self.store.generation == binding.requestGeneration,
            self.session.context?.generation == binding.requestGeneration,
            self.store.document?.identity == binding.identity else { return }
      self.progress?(.painted)
    }
    localReview.paint = { [weak self] marks in
      guard let self else { return }
      do { try self.textView.setReviewSelections(marks.map { mark in
        NativeReaderSelection(ticket: mark.selection.selectionTicket!, fragments: mark.selection.fragments.map {
          .init(blockID: $0.blockID, rangeUTF16: $0.start..<$0.end, exact: $0.exact)
        })
      }); self.hostWindow.reviewCount = marks.count }
      catch { self.report(error) }
    }
    textView.callbacks.focusChanged = { [weak self] _ in self?.hostWindow.updateNavigation() }
    textView.callbacks.semanticActivated = { [weak self] node, context in
      guard let self, self.visibleMode == .nativeReflow, self.textView.context == context,
            self.textView.renderKey == self.textView.requestedRenderKey,
            node.kind == .link, let raw = node.link, !raw.hasPrefix("#"), let url = URL(string: raw),
            NativeOriginalPDFAccess.safeURL(url) else { return }
      self.openHomepage?(url) // Explicit native activation only.
    }
    hostWindow.onMarkReview = { [weak self] in self?.addReview() }
    hostWindow.onUndoReview = { [weak self] in self?.localReview.undo() }
    hostWindow.onClearReview = { [weak self] in self?.localReview.clear() }
    hostWindow.onAppearance = { [weak self] in self?.layoutChanged() }
    hostWindow.onExportPDF = { [weak self] in self?.exportPDFExplicitly() }
    hostWindow.onSaveOffline = { [weak self] in self?.saveOfflineExplicitly() }
    hostWindow.onListOffline = { [weak self] in self?.refreshSavedExplicitly() }
    hostWindow.onOpenOffline = { [weak self] in self?.openSavedExplicitly($0) }
    hostWindow.onCancelStorage = { [weak self] in self?.cancelStorage() }
    hostWindow.onLastEdit = { [weak self] in self?.lastEditExplicitly() }
    hostWindow.onAccount = { [weak self] in self?.accountExplicitly() }
    hostWindow.onManageAccount = { [weak self] url in self?.openHomepage?(url) }
    textView.postsFrameChangedNotifications = true
    layoutObserver = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: textView, queue: .main) { [weak self] _ in
      Task { @MainActor in self?.layoutChanged() }
    }
    textView.scrollView.contentView.postsBoundsChangedNotifications = true
    capsuleScrollObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: nil, queue: .main) { [weak self] notification in
      Task { @MainActor in
        guard let self, let clip = notification.object as? NSClipView,
              clip === self.textView.scrollView.contentView || clip === self.originalPageView.enclosingScrollView?.contentView else { return }
        self.updateCapsule()
      }
    }

  }

  func open(_ profile: Profile, refresh: Bool = true, progress: @escaping (NativeReadProgress) -> Void) -> () -> Void {
    guard !disposed else { progress(.failed("Reader disposed")); return {} }
    guard self.profile == nil || self.profile == profile else {
      progress(.failed("Create a new view for another profile")); return {}
    }
    self.profile = profile; self.progress = progress
    cancelStorage()
    requestTicket.cancel(); let ticket = ReadingOperationTicket(); requestTicket = ticket
    acceptedPaintKey = nil; paintedKey = nil; diagnostic = nil
    hostWindow.initialize()
    hostWindow.installOriginal(originalPageView)
    hostWindow.changeMode = { [weak self] in
      do { try self?.setMode($0) } catch { self?.report(error) }
    }
    hostWindow.onClose = { [weak self] in
      guard let self, self.requestTicket === ticket, !ticket.isCancelled else { return }
      self.closeView()
    }
    hostWindow.storageAvailable = offlineStorage != nil
    if refresh { session.refresh() }
    return { [weak self] in
      ticket.cancel()
      Task { @MainActor in
        guard let self, self.requestTicket === ticket else { return }; self.cancel()
      }
    }
  }

  /// Environment signals belong only to an explicit, still-live Read ticket.
  /// Offline library copies and closed/cancelled views never resolve a service.
  func environmentChanged(_ event: NativeReadEnvironmentEvent) -> Bool {
    guard !disposed, !requestTicket.isCancelled, progress != nil, !session.hasRecoveryCopy else { return false }
    if case .power = event {} else { acceptedPaintKey = nil; paintedKey = nil }
    switch event {
    case .sleep: session.event(.sleep)
    case .wake: session.event(.wake)
    case .network(let online): session.event(.network(online))
    case .power(let constrained): session.event(.power(constrained: constrained))
    }
    return true
  }

  func refresh() { acceptedPaintKey = nil; paintedKey = nil; session.refresh() }

  private func prepare(_ document: NativeReaderDocument, context: NativeReaderRequestContext, reflowOnly: Bool = false, recoveryAssets: [String: Data]? = nil, recoveryPages: NativeOriginalPageRecovery? = nil) async throws -> NativeReaderSession.PreparedAdoption {
    if !reflowOnly, mode == .originalPages { return try await prepareOriginal(document, context: context, recoveryAssets: recoveryAssets, recovery: recoveryPages) }
    let ticket = requestTicket
    let key = try reflowOnly ? textView.retainedPreparationKey(for: document, context: context) : textView.preparationKey(for: document, context: context)
    let descriptors: [String: Data]
    if let recoveryAssets { descriptors = recoveryAssets }
    else if reflowOnly {
      guard let retained = acceptedAssets, retained.document == document else { throw NativeObjectError.stale }
      descriptors = retained.bytes // Previously verified bytes; never a stale transport request.
    } else { descriptors = try await assets(document, context) }
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
          // Empty compiler alt carries no label meaning. Use the existing
          // generic role fallback, not an invalid empty prepared-object label.
          accessibilityLabel: node.alt.flatMap { $0.isEmpty ? nil : $0 } ?? node.math?.normalizedText ?? (node.displayText.isEmpty ? node.kind.rawValue : node.displayText),
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
      return try (reflowOnly ? self.textView.retainedPreparationKey(for: document, context: context) : self.textView.preparationKey(for: document, context: context)) == key
    }, adopt: { [weak self] in
      guard let self, !self.disposed, !ticket.isCancelled,
            try (reflowOnly ? self.textView.retainedPreparationKey(for: document, context: context) : self.textView.preparationKey(for: document, context: context)) == key else { throw NativeObjectError.stale }
      let previous = self.cache
      self.cache = (key, preparedObjects)
      do {
        if reflowOnly {
          guard self.store.document == document else { throw NativeObjectError.stale }
          try self.textView.refreshPreparedObjects(for: key)
        } else { try self.textView.adopt(document, context: context) }
      }
      catch { self.cache = previous; throw error }
      self.acceptedAssets = (document, descriptors)
      self.acceptedPaintKey = key; self.paintedKey = nil; self.diagnostic = nil
      if !reflowOnly {
        self.localReview.clear()
        self.visibleMode = .nativeReflow; self.hostWindow.displayMode(.nativeReflow)
        self.hostWindow.refreshOutline()
      }
      self.applyPendingPresentation(); self.hostWindow.refreshLocalControls()
      if let chat = self.chatView {
        if self.chatContext == self.textView.context { self.configureChatMath(chat, key: key) }
        else { self.rememberCurrentDraft(); chat.dispose(); chat.removeFromSuperview(); self.chatView = nil; self.chatContext = nil }
      }
    })
  }

  func setMode(_ mode: Mode) throws {
    // These requests cannot start preparation. Keep live selection holds below
    // requestMode so their explicit release/reattempt guidance remains visible.
    guard !disposed else { throw NativeReaderContractError.disposed }
    guard !session.hasRecoveryCopy else { throw NativeReaderOperationFailure.unavailable }
    hostWindow.requestMode(mode)
    guard !session.hasSelection else { throw NativeOriginalPageError.heldSelection }
    guard self.mode != mode else { return }
    if mode == .nativeReflow { try hostWindow.resolveAutomaticAppearance() }
    self.mode = mode; session.refresh()
  }

  private func prepareOriginal(_ document: NativeReaderDocument, context: NativeReaderRequestContext, recoveryAssets: [String: Data]? = nil, recovery: NativeOriginalPageRecovery? = nil) async throws -> NativeReaderSession.PreparedAdoption {
    let intent = mode, request = requestTicket, generation = originalPageView.store.viewGeneration
    let delivery: NativeOriginalPageDelivery
    let supplement: NativeOriginalPageSupplement
    if let recovery {
      delivery = NativeOriginalPageDelivery(publication: recovery.publication, data: recovery.data)
      let old = recovery.publication
      let oldContext = NativeReaderRequestContext(requestID: UUID(uuidString: old.requestID)!, viewID: UUID(uuidString: old.viewID)!, generation: old.generation, target: context.target)
      let captured = try await delivery.supplement(context: oldContext, viewGeneration: generation)
      let b = captured.binding
      supplement = NativeOriginalPageSupplement(binding: NativeOriginalPageBinding(identity: b.identity,
        inputFingerprint: b.inputFingerprint, snapshotGeneration: b.snapshotGeneration, requestGeneration: context.generation,
        viewID: context.viewID, viewGeneration: generation, publicationSequence: b.publicationSequence,
        pdfSHA256: b.pdfSHA256, pages: b.pages), data: captured.data)
    } else {
      guard let pageProvider else { throw NativeOriginalPageError.unsupported("original-page-provider-unavailable") }
      delivery = try await pageProvider(context)
      supplement = try await delivery.supplement(context: context, viewGeneration: generation)
    }
    let descriptors: [String: Data]
    if let recoveryAssets { descriptors = recoveryAssets }
    else { descriptors = try await assets(document, context) }
    var limits = NativeOriginalPageLimits(); limits.lazy = true
    let prepared = try await pagePreparer.prepare(supplement, expected: supplement.binding, limits: limits)
    try Task.checkCancellation()
    guard !disposed, !request.isCancelled, mode == intent, originalPageView.store.viewGeneration == generation else { throw NativeOriginalPageError.stale }
    let initialPage = recovery?.viewport.page ?? min(originalPageView.store.pageIndex, prepared.binding.pages.count - 1)
    guard prepared.binding.pages.indices.contains(initialPage) else { throw NativeOriginalPageError.geometry }
    let recoveryScale = recovery?.viewport.scale
    let fit = recovery != nil ? recoveryScale == nil : originalPageView.store.fitsWidth
    let scale = fit ? min(8, max(0.1, originalPageView.store.viewportWidth / prepared.binding.pages[initialPage].displaySize.width)) : (recoveryScale ?? originalPageView.store.scale)
    _ = try await prepared.access.render(page: initialPage, scale: scale)
    _ = try await prepared.access.links(page: initialPage)
    try Task.checkCancellation()
    let ticket = try originalPageView.store.begin(expected: supplement.binding)
    return .init(isCurrent: { [weak self] in
      guard let self else { return false }
      return !self.disposed && !request.isCancelled && self.mode == intent && self.originalPageView.store.viewGeneration == generation
    }, adopt: { [weak self] in
      guard let self, !self.disposed, !request.isCancelled, self.mode == intent,
            self.store.generation == context.generation, self.store.selection == nil else { throw NativeOriginalPageError.stale }
      try self.originalPageView.store.validateAdoption(prepared, for: ticket)
      // All fallible page checks precede canonical publication. Synchronous,
      // same-actor installation cannot interleave a new request/selection here.
      try self.store.adopt(document, for: context)
      try self.originalPageView.store.adopt(prepared, for: ticket)
      self.localReview.clear()
      self.acceptedPageDelivery = delivery; self.acceptedAssets = (document, descriptors)
      self.visibleMode = .originalPages; self.acceptedPaintKey = nil; self.paintedKey = nil
      self.hostWindow.displayMode(.originalPages); self.originalPageView.installed()
      if let recovery { try self.originalPageView.restore(recovery.viewport) }
      self.chatView?.dispose(); self.chatView?.removeFromSuperview(); self.chatView = nil; self.chatContext = nil
    })
  }

  private func recoverySnapshot(drafts: [NativeReaderRecoveredDraft]) throws -> NativeReaderRecoverySnapshot {
    guard let document = store.document, let acceptedAssets, acceptedAssets.document == document else { throw NativeReaderOperationFailure.unavailable }
    var restoration = session.restoration
    if visibleMode == .nativeReflow {
      let viewport = try textView.captureViewport()
      restoration = NativeReaderRestoration(blockID: viewport.blockID, offset: viewport.offset,
        zoom: Double(textView.textAppearance.zoom), selectionTicket: store.selection?.ticket,
        fragments: store.selection?.fragments.map { .init(blockID: $0.blockID, start: $0.rangeUTF16.lowerBound, end: $0.rangeUTF16.upperBound, exact: $0.exact) } ?? [])
    }
    var snapshot = NativeReaderRecoverySnapshot(document: document, assets: acceptedAssets.bytes, restoration: restoration, drafts: drafts)
    snapshot.reviewMarks = localReview.marks
    if visibleMode == .originalPages, let delivery = acceptedPageDelivery {
      snapshot.originalPages = NativeOriginalPageRecovery(publication: delivery.publication, data: delivery.data, viewport: try originalPageView.recovery())
    }
    try snapshot.validate(); return snapshot
  }
  func saveRecovery(to owner: NativeReaderRecoveryStore, drafts: [NativeReaderRecoveredDraft] = []) async throws {
    try await owner.save(recoverySnapshot(drafts: drafts))
  }
  func restoreRecovery(_ snapshot: NativeReaderRecoverySnapshot) async throws {
    try snapshot.validate()
    guard !session.hasSelection else { throw NativeOriginalPageError.heldSelection }
    mode = snapshot.originalPages == nil ? .nativeReflow : .originalPages
    // Snapshot.validate above owns asset/hash authority. Candidate-local capture
    // keeps this input through held preparation retries; live closures stay idle.
    let ticket = requestTicket, epoch = storageEpoch
    try await session.restore(snapshot, matching: snapshot.document.identity, prepare: { [weak self] document, context in
      guard let self else { throw NativeReaderContractError.disposed }
      return try await self.prepare(document, context: context, recoveryAssets: snapshot.assets, recoveryPages: snapshot.originalPages)
    }, didAdopt: { [weak self] document in
      guard let self, !self.disposed, self.requestTicket === ticket, !ticket.isCancelled,
            self.storageEpoch == epoch, self.store.document == document else { return }
      // Every fallible typed bound was checked before enqueue. This completion
      // follows this candidate through resize/hold/release and is consumed once.
      do {
        try self.localReview.restore(snapshot.reviewMarks, document: document)
        self.recoveredDrafts = snapshot.drafts; self.recoveredDraftIdentity = document.identity
        self.currentDrafts.removeAll(); self.currentDraftIdentity = document.identity
        self.hostWindow.presentRecoveredDrafts(snapshot.drafts)
        if snapshot.originalPages == nil {
          self.pendingPresentation = (document, snapshot.restoration)
          var appearance = self.textView.textAppearance; appearance.zoom = CGFloat(snapshot.restoration.zoom)
          try self.textView.setAppearance(appearance)
          self.layoutChanged(); self.applyPendingPresentation()
        }
        self.storageIsOpening = false; self.hostWindow.storageBusy = false
        self.hostWindow.notice.stringValue = "Offline copy · source and chat actions are unavailable."
      } catch { self.report(error) }
    })
  }

  private func applyPendingPresentation() {
    guard let pending = pendingPresentation, pending.0 == store.document,
          textView.renderKey == textView.requestedRenderKey else { return }
    do { try textView.restorePresentation(offset: pending.1.offset); pendingPresentation = nil }
    catch { report(error) }
  }

  func openOfflineLibrary(_ profile: Profile, progress: @escaping (NativeReadProgress) -> Void = { _ in }) {
    _ = open(profile, refresh: false, progress: progress)
    hostWindow.notice.stringValue = "Choose a saved document to read offline."
    hostWindow.present(); refreshSavedExplicitly()
  }
  private func addReview() {
    guard visibleMode == .nativeReflow, let document = store.document, let selection = store.selection else {
      hostWindow.notice.stringValue = "Select text to mark for review."; return
    }
    let location = NativeReaderRestoration(blockID: selection.fragments.first?.blockID, offset: 0, zoom: 1,
      selectionTicket: selection.ticket, fragments: selection.fragments.map { .init(blockID: $0.blockID, start: $0.rangeUTF16.lowerBound, end: $0.rangeUTF16.upperBound, exact: $0.exact) })
    do { try localReview.add(.init(id: UUID(), identity: document.identity, selection: location), document: document) }
    catch { hostWindow.notice.stringValue = "Review mark unavailable. Select at most 32 blocks; your selection is retained." }
  }
  private func rememberCurrentDraft() {
    guard let chat = chatView, let draft = chat.recoveryDraft, let context = chatContext else { return }
    let identity = context.target
    if currentDraftIdentity != identity { currentDrafts.removeAll(); currentDraftIdentity = identity }
    currentDrafts[draft.conversationID] = draft
    if let conversation = chat.presentationConversation, conversation.state.context == context,
       conversation.state.conversationID == draft.conversationID {
      let previous = retainedChatPresentations.last { $0.context == context && $0.conversationID == draft.conversationID }
      let selection = chat.presentationSelection ?? previous?.selection
      if let selection {
        retainedChatPresentations.removeAll { $0.context == context && $0.selection.fragments == selection.fragments }
        retainedChatPresentations.append(.init(context: context, selection: selection, conversationID: draft.conversationID))
        let existing = retainedChatConversations[draft.conversationID]?.conversation
        if existing?.state.context != context || (conversation.state.version >= existing!.state.version && conversation.state.sequence >= existing!.state.sequence) {
          retainedChatConversations[draft.conversationID] = .init(conversation: conversation, models: chat.presentationModels)
        }
        if retainedChatPresentations.count > 32 { retainedChatPresentations.removeFirst() }
        let identifiers = Set(retainedChatPresentations.map(\.conversationID))
        retainedChatConversations = retainedChatConversations.filter { identifiers.contains($0.key) }
      }
    }
  }
  private func storedDrafts() -> [NativeReaderRecoveredDraft] {
    rememberCurrentDraft()
    var result = recoveredDraftIdentity == store.document?.identity ? recoveredDrafts : []
    if currentDraftIdentity == store.document?.identity {
      for draft in currentDrafts.values { result.removeAll { $0.conversationID == draft.conversationID }; result.append(draft) }
    }
    if let draft = chatView?.recoveryDraft, chatContext?.target == store.document?.identity {
      result.removeAll { $0.conversationID == draft.conversationID }; result.append(draft)
    }
    return result
  }
  private func storageOperation(opening: Bool = false, _ operation: @escaping @MainActor () async throws -> Void) {
    guard !disposed, !requestTicket.isCancelled, storageTask == nil, offlineStorage != nil else { return }
    storageEpoch += 1; let epoch = storageEpoch, ticket = requestTicket
    hostWindow.storageBusy = true; storageIsOpening = opening
    storageTask = Task { [weak self] in
      guard let self else { return }
      defer { if self.storageEpoch == epoch {
        self.storageTask = nil
        if !self.storageIsOpening || !self.session.hasPendingRecovery { self.storageIsOpening = false; self.hostWindow.storageBusy = false }
      } }
      do { try await operation() }
      catch {
        if self.storageEpoch == epoch, self.requestTicket === ticket, !Task.isCancelled, !self.disposed {
          self.hostWindow.notice.stringValue = "Offline operation failed; the previous saved copy is unchanged."
        }
      }
    }
  }
  func cancelStorage() {
    exportEpoch += 1; exportTask?.cancel(); exportTask = nil; hostWindow.exportBusy = false
    storageEpoch += 1; storageTask?.cancel(); storageTask = nil; hostWindow.storageBusy = false
    if storageIsOpening {
      pendingPresentation = nil; acceptedPaintKey = nil; paintedKey = nil
      session.cancel() // Revoke a cancelled restore candidate, including later layout retries.
    }
    storageIsOpening = false
  }
  private func saveOfflineExplicitly() {
    guard let storage = offlineStorage else { return }
    let snapshot: NativeReaderRecoverySnapshot
    do { snapshot = try recoverySnapshot(drafts: storedDrafts()) }
    catch NativeReaderTextFailure.staleGeometry { hostWindow.notice.stringValue = "Document layout is updating. Try saving when it is ready."; return }
    catch { hostWindow.notice.stringValue = "Cannot save this reading state. Select at most 32 blocks and use 50%–400% zoom; the previous copy is unchanged."; return }
    let epoch = storageEpoch + 1, ticket = requestTicket
    storageOperation { [weak self] in
      try await storage.save(snapshot); try Task.checkCancellation()
      guard let self, self.storageEpoch == epoch, self.requestTicket === ticket, !self.disposed else { return }
      self.hostWindow.notice.stringValue = "Saved for offline reading."
    }
  }
  private func refreshSavedExplicitly() {
    guard let storage = offlineStorage else { return }
    let epoch = storageEpoch + 1, ticket = requestTicket
    storageOperation { [weak self] in
      let entries = try await storage.list(); try Task.checkCancellation()
      guard let self, self.storageEpoch == epoch, self.requestTicket === ticket, !self.disposed else { return }
      self.hostWindow.setSavedDocuments(entries)
      self.hostWindow.notice.stringValue = entries.isEmpty ? "No saved documents in this project." : "Choose a saved document to open."
    }
  }
  private func openSavedExplicitly(_ identity: NativeDocumentIdentity) {
    guard let storage = offlineStorage else { return }
    guard !session.hasSelection else { hostWindow.notice.stringValue = "Release the selection before opening a saved document."; return }
    let epoch = storageEpoch + 1, ticket = requestTicket
    storageOperation(opening: true) { [weak self] in
      let snapshot = try await storage.load(identity); try Task.checkCancellation()
      guard let self, self.storageEpoch == epoch, self.requestTicket === ticket, !self.disposed else { return }
      try await self.restoreRecovery(snapshot)
      guard self.storageEpoch == epoch, self.requestTicket === ticket, !Task.isCancelled else { return }
      if !self.session.hasPendingRecovery { self.hostWindow.notice.stringValue = "Offline copy · source and chat actions are unavailable." }
    }
  }
  private func currentExportSnapshot() throws -> (NativeReaderDocument, NativeOriginalPageRecovery, UUID) {
    guard !fixtureMode, !disposed, !requestTicket.isCancelled, visibleMode == .originalPages,
          let document = store.document, let accepted = originalPageView.store.accepted,
          let delivery = acceptedPageDelivery, accepted.binding.identity == document.identity,
          accepted.binding.requestGeneration == session.context?.generation,
          accepted.binding.inputFingerprint == delivery.publication.inputFingerprint,
          accepted.binding.pdfSHA256 == delivery.publication.pdfSHA256 else { throw NativeOriginalPageError.stale }
    let original = NativeOriginalPageRecovery(publication: delivery.publication, data: delivery.data, viewport: try originalPageView.recovery())
    try original.validate(document: document)
    return (document, original, accepted.id)
  }
  private func exportPDFExplicitly() {
    guard exportTask == nil, let window = hostWindow.window, let captured = try? currentExportSnapshot() else {
      hostWindow.notice.stringValue = "Open a verified Original PDF before exporting."; return
    }
    exportEpoch += 1; let epoch = exportEpoch, ticket = requestTicket
    hostWindow.exportBusy = true
    exportTask = Task { [weak self] in
      guard let self else { return }
      defer { if self.exportEpoch == epoch { self.exportTask = nil; self.hostWindow.exportBusy = false } }
      do {
        guard let destination = await self.choosePDFDestination(window) else { return }
        try Task.checkCancellation()
        let before = try self.currentExportSnapshot()
        guard self.exportEpoch == epoch, self.requestTicket === ticket, before.0 == captured.0, before.2 == captured.2 else { throw NativeOriginalPageError.stale }
        let stage = self.stagePDFExport
        let job = Task.detached(priority: .userInitiated) {
          try stage(captured.1, captured.0, destination)
        }
        let staged = try await withTaskCancellationHandler(operation: { try await job.value }, onCancel: { job.cancel() })
        try Task.checkCancellation()
        let current = try self.currentExportSnapshot()
        guard self.exportEpoch == epoch, self.requestTicket === ticket, current.0 == captured.0, current.2 == captured.2 else { throw NativeOriginalPageError.stale }
        try staged.commit()
        self.hostWindow.notice.stringValue = "Original PDF exported."
      } catch {
        if self.exportEpoch == epoch, !Task.isCancelled, !self.disposed { self.hostWindow.notice.stringValue = "PDF export failed; the previous file is unchanged." }
      }
    }
  }
  private func lastEditExplicitly() {
    guard visibleMode == .nativeReflow, let context = session.context, let actions, actionTasks.count < 8 else { return }
    let id = UUID()
    actionTasks[id] = Task { [weak self] in
      guard let self else { return }; defer { self.actionTasks.removeValue(forKey: id) }
      do {
        try self.session.authorize(context)
        let owner = try await actions(), anchor = try await owner.lastChange(context: context)
        try Task.checkCancellation(); try self.session.authorize(context)
        guard let anchor, self.textView.navigate(toAnchor: anchor) else { self.hostWindow.notice.stringValue = "No saved edit location is available for this document."; return }
      } catch { if !Task.isCancelled { self.report(error) } }
    }
  }
  private func accountExplicitly() {
    guard let context = session.context, let actions, actionTasks.count < 8 else { return }
    let id = UUID()
    actionTasks[id] = Task { [weak self] in
      guard let self else { return }; defer { self.actionTasks.removeValue(forKey: id) }
      do {
        try self.session.authorize(context); let owner = try await actions()
        let state = try await owner.account(context: context)
        try Task.checkCancellation(); try self.session.authorize(context)
        self.hostWindow.presentAccount(state)
      } catch { if !Task.isCancelled { self.report(error) } }
    }
  }

  /// Reprepare only the latest layout key. Session retains incoming candidates;
  /// an accepted snapshot reflow never adopts/releases selection or changes service state.
  private func layoutChanged() {
    updateCapsule()
    guard !disposed, !requestTicket.isCancelled else { return }
    hostWindow.refreshLocalControls()
    // The initial offscreen/AppKit layout has no retained view to invalidate.
    // Its in-flight candidate already rechecks the exact key in publishPending;
    // restarting it would revoke an awaited offline restore for a frame notice.
    if store.document != nil || session.state != .loading { session.preparationChanged() }
    guard visibleMode == .nativeReflow, let document = store.document, let context = session.context,
          context == textView.context,
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
        self.updateCapsule()
      } catch { if !Task.isCancelled { self.report(error) } }
    }
  }

  private func updatePresentation() {
    hostWindow.updateStatus(state: session.state, failed: session.failure != nil, allowsRefresh: !session.hasRecoveryCopy,
                            allowsModeSwitch: !disposed && !session.hasRecoveryCopy,
                            pendingRecovery: session.hasPendingRecovery)
    chatView?.refreshAuthorization()
    updateCapsule()
  }
  private func sessionChanged() {
    guard !disposed, !requestTicket.isCancelled else { return }
    updatePresentation()
    hostWindow.updateReaderControls(readOnly: session.isReadOnly)
    if let failure = session.failure {
      let message = diagnostic ?? failure
      hostWindow.notice.stringValue = message
      progress?(.failed(message)); return
    }
    if visibleMode == .originalPages, session.state == .reading || session.state == .offline,
       originalPageView.store.accepted?.binding.identity == store.document?.identity {
      progress?(.accepted); progress?(.windowInitialized); hostWindow.present(); return
    }
    guard session.state == .reading || session.state == .offline,
          let key = acceptedPaintKey, textView.renderKey == key, session.context == textView.context else { return }
    progress?(.accepted); progress?(.windowInitialized)
    hostWindow.present()
  }

  private func report(_ error: Error) {
    diagnostic = String(describing: error)
    hostWindow.notice.stringValue = diagnostic ?? "Reader unavailable"
    if let pageError = error as? NativeOriginalPageError, case .stale = pageError { hostWindow.showRetainedFailure() }
    updatePresentation()
  }

  private func selectionChanged(_ selection: NativeReaderSelection?, context: NativeReaderRequestContext) {
    guard visibleMode == .nativeReflow else { return }
    updateCapsule()
    actionTasks.values.forEach { $0.cancel() }
    let previous = selectionTask
    previous?.cancel()
    guard !session.isReadOnly, let actions else { return }
    selectionTask = Task {
      await previous?.value
      do { try Task.checkCancellation(); let owner = try await actions(); try Task.checkCancellation(); try await owner.updateSelection(selection, context: context)
        if let selection {
          let binding = NativeFloatingCapsule.Binding(context: context, ticket: selection.ticket, originalPDF: false)
          let transport = owner.transport
          let attachment = transport.attachment
          var unavailable = [NativeFloatingCapsule.Action: String]()
          if attachment.editorAttachment == nil || attachment.editorConsentID == nil { unavailable[.editor] = "먼저 홈에서 편집기를 연결하세요." }
          if attachment.editorAttachment == nil || attachment.editorConsentID != nil { unavailable[.highlight] = "현재 연결은 원문 쓰기 권한을 제공하지 않습니다." }
          guard self.store.selection?.ticket == selection.ticket, self.session.context == context else { return }
          self.capsuleCapabilities = (binding, unavailable); self.updateCapsule()
        }
      }
      catch { if !Task.isCancelled { report(error) } }
    }
  }
  private func source(_ request: NativeReaderSourceRequest) {
    guard visibleMode == .nativeReflow else { report(NativeOriginalPageError.unsupported("pdf-source-actions-unavailable")); return }
    guard let actions else { report(NativeReaderOperationFailure.unavailable); return }
    let selection = selectionTask
    guard actionTasks.count < 8 else { report(NativeReaderOperationFailure.unavailable); return }
    if request.action == .locate {
      guard !editorBusy else { return }
      editorBusy = true; hostWindow.notice.stringValue = "Checking the selected source and connected editor…"
    }
    let id = UUID()
    actionTasks[id] = Task {
      defer {
        actionTasks.removeValue(forKey: id)
        if request.action == .locate { editorBusy = false }
      }
      do {
        await selection?.value
        try session.authorize(request.context, selection: request.selection.ticket)
        let owner = try await actions()
        if request.action == .locate {
          if let pending = await owner.pendingEditorReceiptID(), pending != request.receiptID {
            try Task.checkCancellation(); try session.authorize(request.context, selection: request.selection.ticket)
            hostWindow.notice.stringValue = "Editor effect is unknown. Check Editor Result before requesting another move."
            return // Preserve the original receipt, including after a second click.
          }
          editorRequest = request
          let receipt = try await owner.jump(request)
          try Task.checkCancellation()
          try session.authorize(request.context, selection: request.selection.ticket)
          hostWindow.notice.stringValue = receipt.feedback
          return
        }
        let result = try await owner.perform(request)
        try Task.checkCancellation()
        try session.authorize(request.context, selection: request.selection.ticket)
        _ = textView.acceptSourceResult(result, for: request)
      } catch {
        if !Task.isCancelled, !disposed, (try? session.authorize(request.context, selection: request.selection.ticket)) != nil {
          if request.action == .locate {
            let status: NativeReaderEditorReceipt.Status
            switch error {
            case NativeReaderOperationFailure.unknownEffect: status = .unknown
            case NativeReaderOperationFailure.unavailable: status = .unavailable
            default: status = .stale
            }
            hostWindow.notice.stringValue = NativeReaderEditorReceipt(context: request.context,
                selectionTicket: request.selection.ticket, receiptID: request.receiptID, status: status).feedback
          } else { report(error) }
        }
      }
    }
  }
  private func checkEditorReceipt() {
    guard !disposed, !editorBusy, visibleMode == .nativeReflow, let request = editorRequest, let actions,
          actionTasks.count < 8 else { return }
    editorBusy = true; hostWindow.notice.stringValue = "Checking editor result…"
    let id = UUID()
    actionTasks[id] = Task {
      defer { actionTasks.removeValue(forKey: id); editorBusy = false }
      do {
        try session.authorize(request.context, selection: request.selection.ticket)
        let owner = try await actions()
        let receipt = try await owner.jump(request, query: true)
        try Task.checkCancellation(); try session.authorize(request.context, selection: request.selection.ticket)
        hostWindow.notice.stringValue = receipt.feedback
      } catch { if !Task.isCancelled { hostWindow.notice.stringValue = "Editor result unavailable for this selection. No move was retried." } }
    }
  }
  private func chat(_ command: NativeReaderChatCommand, context: NativeReaderRequestContext) {
    guard visibleMode == .nativeReflow else { report(NativeOriginalPageError.unsupported("pdf-source-actions-unavailable")); return }
    if case .open(let selection) = command {
      presentLocalComposer(selection, context: context); return
    }
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
        let chat = try presentChat(conversation, actions: owner, context: context)
        chat.presentAccount(try await owner.account(context: context))
      } catch { if !Task.isCancelled { report(error) } }
    }
  }

  private func returnCapsuleFocus() {
    guard let window = hostWindow.window else { return }
    if let view = capsuleFocusReturn as? NSView, view.window === window, !view.isHiddenOrHasHiddenAncestor {
      window.makeFirstResponder(view)
    } else { window.makeFirstResponder(visibleMode == .nativeReflow ? textView.bodyTextView : originalPageView) }
  }
  private func updateCapsule(reopen: Bool = false, focus: Bool = false) {
    guard !disposed, !requestTicket.isCancelled, let context = session.context,
          let root = hostWindow.window?.contentView else { hostWindow.hideCapsule(); return }
    let binding: NativeFloatingCapsule.Binding
    var unavailable = [NativeFloatingCapsule.Action: String]()
    let rects: [NSRect], viewport: NSRect
    if visibleMode == .originalPages {
      guard let selected = originalPageView.selected, let ticket = originalPageView.store.selection?.0,
            selected.snapshotID == originalPageView.store.accepted?.id,
            let rect = try? originalPageView.store.viewRect(forPageRect: selected.pageBounds),
            let clip = originalPageView.enclosingScrollView?.contentView else { hostWindow.hideCapsule(); return }
      binding = .init(context: context, ticket: ticket, originalPDF: true)
      viewport = clip.convert(clip.bounds, to: root)
      rects = [originalPageView.convert(rect, to: root).intersection(viewport)].filter { !$0.isEmpty }
      for action in [NativeFloatingCapsule.Action.source, .highlight, .ask, .editor] { unavailable[action] = "원본 PDF는 복사·검색·탐색만 지원합니다." }
    } else {
      guard let selection = store.selection, let document = store.document,
            textView.renderKey == textView.requestedRenderKey else { hostWindow.hideCapsule(); return }
      binding = .init(context: context, ticket: selection.ticket, originalPDF: false)
      rects = textView.visibleSelectionRects(in: root)
      viewport = textView.scrollView.contentView.convert(textView.scrollView.contentView.bounds, to: root)
      let eligible = (try? selection.validate(in: document)) != nil
      let live = (try? session.authorize(context, selection: selection.ticket)) != nil && actions != nil
      if !eligible || !live {
        for action in [NativeFloatingCapsule.Action.source, .highlight, .ask, .editor] {
          unavailable[action] = !eligible ? "원문·대화는 최대 32개 블록을 지원합니다. 전체 선택은 유지됩니다." : "오프라인·복원·준비 중에는 원문·대화를 사용할 수 없습니다."
        }
      } else if capsuleCapabilities?.0 == binding { unavailable = capsuleCapabilities!.1 }
      else { unavailable[.editor] = "편집기 연결 상태를 확인 중입니다."; unavailable[.highlight] = "원문 쓰기 권한을 확인 중입니다." }
    }
    // Selection changes invalidate Send through the existing Session authority,
    // but an unsent local draft stays visible until explicit dismissal/replacement.
    chatView?.refreshAuthorization()
    if reopen { dismissedCapsule = nil }
    guard dismissedCapsule != binding, !rects.isEmpty else { hostWindow.hideCapsule(); return }
    let summary = unavailable[.ask] ?? "선택한 내용 · 질문하기는 작성기만 엽니다. 명시 전송 전에는 요청하지 않습니다."
    hostWindow.capsule.present(binding, unavailable: unavailable, summary: summary)
    hostWindow.placeCapsule(viewport: viewport, avoiding: rects)
    if focus { capsuleFocusReturn = hostWindow.window?.firstResponder; hostWindow.capsule.focusFirstAction() }
  }
  private func capsuleAction(_ binding: NativeFloatingCapsule.Binding, _ action: NativeFloatingCapsule.Action) {
    guard hostWindow.capsule.binding == binding, session.context == binding.context,
          (visibleMode == .originalPages) == binding.originalPDF else { return }
    if binding.originalPDF {
      guard originalPageView.store.selection?.0 == binding.ticket, action == .copy else { return }
      _ = originalPageView.copyDisplay(); return
    }
    guard store.selection?.ticket == binding.ticket else { return }
    if action == .copy { _ = textView.copyPlainText(); return }
    guard (try? session.authorize(binding.context, selection: binding.ticket)) != nil else { return }
    switch action {
    case .copy: break
    case .source: _ = textView.requestSource(.excerpt)
    case .highlight: _ = textView.requestSource(.highlight)
    case .editor: hostWindow.locateSelected()
    case .ask: textView.openChat()
    }
  }
  private func presentLocalComposer(_ selection: NativeReaderSelection, context: NativeReaderRequestContext) {
    do {
      try session.authorize(context, selection: selection.ticket)
      guard let document = store.document, let actions else { throw NativeReaderOperationFailure.unavailable }
      try selection.validate(in: document)
      capsuleFocusReturn = hostWindow.window?.firstResponder
      rememberCurrentDraft()
      chatView?.dispose(); chatView?.removeFromSuperview()
      let retained = retainedChatPresentations.last { $0.context == context && $0.selection.fragments == selection.fragments }
      let latest = retained.flatMap { retainedChatConversations[$0.conversationID] }
      let resumes = latest?.conversation.state.context == context
      let needsOpen = !resumes || retained?.selection.ticket != selection.ticket
      let chat = NativeReaderChatView(resolveActions: actions, context: context, selection: needsOpen ? selection : nil, authorize: { [weak self] in
        guard let self, self.visibleMode == .nativeReflow else { throw NativeReaderOperationFailure.unavailable }
        try self.session.authorize(context)
      }, authorizeSend: { [weak self] in
        guard let self, self.visibleMode == .nativeReflow else { throw NativeReaderOperationFailure.unavailable }
        try self.session.authorize(context, selection: selection.ticket)
      })
      bindComposer(chat, context: context)
      if resumes, let latest {
        chat.restoreModelChoices(latest.models)
        try chat.adopt(latest.conversation)
      }
      if let key = acceptedPaintKey { configureChatMath(chat, key: key) }
      hostWindow.attachChat(chat); dismissedCapsule = .init(context: context, ticket: selection.ticket, originalPDF: false)
      hostWindow.hideCapsule(); hostWindow.window?.makeFirstResponder(chat.composer)
    } catch { report(error) }
  }
  private func dismissComposer(_ chat: NativeReaderChatView) {
    guard chatView === chat else { return }
    rememberCurrentDraft(); chat.dispose(); chat.removeFromSuperview(); chatView = nil; chatContext = nil
    returnCapsuleFocus()
  }

  /// Compose an existing owner's accepted conversation; no Send/account action is implicit.
  @discardableResult func presentChat(_ conversation: NativeReaderConversation, actions: NativeReaderActions,
                                      context: NativeReaderRequestContext) throws -> NativeReaderChatView {
    try session.authorize(context)
    guard let key = acceptedPaintKey, key.identity == context.target, key.documentGeneration == context.generation else { throw NativeObjectError.stale }
    rememberCurrentDraft()
    chatView?.dispose(); chatView?.removeFromSuperview()
    let selectedTicket = store.selection?.ticket
    let chat = NativeReaderChatView(actions: actions, context: context, authorize: { [weak self] in
      guard let self, self.visibleMode == .nativeReflow else { throw NativeReaderOperationFailure.unavailable }
      try self.session.authorize(context)
    }, authorizeSend: { [weak self] in
      guard let self, let selectedTicket else { throw NativeReaderContractError.invalidSelection }
      try self.session.authorize(context, selection: selectedTicket)
    })
    configureChatMath(chat, key: key)
    bindComposer(chat, context: context)
    try chat.adopt(conversation); hostWindow.attachChat(chat)
    return chat
  }

  /// One host composition seam for local Ask and accepted-conversation entry.
  private func bindComposer(_ chat: NativeReaderChatView, context: NativeReaderRequestContext) {
    if currentDraftIdentity != context.target { currentDrafts.removeAll(); currentDraftIdentity = context.target }
    chat.composer.blocksSystemClipboard = fixtureMode
    chat.answer.blocksSystemClipboard = fixtureMode
    chatView = chat; chatContext = context
    chat.refreshAuthorization()
    chat.onDismiss = { [weak self, weak chat] in if let chat { self?.dismissComposer(chat) } }
    chat.openHomepage = { [weak self] in self?.openHomepage?($0) }
    chat.recoverConversation = { [weak self, weak chat] conversation in
      guard let self, let chat, self.chatView === chat, self.chatContext == context,
            conversation.state.context == context, !self.disposed else { throw NativeReaderContractError.disposed }
      try self.session.authorize(context)
      let id = conversation.state.conversationID
      let recovered = self.currentDrafts[id] ?? (self.recoveredDraftIdentity == context.target ? self.recoveredDrafts.first { $0.conversationID == id } : nil)
      if let recovered, recovered.version > conversation.state.version { throw NativeReaderContractError.staleGeneration }
      self.recoveredDrafts.removeAll { $0.conversationID == id }
      return recovered
    }
    chat.persistDraft = { [weak self, weak chat] draft in
      guard let self, let chat, self.chatView === chat, self.chatContext == context,
            self.currentDraftIdentity == context.target, !self.disposed else { return }
      self.currentDrafts[draft.conversationID] = draft
    }
  }

  private func configureChatMath(_ chat: NativeReaderChatView, key: NativeReaderTextRenderKey) {
    do {
      guard let runtime else { throw NativeObjectError.unsupported("answer-math-runtime-not-delivered") }
      let worker: NativeMathWorker
      if let pinned = chatWorker, pinned.node == runtime.node, pinned.helper == runtime.helper, pinned.runtime == runtime.runtime { worker = pinned.worker }
      else {
        worker = try runtime.worker()
        chatWorker = (runtime.node, runtime.helper, runtime.runtime, worker)
      }
      let context = NativeObjectContext(identity: key.identity, snapshotGeneration: key.documentGeneration,
        generation: key.layoutGeneration, width: Double(key.width), fontSize: Double(key.appearance.effectiveSize), fontName: "system",
        theme: key.appearance.theme == .dark ? .dark : .light, mode: .reflow, pageHeight: 1000)
      try chat.configureMath(worker: worker, context: context)
    } catch { chat.clearMath(reason: String(describing: error)) }
  }

  /// Closing a view explicitly ends its selection lifetime; transport failures do not.
  private func closeView() {
    guard !disposed else { return }
    originalPageView.releaseSelection()
    cancel()
    let revoke = revokeEditorConsent; Task { await revoke() }
    if let selection = store.selection { textView.releaseSelection(ticket: selection.ticket) }
    textView.cancel()
  }

  func cancel() {
    hostWindow.cancelFind()
    hostWindow.hideCapsule()
    cancelStorage()
    // A closed ticket may be cancelled again by its outer lifecycle owner.
    // Do not advance store authority or invalidate another frame twice.
    guard !requestTicket.isCancelled || progress != nil else { return }
    pendingPresentation = nil; localReview.clear()
    preparingKey = nil
    originalPageView.cancel()
    reflowTask?.cancel(); reflowTask = nil
    requestTicket.cancel(); progress = nil; acceptedPaintKey = nil; paintedKey = nil
    selectionTask?.cancel(); selectionTask = nil
    actionTasks.values.forEach { $0.cancel() }; actionTasks.removeAll()
    retainedChatPresentations.removeAll()
    retainedChatConversations.removeAll()
    chatView?.dispose(); session.cancel()
  }
  func dispose() {
    if let observer = capsuleScrollObserver { NotificationCenter.default.removeObserver(observer); capsuleScrollObserver = nil }
    if let observer = layoutObserver { NotificationCenter.default.removeObserver(observer); layoutObserver = nil }
    if let observer = capsuleScrollObserver { NotificationCenter.default.removeObserver(observer); capsuleScrollObserver = nil }
    cancel(); disposed = true; acceptedPageDelivery = nil; acceptedAssets = nil; session.event(.dispose); originalPageView.dispose(); textView.dispose()
    let revoke = revokeEditorConsent; Task { await revoke() }
    hostWindow.window?.close() }
}

@MainActor final class NativeReaderHostWindow: NSWindowController, NSWindowDelegate {
  let reader: NativeReaderTextView
  let notice = NSTextField(wrappingLabelWithString: "원문·대화 작업은 본문 모드에서 사용할 수 있습니다.")
  var onRefresh: (() -> Void)?
  var onCancelRecovery: (() -> Void)?
  var onRetryRecovery: (() -> Void)?
  var onShowCapsule: (() -> Void)?
  var onCapsuleLayout: (() -> Void)?
  let capsule = NativeFloatingCapsule()
  private var capsuleDocked = false
  private var capsuleConstraints = [NSLayoutConstraint]()
  private var pendingRecovery = false
  private let retryRecoveryButton = NativeDesignButton(title: "복원 재시도", target: nil, action: nil)
  private let cancelRecoveryButton = NativeDesignButton(title: "복원 취소", target: nil, action: nil)
  private let brandMark = NativeBrandMarkView()
  private var refreshButton: NSButton?
  private let toolsButton = NativeDesignButton(title: "읽기 도구", target: nil, action: nil)
  private let modeStatus = NSTextField(wrappingLabelWithString: "현재: 본문")
  private let selectionStatus = NSTextField(wrappingLabelWithString: "문서를 준비하고 있습니다…")
  private let auxiliary = NSStackView()
  private let toolsScroll = NativeReaderToolsScrollView()
  private var requestedMode: NativeReaderWindowController.Mode?
  private var allowsModeSwitch = true
  private var requestWasHeld = false
  private var latestState = NativeReaderSession.State.idle
  private var failedState = false
  private var retainedFailure = false
  private var searchSelectionTicket: UUID?
  private var findTask: Task<Void, Never>?
  private var findGeneration = 0
  private var modeButtons = [NSButton]()
  var onClose: (() -> Void)?
  var changeMode: ((NativeReaderWindowController.Mode) -> Void)?
  var onMarkReview: (() -> Void)?
  var onUndoReview: (() -> Void)?
  var onClearReview: (() -> Void)?
  var onAppearance: (() -> Void)?
  var onExportPDF: (() -> Void)?
  var onSaveOffline: (() -> Void)?
  var onListOffline: (() -> Void)?
  var onOpenOffline: ((NativeDocumentIdentity) -> Void)?
  var onCancelStorage: (() -> Void)?
  var onLastEdit: (() -> Void)?
  var onEditorReceipt: (() -> Void)?
  var onAccount: (() -> Void)?
  var onManageAccount: ((URL) -> Void)?
  let contents = NSPopUpButton()
  let theme = NSPopUpButton()
  let textSize = NSPopUpButton()
  private let applyDisplay = NativeDesignButton(title: "Apply Display", target: nil, action: nil)
  private let cancelDisplay = NativeDesignButton(title: "Cancel Display", target: nil, action: nil)
  private var displayPreview: (document: NativeReaderDocument?, appearance: NativeReaderTextAppearance, theme: Int, windowAppearance: NSAppearance?, anchor: NativeReaderViewportAnchor?)?
  private var pendingDisplayViewport: (NativeReaderDocument?, NativeReaderViewportAnchor, NativeReaderTextAppearance)?
  private var committedTheme = 0
  private var appearanceObservation: NSKeyValueObservation?

  let savedDocuments = NSPopUpButton()
  private let back = NativeDesignButton(title: "Back", target: nil, action: nil)
  private let undoReview = NativeDesignButton(title: "Undo review", target: nil, action: nil)
  private let clearReview = NativeDesignButton(title: "Clear review", target: nil, action: nil)
  private let exportPDF = NativeDesignButton(title: "Export PDF", target: nil, action: nil)
  private let saveOffline = NativeDesignButton(title: "Save Offline", target: nil, action: nil)
  private let refreshSaved = NativeDesignButton(title: "Refresh Saved", target: nil, action: nil)
  private let openSaved = NativeDesignButton(title: "Open Saved", target: nil, action: nil)
  private let cancelStorage = NativeDesignButton(title: "Cancel", target: nil, action: nil)
  private let manageAccount = NativeDesignButton(title: "Manage Account", target: nil, action: nil)
  private let accountStatus = NSTextField(wrappingLabelWithString: "계정")
  private let recoveredDraftPicker = NSPopUpButton()
  private let recoveredDraftText = NSTextField(wrappingLabelWithString: "")
  private let recoveredDraftRow = NSStackView()
  private var savedEntries = [NativeReaderRecoveryStore.Entry]()
  private var recoveredDrafts = [NativeReaderRecoveredDraft]()
  private var homepage: URL?
  private var liveButtons = [NSButton]()
  private var reflowRows = [NSView]()
  var reviewCount = 0 { didSet { undoReview.isEnabled = reviewCount > 0; clearReview.isEnabled = reviewCount > 0 } }
  var exportBusy = false { didSet { updateOfflineControls() } }
  var storageAvailable = false { didSet { updateOfflineControls() } }
  var storageBusy = false { didSet { updateOfflineControls() } }
  private var original: NativeReaderOriginalPageView?
  private var originalScroll: NativeReaderPageScrollView?
  private var currentMode: NativeReaderWindowController.Mode = .nativeReflow
  private let sourceControls = NSStackView()
  let findField = NSSearchField()
  private let fixtureMode: Bool
  private let show: Bool
  private let avoidActivation: Bool
  private let stack = NSStackView()
  init(reader: NativeReaderTextView, show: Bool, avoidActivation: Bool, fixtureMode: Bool = false) {
    self.fixtureMode = fixtureMode
    self.reader = reader; self.show = show; self.avoidActivation = avoidActivation
    super.init(window: nil)
  }
  required init?(coder: NSCoder) { nil }
  func initialize() { if window == nil { loadWindow() } }
  override func loadWindow() {
    let window = NativeReaderEditingWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 720),
      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
    window.fixtureMode = fixtureMode
    reader.bodyTextView.blocksSystemClipboard = fixtureMode; reader.bodyTextView.allowsPrivateCopy = true
    window.isReleasedWhenClosed = false; window.delegate = self; window.title = "Lagrangian · 읽기"
    NativeChrome.install(on: window)
    stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 6
    auxiliary.orientation = .vertical; auxiliary.alignment = .leading; auxiliary.spacing = 6
    func row(_ views: [NSView], in parent: NSStackView = stack) -> NativeChromeControlRow {
      let row = NativeChromeControlRow(views)
      parent.addArrangedSubview(row); row.translatesAutoresizingMaskIntoConstraints = false
      row.widthAnchor.constraint(equalTo: parent.widthAnchor).isActive = true
      return row
    }
    func command(_ title: String, _ action: Selector) -> NSButton {
      let button = NativeDesignButton(title: title, target: self, action: action)
      button.identifier = NSUserInterfaceItemIdentifier(NSStringFromSelector(action))
      button.setAccessibilityLabel(title)
      return button
    }
    let reflow = command("본문", #selector(reflowMode)), pdf = command("원본 PDF", #selector(pageMode))
    modeButtons = [reflow, pdf]; reflow.setButtonType(.pushOnPushOff); pdf.setButtonType(.pushOnPushOff); reflow.state = .on
    toolsButton.target = self; toolsButton.action = #selector(toggleTools); toolsButton.setButtonType(.pushOnPushOff)
    toolsButton.identifier = NSUserInterfaceItemIdentifier("toggleTools")
    toolsButton.keyEquivalent = "t"; toolsButton.keyEquivalentModifierMask = [.command, .option]
    toolsButton.setAccessibilityLabel("읽기 도구 펼치기")
    let refresh = command("새로고침", #selector(refreshDocument)); refreshButton = refresh
    brandMark.widthAnchor.constraint(equalToConstant: 28).isActive = true
    brandMark.heightAnchor.constraint(equalToConstant: 26).isActive = true
    _ = row([brandMark, reflow, pdf, toolsButton, refresh, command("선택 작업", #selector(showSelectionActions))])
    retryRecoveryButton.target = self; retryRecoveryButton.action = #selector(retryRecovery)
    cancelRecoveryButton.target = self; cancelRecoveryButton.action = #selector(cancelRecovery)
    retryRecoveryButton.identifier = NSUserInterfaceItemIdentifier("retryRecovery")
    cancelRecoveryButton.identifier = NSUserInterfaceItemIdentifier("cancelRecovery")
    retryRecoveryButton.isHidden = true; cancelRecoveryButton.isHidden = true
    _ = row([retryRecoveryButton, cancelRecoveryButton])
    contents.setAccessibilityLabel("목차"); contents.identifier = NSUserInterfaceItemIdentifier("contents")
    contents.target = self; contents.action = #selector(outlineSelected)
    back.title = "돌아가기"; back.target = self; back.action = #selector(returnFromReference)
    back.identifier = NSUserInterfaceItemIdentifier("returnFromReference")
    let pageNavigation = NSStackView(views: [command("이전 페이지", #selector(previousPage)), command("다음 페이지", #selector(nextPage))])
    pageNavigation.identifier = NSUserInterfaceItemIdentifier("pageNavigation")
    _ = row([NSTextField(labelWithString: "목차"), contents, back, pageNavigation])
    findField.placeholderString = "PDF에서 검색"; findField.setAccessibilityLabel("PDF에서 검색")
    findField.identifier = NSUserInterfaceItemIdentifier("findPage")
    findField.target = self; findField.action = #selector(findPage)
    for field in [findField, modeStatus, selectionStatus] {
      stack.addArrangedSubview(field); field.translatesAutoresizingMaskIntoConstraints = false
      field.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    modeStatus.identifier = NSUserInterfaceItemIdentifier("readerModeStatus")
    selectionStatus.identifier = NSUserInterfaceItemIdentifier("readerSelectionStatus")
    _ = row([command("선택 해제", #selector(releasePageSelection)), command("복사", #selector(copySelected))])
    // Existing native commands stay in one discoverable, scrollable disclosure.
    toolsScroll.hasVerticalScroller = true; toolsScroll.autohidesScrollers = false
    toolsScroll.scrollerStyle = .legacy
    toolsScroll.identifier = NSUserInterfaceItemIdentifier("readerToolsScroll")
    toolsScroll.documentView = auxiliary; toolsScroll.isHidden = true
    stack.addArrangedSubview(toolsScroll); toolsScroll.translatesAutoresizingMaskIntoConstraints = false
    let preferredToolsHeight = toolsScroll.heightAnchor.constraint(equalToConstant: 200)
    preferredToolsHeight.priority = .defaultHigh
    NSLayoutConstraint.activate([
      toolsScroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
      preferredToolsHeight,
      toolsScroll.heightAnchor.constraint(lessThanOrEqualToConstant: 200),
      toolsScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 64)])
    // The scroll document owns its origin and measured height. Pinning its top
    // to the moving clip bounds makes the last rows follow the scroll offset.
    auxiliary.translatesAutoresizingMaskIntoConstraints = true
    _ = row([NSTextField(labelWithString: "원문·대화")], in: auxiliary)
    sourceControls.orientation = .vertical; sourceControls.alignment = .leading
    auxiliary.addArrangedSubview(sourceControls); sourceControls.translatesAutoresizingMaskIntoConstraints = false
    sourceControls.widthAnchor.constraint(equalTo: auxiliary.widthAnchor).isActive = true
    var sourceButtons = [NSView]()
    for (title, action) in [("원문 보기", #selector(sourceSelected)), ("원문 강조", #selector(highlightSelected)),
                            ("질문하기", #selector(askSelected)), ("편집기 위치로", #selector(locateSelected)),
                            ("편집기 결과 확인", #selector(editorReceipt)), ("최근 편집", #selector(lastEdit)), ("계정 상태", #selector(account))] {
      let button = command(title, action); sourceButtons.append(button); liveButtons.append(button)
    }
    _ = row(sourceButtons, in: sourceControls)
    theme.addItems(withTitles: ["밝게", "어둡게", "자동"]); theme.setAccessibilityLabel("테마"); theme.identifier = NSUserInterfaceItemIdentifier("theme")
    theme.target = self; theme.action = #selector(appearanceChanged)
    textSize.addItems(withTitles: ["12", "14", "16", "18", "24", "32"]); textSize.selectItem(withTitle: "14")
    textSize.setAccessibilityLabel("글자 크기"); textSize.identifier = NSUserInterfaceItemIdentifier("textSize")
    textSize.target = self; textSize.action = #selector(appearanceChanged)
    applyDisplay.title = "보기 적용"; cancelDisplay.title = "보기 취소"
    applyDisplay.target = self; applyDisplay.action = #selector(applyDisplayExplicitly)
    cancelDisplay.target = self; cancelDisplay.action = #selector(cancelDisplayExplicitly)
    applyDisplay.isEnabled = false; cancelDisplay.isEnabled = false
    let appearance = row([NSTextField(labelWithString: "테마"), theme, NSTextField(labelWithString: "글자 크기"), textSize,
      command("보기 미리 보기", #selector(previewDisplayExplicitly)), applyDisplay, cancelDisplay], in: auxiliary)
    _ = row([command("확대", #selector(zoomIn)), command("축소", #selector(zoomOut)), command("맞춤", #selector(fitPage)), command("PDF 복사", #selector(copySelected))], in: auxiliary)
    undoReview.title = "검토 표시 취소"; clearReview.title = "검토 표시 지우기"
    undoReview.target = self; undoReview.action = #selector(undoReviewExplicitly)
    clearReview.target = self; clearReview.action = #selector(clearReviewExplicitly)
    let review = row([command("검토 표시", #selector(markSelected)), undoReview, clearReview], in: auxiliary)
    undoReview.isEnabled = false; clearReview.isEnabled = false
    reflowRows = [appearance, review]
    savedDocuments.setAccessibilityLabel("저장한 문서"); savedDocuments.identifier = NSUserInterfaceItemIdentifier("savedDocuments")
    savedDocuments.target = self; savedDocuments.action = #selector(savedDocumentSelected)
    for (button, title, action) in [(saveOffline,"오프라인 저장",#selector(saveOfflineExplicitly)), (refreshSaved,"저장 목록 새로고침",#selector(refreshSavedExplicitly)),
      (openSaved,"저장 문서 열기",#selector(openSavedExplicitly)), (cancelStorage,"작업 취소",#selector(cancelStorageExplicitly)), (exportPDF,"PDF 내보내기",#selector(exportPDFExplicitly))] {
      button.title = title; button.target = self; button.action = action
      button.identifier = NSUserInterfaceItemIdentifier(NSStringFromSelector(action)); button.setAccessibilityLabel(title)
    }
    _ = row([NSTextField(labelWithString: "오프라인 문서"), saveOffline, savedDocuments, refreshSaved, openSaved, cancelStorage, exportPDF], in: auxiliary)
    manageAccount.title = "계정 관리"; manageAccount.target = self; manageAccount.action = #selector(manageAccountExplicitly); manageAccount.isEnabled = false
    _ = row([accountStatus, manageAccount], in: auxiliary)
    recoveredDraftRow.orientation = .vertical; recoveredDraftRow.alignment = .leading
    recoveredDraftPicker.setAccessibilityLabel("복원된 초안"); recoveredDraftPicker.identifier = NSUserInterfaceItemIdentifier("recoveredDrafts")
    recoveredDraftPicker.target = self; recoveredDraftPicker.action = #selector(recoveredDraftSelected)
    recoveredDraftRow.translatesAutoresizingMaskIntoConstraints = false
    recoveredDraftText.translatesAutoresizingMaskIntoConstraints = false
    recoveredDraftRow.addArrangedSubview(recoveredDraftPicker); recoveredDraftRow.addArrangedSubview(recoveredDraftText); recoveredDraftRow.isHidden = true
    auxiliary.addArrangedSubview(recoveredDraftRow)
    recoveredDraftRow.widthAnchor.constraint(equalTo: auxiliary.widthAnchor).isActive = true
    recoveredDraftText.widthAnchor.constraint(equalTo: recoveredDraftRow.widthAnchor).isActive = true
    notice.setAccessibilityLabel("최근 진단"); notice.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    _ = row([notice], in: auxiliary)
    stack.addArrangedSubview(reader)
    for button in [back, applyDisplay, cancelDisplay, undoReview, clearReview, manageAccount] {
      if let action = button.action { button.identifier = NSUserInterfaceItemIdentifier(NSStringFromSelector(action)) }
      button.setAccessibilityLabel(button.title)
    }
    modeStatus.setAccessibilityLabel("읽기 모드"); selectionStatus.setAccessibilityLabel("읽기 상태와 다음 동작")
    updateOfflineControls(); updateNavigation()
    stack.translatesAutoresizingMaskIntoConstraints = false; window.contentView!.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 16),
      stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -16),
      stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 12),
      stack.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor, constant: -12),
      reader.widthAnchor.constraint(equalTo: stack.widthAnchor),
      reader.heightAnchor.constraint(greaterThanOrEqualToConstant: 220)])
    NativeChrome.apply(to: window.contentView!)
    toolsScroll.drawsBackground = false
    self.window = window
    appearanceObservation = window.observe(\.effectiveAppearance, options: []) { [weak self] _, _ in
      Task { @MainActor in self?.automaticAppearanceChanged() }
    }
  }
  func hideCapsule() {
    if let focused = window?.firstResponder as? NSView, focused.isDescendant(of: capsule) {
      window?.makeFirstResponder(currentMode == .originalPages ? original : reader.bodyTextView)
    }
    capsule.hide()
    if capsuleDocked {
      NSLayoutConstraint.deactivate(capsuleConstraints); capsuleConstraints = []
      stack.removeArrangedSubview(capsule); capsule.removeFromSuperview(); capsuleDocked = false
    }
  }
  func placeCapsule(viewport: NSRect, avoiding rects: [NSRect]) {
    guard let root = window?.contentView else { return }
    let size = capsule.preferredSize(width: min(560, max(120, viewport.width - 16)))
    // Only renderer-verified empty space may host an overlay. PDF page content
    // and unavailable/stale geometry are conservatively occupied in full.
    let occupied: [NSRect]
    if currentMode == .originalPages { occupied = [viewport] }
    else if let used = reader.visibleUsedContentBounds(in: root) { occupied = used.isEmpty ? [] : [used] }
    else { occupied = [viewport] }
    if !capsuleDocked, let frame = NativeFloatingCapsule.placement(size: size, viewport: viewport.insetBy(dx: 8, dy: 8), avoiding: rects, occupied: occupied) {
      if capsule.superview !== root { capsule.removeFromSuperview(); root.addSubview(capsule) }
      capsule.translatesAutoresizingMaskIntoConstraints = true; capsule.frame = frame
    } else if !capsuleDocked {
      guard stack.bounds.width.isFinite, stack.bounds.width > 0 else { return }
      let dockSize = capsule.preferredSize(width: stack.bounds.width)
      capsule.removeFromSuperview()
      let index = stack.arrangedSubviews.firstIndex(where: { $0 === reader }) ?? stack.arrangedSubviews.count
      stack.insertArrangedSubview(capsule, at: index); capsule.translatesAutoresizingMaskIntoConstraints = false
      capsuleConstraints = [capsule.widthAnchor.constraint(equalTo: stack.widthAnchor), capsule.heightAnchor.constraint(equalToConstant: dockSize.height)]
      NSLayoutConstraint.activate(capsuleConstraints); capsuleDocked = true
    } else {
      guard stack.bounds.width.isFinite, stack.bounds.width > 0 else { return }
      capsuleConstraints.last?.constant = capsule.preferredSize(width: stack.bounds.width).height
    }
    capsule.layoutSubtreeIfNeeded()
  }
  @objc func showSelectionActions() { onShowCapsule?() }
  @objc func retryRecovery() { if pendingRecovery && failedState { onRetryRecovery?() } }
  @objc func cancelRecovery() { if pendingRecovery { onCancelRecovery?() } }
  func present() {
    guard show, NSApp.activationPolicy() != .prohibited else { return }
    if avoidActivation { window?.orderFrontRegardless() } else { showWindow(nil) }
  }
  func attachChat(_ chat: NativeReaderChatView) {
    stack.addArrangedSubview(chat)
    // Only the explicit composer needs extra height; keep the PDF viewport's
    // ordinary initial size and native scroll behavior unchanged.
    if let window, let content = window.contentView, content.frame.height < 960 {
      window.setContentSize(NSSize(width: content.frame.width, height: 960))
    }
  }
  func installOriginal(_ view: NativeReaderOriginalPageView) {
    guard original == nil else { return }; original = view
    let scroll = NativeReaderPageScrollView()
    scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true; scroll.autohidesScrollers = false
    scroll.scrollerStyle = .legacy
    scroll.setAccessibilityLabel("원본 PDF · 맞춤 또는 가로 스크롤로 페이지 탐색")
    scroll.documentView = view; originalScroll = scroll
    scroll.contentView.postsBoundsChangedNotifications = true
    view.isHidden = true; scroll.isHidden = true; stack.addArrangedSubview(scroll)
    scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
    scroll.translatesAutoresizingMaskIntoConstraints = false
    scroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
  }
  func displayMode(_ mode: NativeReaderWindowController.Mode) {
    cancelFind()
    hideCapsule()
    currentMode = mode
    retainedFailure = false
    if requestedMode == mode { requestedMode = nil; requestWasHeld = false }
    for (index, button) in modeButtons.enumerated() { button.state = (index == 0 ? mode == .nativeReflow : mode == .originalPages) ? .on : .off }
    refreshStatus()
    reader.isHidden = mode == .originalPages; original?.isHidden = mode != .originalPages
    // Source/Highlight/Ask cannot dispatch the retained hidden reflow selection.
    originalScroll?.isHidden = mode != .originalPages
    sourceControls.isHidden = mode == .originalPages
    for row in reflowRows { row.isHidden = mode != .nativeReflow }
    recoveredDraftRow.isHidden = recoveredDrafts.isEmpty
    window?.contentView?.layoutSubtreeIfNeeded()
  }
  @objc func toggleTools() {
    let opening = toolsScroll.isHidden
    if !opening, let window {
      let focused = window.firstResponder as? NSView
      let fieldOwner = (window.firstResponder as? NSTextView).flatMap { $0.isFieldEditor ? $0.delegate as? NSView : nil }
      if focused?.isDescendant(of: auxiliary) == true || fieldOwner?.isDescendant(of: auxiliary) == true { window.makeFirstResponder(toolsButton) }
    }
    toolsScroll.isHidden = !opening; toolsButton.state = opening ? .on : .off
    toolsButton.setAccessibilityLabel(opening ? "읽기 도구 접기" : "읽기 도구 펼치기")
    invalidateControlLayout(); window?.contentView?.layoutSubtreeIfNeeded(); window?.recalculateKeyViewLoop()
  }
  @objc func refreshDocument() { requestedMode = nil; requestWasHeld = false; onRefresh?() }
  func requestMode(_ mode: NativeReaderWindowController.Mode) {
    requestedMode = mode == currentMode ? nil : mode; requestWasHeld = reader.store.selection != nil || original?.selected != nil
    refreshStatus()
  }
  func updateStatus(state: NativeReaderSession.State, failed: Bool, allowsRefresh: Bool = true, allowsModeSwitch: Bool = true, pendingRecovery: Bool = false) {
    self.pendingRecovery = pendingRecovery
    cancelRecoveryButton.isHidden = !pendingRecovery
    retryRecoveryButton.isHidden = !pendingRecovery || !failed
    latestState = state; failedState = failed; refreshButton?.isEnabled = allowsRefresh
    self.allowsModeSwitch = allowsModeSwitch
    for button in modeButtons { button.isEnabled = allowsModeSwitch }
    if !allowsModeSwitch { requestedMode = nil; requestWasHeld = false }
    brandMark.phase = failed ? .error : (state == .loading ? .busy : (state == .offline ? .offline : .idle))
    refreshStatus()
  }
  func showRetainedFailure() { retainedFailure = true; refreshStatus() }
  private func refreshStatus() {
    func name(_ mode: NativeReaderWindowController.Mode) -> String { mode == .nativeReflow ? "본문" : "원본 PDF" }
    for (index, button) in modeButtons.enumerated() { button.state = (index == 0 ? currentMode == .nativeReflow : currentMode == .originalPages) ? .on : .off }
    for button in modeButtons { (button as? NativeDesignButton)?.designRole = button.state == .on ? .primary : .standard }
    modeStatus.stringValue = "현재: " + name(currentMode) + (requestedMode.map { " · 전환 요청: " + name($0) } ?? "")
    if latestState == .disposed {
      selectionStatus.stringValue = "읽기 창이 닫혀 모드를 전환할 수 없습니다."
    } else if pendingRecovery && (retainedFailure || failedState) {
      selectionStatus.stringValue = "복원하지 못했습니다. " + (reader.store.document == nil ? "" : "이전 읽기 결과를 표시 중입니다. ") + "‘복원 재시도’ 또는 ‘복원 취소’ 후 저장 문서를 다시 여세요. 원문·대화는 사용할 수 없습니다."
    } else if pendingRecovery && latestState == .loading {
      selectionStatus.stringValue = "저장 문서를 복원 준비 중입니다… 이전 읽기 결과는 유지됩니다. ‘복원 취소’로 중단할 수 있습니다."
    } else if retainedFailure || failedState {
      selectionStatus.stringValue = (reader.store.document == nil ? "문서를 불러오지 못했습니다. " : "이전 읽기 결과를 표시 중입니다. ") + (refreshButton?.isEnabled == true ? "최신 결과를 보려면 ‘새로고침’을 누르세요." : "저장 문서를 다시 열어 복원하세요.")
    } else if !allowsModeSwitch {
      selectionStatus.stringValue = "오프라인 복원본에서는 모드를 전환할 수 없습니다. 원문·대화 작업은 사용할 수 없습니다."
    } else if let requestedMode {
      let next = name(requestedMode)
      if reader.store.selection != nil { selectionStatus.stringValue = "본문에서 선택한 내용이 있어 전환을 보류합니다. ‘선택 해제’ 후 ‘\(next)’ 버튼을 다시 누르세요." }
      else if let selection = original?.store.selection {
        let origin = selection.0 == searchSelectionTicket ? "검색 결과에서 선택한 부분" : "PDF에서 선택한 부분"
        selectionStatus.stringValue = origin + "이 있어 전환을 보류합니다. ‘선택 해제’ 후 ‘\(next)’ 버튼을 다시 누르세요."
      } else if requestWasHeld { selectionStatus.stringValue = "선택이 해제되었습니다. ‘\(next)’ 버튼을 다시 눌러 전환하세요." }
      else { selectionStatus.stringValue = "\(next) 모드를 준비하고 있습니다…" }
    } else {
      switch latestState {
      case .idle, .loading: selectionStatus.stringValue = "문서를 준비하고 있습니다…"
      case .reading: selectionStatus.stringValue = "문서를 읽고 있습니다."
      case .offline: selectionStatus.stringValue = "오프라인 읽기 · 원문·대화 작업은 사용할 수 없습니다."
      case .sleeping: selectionStatus.stringValue = "읽기를 일시 중지했습니다."
      case .disposed: selectionStatus.stringValue = "읽기 창이 닫혔습니다."
      }
    }
  }
  @objc func reflowMode() { changeMode?(.nativeReflow) }
  @objc func pageMode() { changeMode?(.originalPages) }
  @objc func previousPage() { if let original { pageAction { try original.jump(to: max(0, original.store.pageIndex - 1)) } } }
  @objc func nextPage() { if let original { pageAction { try original.jump(to: original.store.pageIndex + 1) } } }
  @objc func zoomIn() {
    if currentMode == .nativeReflow { beginDisplayPreview(); reader.changeZoom(by: 1.25); onAppearance?() }
    else if let original { pageAction { try original.zoom(original.store.displayedScale * 1.25) } }
  }
  @objc func zoomOut() {
    if currentMode == .nativeReflow { beginDisplayPreview(); reader.changeZoom(by: 1 / 1.25); onAppearance?() }
    else if let original { pageAction { try original.zoom(original.store.displayedScale / 1.25) } }
  }
  @objc func fitPage() {
    if currentMode == .nativeReflow { beginDisplayPreview(); var value = reader.textAppearance; value.zoom = 1; try? reader.setAppearance(value); onAppearance?() }
    else if let original { pageAction { try original.zoom(nil) } }
  }
  @objc func releasePageSelection() {
    cancelFind()
    if currentMode == .originalPages { original?.releaseSelection() }
    else if let selected = reader.store.selection { reader.releaseSelection(ticket: selected.ticket) }
    refreshStatus()
  }
  private func pageAction(_ action: () throws -> Void) {
    guard currentMode == .originalPages else { return }
    do { try action() } catch { notice.stringValue = String(describing: error) }
  }
  @objc func findPage() {
    guard currentMode == .originalPages, let original else { return }
    cancelFind()
    let generation = findGeneration, snapshot = original.store.accepted?.id, selected = original.store.selection?.0
    let query = findField.stringValue
    findTask = Task { [weak self] in
      do {
        guard let hit = try await original.search(query).first else { return }
        try Task.checkCancellation()
        guard let self, self.findGeneration == generation, self.currentMode == .originalPages,
              !original.isHidden, original.store.accepted?.id == snapshot,
              original.store.selection?.0 == selected else { return }
        try original.jump(to: hit.pageIndex)
        try await original.select(page: hit.pageIndex, range: hit.rangeUTF16)
        try Task.checkCancellation()
        guard self.findGeneration == generation else { return }
        self.searchSelectionTicket = original.store.selection?.0; self.refreshStatus()
      } catch {
        guard let self, !Task.isCancelled, self.findGeneration == generation else { return }
        self.notice.stringValue = String(describing: error)
        if case NativeOriginalPageError.stale = error { self.showRetainedFailure() }
      }
    }
  }
  func cancelFind() { findGeneration += 1; findTask?.cancel(); findTask = nil }
  @objc func copySelected() { if currentMode == .originalPages { _ = original?.copyDisplay() } else { _ = reader.copyPlainText() } }
  @objc func sourceSelected() { guard currentMode == .nativeReflow else { return }; _ = reader.requestSource(.excerpt) }
  @objc func highlightSelected() { guard currentMode == .nativeReflow else { return }; _ = reader.requestSource(.highlight) }
  @objc func askSelected() { guard currentMode == .nativeReflow else { return }; reader.openChat() }
  func refreshOutline() {
    let previous = contents.selectedItem?.representedObject as? String
    contents.removeAllItems()
    for node in reader.outline {
      let item = NSMenuItem(title: String(repeating: "  ", count: min(5, max(0, (node.headingLevel ?? 1)-1))) + String(node.displayText.prefix(120)), action: nil, keyEquivalent: "")
      item.representedObject = node.id; contents.menu?.addItem(item)
    }
    if let previous, let item = contents.itemArray.first(where: { $0.representedObject as? String == previous }) { contents.select(item) }
    contents.toolTip = contents.titleOfSelectedItem
    invalidateControlLayout(); updateNavigation()
  }
  func updateNavigation() { contents.isEnabled = currentMode == .nativeReflow && !reader.outline.isEmpty; back.isEnabled = reader.canReturnFromReference }
  func updateReaderControls(readOnly: Bool) {
    for button in liveButtons { button.isEnabled = !readOnly && currentMode == .nativeReflow }
    if readOnly { homepage = nil; manageAccount.isEnabled = false; accountStatus.stringValue = "오프라인 · 계정 작업을 사용할 수 없습니다" }
    updateNavigation(); updateOfflineControls()
  }
  private func updateOfflineControls() {
    let prepared = reader.store.document != nil && (currentMode == .originalPages || (reader.renderKey != nil && reader.renderKey == reader.requestedRenderKey))
    saveOffline.isEnabled = storageAvailable && !storageBusy && prepared
    refreshSaved.isEnabled = storageAvailable && !storageBusy
    openSaved.isEnabled = storageAvailable && !storageBusy && !savedEntries.isEmpty
    savedDocuments.isEnabled = !storageBusy && !savedEntries.isEmpty
    cancelStorage.isEnabled = storageBusy || exportBusy
    exportPDF.isEnabled = !fixtureMode && currentMode == .originalPages && original?.store.accepted != nil && !exportBusy
    if exportBusy { saveOffline.isEnabled = false; openSaved.isEnabled = false; refreshSaved.isEnabled = false }
  }
  private func invalidateControlLayout() {
    func invalidate(_ view: NSView) {
      if view is NativeChromeControlRow { view.invalidateIntrinsicContentSize(); view.needsLayout = true }
      for child in view.subviews { invalidate(child) }
    }
    invalidate(stack)
    toolsScroll.needsLayout = true
  }
  func refreshLocalControls() {
    invalidateControlLayout()
    updateOfflineControls()
    if let preview = displayPreview, preview.document != reader.store.document {
      // The new snapshot keeps the displayed settings. Adopt that same baseline
      // for the next preview, rather than mixing it with the old committed menu.
      committedTheme = theme.indexOfSelectedItem
      displayPreview = nil; pendingDisplayViewport = nil; cancelDisplay.isEnabled = false
    }
    applyDisplay.isEnabled = displayPreview != nil && reader.renderKey != nil && reader.renderKey == reader.requestedRenderKey
    if let pending = pendingDisplayViewport, pending.0 == reader.store.document,
       reader.textAppearance == pending.2, reader.renderKey == reader.requestedRenderKey {
      reader.restoreViewport(pending.1); pendingDisplayViewport = nil
    }
  }
  func setSavedDocuments(_ entries: [NativeReaderRecoveryStore.Entry]) {
    savedEntries = entries; savedDocuments.removeAllItems(); savedDocuments.addItems(withTitles: entries.map(\.title)); invalidateControlLayout(); updateOfflineControls()
  }
  func presentRecoveredDrafts(_ values: [NativeReaderRecoveredDraft]) {
    recoveredDrafts = values; recoveredDraftPicker.removeAllItems()
    for (index, _) in values.enumerated() { recoveredDraftPicker.addItem(withTitle: "복원된 초안 \(index+1)") }
    recoveredDraftRow.isHidden = values.isEmpty; recoveredDraftSelected()
  }
  func presentAccount(_ state: NativeReaderAccountState) {
    accountStatus.stringValue = state.signedIn ? (state.planEnabled ? "계정 연결됨" : "이용 가능한 플랜이 없습니다") : "설정된 홈페이지에서 로그인하세요."
    homepage = state.homepage; manageAccount.isEnabled = state.homepage != nil; invalidateControlLayout()
  }
  @objc func outlineSelected() { guard currentMode == .nativeReflow, let id = contents.selectedItem?.representedObject as? String else { return }; _ = reader.navigate(toNodeID: id); updateNavigation() }
  @objc func returnFromReference() { guard currentMode == .nativeReflow else { return }; _ = reader.returnFromReference(); updateNavigation() }
  private func beginDisplayPreview() {
    guard currentMode == .nativeReflow, displayPreview == nil else { return }
    displayPreview = (reader.store.document, reader.textAppearance, committedTheme, window?.appearance, reader.viewportAnchor())
    cancelDisplay.isEnabled = true; applyDisplay.isEnabled = true
  }
  @objc func previewDisplayExplicitly() { beginDisplayPreview() }
  @objc func applyDisplayExplicitly() {
    guard currentMode == .nativeReflow, reader.renderKey == reader.requestedRenderKey else { return }
    committedTheme = theme.indexOfSelectedItem
    displayPreview = nil; pendingDisplayViewport = nil; applyDisplay.isEnabled = false; cancelDisplay.isEnabled = false
  }
  @objc func cancelDisplayExplicitly() {
    guard let preview = displayPreview else { return }
    displayPreview = nil; applyDisplay.isEnabled = false; cancelDisplay.isEnabled = false
    guard preview.document == reader.store.document else { return }
    theme.selectItem(at: preview.theme); textSize.selectItem(withTitle: String(Int(preview.appearance.fontSize)))
    window?.appearance = preview.windowAppearance
    if let anchor = preview.anchor { pendingDisplayViewport = (preview.document, anchor, preview.appearance) }
    do { try reader.setAppearance(preview.appearance); onAppearance?(); refreshLocalControls() }
    catch { notice.stringValue = "Display settings unavailable." }
  }
  private func automaticAppearanceChanged() {
    guard currentMode == .nativeReflow else { return }
    let prior = reader.textAppearance
    do { try resolveAutomaticAppearance(); if prior != reader.textAppearance { onAppearance?() } }
    catch { notice.stringValue = "Display settings unavailable." }
  }
  /// Called before a new Reflow preparation too: Original PDF deliberately
  /// ignores color events, so its retained text key is not the current theme.
  func resolveAutomaticAppearance() throws {
    guard theme.indexOfSelectedItem == 2, let window else { return }
    var value = reader.textAppearance
    value.theme = window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
    guard value != reader.textAppearance else { return }
    try reader.setAppearance(value)
  }
  @objc func appearanceChanged() {
    guard currentMode == .nativeReflow else { return }
    beginDisplayPreview()
    var value = reader.textAppearance
    // The concrete render key always contains resolved colors, while Automatic
    // inherits only this window's effective appearance (never changes the OS).
    switch theme.indexOfSelectedItem {
    case 1: window?.appearance = NSAppearance(named: .darkAqua); value.theme = .dark
    case 2: window?.appearance = nil; value.theme = window?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
    default: window?.appearance = NSAppearance(named: .aqua); value.theme = .light
    }
    if let title = textSize.titleOfSelectedItem, let size = Double(title) { value.fontSize = CGFloat(size) }
    do { try reader.setAppearance(value); onAppearance?(); refreshLocalControls() }
    catch { notice.stringValue = "Display settings unavailable." }
  }
  @objc func markSelected() { guard currentMode == .nativeReflow else { return }; onMarkReview?() }
  @objc func undoReviewExplicitly() { onUndoReview?() }
  @objc func clearReviewExplicitly() { onClearReview?() }
  @objc func savedDocumentSelected() { updateOfflineControls() }
  @objc func exportPDFExplicitly() { if !fixtureMode { onExportPDF?() } }
  @objc func saveOfflineExplicitly() { onSaveOffline?() }
  @objc func refreshSavedExplicitly() { onListOffline?() }
  @objc func openSavedExplicitly() { let i = savedDocuments.indexOfSelectedItem; guard savedEntries.indices.contains(i) else { return }; onOpenOffline?(savedEntries[i].identity) }
  @objc func cancelStorageExplicitly() { onCancelStorage?() }
  @objc func recoveredDraftSelected() {
    let i = recoveredDraftPicker.indexOfSelectedItem
    guard recoveredDrafts.indices.contains(i) else { recoveredDraftText.stringValue = ""; return }
    let draft = recoveredDrafts[i]
    recoveredDraftText.stringValue = draft.text + (draft.pendingMessageID == nil ? "" : "\nPrevious Send is unconfirmed. Reconnect and refresh its conversation before an explicit retry.")
  }
  @objc func lastEdit() { onLastEdit?() }
  @objc func locateSelected() { guard currentMode == .nativeReflow else { return }; _ = reader.requestSource(.locate) }
  @objc func editorReceipt() { guard currentMode == .nativeReflow else { return }; onEditorReceipt?() }
  @objc func account() { onAccount?() }
  @objc func manageAccountExplicitly() { if let homepage { onManageAccount?(homepage) } }
  func windowDidResize(_ notification: Notification) { onCapsuleLayout?() }
  func windowWillClose(_ notification: Notification) { cancelFind(); hideCapsule(); onClose?() }
}

/// Size the tools from their wrapping rows without binding the document origin
/// to the clip view's changing bounds. Scrolling can then reveal every last row.
@MainActor private final class NativeReaderToolsScrollView: NSScrollView {
  override func layout() {
    super.layout()
    guard let document = documentView as? NSStackView else { return }
    document.setFrameSize(NSSize(width: contentSize.width, height: document.fittingSize.height))
    document.layoutSubtreeIfNeeded()
    document.setFrameSize(NSSize(width: contentSize.width, height: document.fittingSize.height))
    document.setFrameOrigin(.zero)
  }
}

/// The scroll viewport supplies width; the document view supplies page size.
/// Resizing a zoomed document must not recursively change its own fit width.
@MainActor private final class NativeReaderPageScrollView: NSScrollView {
  override func layout() {
    super.layout()
    (documentView as? NativeReaderOriginalPageView)?.resizeViewport(contentSize)
  }
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
