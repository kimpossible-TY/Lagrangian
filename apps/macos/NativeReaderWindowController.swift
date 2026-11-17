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
  var choosePDFDestination: (NSWindow) async -> URL? = { window in
    await withCheckedContinuation { continuation in
      let panel = NSSavePanel(); panel.allowedContentTypes = [.pdf]; panel.nameFieldStringValue = "Document.pdf"
      panel.beginSheetModal(for: window) { response in continuation.resume(returning: response == .OK ? panel.url : nil) }
    }
  }
  private var chatContext: NativeReaderRequestContext?
  private(set) var chatView: NativeReaderChatView?
  lazy var hostWindow = NativeReaderHostWindow(reader: textView, show: show, avoidActivation: avoidActivation)

  init(provider: NativeReaderDocumentProviding, target: @escaping Target,
       assets: @escaping Assets = { document, _ in
         guard document.assets.isEmpty else { throw NativeObjectError.unsupported("asset-provider-unavailable") }
         return [:]
       }, runtime: NativeReaderRuntime? = nil,
       actions: (() async throws -> NativeReaderActions)? = nil,
       originalPages: ((NativeReaderRequestContext) async throws -> NativeOriginalPageDelivery)? = nil,
       invalidate: @escaping () async -> Void = {}, show: Bool = true, avoidActivation: Bool = false,
       offlineStorage: NativeReaderOfflineStorage? = nil) {
    self.provider = provider; self.target = target; self.assets = assets; self.runtime = runtime
    self.actions = actions; self.invalidate = invalidate; self.show = show; self.avoidActivation = avoidActivation
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
    textView.cachedObject = { [weak self] node, key in
      guard let cache = self?.cache, cache.key == key else { return nil }
      return cache.objects[node.id]
    }
    textView.callbacks.selectionChanged = { [weak self] selection in
      guard let self, self.visibleMode == .nativeReflow, let selection else { return }
      do { try self.session.hold(selection) } catch { self.report(error) }
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
    originalPageView.onHold = { [weak self] in self?.session.holdOriginalPageSelection($0) }
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
    guard !disposed, !session.hasSelection else { throw NativeOriginalPageError.heldSelection }
    guard self.mode != mode else { return }
    guard !session.hasRecoveryCopy else { throw NativeReaderOperationFailure.unavailable }
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
    guard let draft = chatView?.recoveryDraft, let identity = chatContext?.target else { return }
    if currentDraftIdentity != identity { currentDrafts.removeAll(); currentDraftIdentity = identity }
    currentDrafts[draft.conversationID] = draft
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
    guard !disposed, !requestTicket.isCancelled, visibleMode == .originalPages,
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
        let job = Task.detached(priority: .userInitiated) {
          try NativeReaderRecoveryStore.stageOriginalPDF(captured.1, document: captured.0, to: destination)
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
      } catch { if !Task.isCancelled { self.report(error) } }
    }
  }

  private func sessionChanged() {
    guard !disposed, !requestTicket.isCancelled else { return }
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
  }

  private func selectionChanged(_ selection: NativeReaderSelection?, context: NativeReaderRequestContext) {
    guard visibleMode == .nativeReflow else { return }
    let previous = selectionTask
    previous?.cancel()
    guard !session.isReadOnly, let actions else { return }
    selectionTask = Task {
      await previous?.value
      do { try Task.checkCancellation(); let owner = try await actions(); try Task.checkCancellation(); try await owner.updateSelection(selection, context: context) }
      catch { if !Task.isCancelled { report(error) } }
    }
  }
  private func source(_ request: NativeReaderSourceRequest) {
    guard visibleMode == .nativeReflow else { report(NativeOriginalPageError.unsupported("pdf-source-actions-unavailable")); return }
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
        let accepted = textView.acceptSourceResult(result, for: request)
        if accepted, request.action == .locate {
          if let anchor = result.destinationAnchor { _ = textView.navigate(toAnchor: anchor) }
          hostWindow.notice.stringValue = "Source location verified. Opening the editor is not available through this connection."
        }
      } catch { if !Task.isCancelled { report(error) } }
    }
  }
  private func chat(_ command: NativeReaderChatCommand, context: NativeReaderRequestContext) {
    guard visibleMode == .nativeReflow else { report(NativeOriginalPageError.unsupported("pdf-source-actions-unavailable")); return }
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

  /// Compose an existing owner's accepted conversation; no Send/account action is implicit.
  @discardableResult func presentChat(_ conversation: NativeReaderConversation, actions: NativeReaderActions,
                                      context: NativeReaderRequestContext) throws -> NativeReaderChatView {
    try session.authorize(context)
    guard let key = acceptedPaintKey, key.identity == context.target, key.documentGeneration == context.generation else { throw NativeObjectError.stale }
    rememberCurrentDraft()
    chatView?.dispose(); chatView?.removeFromSuperview()
    if currentDraftIdentity != context.target { currentDrafts.removeAll(); currentDraftIdentity = context.target }
    let chat = NativeReaderChatView(actions: actions, context: context, authorize: { [weak self] in
      guard let self else { throw NativeReaderContractError.disposed }; try self.session.authorize(context)
    })
    configureChatMath(chat, key: key)
    chat.openHomepage = { [weak self] in self?.openHomepage?($0) }
    let id = conversation.state.conversationID
    let recovered = currentDrafts[id] ?? (recoveredDraftIdentity == context.target ? recoveredDrafts.first { $0.conversationID == id } : nil)
    recoveredDrafts.removeAll { $0.conversationID == id } // Initial recovery is consumed, never a live authority.
    chatView = chat; chatContext = context
    chat.persistDraft = { [weak self, weak chat] draft in
      guard let self, let chat, self.chatView === chat, self.chatContext == context,
            self.currentDraftIdentity == context.target, !self.disposed else { return }
      self.currentDrafts[draft.conversationID] = draft
    }
    chat.present(conversation, recovered: recovered); hostWindow.attachChat(chat)
    return chat
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
    if let selection = store.selection { textView.releaseSelection(ticket: selection.ticket) }
    textView.cancel()
  }

  func cancel() {
    cancelStorage(); pendingPresentation = nil; localReview.clear()
    preparingKey = nil
    originalPageView.cancel()
    reflowTask?.cancel(); reflowTask = nil
    requestTicket.cancel(); progress = nil; acceptedPaintKey = nil; paintedKey = nil
    selectionTask?.cancel(); selectionTask = nil
    actionTasks.values.forEach { $0.cancel() }; actionTasks.removeAll()
    chatView?.dispose(); session.cancel()
  }
  func dispose() {
    if let observer = layoutObserver { NotificationCenter.default.removeObserver(observer); layoutObserver = nil }
    cancel(); disposed = true; acceptedPageDelivery = nil; acceptedAssets = nil; session.event(.dispose); originalPageView.dispose(); textView.dispose(); hostWindow.window?.close() }
}

@MainActor final class NativeReaderHostWindow: NSWindowController, NSWindowDelegate {
  let reader: NativeReaderTextView
  let notice = NSTextField(wrappingLabelWithString: "Native Reader · reflow / original PDF; source actions require reflow")
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
  var onAccount: (() -> Void)?
  var onManageAccount: ((URL) -> Void)?
  let contents = NSPopUpButton()
  let theme = NSPopUpButton()
  let textSize = NSPopUpButton()
  private let applyDisplay = NSButton(title: "Apply Display", target: nil, action: nil)
  private let cancelDisplay = NSButton(title: "Cancel Display", target: nil, action: nil)
  private var displayPreview: (document: NativeReaderDocument?, appearance: NativeReaderTextAppearance, theme: Int, windowAppearance: NSAppearance?, anchor: NativeReaderViewportAnchor?)?
  private var pendingDisplayViewport: (NativeReaderDocument?, NativeReaderViewportAnchor, NativeReaderTextAppearance)?
  private var committedTheme = 0
  private var appearanceObservation: NSKeyValueObservation?

  let savedDocuments = NSPopUpButton()
  private let back = NSButton(title: "Back", target: nil, action: nil)
  private let undoReview = NSButton(title: "Undo review", target: nil, action: nil)
  private let clearReview = NSButton(title: "Clear review", target: nil, action: nil)
  private let exportPDF = NSButton(title: "Export PDF", target: nil, action: nil)
  private let saveOffline = NSButton(title: "Save Offline", target: nil, action: nil)
  private let refreshSaved = NSButton(title: "Refresh Saved", target: nil, action: nil)
  private let openSaved = NSButton(title: "Open Saved", target: nil, action: nil)
  private let cancelStorage = NSButton(title: "Cancel", target: nil, action: nil)
  private let manageAccount = NSButton(title: "Manage Account", target: nil, action: nil)
  private let accountStatus = NSTextField(labelWithString: "Account")
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
  private let findField = NSSearchField()
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
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 720),
      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.delegate = self; window.title = "Lagrangian · Native Reader"
    stack.orientation = .vertical; stack.alignment = .width
    let controls = NSStackView()
    for (title, action) in [("Copy", #selector(copySelected)), ("Source", #selector(sourceSelected)),
                             ("Highlight", #selector(highlightSelected)), ("Ask", #selector(askSelected)),
                             ("Locate Source", #selector(locateSelected)), ("Last Edit", #selector(lastEdit)), ("Account", #selector(account))] {
      let button = NSButton(title: title, target: self, action: action)
      controls.addArrangedSubview(button)
      if title != "Copy" { liveButtons.append(button) }
    }
    sourceControls.addArrangedSubview(controls)
    let paging = NSStackView()
    for (title, action) in [("Reflow", #selector(reflowMode)), ("Original PDF", #selector(pageMode)),
                            ("Previous", #selector(previousPage)), ("Next", #selector(nextPage)),
                            ("Zoom +", #selector(zoomIn)), ("Zoom −", #selector(zoomOut)), ("Fit", #selector(fitPage)),
                            ("Release selection", #selector(releasePageSelection)), ("Copy PDF", #selector(copySelected))] {
      paging.addArrangedSubview(NSButton(title: title, target: self, action: action))
    }
    findField.placeholderString = "Find in PDF"; findField.target = self; findField.action = #selector(findPage)
    stack.addArrangedSubview(notice); stack.addArrangedSubview(sourceControls); stack.addArrangedSubview(paging)
    contents.setAccessibilityLabel("Contents"); contents.target = self; contents.action = #selector(outlineSelected)
    back.target = self; back.action = #selector(returnFromReference)
    let navigation = NSStackView(views: [NSTextField(labelWithString: "Contents"), contents, back])
    theme.addItems(withTitles: ["Light", "Dark", "Automatic"]); theme.setAccessibilityLabel("Theme")
    theme.target = self; theme.action = #selector(appearanceChanged)
    textSize.addItems(withTitles: ["12", "14", "16", "18", "24", "32"]); textSize.selectItem(withTitle: "14"); textSize.setAccessibilityLabel("Text size")
    textSize.target = self; textSize.action = #selector(appearanceChanged)
    let preview = NSButton(title: "Preview Display", target: self, action: #selector(previewDisplayExplicitly))
    applyDisplay.target = self; applyDisplay.action = #selector(applyDisplayExplicitly)
    cancelDisplay.target = self; cancelDisplay.action = #selector(cancelDisplayExplicitly)
    applyDisplay.isEnabled = false; cancelDisplay.isEnabled = false
    let appearance = NSStackView(views: [NSTextField(labelWithString: "Theme"), theme, NSTextField(labelWithString: "Text size"), textSize, preview, applyDisplay, cancelDisplay])
    let mark = NSButton(title: "Mark for review", target: self, action: #selector(markSelected))
    undoReview.target = self; undoReview.action = #selector(undoReviewExplicitly)
    clearReview.target = self; clearReview.action = #selector(clearReviewExplicitly)
    let review = NSStackView(views: [mark, undoReview, clearReview])
    undoReview.isEnabled = false; clearReview.isEnabled = false
    reflowRows = [navigation, appearance, review]
    for row in reflowRows { stack.addArrangedSubview(row) }
    savedDocuments.setAccessibilityLabel("Saved documents"); savedDocuments.target = self; savedDocuments.action = #selector(savedDocumentSelected)
    exportPDF.target = self; exportPDF.action = #selector(exportPDFExplicitly)
    saveOffline.target = self; saveOffline.action = #selector(saveOfflineExplicitly)
    refreshSaved.target = self; refreshSaved.action = #selector(refreshSavedExplicitly)
    openSaved.target = self; openSaved.action = #selector(openSavedExplicitly)
    cancelStorage.target = self; cancelStorage.action = #selector(cancelStorageExplicitly)
    stack.addArrangedSubview(NSStackView(views: [saveOffline, savedDocuments, refreshSaved, openSaved, cancelStorage, exportPDF]))
    manageAccount.target = self; manageAccount.action = #selector(manageAccountExplicitly); manageAccount.isEnabled = false
    stack.addArrangedSubview(NSStackView(views: [accountStatus, manageAccount]))
    recoveredDraftRow.orientation = .vertical; recoveredDraftRow.alignment = .leading
    recoveredDraftPicker.setAccessibilityLabel("Recovered drafts"); recoveredDraftPicker.target = self; recoveredDraftPicker.action = #selector(recoveredDraftSelected)
    recoveredDraftRow.addArrangedSubview(recoveredDraftPicker); recoveredDraftRow.addArrangedSubview(recoveredDraftText); recoveredDraftRow.isHidden = true
    stack.addArrangedSubview(recoveredDraftRow)
    stack.addArrangedSubview(findField); stack.addArrangedSubview(reader)
    updateOfflineControls(); updateNavigation()
    stack.translatesAutoresizingMaskIntoConstraints = false; window.contentView!.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 16),
      stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -16),
      stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 16),
      stack.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor, constant: -16),
      reader.heightAnchor.constraint(greaterThanOrEqualToConstant: 220)])
    self.window = window
    appearanceObservation = window.observe(\.effectiveAppearance, options: []) { [weak self] _, _ in
      Task { @MainActor in self?.automaticAppearanceChanged() }
    }
  }
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
    scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true; scroll.autohidesScrollers = true
    scroll.documentView = view; originalScroll = scroll
    view.isHidden = true; scroll.isHidden = true; stack.addArrangedSubview(scroll)
    scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
  }
  func displayMode(_ mode: NativeReaderWindowController.Mode) {
    currentMode = mode; reader.isHidden = mode == .originalPages; original?.isHidden = mode != .originalPages
    // Source/Highlight/Ask cannot dispatch the retained hidden reflow selection.
    originalScroll?.isHidden = mode != .originalPages
    sourceControls.isHidden = mode == .originalPages
    for row in reflowRows { row.isHidden = mode != .nativeReflow }
    recoveredDraftRow.isHidden = recoveredDrafts.isEmpty
    window?.contentView?.layoutSubtreeIfNeeded()
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
    if currentMode == .originalPages { original?.releaseSelection() }
    else if let selected = reader.store.selection { reader.releaseSelection(ticket: selected.ticket) }
  }
  private func pageAction(_ action: () throws -> Void) {
    guard currentMode == .originalPages else { return }
    do { try action() } catch { notice.stringValue = String(describing: error) }
  }
  @objc func findPage() {
    guard currentMode == .originalPages, let original else { return }
    let query = findField.stringValue
    Task { do { if let hit = try await original.search(query).first { guard self.currentMode == .originalPages, !original.isHidden else { return }; try original.jump(to: hit.pageIndex); try await original.select(page: hit.pageIndex, range: hit.rangeUTF16) } }
      catch { notice.stringValue = String(describing: error) } }
  }
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
    updateNavigation()
  }
  func updateNavigation() { contents.isEnabled = currentMode == .nativeReflow && !reader.outline.isEmpty; back.isEnabled = reader.canReturnFromReference }
  func updateReaderControls(readOnly: Bool) {
    for button in liveButtons { button.isEnabled = !readOnly && currentMode == .nativeReflow }
    if readOnly { homepage = nil; manageAccount.isEnabled = false; accountStatus.stringValue = "Offline · account actions unavailable" }
    updateNavigation(); updateOfflineControls()
  }
  private func updateOfflineControls() {
    let prepared = reader.store.document != nil && (currentMode == .originalPages || (reader.renderKey != nil && reader.renderKey == reader.requestedRenderKey))
    saveOffline.isEnabled = storageAvailable && !storageBusy && prepared
    refreshSaved.isEnabled = storageAvailable && !storageBusy
    openSaved.isEnabled = storageAvailable && !storageBusy && !savedEntries.isEmpty
    savedDocuments.isEnabled = !storageBusy && !savedEntries.isEmpty
    cancelStorage.isEnabled = storageBusy || exportBusy
    exportPDF.isEnabled = currentMode == .originalPages && original?.store.accepted != nil && !exportBusy
    if exportBusy { saveOffline.isEnabled = false; openSaved.isEnabled = false; refreshSaved.isEnabled = false }
  }
  func refreshLocalControls() {
    updateOfflineControls()
    if let preview = displayPreview, preview.document != reader.store.document { displayPreview = nil; cancelDisplay.isEnabled = false }
    applyDisplay.isEnabled = displayPreview != nil && reader.renderKey != nil && reader.renderKey == reader.requestedRenderKey
    if let pending = pendingDisplayViewport, pending.0 == reader.store.document,
       reader.textAppearance == pending.2, reader.renderKey == reader.requestedRenderKey {
      reader.restoreViewport(pending.1); pendingDisplayViewport = nil
    }
  }
  func setSavedDocuments(_ entries: [NativeReaderRecoveryStore.Entry]) {
    savedEntries = entries; savedDocuments.removeAllItems(); savedDocuments.addItems(withTitles: entries.map(\.title)); updateOfflineControls()
  }
  func presentRecoveredDrafts(_ values: [NativeReaderRecoveredDraft]) {
    recoveredDrafts = values; recoveredDraftPicker.removeAllItems()
    for (index, _) in values.enumerated() { recoveredDraftPicker.addItem(withTitle: "Saved draft \(index+1)") }
    recoveredDraftRow.isHidden = values.isEmpty; recoveredDraftSelected()
  }
  func presentAccount(_ state: NativeReaderAccountState) {
    accountStatus.stringValue = state.signedIn ? (state.planEnabled ? "Account connected" : "Plan unavailable") : "Sign in on the configured Homepage."
    homepage = state.homepage; manageAccount.isEnabled = state.homepage != nil
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
    guard currentMode == .nativeReflow, theme.titleOfSelectedItem == "Automatic", let window else { return }
    var value = reader.textAppearance
    value.theme = window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
    guard value != reader.textAppearance else { return }
    do { try reader.setAppearance(value); onAppearance?() } catch { notice.stringValue = "Display settings unavailable." }
  }
  @objc func appearanceChanged() {
    guard currentMode == .nativeReflow else { return }
    beginDisplayPreview()
    var value = reader.textAppearance
    // The concrete render key always contains resolved colors, while Automatic
    // inherits only this window's effective appearance (never changes the OS).
    switch theme.titleOfSelectedItem {
    case "Dark": window?.appearance = NSAppearance(named: .darkAqua); value.theme = .dark
    case "Automatic": window?.appearance = nil; value.theme = window?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
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
  @objc func exportPDFExplicitly() { onExportPDF?() }
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
  @objc func account() { onAccount?() }
  @objc func manageAccountExplicitly() { if let homepage { onManageAccount?(homepage) } }
  func windowWillClose(_ notification: Notification) { onClose?() }
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
