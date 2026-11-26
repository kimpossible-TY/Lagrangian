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
  let layoutCache: NativeReaderLayoutCache?
  let save: (NativeReaderRecoverySnapshot) async throws -> Void
  let list: () async throws -> [NativeReaderRecoveryStore.Entry]
  let load: (NativeDocumentIdentity) async throws -> NativeReaderRecoverySnapshot
  init(owner: NativeReaderRecoveryStore) {
    layoutCache = NativeReaderLayoutCache(root: owner.root.deletingLastPathComponent().appendingPathComponent("layout-cache", isDirectory: true))
    save = { try await owner.save($0) }; list = { try await owner.list() }
    load = { try await owner.load(identity: $0) }
  }
  init(save: @escaping (NativeReaderRecoverySnapshot) async throws -> Void,
       list: @escaping () async throws -> [NativeReaderRecoveryStore.Entry],
       load: @escaping (NativeDocumentIdentity) async throws -> NativeReaderRecoverySnapshot) {
    self.layoutCache = nil
    self.save = save; self.list = list; self.load = load
  }
}

/// An offline library has no live document operation. It cannot impersonate a
/// managed attachment or acquire source/chat authority.
struct NativeReaderOfflineProvider: NativeReaderDocumentProviding {
  func document(for context: NativeReaderRequestContext) async throws -> NativeReaderDocument { throw NativeReaderOperationFailure.unavailable }
}

@MainActor private final class CrossProjectPopoverDelegate: NSObject, NSPopoverDelegate {
  var didClose: ((NSPopover) -> Void)?
  func popoverDidClose(_ notification: Notification) {
    if let popover = notification.object as? NSPopover { didClose?(popover) }
  }
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
  private let layoutCache: NativeReaderLayoutCache?
  private let viewedLayouts = NativeReaderViewedLayouts()
  private var cachedWindow: NativeReaderLayoutSnapshot?
  private var layoutOpenTask: Task<Void, Never>?
  private var versionTask: Task<NativeDocumentIdentity, Error>?
  private(set) var layoutPersistenceTask: Task<Void, Never>?
  private var persistedLayoutKey: NativeReaderLayoutCacheKey?
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
  var crossProjectCatalogProvider: (() -> CrossProjectCatalog?)?
  var crossProjectSnippetLoader: ((CrossProjectTarget) async -> CrossProjectPreviewContent?)?
  var onOpenCrossProjectTarget: ((CrossProjectPreviewContent, CrossProjectNavigationEntry) -> Void)?
  var canReturnFromCrossProject: (() -> Bool)? {
    didSet { hostWindow.canReturnFromCrossProject = canReturnFromCrossProject; hostWindow.updateNavigation() }
  }
  var onReturnFromCrossProject: (() -> Bool)? {
    didSet { hostWindow.onReturnFromCrossProject = onReturnFromCrossProject }
  }
  var pendingCrossProjectTarget: CrossProjectNavigationEntry?
  private(set) var activeCrossProjectPreviewView: NativeCrossProjectPreviewView?
  private var crossProjectPreviewTask: Task<Void, Never>?
  private var crossProjectPreviewPopover: NSPopover?
  private let crossProjectPopoverDelegate = CrossProjectPopoverDelegate()
  private var crossProjectPreviewSerial = 0
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
       offlineStorage: NativeReaderOfflineStorage? = nil, layoutCache: NativeReaderLayoutCache? = nil) {
    self.provider = provider; self.target = target; self.assets = assets; self.runtime = runtime
    self.actions = actions; self.invalidate = invalidate; self.show = show; self.avoidActivation = avoidActivation
    if let managed = provider as? NativeReaderManagedClient {
      revokeEditorConsent = { await managed.revokeEditorConsent() }
    } else { revokeEditorConsent = {} }
    self.fixtureMode = fixtureMode
    self.offlineStorage = offlineStorage
    self.layoutCache = layoutCache ?? offlineStorage?.layoutCache
    self.pageProvider = originalPages
    if self.pageProvider == nil, let managed = provider as? NativeReaderManagedClient {
      self.pageProvider = { try await managed.originalPages(for: $0) }
    }
    session = NativeReaderSession(store: store, provider: provider, target: { [weak self] in
      guard let self, let profile = self.profile else { throw NativeReaderOperationFailure.unavailable }
      if let version = self.versionTask {
        let ticket = self.requestTicket
        defer { if self.requestTicket === ticket { self.versionTask = nil } }
        let identity = try await version.value
        try Task.checkCancellation()
        if let cached = self.cachedWindow, cached.key.documentID != identity.documentID || cached.key.revision != identity.revision {
          self.layoutPersistenceTask?.cancel()
          try? await self.layoutCache?.invalidate(ownerID: cached.ownerID, key: cached.key)
        }
        return identity
      }
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
      self.hostWindow.cancelFind()
      if self.storageIsOpening { self.cancelStorage() } else { self.session.cancel() }
      self.hostWindow.setNotice("복원을 취소했습니다. 저장 목록에서 문서를 다시 열 수 있습니다.")
    }
    hostWindow.capsule.onAction = { [weak self] in self?.capsuleAction($0, $1) }
    hostWindow.capsule.onDismiss = { [weak self] binding in
      guard let self, self.hostWindow.capsule.binding == binding else { return }
      if binding.originalPDF, self.originalPageView.store.selection?.0 == self.hostWindow.currentSearchSelectionTicket {
        self.originalPageView.releaseSelection()
        self.hostWindow.clearSearchSelectionTicket()
      }
      self.dismissedCapsule = binding; self.hostWindow.hideCapsule()
    }
    hostWindow.capsule.onReleaseSelection = { [weak self] binding in
      guard let self, self.hostWindow.capsule.binding == binding, binding.originalPDF else { return }
      self.hostWindow.releasePageSelection()
    }
    hostWindow.onRetryRecovery = { [weak self] in
      guard let self, self.session.hasPendingRecovery, self.session.failure != nil else { return }
      self.hostWindow.cancelFind()
      self.session.preparationChanged()
    }
    hostWindow.capsuleFocusTarget = { [weak self] in self?.returnCapsuleFocus() }
    hostWindow.onShowCapsule = { [weak self] in self?.updateCapsule(reopen: true, focus: true) }
    hostWindow.onCapsuleLayout = { [weak self] in self?.updateCapsule() }
    hostWindow.onEditorReceipt = { [weak self] in self?.checkEditorReceipt() }
    textView.cachedObject = { [weak self] node, key in
      if let object = self?.textView.cachedLazyObject(node.id, key: key) { return object }
      guard let cache = self?.cache, Self.sameObjectGeometry(cache.key, key),
            let object = cache.objects[node.id] else { return nil }
      return cache.key == key ? object : Self.rebindObject(object, to: key)
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
    textView.callbacks.readingPositionChanged = { [weak self] in self?.persistLayoutWindow() }
    textView.callbacks.layoutChanged = { [weak self] in self?.layoutChanged() }
    textView.callbacks.statusChanged = { [weak self] message in
      guard let self else { return }
      self.diagnostic = message
      self.layoutChanged()
    }
    originalPageView.onInteraction = { [weak self] in
      self?.hostWindow.cancelFind()
      Task { @MainActor in self?.hostWindow.updatePageNavigation() }
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
      self.hostWindow.updatePageNavigation()
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
            node.kind == .link else { return }
      let safeExternalURL = node.link.flatMap { raw -> URL? in
        guard !raw.hasPrefix("#"), let url = URL(string: raw), NativeOriginalPDFAccess.safeURL(url) else { return nil }
        return url
      }
      let resolution: CrossProjectResolution
      if let meta = node.projectRef {
        resolution = self.crossProjectCatalogProvider?()?.resolve(projectKey: meta.project, label: meta.label) ?? .unresolved
      } else {
        guard let raw = node.link, safeExternalURL != nil else { return }
        resolution = self.crossProjectCatalogProvider?()?.resolve(url: raw, linkText: node.displayText) ?? .unresolved
      }
      let target: CrossProjectTarget
      switch resolution {
      case .unique(let resolved): target = resolved
      case .ambiguous: return
      case .unresolved:
        if let safeExternalURL { self.openHomepage?(safeExternalURL) }
        return
      }
      self.dismissCrossProjectPreview()
      self.crossProjectPreviewSerial += 1
      let serial = self.crossProjectPreviewSerial
      let previewView = NativeCrossProjectPreviewView(content: CrossProjectPreviewContent(
        projectKey: target.projectKey, projectTitle: target.project.title, referenceText: target.entry.text,
        label: target.label, snippetText: target.entry.text + " · p. " + String(target.entry.page), truncated: false))
      self.activeCrossProjectPreviewView = previewView
      previewView.onOpenTarget = { [weak self, weak previewView] content in
        guard let self, let previewView, self.activeCrossProjectPreviewView === previewView else { return }
        self.dismissCrossProjectPreview()
        let pos = self.textView.currentCrossProjectPosition()
        let entry = CrossProjectNavigationEntry(profileID: self.profile?.id ?? "", documentTitle: self.profile?.name ?? "",
          anchor: pos.anchor, blockID: pos.blockID, scrollOffset: pos.scrollOffset)
        if let open = self.onOpenCrossProjectTarget { open(content, entry) }
        else if let safeExternalURL { self.openHomepage?(safeExternalURL) }
      }
      if self.textView.window != nil {
        let popover = NSPopover()
        popover.behavior = .transient
        self.crossProjectPopoverDelegate.didClose = { [weak self] closed in
          guard let self, self.crossProjectPreviewPopover === closed else { return }
          self.dismissCrossProjectPreview()
        }
        popover.delegate = self.crossProjectPopoverDelegate
        let controller = NSViewController(); controller.view = previewView
        popover.contentViewController = controller
        popover.contentSize = NSSize(width: 340, height: 180)
        self.crossProjectPreviewPopover = popover
        let rect = self.textView.nodeRectInView(forNodeID: node.id)
          ?? NSRect(x: self.textView.bounds.midX, y: min(self.textView.bounds.maxY, 24), width: 1, height: 1)
        popover.show(relativeTo: rect, of: self.textView, preferredEdge: .maxY)
      }
      if let loader = self.crossProjectSnippetLoader {
        self.crossProjectPreviewTask = Task { @MainActor [weak self, weak previewView] in
          guard let loaded = await loader(target), !Task.isCancelled, let self, let previewView,
                self.crossProjectPreviewSerial == serial, self.activeCrossProjectPreviewView === previewView else { return }
          previewView.update(content: loaded)
        }
      }
    }
    hostWindow.onMarkReview = { [weak self] in self?.addReview() }
    hostWindow.onUndoReview = { [weak self] in guard let self, !self.session.isReadOnly else { return }; self.localReview.undo() }
    hostWindow.onClearReview = { [weak self] in guard let self, !self.session.isReadOnly else { return }; self.localReview.clear() }
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
    let reopening = self.profile != nil
    if reopening { cancel() } else { cancelStorage() }
    requestTicket.cancel()
    originalPageView.releaseSelection()
    if let selection = store.selection { textView.releaseSelection(ticket: selection.ticket) }
    if !reopening { originalPageView.cancel() }
    textView.cancel()
    reflowTask?.cancel(); reflowTask = nil
    selectionTask?.cancel(); selectionTask = nil
    actionTasks.values.forEach { $0.cancel() }; actionTasks.removeAll()
    pendingPresentation = nil
    preparingKey = nil
    localReview.clear()
    retainedChatPresentations.removeAll()
    retainedChatConversations.removeAll()
    self.profile = profile; self.progress = progress
    let ticket = ReadingOperationTicket(); requestTicket = ticket
    acceptedPaintKey = nil; paintedKey = nil; diagnostic = nil
    acceptedPageDelivery = nil
    mode = .nativeReflow; visibleMode = .nativeReflow
    dismissedCapsule = nil; capsuleCapabilities = nil
    recoveredDrafts.removeAll(); recoveredDraftIdentity = nil
    currentDrafts.removeAll(); currentDraftIdentity = nil
    chatView?.dispose(); chatView?.removeFromSuperview(); chatView = nil; chatContext = nil
    hostWindow.initialize()
    hostWindow.installOriginal(originalPageView)
    hostWindow.prepareForOpen()
    try? hostWindow.resolveAutomaticAppearance()
    hostWindow.changeMode = { [weak self] in
      do { try self?.setMode($0) } catch { self?.report(error) }
    }
    hostWindow.onClose = { [weak self] in
      guard let self, self.requestTicket === ticket, !ticket.isCancelled else { return }
      self.closeView()
    }
    hostWindow.storageAvailable = offlineStorage != nil
    if refresh {
      if let layoutCache {
        if session.state == .sleeping { session.event(.wake) }
        // Resolve the server version concurrently with local disk validation
        // and paint; no network result can grant the cached body authority.
        versionTask = Task { try await target(profile) }
        layoutOpenTask = Task { [weak self] in
          guard let self else { return }
          if let snapshot = try? await layoutCache.latest(ownerID: Self.cacheOwner(profile)),
             !Task.isCancelled, !ticket.isCancelled {
            do {
              self.cachedWindow = snapshot; self.persistedLayoutKey = snapshot.key
              await self.viewedLayouts.seed(snapshot)
              var appearance = self.textView.textAppearance
              appearance.zoom = CGFloat(snapshot.restoration.zoom)
              try self.textView.setAppearance(appearance)
              try await self.session.restoreLayoutWindow(snapshot) { [weak self] document, context in
                guard let self else { throw NativeObjectError.cancelled }
                return try await self.prepare(document, context: context, recoveryAssets: snapshot.assets, cached: true)
              }
            } catch { self.cachedWindow = nil }
          }
          guard !Task.isCancelled, !ticket.isCancelled else { return }
          self.session.event(.network(true))
        }
      } else {
        if session.state == .sleeping { session.event(.wake) }
        session.event(.network(true))
      }
    }
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
    switch event {
    case .sleep, .network(false):
      versionTask?.cancel(); versionTask = nil
    default: break
    }
    if case .power = event {} else { acceptedPaintKey = nil; paintedKey = nil }
    switch event {
    case .sleep: session.event(.sleep)
    case .wake: session.event(.wake)
    case .network(let online): session.event(.network(online))
    case .power(let constrained): session.event(.power(constrained: constrained))
    }
    return true
  }

  func refresh() { hostWindow.cancelFind(); acceptedPaintKey = nil; paintedKey = nil; session.refresh() }

  func prepare(_ document: NativeReaderDocument, context: NativeReaderRequestContext, reflowOnly: Bool = false, recoveryAssets: [String: Data]? = nil, recoveryPages: NativeOriginalPageRecovery? = nil, cached: Bool = false) async throws -> NativeReaderSession.PreparedAdoption {
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
    let bounded = layoutCache != nil && recoveryPages == nil && (recoveryAssets == nil || cached)
    textView.preparesViewedWindowsOnly = bounded
    let large = bounded || NativeReaderPreparedTextObject.isLarge(document)
    let diskKey = Self.layoutKey(key)
    if bounded, let previous = persistedLayoutKey, previous != diskKey, let profile {
      layoutPersistenceTask?.cancel()
      try? await layoutCache?.invalidate(ownerID: Self.cacheOwner(profile), key: previous)
    }
    if bounded { persistedLayoutKey = diskKey }
    let restored = cachedWindow?.restoration
    let retainedViewport = reflowOnly || session.isCachedCopy ? try? textView.captureViewport() : nil
    let nodes = bounded ? [] : NativeReaderPreparedTextObject.initialNodes(in: document)
    let worker: NativeMathWorker?
    if let runtime, document.blocks.flatMap(\.orderedNodes).contains(where: { $0.kind == .math }) {
      if cached { worker = try? runtime.worker() }
      else { worker = try runtime.worker() }
    } else {
      if !bounded, document.blocks.flatMap(\.orderedNodes).contains(where: { $0.kind == .math }) {
        throw NativeObjectError.unsupported("math-runtime-not-delivered")
      }
      worker = nil
    }
    preparingKey = key
    defer { if preparingKey == key { preparingKey = nil } }
    let objects: [String: NativeReaderPreparedTextObject]
    if nodes.isEmpty { objects = [:] }
    else {
      objects = try await Self.prepareObjects(document, nodes: nodes, key: key, assets: descriptors,
        worker: worker, ticket: ticket, fullDocument: !large, viewedLayouts: bounded ? viewedLayouts : nil)
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
      if !reflowOnly { self.dismissCrossProjectPreview() }
      self.acceptedAssets = (document, descriptors)
      if bounded, let offset = retainedViewport?.offset ?? restored?.offset {
        try self.textView.restoreReadingPosition(blockID: retainedViewport?.blockID ?? restored?.blockID, offset: offset)
      }
      if large {
        let layouts = bounded ? self.viewedLayouts : nil
        self.textView.configureLazyObjects(key: key, initial: preparedObjects) { nodes, currentKey in
          try await Self.prepareObjects(document, nodes: nodes, key: currentKey, assets: descriptors,
            worker: worker, ticket: ticket, viewedLayouts: layouts)
        }
        // The LRU and attachment cells are the only retained paint owners.
        self.cache = (key, [:])
      } else { self.textView.cancelLazyPreparation() }
      self.acceptedPaintKey = key; self.paintedKey = nil; self.diagnostic = nil
      if !reflowOnly {
        self.localReview.clear()
        self.visibleMode = .nativeReflow; self.hostWindow.displayMode(.nativeReflow)
        self.hostWindow.refreshOutline()
      }
      if !cached { self.cachedWindow = nil }
      self.applyPendingPresentation()
      if !reflowOnly, let target = self.pendingCrossProjectTarget {
        self.pendingCrossProjectTarget = nil
        _ = self.textView.scrollToCrossProjectLocation(anchor: target.anchor, blockID: target.blockID, scrollOffset: target.scrollOffset)
        self.hostWindow.updateNavigation()
      }
      self.hostWindow.refreshLocalControls()
      self.textView.prepareVisibleObjects()
      self.persistLayoutWindow()
      if let chat = self.chatView {
        if self.chatContext == self.textView.context { self.configureChatMath(chat, key: key) }
        else { self.rememberCurrentDraft(); chat.dispose(); chat.removeFromSuperview(); self.chatView = nil; self.chatContext = nil }
      }
    })
  }

  private nonisolated static func prepareObjects(_ document: NativeReaderDocument, nodes: [NativeReaderNode],
    key: NativeReaderTextRenderKey, assets: [String: Data], worker: NativeMathWorker?,
    ticket: ReadingOperationTicket, fullDocument: Bool = false, viewedLayouts: NativeReaderViewedLayouts? = nil) async throws -> [String: NativeReaderPreparedTextObject] {
    guard !nodes.isEmpty else { return [:] }
    let c = NativeObjectContext(identity: document.identity, snapshotGeneration: document.generation,
      generation: key.layoutGeneration, width: Double(key.width), fontSize: Double(key.appearance.effectiveSize),
      fontName: key.appearance.fontName, theme: key.appearance.theme == .dark ? .dark : .light, mode: .reflow, pageHeight: 1000)
    let job = Task.detached(priority: .userInitiated) {
      precondition(!Thread.isMainThread, "Object preparation must leave the UI thread")
      var selected = nodes
      while true {
        do {
          var mathLayouts = [String: NativeMathLayout]()
          let plan = try await NativeReaderPagedLayout.layout(document: document,
            blockIDs: Set(fullDocument ? document.blocks.map(\.id) : selected.map(\.id)), context: c, assets: assets,
            mathBatch: { items, context in
              let diskKey = Self.layoutKey(key)
              let cached = await viewedLayouts?.cached(for: diskKey) ?? [:]
              var result = [String: NativeMathLayout]()
              var missing = [(id: String, math: NativeMath, width: Double)]()
              for item in items {
                if let value = cached[item.id], let rebound = try? value.rebinding(math: item.math, context: context, width: item.width) {
                  result[item.id] = rebound
                } else { missing.append(item) }
              }
              if !missing.isEmpty {
                guard let worker else { throw NativeObjectError.unsupported("math-runtime-not-delivered") }
                result.merge(try await worker.calculateBatch(missing, context: context)) { _, new in new }
              }
              try Task.checkCancellation()
              guard !ticket.isCancelled else { throw NativeObjectError.cancelled }
              await viewedLayouts?.record(result, key: diskKey)
              mathLayouts.merge(result) { _, new in new }
              return result
            }, math: { node, width in
              guard let worker, let math = node.math else { throw NativeObjectError.unsupported("math-runtime-not-delivered") }
              let layout = try await worker.calculate(math, context: c, width: width)
              mathLayouts[node.id] = layout
              return layout
            }, cancelled: { ticket.isCancelled })
          guard plan.diagnostics.isEmpty else { throw NativeObjectError.unsupported(plan.diagnostics.joined(separator: ";")) }
          var objects = [String: NativeReaderPreparedTextObject]()
          for node in selected {
            try Task.checkCancellation()
            guard let region = plan.regions.first(where: { $0.node.id == node.id }) else { throw NativeReaderTextFailure.unsupportedObject(node.id) }
            let bounds = region.frames.reduce(CGRect.null) { $0.union($1) }
            guard !bounds.isNull, bounds.width > 0, bounds.height > 0, bounds.width <= key.width else { throw NativeObjectError.invalidGeometry }
            let ids = Set(node.orderedNodes.map(\.id))
            let cost = plan.blockCosts[node.id] ?? plan.cost
            let subplan = NativeObjectPlan(context: plan.context, items: plan.items.filter { ids.contains($0.nodeID) },
              regions: plan.regions.filter { ids.contains($0.node.id) }, size: bounds.size, pageCount: 1, diagnostics: [], cost: cost)
            var prepared = NativeReaderPreparedTextObject(key: key, size: bounds.size,
              baseline: min(bounds.height, CGFloat(c.fontSize) * 0.2),
              accessibilityLabel: NativeReaderPreparedTextObject.label(for: node), draw: { rect in
                guard let context = NSGraphicsContext.current?.cgContext else { return }
                context.saveGState(); context.clip(to: rect)
                context.translateBy(x: rect.minX - bounds.minX, y: rect.minY - bounds.minY)
                NativeReaderObjectRenderer.draw(subplan, in: context); context.restoreGState()
              }, cost: cost)
            prepared.mathLayouts = mathLayouts.filter { ids.contains($0.key) }
            prepared.hitNode = { subplan.hit(CGPoint(x: $0.x + bounds.minX, y: $0.y + bounds.minY))?.node.id }
            prepared.accessibilityLabelForNode = { id in subplan.regions.first { $0.node.id == id }.map { NativeReaderPreparedTextObject.label(for: $0.node) } }
            objects[node.id] = prepared
          }
          if !fullDocument && objects.values.reduce(0, { $0 + $1.cost }) > NativeReaderLazyObjectCache.maxCost {
            throw NativeObjectError.budget
          }
          return objects
        } catch NativeObjectError.budget where !fullDocument && selected.count > 1 {
          selected = Array(selected.prefix(max(1, selected.count / 2)))
        }
      }
    }
    return try await withTaskCancellationHandler(operation: {
      let objects = try await job.value
      try Task.checkCancellation()
      guard !ticket.isCancelled else { throw NativeObjectError.cancelled }
      return objects
    }, onCancel: { job.cancel() })
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
    textView.cancelLazyPreparation()
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
      self.dismissCrossProjectPreview()
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
    hostWindow.cancelFind()
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
        self.hostWindow.setNotice("오프라인 복사본 · 원문 및 대화 작업은 사용할 수 없습니다.")
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
    hostWindow.setNotice("오프라인으로 읽을 저장 문서를 선택하세요.")
    hostWindow.present(); refreshSavedExplicitly()
  }
  private func addReview() {
    guard !session.isReadOnly, visibleMode == .nativeReflow, let document = store.document, let selection = store.selection else {
      hostWindow.setNotice("Select text to mark for review."); return
    }
    let location = NativeReaderRestoration(blockID: selection.fragments.first?.blockID, offset: 0, zoom: 1,
      selectionTicket: selection.ticket, fragments: selection.fragments.map { .init(blockID: $0.blockID, start: $0.rangeUTF16.lowerBound, end: $0.rangeUTF16.upperBound, exact: $0.exact) })
    do { try localReview.add(.init(id: UUID(), identity: document.identity, selection: location), document: document) }
    catch { hostWindow.setNotice("Review mark unavailable. Select at most 32 blocks; your selection is retained.") }
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
          self.hostWindow.setNotice("오프라인 작업에 실패했습니다. 이전에 저장된 복사본은 그대로 유지됩니다.")
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
    catch NativeReaderTextFailure.staleGeometry { hostWindow.setNotice("문서 레이아웃을 업데이트하는 중입니다. 준비되면 다시 저장하세요."); return }
    catch { hostWindow.setNotice("현재 읽기 상태를 저장할 수 없습니다. 최대 32개 블록 이하 선택과 50%–400% 배율에서만 저장할 수 있으며 이전 복사본은 그대로 유지됩니다."); return }
    let epoch = storageEpoch + 1, ticket = requestTicket
    storageOperation { [weak self] in
      try await storage.save(snapshot); try Task.checkCancellation()
      guard let self, self.storageEpoch == epoch, self.requestTicket === ticket, !self.disposed else { return }
      self.hostWindow.setNotice("오프라인 읽기용으로 저장했습니다.")
    }
  }
  private func refreshSavedExplicitly() {
    guard let storage = offlineStorage else { return }
    let epoch = storageEpoch + 1, ticket = requestTicket
    storageOperation { [weak self] in
      let entries = try await storage.list(); try Task.checkCancellation()
      guard let self, self.storageEpoch == epoch, self.requestTicket === ticket, !self.disposed else { return }
      self.hostWindow.setSavedDocuments(entries)
      self.hostWindow.setNotice(entries.isEmpty ? "이 프로젝트에 저장된 문서가 없습니다." : "열 저장 문서를 선택하세요.")
    }
  }
  private func openSavedExplicitly(_ identity: NativeDocumentIdentity) {
    guard let storage = offlineStorage else { return }
    guard !session.hasSelection else { hostWindow.setNotice("저장 문서를 열기 전에 선택을 해제하세요."); return }
    hostWindow.cancelFind()
    let epoch = storageEpoch + 1, ticket = requestTicket
    storageOperation(opening: true) { [weak self] in
      let snapshot = try await storage.load(identity); try Task.checkCancellation()
      guard let self, self.storageEpoch == epoch, self.requestTicket === ticket, !self.disposed else { return }
      try await self.restoreRecovery(snapshot)
      guard self.storageEpoch == epoch, self.requestTicket === ticket, !Task.isCancelled else { return }
      if !self.session.hasPendingRecovery { self.hostWindow.setNotice("오프라인 복사본 · 원문 및 대화 작업은 사용할 수 없습니다.") }
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
      hostWindow.setNotice("Open a verified Original PDF before exporting."); return
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
        self.hostWindow.setNotice("Original PDF exported.")
      } catch {
        if self.exportEpoch == epoch, !Task.isCancelled, !self.disposed { self.hostWindow.setNotice("PDF export failed; the previous file is unchanged.") }
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
        guard let anchor, self.textView.navigate(toAnchor: anchor) else { self.hostWindow.setNotice("No saved edit location is available for this document."); return }
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

  private nonisolated static func cacheOwner(_ profile: Profile) -> String {
    [profile.id, profile.root, profile.entry].joined(separator: "\n")
  }
  private nonisolated static func layoutKey(_ key: NativeReaderTextRenderKey) -> NativeReaderLayoutCacheKey {
    NativeReaderLayoutCacheKey(documentID: key.identity.documentID, revision: key.identity.revision,
      width: Double(key.width), fontSize: Double(key.appearance.effectiveSize),
      fontName: key.appearance.fontName, theme: key.appearance.theme.rawValue)
  }
  /// Capture just renderer-owned viewport scalars on main. Actor work performs
  /// collection, validation, compression, hashing and disk I/O off the UI thread.
  func persistLayoutWindow(immediate: Bool = false) {
    guard let layoutCache, let profile, !disposed, visibleMode == .nativeReflow,
          !session.isReadOnly, let document = store.document, let key = textView.renderKey,
          key == textView.requestedRenderKey, acceptedPaintKey == key,
          let viewport = try? textView.captureViewport(), let acceptedAssets,
          acceptedAssets.document == document else { return }
    let restoration = NativeReaderRestoration(blockID: viewport.blockID, offset: viewport.offset,
      zoom: Double(textView.textAppearance.zoom), selectionTicket: nil, fragments: [])
    let diskKey = Self.layoutKey(key), owner = Self.cacheOwner(profile), layouts = viewedLayouts
    let bytes = acceptedAssets.bytes, windowBlocks = textView.viewedWindowBlockIDs
    let visibleMathLayouts = textView.viewedWindowMathLayouts
    layoutPersistenceTask?.cancel()
    layoutPersistenceTask = Task {
      do {
        if !immediate { try await Task.sleep(nanoseconds: 150_000_000) }
        try Task.checkCancellation()
        await layouts.record(visibleMathLayouts, key: diskKey)
        let values = await layouts.cached(for: diskKey)
        let snapshot = await Task.detached(priority: .utility) {
          let blocks = document.blocks.filter { block in
            block.id == viewport.blockID || windowBlocks.contains(block.id) || block.orderedNodes.contains { values[$0.id] != nil }
          }
          let referenced = Set(blocks.flatMap(\.orderedNodes).compactMap(\.assetID))
          return NativeReaderLayoutSnapshot(ownerID: owner, key: diskKey, document: document,
            restoration: restoration, viewedBlockIDs: Set(blocks.map(\.id)), layouts: values,
            assets: bytes.filter { referenced.contains($0.key) })
        }.value
        try Task.checkCancellation()
        try await layoutCache.save(snapshot)
      } catch { /* A disposable cache must not interrupt live reading. */ }
    }
  }

  private static func sameObjectGeometry(_ lhs: NativeReaderTextRenderKey, _ rhs: NativeReaderTextRenderKey) -> Bool {
    lhs.identity == rhs.identity &&
    lhs.documentGeneration == rhs.documentGeneration &&
    lhs.viewID == rhs.viewID &&
    lhs.width == rhs.width &&
    lhs.appearance == rhs.appearance
  }

  private static func rebindObject(_ object: NativeReaderPreparedTextObject, to key: NativeReaderTextRenderKey) -> NativeReaderPreparedTextObject {
    var rebound = NativeReaderPreparedTextObject(
      key: key,
      size: object.size,
      baseline: object.baseline,
      accessibilityLabel: object.accessibilityLabel,
      draw: object.draw
    )
    rebound.cost = object.cost
    rebound.mathLayouts = object.mathLayouts
    rebound.isPlaceholder = object.isPlaceholder
    rebound.hitNode = object.hitNode
    rebound.accessibilityLabelForNode = object.accessibilityLabelForNode
    return rebound
  }

  /// Reprepare only the latest layout key. Session retains incoming candidates;
  /// an accepted snapshot reflow never adopts/releases selection or changes service state.
  private func layoutChanged() {
    textView.invalidateStaleLazyPreparation()
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
    if !textView.preparesViewedWindowsOnly, !NativeReaderPreparedTextObject.isLarge(document), textView.renderKey == key,
       let currentCache = cache, Self.sameObjectGeometry(currentCache.key, key) {
      let rebound = currentCache.objects.mapValues { Self.rebindObject($0, to: key) }
      cache = (key, rebound)
      if acceptedPaintKey == currentCache.key {
        acceptedPaintKey = key
        paintedKey = nil
      }
      try? textView.refreshPreparedObjects(for: key)
      reflowTask?.cancel()
      reflowTask = nil
      return
    }
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
    textView.invalidateStaleLazyPreparation()
    // A failed or selection-held refresh settles on the retained render key.
    // Resume its viewport work without replacing its provider or prepared LRU.
    textView.prepareVisibleObjects()
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
    if session.isCachedCopy { hostWindow.setNotice("캐시된 화면 (읽기 전용) · 최신 버전 확인 중...") }
    else if session.state == .reading { hostWindow.setNotice(""); persistLayoutWindow() }
    if let failure = session.failure {
      let message = diagnostic ?? failure
      hostWindow.setNotice(message)
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
    if let pageError = error as? NativeOriginalPageError {
      let message = NativeReaderHostWindow.message(for: pageError, inOriginalPDF: visibleMode == .originalPages)
      diagnostic = message
      hostWindow.showActionNotice(message)
      if case .stale = pageError { hostWindow.showRetainedFailure() }
      updatePresentation()
      return
    }
    let message = NativeReaderHostWindow.message(for: error, inOriginalPDF: visibleMode == .originalPages)
    diagnostic = error is NativeObjectError ? String(describing: error) : message
    hostWindow.setNotice(message)
    updatePresentation()
  }

  private func selectionChanged(_ selection: NativeReaderSelection?, context: NativeReaderRequestContext) {
    guard visibleMode == .nativeReflow else { return }
    updateCapsule()
    hostWindow.refreshSelectionActionsAvailability()
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
    guard !session.isReadOnly else { return }
    guard visibleMode == .nativeReflow else { report(NativeOriginalPageError.unsupported("pdf-source-actions-unavailable")); return }
    guard let actions else { report(NativeReaderOperationFailure.unavailable); return }
    let selection = selectionTask
    guard actionTasks.count < 8 else { report(NativeReaderOperationFailure.unavailable); return }
    if request.action == .locate {
      guard !editorBusy else { return }
      editorBusy = true; hostWindow.setNotice("Checking the selected source and connected editor…")
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
            hostWindow.setNotice("Editor effect is unknown. Check Editor Result before requesting another move.")
            return // Preserve the original receipt, including after a second click.
          }
          editorRequest = request
          let receipt = try await owner.jump(request)
          try Task.checkCancellation()
          try session.authorize(request.context, selection: request.selection.ticket)
          hostWindow.setNotice(receipt.feedback)
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
            hostWindow.setNotice(NativeReaderEditorReceipt(context: request.context,
                selectionTicket: request.selection.ticket, receiptID: request.receiptID, status: status).feedback)
          } else { report(error) }
        }
      }
    }
  }
  private func checkEditorReceipt() {
    guard !disposed, !editorBusy, visibleMode == .nativeReflow, let request = editorRequest, let actions,
          actionTasks.count < 8 else { return }
    editorBusy = true; hostWindow.setNotice("Checking editor result…")
    let id = UUID()
    actionTasks[id] = Task {
      defer { actionTasks.removeValue(forKey: id); editorBusy = false }
      do {
        try session.authorize(request.context, selection: request.selection.ticket)
        let owner = try await actions()
        let receipt = try await owner.jump(request, query: true)
        try Task.checkCancellation(); try session.authorize(request.context, selection: request.selection.ticket)
        hostWindow.setNotice(receipt.feedback)
      } catch { if !Task.isCancelled { hostWindow.setNotice("Editor result unavailable for this selection. No move was retried.") } }
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

  private func returnCapsuleFocus() -> NSView {
    if let view = capsuleFocusReturn as? NSView, !view.isDescendant(of: hostWindow.capsule),
       view.window === hostWindow.window, !view.isHiddenOrHasHiddenAncestor {
      return view
    }
    return visibleMode == .nativeReflow ? textView.bodyTextView : originalPageView
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
      binding = .init(context: context, ticket: ticket, originalPDF: true, offlineOriginalPDF: session.hasRecoveryCopy)
      viewport = clip.convert(clip.bounds, to: root)
      rects = [originalPageView.convert(rect, to: root).intersection(viewport)].filter { !$0.isEmpty }
      for action in [NativeFloatingCapsule.Action.source, .highlight, .ask, .editor] { unavailable[action] = "원본 PDF는 복사·검색·탐색만 지원합니다." }
    } else {
      guard let selection = store.selection, let document = store.document else { hostWindow.hideCapsule(); return }
      guard textView.renderKey == textView.requestedRenderKey else { return }
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
    let summary: String
    if visibleMode == .originalPages {
      let query = hostWindow.findField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
      if originalPageView.store.selection?.0 == hostWindow.currentSearchSelectionTicket, !query.isEmpty {
        summary = "검색 적중 · ‘\(String(query.prefix(32)))’"
      } else {
        let snippet = originalPageView.selected?.displayText.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        summary = snippet.isEmpty ? "PDF에서 선택한 내용" : "PDF 선택 · ‘\(String(snippet.prefix(32)))’"
      }
    } else {
      summary = unavailable[.ask] ?? "선택한 내용 · 사용 가능한 작업만 표시합니다."
    }
    hostWindow.capsule.present(binding, unavailable: unavailable, summary: summary)
    hostWindow.placeCapsule(viewport: viewport, avoiding: rects)
    if focus {
      if let focused = hostWindow.window?.firstResponder as? NSView, !focused.isDescendant(of: hostWindow.capsule) {
        capsuleFocusReturn = focused
      }
      hostWindow.capsule.focusFirstAction()
    }
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
      if let focused = hostWindow.window?.firstResponder as? NSView, !focused.isDescendant(of: hostWindow.capsule) {
        capsuleFocusReturn = focused
      }
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
      hostWindow.window?.makeFirstResponder(chat.composer); hostWindow.hideCapsule(restoringFocus: false)
    } catch { report(error) }
  }
  private func dismissComposer(_ chat: NativeReaderChatView) {
    guard chatView === chat else { return }
    rememberCurrentDraft(); hostWindow.window?.makeFirstResponder(returnCapsuleFocus())
    chat.dispose(); chat.removeFromSuperview(); chatView = nil; chatContext = nil
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

  private func dismissCrossProjectPreview() {
    crossProjectPreviewTask?.cancel(); crossProjectPreviewTask = nil
    let popover = crossProjectPreviewPopover; crossProjectPreviewPopover = nil
    popover?.close()
    activeCrossProjectPreviewView = nil
  }

  /// Closing a view explicitly ends its selection lifetime; transport failures do not.
  private func closeView() {
    dismissCrossProjectPreview()
    guard !disposed else { return }
    originalPageView.releaseSelection()
    cancel()
    mode = .nativeReflow
    visibleMode = .nativeReflow
    acceptedPageDelivery = nil
    let revoke = revokeEditorConsent; Task { await revoke() }
    if let selection = store.selection { textView.releaseSelection(ticket: selection.ticket) }
    textView.cancel()
    hostWindow.prepareForOpen()
  }

  func cancel() {
    dismissCrossProjectPreview()
    persistLayoutWindow(immediate: true)
    layoutOpenTask?.cancel(); layoutOpenTask = nil
    versionTask?.cancel(); versionTask = nil
    textView.cancelLazyPreparation()
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
    dismissCrossProjectPreview()
    if let observer = capsuleScrollObserver { NotificationCenter.default.removeObserver(observer); capsuleScrollObserver = nil }
    if let observer = layoutObserver { NotificationCenter.default.removeObserver(observer); layoutObserver = nil }
    cancel(); disposed = true; acceptedPageDelivery = nil; acceptedAssets = nil; session.event(.dispose); originalPageView.dispose(); textView.dispose()
    let revoke = revokeEditorConsent; Task { await revoke() }
    hostWindow.window?.close() }
}

private final class NativeDesignSearchFieldCell: NSSearchFieldCell {
  private func textLineHeight() -> CGFloat {
    let activeFont = font ?? NativeAppDesign.Typography.font(.control)
    return ceil(activeFont.ascender - activeFont.descender + activeFont.leading)
  }

  private func iconSide(for bounds: NSRect) -> CGFloat {
    min(18, max(12, bounds.height - 8))
  }

  override func searchButtonRect(forBounds rect: NSRect) -> NSRect {
    let side = iconSide(for: rect)
    let x = rect.minX + 9
    let y = rect.minY + floor((rect.height - side) / 2)
    return NSRect(x: x, y: y, width: side, height: side)
  }

  override func cancelButtonRect(forBounds rect: NSRect) -> NSRect {
    let side = iconSide(for: rect)
    let x = rect.maxX - 9 - side
    let y = rect.minY + floor((rect.height - side) / 2)
    return NSRect(x: x, y: y, width: side, height: side)
  }

  override func searchTextRect(forBounds rect: NSRect) -> NSRect {
    let leftEdge = searchButtonRect(forBounds: rect).maxX + 5
    let rightEdge = cancelButtonRect(forBounds: rect).minX - 5
    let width = max(0, rightEdge - leftEdge)
    let lineHeight = min(rect.height, textLineHeight())
    let y = rect.minY + floor((rect.height - lineHeight) / 2)
    return NSRect(x: leftEdge, y: y, width: width, height: lineHeight)
  }

  private func centeredLineRect(in rect: NSRect) -> NSRect {
    let lineHeight = min(rect.height, textLineHeight())
    let y = rect.minY + floor((rect.height - lineHeight) / 2)
    return NSRect(x: rect.minX, y: y, width: rect.width, height: lineHeight)
  }

  private func isFullCellBounds(_ rect: NSRect) -> Bool {
    if let cv = controlView {
      return abs(rect.minX - cv.bounds.minX) <= 1.0
        && abs(rect.width - cv.bounds.width) <= 1.0
        && abs(rect.height - cv.bounds.height) <= 1.0
    }
    return rect.minX <= 1.0 && rect.height > textLineHeight() + 2.0
  }

  override func drawingRect(forBounds rect: NSRect) -> NSRect {
    isFullCellBounds(rect) ? searchTextRect(forBounds: rect) : centeredLineRect(in: rect)
  }

  override func titleRect(forBounds rect: NSRect) -> NSRect {
    isFullCellBounds(rect) ? searchTextRect(forBounds: rect) : centeredLineRect(in: rect)
  }

  private func positionFieldEditor(_ textObj: NSText, in controlView: NSView, cellFrame: NSRect) {
    let targetFrame = isFullCellBounds(cellFrame) ? searchTextRect(forBounds: cellFrame) : centeredLineRect(in: cellFrame)
    let textRect = NSRect(
      x: targetFrame.minX,
      y: targetFrame.minY,
      width: max(0, targetFrame.width),
      height: max(1, targetFrame.height)
    )
    guard textRect.width > 0 else { return }
    if let clipView = textObj.superview as? NSClipView, clipView.superview === controlView {
      let sameSize = abs(clipView.frame.width - textRect.width) <= 0.5 && abs(clipView.frame.height - textRect.height) <= 0.5
      let preservedX = sameSize ? clipView.bounds.origin.x : 0
      clipView.frame = textRect
      clipView.setBoundsOrigin(NSPoint(x: preservedX, y: 0))
      if let textView = textObj as? NSTextView {
        textView.minSize = textRect.size
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: textRect.height)
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = false
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: textRect.height)
      }
      let editorWidth = max(textRect.width, textObj.frame.width)
      textObj.frame = NSRect(origin: .zero, size: NSSize(width: sameSize ? editorWidth : textRect.width, height: textRect.height))
      if let textView = textObj as? NSTextView {
        let range = textView.selectedRange()
        if range.location != NSNotFound {
          textView.scrollRangeToVisible(range)
        }
      }
    } else if textObj.superview === controlView {
      textObj.frame = textRect
    }
  }

  override func edit(
    withFrame rect: NSRect,
    in controlView: NSView,
    editor textObj: NSText,
    delegate: Any?,
    event: NSEvent?
  ) {
    super.edit(withFrame: rect, in: controlView, editor: textObj, delegate: delegate, event: event)
    positionFieldEditor(textObj, in: controlView, cellFrame: rect)
  }

  override func select(
    withFrame rect: NSRect,
    in controlView: NSView,
    editor textObj: NSText,
    delegate: Any?,
    start selStart: Int,
    length selLength: Int
  ) {
    super.select(
      withFrame: rect,
      in: controlView,
      editor: textObj,
      delegate: delegate,
      start: selStart,
      length: selLength
    )
    positionFieldEditor(textObj, in: controlView, cellFrame: rect)
  }

  override func setUpFieldEditorAttributes(_ textObj: NSText) -> NSText {
    let configured = super.setUpFieldEditorAttributes(textObj)
    let inkColor: NSColor = {
      if let searchField = controlView as? NativeDesignSearchField {
        return NativeAppDesign.palette(searchField.preferences).ink
      }
      if let controlView {
        return NativeAppDesign.palette(.current(appearance: controlView.effectiveAppearance)).ink
      }
      return NativeChrome.color(\.ink)
    }()
    if let textView = configured as? NSTextView {
      textView.drawsBackground = false
      textView.backgroundColor = .clear
      textView.textColor = inkColor
      textView.insertionPointColor = inkColor
    }
    return configured
  }

  override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
    guard cellFrame.width > 0, cellFrame.height > 0 else { return }
    let searchField = controlView as? NativeDesignSearchField
    let prefs = searchField?.preferences ?? .current(appearance: controlView.effectiveAppearance)
    let palette = NativeAppDesign.palette(prefs)
    let isFocused: Bool = {
      guard let window = controlView.window, let responder = window.firstResponder else { return false }
      if responder === controlView { return true }
      if let textView = responder as? NSTextView, textView.isFieldEditor,
         (textView.delegate as? NSView) === controlView {
        return true
      }
      return false
    }()
    let lineWidth = isFocused
      ? NativeAppDesign.Shape.strongStroke
      : (prefs.increasedContrast ? NativeAppDesign.Shape.strongStroke : NativeAppDesign.Shape.stroke)
    let strokeColor = isFocused ? palette.accent : palette.boundary
    let radius = min(cellFrame.height / 2, NativeAppDesign.Shape.floatingRadius)
    let path = NSBezierPath(
      roundedRect: cellFrame.insetBy(dx: lineWidth / 2, dy: lineWidth / 2),
      xRadius: radius,
      yRadius: radius
    )
    palette.panel.setFill()
    path.fill()
    strokeColor.setStroke()
    path.lineWidth = lineWidth
    path.stroke()
    drawInterior(withFrame: cellFrame, in: controlView)
  }
}

@MainActor private final class NativeDesignSearchField: NSSearchField {
  var preferencesOverride: NativeAppDesign.Preferences? { didSet { needsDisplay = true } }
  private var observation: NativeDesignObservation?
  var preferences: NativeAppDesign.Preferences {
    preferencesOverride ?? .current(appearance: effectiveAppearance)
  }
  override init(frame: NSRect) {
    super.init(frame: frame)
    configureCell()
    observation = NativeDesignObservation(view: self)
  }
  required init?(coder: NSCoder) {
    super.init(coder: coder)
    configureCell()
    observation = NativeDesignObservation(view: self)
  }
  private func configureCell() {
    let customCell = NativeDesignSearchFieldCell(textCell: stringValue)
    customCell.bezelStyle = .roundedBezel
    customCell.isBezeled = false
    customCell.isBordered = false
    customCell.drawsBackground = false
    customCell.isEditable = true
    customCell.isSelectable = true
    customCell.isScrollable = true
    customCell.usesSingleLineMode = true
    customCell.sendsWholeSearchString = true
    customCell.sendsSearchStringImmediately = false
    customCell.sendsActionOnEndEditing = false
    cell = customCell
  }
  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    needsDisplay = true
  }
}

@MainActor final class NativeReaderToolbarView: NSView {
  var onLayoutWidth: ((CGFloat) -> Void)?
  private var lastWidth: CGFloat = 0
  override func setFrameSize(_ newSize: NSSize) {
    super.setFrameSize(newSize)
    if abs(newSize.width - lastWidth) > 0.5 {
      lastWidth = newSize.width
      onLayoutWidth?(newSize.width)
    }
  }
  override func layout() {
    onLayoutWidth?(bounds.width)
    super.layout()
  }
}

@MainActor final class NativeReaderHostWindow: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
  let reader: NativeReaderTextView
  var canReturnFromCrossProject: (() -> Bool)?
  var onReturnFromCrossProject: (() -> Bool)?
  let notice = NSTextField(wrappingLabelWithString: "원문·대화 작업은 본문 모드에서 사용할 수 있습니다.")
  var onRefresh: (() -> Void)?
  var onCancelRecovery: (() -> Void)?
  var onRetryRecovery: (() -> Void)?
  var onShowCapsule: (() -> Void)?
  var capsuleFocusTarget: (() -> NSView?)?
  var onCapsuleLayout: (() -> Void)?
  let capsule = NativeFloatingCapsule()
  private var capsuleDocked = false
  private var capsuleConstraints = [NSLayoutConstraint]()
  private var capsuleDockWindowHeightDelta: CGFloat = 0
  private var capsuleDockUserResizedHeight = false
  private var isAdjustingWindowHeightForDock = false
  private var lastObservedWindowHeight: CGFloat?
  private var overlayTopConstraint: NSLayoutConstraint?
  private var pendingRecovery = false
  private let retryRecoveryButton = NativeDesignButton(title: "복원 재시도", target: nil, action: nil)
  private let cancelRecoveryButton = NativeDesignButton(title: "복원 취소", target: nil, action: nil)
  private let releaseSelectionButton = NativeDesignButton(title: "선택 해제", target: nil, action: nil)
  private let brandMark = NativeBrandMarkView()
  private var refreshButton: NSButton?
  private var selectionActionsButton: NSButton?
  private var findButton: NativeDesignButton?
  private var aaButton: NativeDesignButton?
  private var moreButton: NativeDesignButton?
  let moreMenu = NSMenu(title: "더보기")
  private(set) var isMoreMenuOpen = false
  private(set) var isDisplayPopoverOpen = false
  private let displayPopoverHost = NSView()
  private let displayPopoverSurface = NativeDesignSurface()
  private var displayPopoverConstraints = [NSLayoutConstraint]()
  nonisolated(unsafe) private var displayPopoverMouseMonitor: Any?
  private var themeButtons = [NativeDesignButton]()
  private let decreaseFontButton = NativeDesignButton(title: "−", target: nil, action: nil)
  private let increaseFontButton = NativeDesignButton(title: "+", target: nil, action: nil)
  private let fontSizeLabel = NSTextField(labelWithString: "14pt")
  private(set) var selectedThemeIndex = 0
  let toolbarView = NativeReaderToolbarView()
  private let leftToolbarGroup = NSStackView()
  private let centerToolbarGroup = NSStackView()
  private let rightToolbarGroup = NSStackView()
  private let modeSegmentSurface = NativeDesignSurface()
  private let offlineBadgeSurface = NativeDesignSurface()
  private let offlineBadgeLabel = NSTextField(labelWithString: "오프라인 PDF")
  private let overlayStack = NSStackView()
  private let statusBanner = NativeDesignSurface()
  private let statusBannerStack = NSStackView()
  private let noticeBanner = NativeDesignSurface()
  private let modeStatus = NSTextField(wrappingLabelWithString: "현재: 본문")
  private let selectionStatus = NSTextField(wrappingLabelWithString: "문서를 준비하고 있습니다…")
  private var requestedMode: NativeReaderWindowController.Mode?
  private var allowsRefresh = true
  private var allowsModeSwitch = true
  private var isReadOnlyState = true
  private var requestWasHeld = false
  private var latestState = NativeReaderSession.State.idle
  private var failedState = false
  private var retainedFailure = false
  private var searchSelectionTicket: UUID?
  var currentSearchSelectionTicket: UUID? { searchSelectionTicket }
  func clearSearchSelectionTicket() { searchSelectionTicket = nil }
  private var isReleasingSearchSelectionForFind = false
  private var findTask: Task<Void, Never>?
  private var findGeneration = 0
  private var findFailure: String?
  private var actionFailure: String?
  private let noticeDismissButton = NativeDesignButton(title: "×", target: nil, action: nil)
  private var findExpandedAtNarrowWidth = false
  private var isNarrowToolbar = false
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
  private var appearanceObservation: NSKeyValueObservation?

  let savedDocuments = NSPopUpButton()
  private let back = NativeDesignButton(title: "돌아가기", target: nil, action: nil)
  private let exportPDF = NativeDesignButton(title: "PDF 내보내기", target: nil, action: nil)
  private let saveOffline = NativeDesignButton(title: "오프라인 저장", target: nil, action: nil)
  private let accountStatus = NSTextField(wrappingLabelWithString: "계정")
  private let recoveredDraftPicker = NSPopUpButton()
  private let recoveredDraftText = NSTextField(wrappingLabelWithString: "")
  private let recoveredDraftRow = NSStackView()
  private var savedEntries = [NativeReaderRecoveryStore.Entry]()
  private var recoveredDrafts = [NativeReaderRecoveredDraft]()
  private var homepage: URL?
  var reviewCount = 0 { didSet { rebuildMoreMenu() } }
  var exportBusy = false { didSet { updateOfflineControls() } }
  var storageAvailable = false { didSet { updateOfflineControls() } }
  var storageBusy = false { didSet { updateOfflineControls() } }
  private var original: NativeReaderOriginalPageView?
  private var originalScroll: NativeReaderPageScrollView?
  private var currentMode: NativeReaderWindowController.Mode = .nativeReflow
  private var pageNavigation: NSStackView?
  private var previousPageButton: NativeDesignButton?
  private var nextPageButton: NativeDesignButton?
  private let pageCounterLabel = NSTextField(labelWithString: "1 / 1")
  let findField: NSSearchField = NativeDesignSearchField()
  var findFieldPreferencesOverride: NativeAppDesign.Preferences? {
    get { (findField as? NativeDesignSearchField)?.preferencesOverride }
    set { (findField as? NativeDesignSearchField)?.preferencesOverride = newValue }
  }
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
  var displayPopoverContentView: NSView { displayPopoverSurface }
  override func loadWindow() {
    let window = NativeReaderEditingWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 720),
      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
    window.fixtureMode = fixtureMode
    window.minSize = NSSize(width: 520, height: 420)
    reader.bodyTextView.blocksSystemClipboard = fixtureMode; reader.bodyTextView.allowsPrivateCopy = true
    window.isReleasedWhenClosed = false; window.delegate = self; window.title = "Lagrangian · 읽기"
    NativeChrome.install(on: window)
    stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 6

    func command(_ title: String, _ action: Selector) -> NativeDesignButton {
      let button = NativeDesignButton(title: title, target: self, action: action)
      button.identifier = NSUserInterfaceItemIdentifier(NSStringFromSelector(action))
      button.setAccessibilityLabel(title)
      return button
    }

    // Unified single-row toolbar
    toolbarView.translatesAutoresizingMaskIntoConstraints = false
    stack.addArrangedSubview(toolbarView)
    toolbarView.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    toolbarView.heightAnchor.constraint(equalToConstant: 36).isActive = true

    for group in [leftToolbarGroup, centerToolbarGroup, rightToolbarGroup] {
      group.orientation = .horizontal; group.alignment = .centerY; group.spacing = 6
      group.translatesAutoresizingMaskIntoConstraints = false
      toolbarView.addSubview(group)
    }
    let centerAlign = centerToolbarGroup.centerXAnchor.constraint(equalTo: toolbarView.centerXAnchor)
    centerAlign.priority = NSLayoutConstraint.Priority(480)
    let centerMinLeading = centerToolbarGroup.leadingAnchor.constraint(greaterThanOrEqualTo: leftToolbarGroup.trailingAnchor, constant: 8)
    centerMinLeading.priority = NSLayoutConstraint.Priority(490)
    let centerMaxTrailing = centerToolbarGroup.trailingAnchor.constraint(lessThanOrEqualTo: rightToolbarGroup.leadingAnchor, constant: -8)
    centerMaxTrailing.priority = NSLayoutConstraint.Priority(490)
    NSLayoutConstraint.activate([
      leftToolbarGroup.leadingAnchor.constraint(equalTo: toolbarView.leadingAnchor),
      leftToolbarGroup.centerYAnchor.constraint(equalTo: toolbarView.centerYAnchor),
      centerAlign,
      centerToolbarGroup.centerYAnchor.constraint(equalTo: toolbarView.centerYAnchor),
      centerMinLeading,
      centerMaxTrailing,
      rightToolbarGroup.trailingAnchor.constraint(equalTo: toolbarView.trailingAnchor),
      rightToolbarGroup.centerYAnchor.constraint(equalTo: toolbarView.centerYAnchor)
    ])
    toolbarView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    leftToolbarGroup.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    centerToolbarGroup.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(495), for: .horizontal)
    rightToolbarGroup.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    brandMark.translatesAutoresizingMaskIntoConstraints = false
    brandMark.widthAnchor.constraint(equalToConstant: 26).isActive = true
    brandMark.heightAnchor.constraint(equalToConstant: 24).isActive = true

    contents.setAccessibilityLabel("목차"); contents.identifier = NSUserInterfaceItemIdentifier("contents")
    contents.target = self; contents.action = #selector(outlineSelected)
    contents.translatesAutoresizingMaskIntoConstraints = false
    contents.widthAnchor.constraint(lessThanOrEqualToConstant: 160).isActive = true
    contents.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    (contents.cell as? NSPopUpButtonCell)?.lineBreakMode = .byTruncatingTail

    offlineBadgeSurface.role = .panel
    offlineBadgeSurface.identifier = NSUserInterfaceItemIdentifier("offlinePDFBadge")
    offlineBadgeSurface.translatesAutoresizingMaskIntoConstraints = false
    offlineBadgeLabel.font = NativeAppDesign.Typography.font(.caption)
    offlineBadgeLabel.textColor = NativeChrome.color(\.ink)
    offlineBadgeLabel.setAccessibilityLabel("오프라인 PDF")
    offlineBadgeLabel.translatesAutoresizingMaskIntoConstraints = false
    offlineBadgeSurface.addSubview(offlineBadgeLabel)
    NSLayoutConstraint.activate([
      offlineBadgeLabel.leadingAnchor.constraint(equalTo: offlineBadgeSurface.leadingAnchor, constant: 10),
      offlineBadgeLabel.trailingAnchor.constraint(equalTo: offlineBadgeSurface.trailingAnchor, constant: -10),
      offlineBadgeLabel.topAnchor.constraint(equalTo: offlineBadgeSurface.topAnchor, constant: 5),
      offlineBadgeLabel.bottomAnchor.constraint(equalTo: offlineBadgeSurface.bottomAnchor, constant: -5)
    ])
    offlineBadgeSurface.isHidden = true

    let reflow = command("본문", #selector(reflowMode)), pdf = command("원본 PDF", #selector(pageMode))
    modeButtons = [reflow, pdf]
    reflow.setButtonType(.pushOnPushOff); pdf.setButtonType(.pushOnPushOff); reflow.state = .on
    modeSegmentSurface.role = .panel
    modeSegmentSurface.translatesAutoresizingMaskIntoConstraints = false
    let modeStack = NSStackView(views: [reflow, pdf])
    modeStack.orientation = .horizontal; modeStack.spacing = 2
    modeStack.translatesAutoresizingMaskIntoConstraints = false
    modeSegmentSurface.addSubview(modeStack)
    NSLayoutConstraint.activate([
      modeStack.leadingAnchor.constraint(equalTo: modeSegmentSurface.leadingAnchor, constant: 3),
      modeStack.trailingAnchor.constraint(equalTo: modeSegmentSurface.trailingAnchor, constant: -3),
      modeStack.topAnchor.constraint(equalTo: modeSegmentSurface.topAnchor, constant: 2),
      modeStack.bottomAnchor.constraint(equalTo: modeSegmentSurface.bottomAnchor, constant: -2)
    ])

    let prev = command("‹", #selector(previousPage))
    prev.identifier = NSUserInterfaceItemIdentifier("previousPage")
    prev.setAccessibilityLabel("이전 페이지")
    let next = command("›", #selector(nextPage))
    next.identifier = NSUserInterfaceItemIdentifier("nextPage")
    next.setAccessibilityLabel("다음 페이지")
    previousPageButton = prev; nextPageButton = next
    pageCounterLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
    pageCounterLabel.textColor = NativeChrome.color(\.ink)
    pageCounterLabel.alignment = .center
    pageCounterLabel.identifier = NSUserInterfaceItemIdentifier("pageCounter")
    pageCounterLabel.setAccessibilityLabel("페이지 번호")
    let nav = NSStackView(views: [prev, pageCounterLabel, next])
    nav.orientation = .horizontal; nav.alignment = .centerY; nav.spacing = 6
    nav.identifier = NSUserInterfaceItemIdentifier("pageNavigation")
    nav.isHidden = true
    pageNavigation = nav

    let find = command("🔍", #selector(triggerFind))
    find.setAccessibilityLabel("검색")
    find.keyEquivalent = "f"; find.keyEquivalentModifierMask = [.command]
    findButton = find

    let aa = command("Aa", #selector(toggleDisplayPopover))
    aa.setAccessibilityLabel("보기 설정")
    aa.setButtonType(.pushOnPushOff)
    aaButton = aa

    let more = command("•••", #selector(toggleTools))
    more.setAccessibilityLabel("더보기")
    more.keyEquivalent = "t"; more.keyEquivalentModifierMask = [.command, .option]
    moreButton = more

    findField.textColor = NativeChrome.color(\.ink)
    findField.font = NativeAppDesign.Typography.font(.control)
    findField.focusRingType = .none
    if let cell = findField.cell as? NSSearchFieldCell {
      cell.cancelButtonCell?.target = self
      cell.cancelButtonCell?.action = #selector(clearFindField)
    }
    findField.placeholderAttributedString = NSAttributedString(
      string: "PDF에서 검색",
      attributes: [.foregroundColor: NativeChrome.color(\.secondaryInk), .font: NativeAppDesign.Typography.font(.control)])
    findField.setAccessibilityLabel("PDF에서 검색")
    findField.identifier = NSUserInterfaceItemIdentifier("findPage")
    findField.target = self; findField.action = #selector(findPage)
    findField.translatesAutoresizingMaskIntoConstraints = false
    let findPreferredWidth = findField.widthAnchor.constraint(equalToConstant: 168)
    findPreferredWidth.priority = NSLayoutConstraint.Priority(470)
    let findMinWidth = findField.widthAnchor.constraint(greaterThanOrEqualToConstant: 96)
    findMinWidth.priority = NSLayoutConstraint.Priority(480)
    findPreferredWidth.isActive = true
    findMinWidth.isActive = true
    findField.heightAnchor.constraint(equalToConstant: 30).isActive = true
    findField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    findField.isHidden = true

    leftToolbarGroup.addArrangedSubview(brandMark)
    leftToolbarGroup.addArrangedSubview(contents)
    leftToolbarGroup.addArrangedSubview(offlineBadgeSurface)
    centerToolbarGroup.addArrangedSubview(modeSegmentSurface)
    centerToolbarGroup.addArrangedSubview(nav)
    rightToolbarGroup.addArrangedSubview(find)
    rightToolbarGroup.addArrangedSubview(aa)
    rightToolbarGroup.addArrangedSubview(findField)
    rightToolbarGroup.addArrangedSubview(more)
    toolbarView.onLayoutWidth = { [weak self] _ in self?.updateToolbarLayout() }

    // Hidden compatibility triggers for programmatic tests & responder chain
    let refresh = command("새로고침", #selector(refreshDocument)); refreshButton = refresh
    let selectionActions = command("선택 작업", #selector(showSelectionActions))
    selectionActions.isEnabled = false; selectionActionsButton = selectionActions
    for hidden in [refresh, selectionActions] {
      hidden.isHidden = true
      hidden.frame = NSRect(x: 0, y: 0, width: 1, height: 1)
      toolbarView.addSubview(hidden)
    }

    // Build opaque immediate Aa popover
    buildDisplayPopover()

    // Compact contextual status banner (floating overlay, hidden during normal reading)
    statusBanner.role = .floating
    statusBanner.translatesAutoresizingMaskIntoConstraints = false
    statusBannerStack.orientation = .vertical; statusBannerStack.alignment = .leading; statusBannerStack.spacing = 4
    statusBannerStack.translatesAutoresizingMaskIntoConstraints = false
    statusBanner.addSubview(statusBannerStack)
    NSLayoutConstraint.activate([
      statusBannerStack.leadingAnchor.constraint(equalTo: statusBanner.leadingAnchor, constant: 12),
      statusBannerStack.trailingAnchor.constraint(equalTo: statusBanner.trailingAnchor, constant: -12),
      statusBannerStack.topAnchor.constraint(equalTo: statusBanner.topAnchor, constant: 8),
      statusBannerStack.bottomAnchor.constraint(equalTo: statusBanner.bottomAnchor, constant: -8)
    ])
    modeStatus.identifier = NSUserInterfaceItemIdentifier("readerModeStatus")
    selectionStatus.identifier = NSUserInterfaceItemIdentifier("readerSelectionStatus")
    modeStatus.font = NativeAppDesign.Typography.font(.caption)
    selectionStatus.font = NativeAppDesign.Typography.font(.caption)
    modeStatus.setAccessibilityLabel("읽기 모드"); selectionStatus.setAccessibilityLabel("읽기 상태와 다음 동작")
    modeStatus.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    selectionStatus.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    retryRecoveryButton.target = self; retryRecoveryButton.action = #selector(retryRecovery)
    cancelRecoveryButton.target = self; cancelRecoveryButton.action = #selector(cancelRecovery)
    retryRecoveryButton.identifier = NSUserInterfaceItemIdentifier("retryRecovery")
    cancelRecoveryButton.identifier = NSUserInterfaceItemIdentifier("cancelRecovery")
    retryRecoveryButton.isHidden = true; cancelRecoveryButton.isHidden = true
    releaseSelectionButton.target = self; releaseSelectionButton.action = #selector(releasePageSelection)
    releaseSelectionButton.identifier = NSUserInterfaceItemIdentifier("releasePageSelection")
    releaseSelectionButton.setAccessibilityLabel("선택 해제")
    releaseSelectionButton.isHidden = true
    let bannerActions = NativeChromeControlRow([releaseSelectionButton, retryRecoveryButton, cancelRecoveryButton])
    recoveredDraftRow.orientation = .vertical; recoveredDraftRow.alignment = .leading
    recoveredDraftPicker.setAccessibilityLabel("복원된 초안"); recoveredDraftPicker.identifier = NSUserInterfaceItemIdentifier("recoveredDrafts")
    recoveredDraftPicker.target = self; recoveredDraftPicker.action = #selector(recoveredDraftSelected)
    recoveredDraftRow.translatesAutoresizingMaskIntoConstraints = false
    recoveredDraftText.translatesAutoresizingMaskIntoConstraints = false
    recoveredDraftRow.addArrangedSubview(recoveredDraftPicker); recoveredDraftRow.addArrangedSubview(recoveredDraftText); recoveredDraftRow.isHidden = true
    for item in [modeStatus, selectionStatus, bannerActions, recoveredDraftRow] {
      statusBannerStack.addArrangedSubview(item)
      item.translatesAutoresizingMaskIntoConstraints = false
      item.widthAnchor.constraint(equalTo: statusBannerStack.widthAnchor).isActive = true
    }
    statusBanner.isHidden = true

    noticeBanner.role = .floating
    noticeBanner.identifier = NSUserInterfaceItemIdentifier("noticeBanner")
    noticeBanner.translatesAutoresizingMaskIntoConstraints = false
    noticeBanner.isHidden = true
    notice.setAccessibilityLabel("최근 진단"); notice.font = NativeAppDesign.Typography.font(.caption)
    notice.translatesAutoresizingMaskIntoConstraints = false
    notice.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    notice.isHidden = true
    noticeDismissButton.target = self
    noticeDismissButton.action = #selector(dismissNotice)
    noticeDismissButton.identifier = NSUserInterfaceItemIdentifier("dismissNotice")
    noticeDismissButton.setAccessibilityLabel("알림 닫기")
    noticeDismissButton.toolTip = "알림 닫기"
    noticeDismissButton.font = NativeAppDesign.Typography.font(.caption)
    noticeDismissButton.translatesAutoresizingMaskIntoConstraints = false
    noticeDismissButton.setContentHuggingPriority(.required, for: .horizontal)
    noticeDismissButton.setContentCompressionResistancePriority(.required, for: .horizontal)
    noticeBanner.addSubview(notice)
    noticeBanner.addSubview(noticeDismissButton)
    NSLayoutConstraint.activate([
      notice.leadingAnchor.constraint(equalTo: noticeBanner.leadingAnchor, constant: 12),
      notice.topAnchor.constraint(greaterThanOrEqualTo: noticeBanner.topAnchor, constant: 6),
      notice.bottomAnchor.constraint(lessThanOrEqualTo: noticeBanner.bottomAnchor, constant: -6),
      notice.centerYAnchor.constraint(equalTo: noticeBanner.centerYAnchor),
      noticeDismissButton.leadingAnchor.constraint(equalTo: notice.trailingAnchor, constant: 8),
      noticeDismissButton.trailingAnchor.constraint(equalTo: noticeBanner.trailingAnchor, constant: -8),
      noticeDismissButton.topAnchor.constraint(greaterThanOrEqualTo: noticeBanner.topAnchor, constant: 4),
      noticeDismissButton.bottomAnchor.constraint(lessThanOrEqualTo: noticeBanner.bottomAnchor, constant: -4),
      noticeDismissButton.centerYAnchor.constraint(equalTo: noticeBanner.centerYAnchor)
    ])

    overlayStack.orientation = .vertical
    overlayStack.alignment = .centerX
    overlayStack.spacing = 6
    overlayStack.translatesAutoresizingMaskIntoConstraints = false
    overlayStack.addArrangedSubview(statusBanner)
    overlayStack.addArrangedSubview(noticeBanner)
    overlayStack.isHidden = true

    back.target = self; back.action = #selector(returnFromReference)
    back.identifier = NSUserInterfaceItemIdentifier("returnFromReference")
    back.setAccessibilityLabel("돌아가기")
    savedDocuments.setAccessibilityLabel("저장한 문서"); savedDocuments.identifier = NSUserInterfaceItemIdentifier("savedDocuments")
    savedDocuments.target = self; savedDocuments.action = #selector(savedDocumentSelected)
    moreMenu.autoenablesItems = false

    stack.addArrangedSubview(reader)
    updateOfflineControls(); updateNavigation(); refreshSelectionActionsAvailability(); updateAppearanceControls()
    stack.translatesAutoresizingMaskIntoConstraints = false; window.contentView!.addSubview(stack)
    window.contentView!.addSubview(overlayStack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 16),
      stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -16),
      stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 8),
      stack.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor, constant: -8),
      reader.widthAnchor.constraint(equalTo: stack.widthAnchor),
      // NativeReaderTextView reserves 42pt below its inner clip for visible status.
      reader.heightAnchor.constraint(greaterThanOrEqualToConstant: 220 + 42),
      overlayStack.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
      overlayStack.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
      statusBanner.widthAnchor.constraint(equalTo: overlayStack.widthAnchor),
      noticeBanner.leadingAnchor.constraint(greaterThanOrEqualTo: overlayStack.leadingAnchor),
      noticeBanner.trailingAnchor.constraint(lessThanOrEqualTo: overlayStack.trailingAnchor)])
    updateOverlayTopConstraint()
    // Keep initial Reflow chrome synchronized with the default "밝게" theme picker.
    window.appearance = NSAppearance(named: .aqua)
    NativeChrome.apply(to: window.contentView!)
    self.window = window
    updateDisplayPopoverAppearance()
    appearanceObservation = window.observe(\.effectiveAppearance, options: []) { [weak self] _, _ in
      Task { @MainActor in self?.automaticAppearanceChanged() }
    }
    refreshOutline()
    updateToolbarLayout()
    rebuildMoreMenu()
  }

  private func buildDisplayPopover() {
    displayPopoverHost.wantsLayer = true
    displayPopoverHost.layer?.masksToBounds = false
    displayPopoverHost.translatesAutoresizingMaskIntoConstraints = false
    let popoverShadow = NSShadow()
    popoverShadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
    popoverShadow.shadowOffset = NSSize(width: 0, height: -4)
    popoverShadow.shadowBlurRadius = 12
    displayPopoverHost.shadow = popoverShadow

    displayPopoverSurface.role = .floating
    displayPopoverSurface.identifier = NSUserInterfaceItemIdentifier("displayPopoverSurface")
    displayPopoverSurface.translatesAutoresizingMaskIntoConstraints = false
    displayPopoverSurface.wantsLayer = true
    displayPopoverSurface.setContentHuggingPriority(.defaultHigh, for: .horizontal)
    displayPopoverSurface.setContentHuggingPriority(.defaultHigh, for: .vertical)
    displayPopoverHost.addSubview(displayPopoverSurface)
    NSLayoutConstraint.activate([
      displayPopoverSurface.leadingAnchor.constraint(equalTo: displayPopoverHost.leadingAnchor),
      displayPopoverSurface.trailingAnchor.constraint(equalTo: displayPopoverHost.trailingAnchor),
      displayPopoverSurface.topAnchor.constraint(equalTo: displayPopoverHost.topAnchor),
      displayPopoverSurface.bottomAnchor.constraint(equalTo: displayPopoverHost.bottomAnchor)
    ])

    let container = NSStackView()
    container.orientation = .vertical; container.alignment = .leading; container.spacing = 10
    container.translatesAutoresizingMaskIntoConstraints = false
    container.setContentHuggingPriority(.defaultHigh, for: .horizontal)
    container.setContentHuggingPriority(.defaultHigh, for: .vertical)
    displayPopoverSurface.addSubview(container)
    NSLayoutConstraint.activate([
      container.leadingAnchor.constraint(equalTo: displayPopoverSurface.leadingAnchor, constant: 14),
      container.trailingAnchor.constraint(equalTo: displayPopoverSurface.trailingAnchor, constant: -14),
      container.topAnchor.constraint(equalTo: displayPopoverSurface.topAnchor, constant: 12),
      container.bottomAnchor.constraint(equalTo: displayPopoverSurface.bottomAnchor, constant: -12),
      container.widthAnchor.constraint(greaterThanOrEqualToConstant: 244)
    ])

    let themeTitle = NSTextField(labelWithString: "테마")
    themeTitle.font = NativeAppDesign.Typography.font(.caption)
    themeTitle.textColor = NativeChrome.color(\.secondaryInk)
    let light = NativeDesignButton(title: "밝게", target: self, action: #selector(selectLightTheme))
    light.identifier = NSUserInterfaceItemIdentifier("themeLight")
    light.setAccessibilityLabel("밝게")
    let dark = NativeDesignButton(title: "어둡게", target: self, action: #selector(selectDarkTheme))
    dark.identifier = NSUserInterfaceItemIdentifier("themeDark")
    dark.setAccessibilityLabel("어둡게")
    let auto = NativeDesignButton(title: "자동", target: self, action: #selector(selectAutomaticTheme))
    auto.identifier = NSUserInterfaceItemIdentifier("themeAutomatic")
    auto.setAccessibilityLabel("자동")
    themeButtons = [light, dark, auto]
    for b in themeButtons { b.setButtonType(.pushOnPushOff) }

    let themePill = NativeDesignSurface()
    themePill.role = .panel
    themePill.translatesAutoresizingMaskIntoConstraints = false
    let themeStack = NSStackView(views: themeButtons)
    themeStack.orientation = .horizontal; themeStack.spacing = 2; themeStack.distribution = .fillEqually
    themeStack.translatesAutoresizingMaskIntoConstraints = false
    themePill.addSubview(themeStack)
    NSLayoutConstraint.activate([
      themeStack.leadingAnchor.constraint(equalTo: themePill.leadingAnchor, constant: 3),
      themeStack.trailingAnchor.constraint(equalTo: themePill.trailingAnchor, constant: -3),
      themeStack.topAnchor.constraint(equalTo: themePill.topAnchor, constant: 2),
      themeStack.bottomAnchor.constraint(equalTo: themePill.bottomAnchor, constant: -2)
    ])

    let fontLabel = NSTextField(labelWithString: "글자 크기")
    fontLabel.font = NativeAppDesign.Typography.font(.caption)
    fontLabel.textColor = NativeChrome.color(\.secondaryInk)
    decreaseFontButton.target = self; decreaseFontButton.action = #selector(decreaseFontSize)
    decreaseFontButton.identifier = NSUserInterfaceItemIdentifier("decreaseFontSize")
    decreaseFontButton.setAccessibilityLabel("글자 작게")
    increaseFontButton.target = self; increaseFontButton.action = #selector(increaseFontSize)
    increaseFontButton.identifier = NSUserInterfaceItemIdentifier("increaseFontSize")
    increaseFontButton.setAccessibilityLabel("글자 크게")
    fontSizeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
    fontSizeLabel.textColor = NativeChrome.color(\.ink)
    fontSizeLabel.alignment = .center
    fontSizeLabel.identifier = NSUserInterfaceItemIdentifier("fontSizeLabel")
    fontSizeLabel.setAccessibilityLabel("글자 크기")
    fontSizeLabel.translatesAutoresizingMaskIntoConstraints = false
    fontSizeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true

    let fontStepper = NSStackView(views: [decreaseFontButton, fontSizeLabel, increaseFontButton])
    fontStepper.orientation = .horizontal; fontStepper.alignment = .centerY; fontStepper.spacing = 6
    let fontRow = NSStackView(views: [fontLabel, fontStepper])
    fontRow.orientation = .horizontal; fontRow.alignment = .centerY; fontRow.distribution = .equalSpacing

    let separator = NSBox()
    separator.boxType = .separator
    separator.translatesAutoresizingMaskIntoConstraints = false

    saveOffline.title = "오프라인 저장"; saveOffline.target = self; saveOffline.action = #selector(saveOfflineExplicitly)
    saveOffline.identifier = NSUserInterfaceItemIdentifier("saveOfflineExplicitly")
    saveOffline.setAccessibilityLabel("오프라인 저장")
    exportPDF.title = "PDF 내보내기"; exportPDF.target = self; exportPDF.action = #selector(exportPDFExplicitly)
    exportPDF.identifier = NSUserInterfaceItemIdentifier("exportPDFExplicitly")
    exportPDF.setAccessibilityLabel("PDF 내보내기")

    let actionsRow = NSStackView(views: [saveOffline, exportPDF])
    actionsRow.orientation = .horizontal; actionsRow.spacing = 6; actionsRow.distribution = .fillEqually

    for item in [themeTitle, themePill, fontRow, separator, actionsRow] {
      container.addArrangedSubview(item)
      item.translatesAutoresizingMaskIntoConstraints = false
      item.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true
    }

    updateDisplayPopoverAppearance()
    layoutDisplayPopoverSurface()
  }
  private func updateDisplayPopoverAppearance() {
    let prefsOverride = window.map { NativeAppDesign.Preferences.current(appearance: $0.effectiveAppearance) }
    let prefs = prefsOverride ?? displayPopoverSurface.preferences
    displayPopoverSurface.preferencesOverride = prefsOverride
    displayPopoverSurface.wantsLayer = true
    if let layer = displayPopoverSurface.layer {
      layer.cornerRadius = NativeAppDesign.Shape.floatingRadius
      layer.masksToBounds = true
      layer.borderWidth = max(1.0, prefs.increasedContrast ? NativeAppDesign.Shape.strongStroke : NativeAppDesign.Shape.stroke)
      layer.borderColor = NativeAppDesign.palette(prefs).boundary.cgColor
    }
    displayPopoverHost.layer?.masksToBounds = false
    displayPopoverSurface.needsDisplay = true
  }
  private func layoutDisplayPopoverSurface() {
    displayPopoverSurface.layoutSubtreeIfNeeded()
    let popSize = displayPopoverSurface.fittingSize
    displayPopoverHost.frame = NSRect(origin: .zero, size: popSize)
    displayPopoverHost.layoutSubtreeIfNeeded()
    if displayPopoverSurface.bounds.size != popSize {
      displayPopoverSurface.frame = NSRect(origin: .zero, size: popSize)
      displayPopoverSurface.layoutSubtreeIfNeeded()
    }
  }
  private func updateOverlayTopConstraint() {
    overlayTopConstraint?.isActive = false
    let anchor = (capsuleDocked && capsule.superview != nil && !capsule.isHidden)
      ? capsule.bottomAnchor
      : toolbarView.bottomAnchor
    let constraint = overlayStack.topAnchor.constraint(equalTo: anchor, constant: 6)
    constraint.isActive = true
    overlayTopConstraint = constraint
  }
  private func adjustWindowHeightForCapsuleDock(to targetDelta: CGFloat) {
    guard !isAdjustingWindowHeightForDock else { return }
    let delta = targetDelta - capsuleDockWindowHeightDelta
    if abs(delta) < 0.5 { return }
    guard let window, !window.styleMask.contains(.fullScreen) else { return }
    var frame = window.frame
    let currentHeight = frame.size.height
    let topY = frame.maxY
    let visible = window.screen?.visibleFrame
    var newHeight = max(window.minSize.height, currentHeight + delta)
    if let visible {
      newHeight = min(visible.height, newHeight)
    }
    if abs(newHeight - currentHeight) < 0.5 {
      if targetDelta == 0 { capsuleDockWindowHeightDelta = 0 }
      lastObservedWindowHeight = window.frame.size.height
      return
    }
    let newOriginY = visible.map { max($0.minY, min($0.maxY - newHeight, topY - newHeight)) } ?? (topY - newHeight)
    frame.origin.y = newOriginY
    frame.size.height = newHeight
    isAdjustingWindowHeightForDock = true
    defer { isAdjustingWindowHeightForDock = false }
    window.setFrame(frame, display: window.isVisible, animate: false)
    let actualDelta = window.frame.size.height - currentHeight
    capsuleDockWindowHeightDelta = targetDelta == 0 ? 0 : max(0, capsuleDockWindowHeightDelta + actualDelta)
    lastObservedWindowHeight = window.frame.size.height
  }
  func hideCapsule(restoringFocus: Bool = true) {
    if restoringFocus, let focused = window?.firstResponder as? NSView, focused.isDescendant(of: capsule) {
      window?.makeFirstResponder(capsuleFocusTarget?() ?? (currentMode == .originalPages ? original : reader.bodyTextView))
    }
    capsule.hide()
    capsuleDockUserResizedHeight = false
    if capsuleDocked {
      NSLayoutConstraint.deactivate(capsuleConstraints); capsuleConstraints = []
      stack.removeArrangedSubview(capsule); capsule.removeFromSuperview(); capsuleDocked = false
      updateOverlayTopConstraint()
      adjustWindowHeightForCapsuleDock(to: 0)
      window?.contentView?.layoutSubtreeIfNeeded()
    } else {
      adjustWindowHeightForCapsuleDock(to: 0)
    }
  }
  func placeCapsule(viewport: NSRect, avoiding rects: [NSRect]) {
    guard let root = window?.contentView else { return }
    let size = capsule.preferredSize(width: min(620, max(120, viewport.width - 16)))
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
      let dockHeight = ceil(capsule.preferredSize(width: stack.bounds.width).height)
      capsule.removeFromSuperview()
      let index = stack.arrangedSubviews.firstIndex(where: { $0 === reader }) ?? stack.arrangedSubviews.count
      stack.insertArrangedSubview(capsule, at: index); capsule.translatesAutoresizingMaskIntoConstraints = false
      capsuleConstraints = [capsule.widthAnchor.constraint(equalTo: stack.widthAnchor), capsule.heightAnchor.constraint(equalToConstant: dockHeight)]
      NSLayoutConstraint.activate(capsuleConstraints); capsuleDocked = true
      capsuleDockUserResizedHeight = false
      updateOverlayTopConstraint()
      adjustWindowHeightForCapsuleDock(to: currentMode == .nativeReflow ? dockHeight + stack.spacing : 0)
      root.layoutSubtreeIfNeeded()
    } else {
      guard stack.bounds.width.isFinite, stack.bounds.width > 0 else { return }
      let dockHeight = ceil(capsule.preferredSize(width: stack.bounds.width).height)
      capsuleConstraints.last?.constant = dockHeight
      updateOverlayTopConstraint()
      if !capsuleDockUserResizedHeight {
        adjustWindowHeightForCapsuleDock(to: currentMode == .nativeReflow ? dockHeight + stack.spacing : 0)
      }
      root.layoutSubtreeIfNeeded()
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
    chat.translatesAutoresizingMaskIntoConstraints = false
    stack.addArrangedSubview(chat)
    chat.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    // Only the explicit composer needs extra height; keep the PDF viewport's
    // ordinary initial size and native scroll behavior unchanged.
    if let window, let content = window.contentView, content.frame.height < 960 {
      window.setContentSize(NSSize(width: content.frame.width, height: 960))
    }
  }
  func installOriginal(_ view: NativeReaderOriginalPageView) {
    guard original == nil else { return }; original = view
    let scroll = NativeReaderPageScrollView()
    scroll.drawsBackground = false
    scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true; scroll.autohidesScrollers = false
    scroll.scrollerStyle = .legacy
    scroll.setAccessibilityLabel("원본 PDF · 맞춤 또는 가로 스크롤로 페이지 탐색")
    scroll.documentView = view; originalScroll = scroll
    scroll.contentView.postsBoundsChangedNotifications = true
    view.isHidden = true; scroll.isHidden = true; stack.addArrangedSubview(scroll)
    // The always-visible legacy horizontal scroller sits outside the reading clip.
    scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 220 + NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)).isActive = true
    scroll.translatesAutoresizingMaskIntoConstraints = false
    scroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
  }
  func displayMode(_ mode: NativeReaderWindowController.Mode) {
    clearNotice()
    cancelFind()
    hideCapsule()
    if mode != currentMode { closeDisplayPopover() }
    findExpandedAtNarrowWidth = false
    currentMode = mode
    syncWindowAppearance()
    retainedFailure = false
    if requestedMode == mode { requestedMode = nil; requestWasHeld = false }
    for (index, button) in modeButtons.enumerated() { button.state = (index == 0 ? mode == .nativeReflow : mode == .originalPages) ? .on : .off }
    refreshStatus()
    if mode != .nativeReflow { _ = reader.hideFindBar() }
    reader.isHidden = mode == .originalPages; original?.isHidden = mode != .originalPages
    originalScroll?.isHidden = mode != .originalPages
    updateToolbarLayout()
    updatePageNavigation()
    if let responderView = window?.firstResponder as? NSView {
      let fieldOwner = (responderView as? NSTextView).flatMap { $0.isFieldEditor ? $0.delegate as? NSView : nil }
      let inHiddenReader = reader.isHidden && responderView.isDescendant(of: reader)
      let inHiddenOriginal = (original?.isHidden == true && original.map { responderView.isDescendant(of: $0) } == true) ||
        (originalScroll?.isHidden == true && originalScroll.map { responderView.isDescendant(of: $0) } == true)
      let inHiddenFindField = findField.isHidden && (responderView.isDescendant(of: findField) || fieldOwner?.isDescendant(of: findField) == true)
      if responderView.isHiddenOrHasHiddenAncestor || fieldOwner?.isHiddenOrHasHiddenAncestor == true ||
          inHiddenReader || inHiddenOriginal || inHiddenFindField {
        window?.makeFirstResponder(nil)
      }
    }
    invalidateControlLayout()
    window?.contentView?.layoutSubtreeIfNeeded()
    rebuildMoreMenu()
  }
  func prepareForOpen() {
    cancelFind()
    hideCapsule()
    capsuleDockUserResizedHeight = false
    capsuleDockWindowHeightDelta = 0
    lastObservedWindowHeight = window?.frame.size.height
    closeDisplayPopover()
    isMoreMenuOpen = false
    findExpandedAtNarrowWidth = false
    findField.stringValue = ""
    requestedMode = nil
    requestWasHeld = false
    searchSelectionTicket = nil
    findFailure = nil
    actionFailure = nil
    retainedFailure = false
    pendingRecovery = false
    latestState = .idle
    failedState = false
    allowsRefresh = true
    allowsModeSwitch = true
    isReadOnlyState = true
    refreshButton?.isEnabled = true
    for button in modeButtons { button.isEnabled = true }
    brandMark.phase = .idle
    cancelRecoveryButton.isHidden = true
    retryRecoveryButton.isHidden = true
    homepage = nil
    accountStatus.stringValue = "계정"
    window?.title = "Lagrangian · 읽기"
    presentRecoveredDrafts([])
    displayMode(.nativeReflow)
    syncWindowAppearance()
    notice.stringValue = "원문·대화 작업은 본문 모드에서 사용할 수 있습니다."
    noticeBanner.isHidden = true
    notice.isHidden = true
    updateOverlayVisibility()
    refreshStatusBannerVisibility()
    rebuildMoreMenu()
  }

  func updateToolbarLayout(forWidth overrideWidth: CGFloat? = nil) {
    guard let findButton, let aaButton, let moreButton else { return }
    let availableWidth = overrideWidth ?? window?.contentView?.bounds.width ?? (toolbarView.bounds.width > 0 ? toolbarView.bounds.width + 32 : 980)
    let narrow = availableWidth <= 640
    let wasNarrow = isNarrowToolbar
    isNarrowToolbar = narrow

    let inPDF = currentMode == .originalPages
    let showOfflineBadge = inPDF && !allowsModeSwitch && !pendingRecovery

    // Place modeSegment centered in Reflow, or on the left in online PDF mode
    if inPDF {
      if modeSegmentSurface.superview !== leftToolbarGroup {
        modeSegmentSurface.removeFromSuperview()
        leftToolbarGroup.addArrangedSubview(modeSegmentSurface)
      }
    } else {
      if modeSegmentSurface.superview !== centerToolbarGroup {
        modeSegmentSurface.removeFromSuperview()
        centerToolbarGroup.insertArrangedSubview(modeSegmentSurface, at: 0)
      }
    }

    if brandMark.isHidden != narrow { brandMark.isHidden = narrow }
    if contents.isHidden != narrow { contents.isHidden = narrow }
    if offlineBadgeSurface.isHidden != !showOfflineBadge { offlineBadgeSurface.isHidden = !showOfflineBadge }

    let hideModeSegment = inPDF && (!allowsModeSwitch || narrow)
    if modeSegmentSurface.isHidden != hideModeSegment { modeSegmentSurface.isHidden = hideModeSegment }
    if let pageNavigation, pageNavigation.isHidden != !inPDF { pageNavigation.isHidden = !inPDF }

    let hideFindButton = inPDF || narrow
    if findButton.isHidden != hideFindButton { findButton.isHidden = hideFindButton }
    if aaButton.isHidden != inPDF { aaButton.isHidden = inPDF }

    let showFindField = inPDF && (!narrow || findExpandedAtNarrowWidth)
    if findField.isHidden != !showFindField { findField.isHidden = !showFindField }
    if moreButton.isHidden { moreButton.isHidden = false }

    if narrow != wasNarrow { rebuildMoreMenu() }
  }

  func updatePageNavigation() {
    guard let previousPageButton, let nextPageButton else { return }
    let total = original?.store.accepted?.binding.pages.count ?? 0
    let index = original?.store.pageIndex ?? 0
    if total > 0 {
      pageCounterLabel.stringValue = "\(index + 1) / \(total)"
      previousPageButton.isEnabled = index > 0
      nextPageButton.isEnabled = index + 1 < total
    } else {
      pageCounterLabel.stringValue = "0 / 0"
      previousPageButton.isEnabled = false
      nextPageButton.isEnabled = false
    }
    pageNavigation?.invalidateIntrinsicContentSize()
    pageNavigation?.needsLayout = true
  }

  @objc func toggleDisplayPopover() {
    guard currentMode == .nativeReflow, let aaButton else { return }
    if isDisplayPopoverOpen {
      closeDisplayPopover()
    } else {
      updateAppearanceControls()
      updateDisplayPopoverAppearance()
      isDisplayPopoverOpen = true
      aaButton.designRole = .primary
      aaButton.state = .on
      if let contentView = window?.contentView {
        NSLayoutConstraint.deactivate(displayPopoverConstraints)
        displayPopoverConstraints.removeAll()
        if displayPopoverHost.superview != nil {
          displayPopoverHost.removeFromSuperview()
        }
        displayPopoverHost.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(displayPopoverHost, positioned: .above, relativeTo: nil)
        let constraints = [
          displayPopoverHost.topAnchor.constraint(equalTo: toolbarView.bottomAnchor, constant: 6),
          displayPopoverHost.trailingAnchor.constraint(equalTo: toolbarView.trailingAnchor, constant: -8),
          displayPopoverHost.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 8),
          displayPopoverHost.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -8)
        ]
        NSLayoutConstraint.activate(constraints)
        displayPopoverConstraints = constraints
        contentView.layoutSubtreeIfNeeded()
        displayPopoverSurface.layoutSubtreeIfNeeded()
      } else {
        layoutDisplayPopoverSurface()
      }
      installDisplayPopoverMonitor()
    }
  }

  private func installDisplayPopoverMonitor() {
    removeDisplayPopoverMonitor()
    displayPopoverMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
      let eventWindowNumber = event.windowNumber
      let location = event.locationInWindow
      MainActor.assumeIsolated {
        guard let self, self.isDisplayPopoverOpen else { return }
        guard let targetWindow = self.window, eventWindowNumber == targetWindow.windowNumber else {
          self.closeDisplayPopover()
          return
        }
        let inPopover = self.displayPopoverHost.superview != nil &&
          self.displayPopoverHost.bounds.contains(self.displayPopoverHost.convert(location, from: nil))
        let inAAButton = self.aaButton.map { button in
          !button.isHiddenOrHasHiddenAncestor && button.bounds.contains(button.convert(location, from: nil))
        } ?? false
        if !inPopover && !inAAButton {
          self.closeDisplayPopover()
        }
      }
      return event
    }
  }

  nonisolated private func removeDisplayPopoverMonitor() {
    if let monitor = displayPopoverMouseMonitor {
      NSEvent.removeMonitor(monitor)
      displayPopoverMouseMonitor = nil
    }
  }

  private func closeDisplayPopover() {
    removeDisplayPopoverMonitor()
    let restoreFocusToAA: Bool = {
      guard let responderView = window?.firstResponder as? NSView else { return false }
      if responderView === displayPopoverHost || responderView.isDescendant(of: displayPopoverHost) {
        return true
      }
      if let textView = responderView as? NSTextView,
         let delegateView = textView.delegate as? NSView,
         delegateView.isDescendant(of: displayPopoverHost) {
        return true
      }
      return false
    }()
    NSLayoutConstraint.deactivate(displayPopoverConstraints)
    displayPopoverConstraints.removeAll()
    if displayPopoverHost.superview != nil {
      displayPopoverHost.removeFromSuperview()
    }
    if isDisplayPopoverOpen {
      isDisplayPopoverOpen = false
      aaButton?.designRole = .standard
      aaButton?.state = .off
    }
    layoutDisplayPopoverSurface()
    if restoreFocusToAA, let aaButton, !aaButton.isHiddenOrHasHiddenAncestor {
      window?.makeFirstResponder(aaButton)
    }
  }

  @objc func toggleTools() {
    guard let moreButton else { return }
    rebuildMoreMenu()
    isMoreMenuOpen.toggle()
    if isMoreMenuOpen, window?.isVisible == true {
      moreMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: moreButton.isFlipped ? moreButton.bounds.height + 4 : -4), in: moreButton)
      isMoreMenuOpen = false
    }
  }

  @objc func triggerFind() {
    if currentMode == .nativeReflow {
      _ = reader.performFindAction(.showFindInterface)
    } else {
      if isNarrowToolbar && !findExpandedAtNarrowWidth {
        findExpandedAtNarrowWidth = true
        updateToolbarLayout()
        window?.contentView?.layoutSubtreeIfNeeded()
      }
      window?.makeFirstResponder(findField)
    }
  }

  @objc func clearFindField() {
    findField.stringValue = ""
    findExpandedAtNarrowWidth = false
    if currentMode == .originalPages,
       let searchTicket = searchSelectionTicket,
       original?.store.selection?.0 == searchTicket {
      original?.releaseSelection()
      searchSelectionTicket = nil
    }
    clearNotice()
    cancelFind()
    original?.invalidateFind()
    updateToolbarLayout()
  }

  @objc func refreshDocument() { requestedMode = nil; requestWasHeld = false; cancelFind(); onRefresh?() }
  func requestMode(_ mode: NativeReaderWindowController.Mode) {
    cancelFind()
    requestedMode = mode == currentMode ? nil : mode; requestWasHeld = reader.store.selection != nil || original?.selected != nil
    refreshStatus()
  }
  func updateStatus(state: NativeReaderSession.State, failed: Bool, allowsRefresh: Bool = true, allowsModeSwitch: Bool = true, pendingRecovery: Bool = false) {
    let changed = state != latestState || failed != failedState || allowsRefresh != self.allowsRefresh ||
      allowsModeSwitch != self.allowsModeSwitch || pendingRecovery != self.pendingRecovery
    if changed { findFailure = nil; actionFailure = nil }
    self.pendingRecovery = pendingRecovery
    cancelRecoveryButton.isHidden = !pendingRecovery
    retryRecoveryButton.isHidden = !pendingRecovery || !failed
    latestState = state; failedState = failed; self.allowsRefresh = allowsRefresh; refreshButton?.isEnabled = allowsRefresh
    self.allowsModeSwitch = allowsModeSwitch
    for button in modeButtons { button.isEnabled = allowsModeSwitch }
    if !allowsModeSwitch { requestedMode = nil; requestWasHeld = false }
    brandMark.phase = failed ? .error : (state == .loading ? .busy : (state == .offline ? .offline : .idle))
    syncWindowAppearance()
    updateToolbarLayout()
    updatePageNavigation()
    refreshStatus()
  }
  func showRetainedFailure() { findFailure = nil; actionFailure = nil; retainedFailure = true; refreshStatus() }
  private var hasActiveSelectionInCurrentMode: Bool {
    guard latestState != .disposed else { return false }
    if currentMode == .originalPages {
      return original?.selected != nil && original?.store.selection != nil &&
        original?.selected?.snapshotID == original?.store.accepted?.id
    }
    return reader.store.document != nil && reader.store.selection != nil
  }
  func refreshSelectionActionsAvailability() {
    let active = hasActiveSelectionInCurrentMode
    selectionActionsButton?.isEnabled = active
    releaseSelectionButton.isEnabled = active
    refreshStatusBannerVisibility()
    rebuildMoreMenu()
  }
  private func updateOverlayVisibility() {
    overlayStack.isHidden = statusBanner.isHidden && noticeBanner.isHidden
  }
  func setNotice(_ message: String) {
    notice.stringValue = message
    let hasMessage = !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    noticeBanner.isHidden = !hasMessage
    notice.isHidden = !hasMessage
    updateOverlayVisibility()
    invalidateControlLayout(in: overlayStack)
    rebuildMoreMenu()
  }
  private func clearNotice() {
    guard !noticeBanner.isHidden || !notice.isHidden else { return }
    noticeBanner.isHidden = true
    notice.isHidden = true
    updateOverlayVisibility()
    invalidateControlLayout(in: overlayStack)
    rebuildMoreMenu()
  }
  @objc func dismissNotice() { clearNotice() }
  func showActionNotice(_ message: String) {
    actionFailure = message
    refreshStatus()
  }
  static func message(for error: Error, inOriginalPDF: Bool = true) -> String {
    if let pageError = error as? NativeOriginalPageError {
      switch pageError {
      case .heldSelection:
        return inOriginalPDF
          ? "PDF에서 선택한 내용이 있습니다. ‘선택 해제’ 후 다시 시도하세요."
          : "선택한 내용이 있습니다. ‘선택 해제’ 후 다시 시도하세요."
      case .budget:
        return "PDF 표시 한도를 넘었습니다. 더보기(•••)에서 배율을 줄인 뒤 다시 시도하세요."
      case .stale, .cancelled:
        return "페이지 상태가 변경되었습니다. 다시 시도하세요."
      case .binding, .geometry, .invalidPDF, .encrypted:
        return "원본 PDF 페이지를 표시할 수 없습니다. ‘새로고침’하거나 저장 문서를 다시 여세요."
      case .unsupported:
        return "원본 PDF에서는 이 작업을 사용할 수 없습니다."
      }
    }
    switch error {
    case NativeReaderOperationFailure.unavailable:
      return "현재 상태에서는 이 작업을 사용할 수 없습니다."
    case NativeReaderOperationFailure.unknownEffect:
      return "편집기 작업 결과를 확인하지 못했습니다. ‘편집기 결과 확인’을 누르세요."
    case NativeReaderContractError.disposed:
      return "읽기 창이 닫혔습니다."
    case NativeReaderContractError.invalidSelection:
      return "선택한 내용을 다시 지정한 뒤 시도하세요."
    case NativeReaderContractError.wrongTarget, NativeReaderContractError.staleGeneration:
      return "문서 상태가 변경되었습니다. ‘새로고침’ 후 다시 시도하세요."
    case NativeReaderTextFailure.staleGeometry:
      return "문서 레이아웃을 준비 중입니다. 잠시 후 다시 시도하세요."
    case is NativeReaderTextFailure:
      return "본문 작업을 완료할 수 없습니다. 다시 시도하세요."
    case is NativeObjectError:
      return "문서 개체를 표시할 수 없습니다. 다시 시도하세요."
    default:
      return "작업을 완료할 수 없습니다. 다시 시도하세요."
    }
  }
  private func refreshStatusBannerVisibility() {
    let showBanner = pendingRecovery || failedState || retainedFailure || requestedMode != nil ||
      findFailure != nil || actionFailure != nil || !recoveredDrafts.isEmpty || latestState == .disposed
    releaseSelectionButton.isHidden = !(requestedMode != nil && hasActiveSelectionInCurrentMode)
    if statusBanner.isHidden != !showBanner {
      statusBanner.isHidden = !showBanner
      invalidateControlLayout(in: overlayStack)
    }
    updateOverlayVisibility()
  }
  private func refreshStatus() {
    func name(_ mode: NativeReaderWindowController.Mode) -> String { mode == .nativeReflow ? "본문" : "원본 PDF" }
    for (index, button) in modeButtons.enumerated() {
      let active = index == 0 ? currentMode == .nativeReflow : currentMode == .originalPages
      button.state = active ? .on : .off
      (button as? NativeDesignButton)?.designRole = active ? .primary : .standard
    }
    let activeSelection = hasActiveSelectionInCurrentMode
    selectionActionsButton?.isEnabled = activeSelection
    releaseSelectionButton.isEnabled = activeSelection
    modeStatus.stringValue = "현재: " + name(currentMode) + (requestedMode.map { " · 전환 요청: " + name($0) } ?? "")
    let detailSuffix = [findFailure, actionFailure].compactMap { $0 }.map { " " + $0 }.joined()
    if latestState == .disposed {
      selectionStatus.stringValue = "읽기 창이 닫혀 모드를 전환할 수 없습니다."
    } else if pendingRecovery && (retainedFailure || failedState) {
      selectionStatus.stringValue = "복원하지 못했습니다. " + (reader.store.document == nil ? "" : "이전 읽기 결과를 표시 중입니다. ") + "‘복원 재시도’ 또는 ‘복원 취소’ 후 저장 문서를 다시 여세요. 원문·대화는 사용할 수 없습니다." + detailSuffix
    } else if pendingRecovery && latestState == .loading {
      selectionStatus.stringValue = "저장 문서를 복원 준비 중입니다… 이전 읽기 결과는 유지됩니다. ‘복원 취소’로 중단할 수 있습니다." + detailSuffix
    } else if retainedFailure || failedState {
      selectionStatus.stringValue = (reader.store.document == nil ? "문서를 불러오지 못했습니다. " : "이전 읽기 결과를 표시 중입니다. ") + (refreshButton?.isEnabled == true ? "최신 결과를 보려면 ‘새로고침’을 누르세요." : "저장 문서를 다시 열어 복원하세요.") + detailSuffix
    } else if let findFailure {
      selectionStatus.stringValue = findFailure
    } else if let actionFailure, requestedMode == nil {
      selectionStatus.stringValue = actionFailure
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
    refreshStatusBannerVisibility()
    rebuildMoreMenu()
  }
  @objc func reflowMode() { changeMode?(.nativeReflow) }
  @objc func pageMode() { changeMode?(.originalPages) }
  @objc func previousPage() {
    cancelFind()
    if let original {
      pageAction { try original.jump(to: max(0, original.store.pageIndex - 1)) }
      updatePageNavigation()
    }
  }
  @objc func nextPage() {
    cancelFind()
    if let original {
      let lastIndex = max(0, (original.store.accepted?.binding.pages.count ?? 1) - 1)
      pageAction { try original.jump(to: min(lastIndex, original.store.pageIndex + 1)) }
      updatePageNavigation()
    }
  }
  @objc func zoomIn() {
    cancelFind()
    if currentMode == .nativeReflow { reader.changeZoom(by: 1.25); onAppearance?(); updateAppearanceControls() }
    else if let original { pageAction { try original.zoom(original.store.displayedScale * 1.25) } }
  }
  @objc func zoomOut() {
    cancelFind()
    if currentMode == .nativeReflow { reader.changeZoom(by: 1 / 1.25); onAppearance?(); updateAppearanceControls() }
    else if let original { pageAction { try original.zoom(original.store.displayedScale / 1.25) } }
  }
  @objc func fitPage() {
    cancelFind()
    if currentMode == .nativeReflow { var value = reader.textAppearance; value.zoom = 1; try? reader.setAppearance(value); onAppearance?(); updateAppearanceControls() }
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
    let hadActionFailure = actionFailure != nil
    actionFailure = nil
    do {
      try action()
      if hadActionFailure { refreshStatus() }
    } catch {
      let message: String
      if !allowsRefresh {
        switch error {
        case NativeOriginalPageError.heldSelection, NativeOriginalPageError.budget,
             NativeOriginalPageError.stale, NativeOriginalPageError.cancelled,
             NativeOriginalPageError.unsupported, NativeReaderOperationFailure.unavailable,
             NativeReaderContractError.disposed, NativeReaderContractError.invalidSelection:
          message = Self.message(for: error, inOriginalPDF: true)
        default:
          message = "원본 PDF 페이지를 표시할 수 없습니다. 오프라인 복사본을 다시 여세요."
        }
      } else {
        message = Self.message(for: error, inOriginalPDF: true)
      }
      showActionNotice(message)
    }
  }
  @objc func findPage() {
    guard currentMode == .originalPages, let original else { return }
    cancelFind()
    original.invalidateFind()
    let query = findField.stringValue
    guard !query.isEmpty else { return }
    let searchGeneration = findGeneration, snapshot = original.store.accepted?.id
    findTask = Task { [weak self] in
      defer { if let self, self.findGeneration == searchGeneration { self.findTask = nil } }
      var jumping = false
      do {
        let hits = try await original.search(query)
        try Task.checkCancellation()
        guard let self, self.findGeneration == searchGeneration, self.currentMode == .originalPages,
              !original.isHidden, original.store.accepted?.id == snapshot else { return }
        guard let hit = hits.first else {
          self.findFailure = nil
          self.setNotice("검색 결과 없음: ‘\(query)’을(를) 찾을 수 없습니다.")
          self.refreshStatus()
          return
        }
        // Keep cancellation authority through adoption. Only this Find's own
        // synchronous jump bypasses external-interaction invalidation.
        if let searchTicket = self.searchSelectionTicket, original.store.selection?.0 == searchTicket {
          self.isReleasingSearchSelectionForFind = true
          original.releaseSelection()
          self.isReleasingSearchSelectionForFind = false
          self.searchSelectionTicket = nil
        }
        jumping = true
        try original.jump(to: hit.pageIndex, invalidatesFind: false)
        self.updatePageNavigation()
        try await original.select(page: hit.pageIndex, range: hit.rangeUTF16, isValid: { [weak self] in
          guard let self else { return false }
          return !Task.isCancelled && self.findGeneration == searchGeneration && self.currentMode == .originalPages && !original.isHidden
        })
        try Task.checkCancellation()
        self.findFailure = nil; self.searchSelectionTicket = original.store.selection?.0
        self.clearNotice()
        self.refreshStatus()
        self.onCapsuleLayout?()
      } catch {
        guard let self, !Task.isCancelled, self.findGeneration == searchGeneration,
              self.currentMode == .originalPages, !original.isHidden,
              original.store.accepted?.id == snapshot else { return }
        if error is CancellationError { return }
        let reason: String
        switch error {
        case NativeOriginalPageError.stale, NativeOriginalPageError.cancelled:
          return
        case NativeOriginalPageError.budget:
          if jumping {
            reason = "검색 이동 실패: PDF 표시 한도를 넘었습니다. 더보기(•••)에서 배율을 줄인 뒤 다시 검색하세요."
          } else if query.utf16.count > 256 {
            reason = "검색 실패: 검색어가 256자(UTF-16) 한도를 넘었습니다. 더 짧고 구체적인 검색어를 입력해 다시 검색하세요."
          } else {
            reason = "검색 실패: 검색 결과 수나 문서 검색량 한도를 넘었습니다. 더 구체적인 검색어로 좁혀 다시 검색하세요."
          }
        case NativeOriginalPageError.heldSelection:
          reason = "검색 이동 실패: PDF에서 선택한 내용이 있습니다. ‘선택 해제’ 후 다시 검색하세요."
        case NativeOriginalPageError.unsupported:
          reason = "검색 실패: 이 페이지의 텍스트 위치를 선택할 수 없습니다. 다른 검색어로 다시 검색하세요."
        default:
          reason = self.allowsRefresh
            ? Self.message(for: error, inOriginalPDF: true)
            : "검색 실패: 원본 PDF 검색에 실패했습니다. 오프라인 복사본을 다시 열거나 검색어를 바꿔 보세요."
        }
        self.findFailure = reason; self.setNotice(reason); self.refreshStatus()
      }
    }
  }
  func cancelFind() {
    guard !isReleasingSearchSelectionForFind else { return }
    findGeneration += 1; findTask?.cancel(); findTask = nil
    findFailure = nil; actionFailure = nil
    if findExpandedAtNarrowWidth {
      findExpandedAtNarrowWidth = false
      updateToolbarLayout()
    }
    refreshStatus()
  }
  @objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    if menuItem.action == #selector(NSResponder.performTextFinderAction(_:)) {
      guard let action = NSTextFinder.Action(rawValue: menuItem.tag) else { return false }
      switch currentMode {
      case .nativeReflow:
        return reader.canPerformFind(tag: action.rawValue)
      case .originalPages:
        return action == .showFindInterface
      }
    }
    return menuItem.isEnabled && (menuItem.action.map { responds(to: $0) } ?? false)
  }
  override func performTextFinderAction(_ sender: Any?) {
    guard let tag = (sender as? NSValidatedUserInterfaceItem)?.tag ?? (sender as? NSControl)?.tag,
          let action = NSTextFinder.Action(rawValue: tag) else { return }
    if currentMode == .nativeReflow {
      _ = reader.performFindAction(action)
    } else if currentMode == .originalPages && action == .showFindInterface {
      triggerFind()
    }
  }
  @objc func copySelected() { if currentMode == .originalPages { _ = original?.copyDisplay() } else { _ = reader.copyPlainText() } }
  @objc func sourceSelected() { guard currentMode == .nativeReflow else { return }; _ = reader.requestSource(.excerpt) }
  @objc func highlightSelected() { guard currentMode == .nativeReflow else { return }; _ = reader.requestSource(.highlight) }
  @objc func askSelected() { guard currentMode == .nativeReflow else { return }; reader.openChat() }
  func refreshOutline() {
    let previous = contents.selectedItem?.representedObject as? String
    contents.removeAllItems()
    if reader.outline.isEmpty {
      let empty = NSMenuItem(title: "목차", action: nil, keyEquivalent: "")
      empty.isEnabled = false
      contents.menu?.addItem(empty)
    } else {
      for node in reader.outline {
        let item = NSMenuItem(title: String(repeating: "  ", count: min(5, max(0, (node.headingLevel ?? 1)-1))) + String(node.displayText.prefix(120)), action: nil, keyEquivalent: "")
        item.representedObject = node.id; contents.menu?.addItem(item)
      }
      if let previous, let item = contents.itemArray.first(where: { $0.representedObject as? String == previous }) { contents.select(item) }
    }
    contents.toolTip = contents.titleOfSelectedItem
    invalidateControlLayout(); updateNavigation(); rebuildMoreMenu()
  }
  func updateNavigation() {
    contents.isEnabled = currentMode == .nativeReflow && !reader.outline.isEmpty
    back.isEnabled = currentMode == .nativeReflow && (reader.canReturnFromReference || (canReturnFromCrossProject?() ?? false))
    rebuildMoreMenu()
  }
  func updateReaderControls(readOnly: Bool) {
    isReadOnlyState = readOnly
    if readOnly { homepage = nil; accountStatus.stringValue = "오프라인 · 계정 작업을 사용할 수 없습니다" }
    updateNavigation(); updateOfflineControls(); rebuildMoreMenu()
  }
  private func updateOfflineControls() {
    let prepared = reader.store.document != nil && (currentMode == .originalPages || (reader.renderKey != nil && reader.renderKey == reader.requestedRenderKey))
    saveOffline.isEnabled = storageAvailable && !storageBusy && prepared
    savedDocuments.isEnabled = !storageBusy && !savedEntries.isEmpty
    exportPDF.isEnabled = !fixtureMode && currentMode == .originalPages && original?.store.accepted != nil && !exportBusy
    if exportBusy { saveOffline.isEnabled = false }
    rebuildMoreMenu()
  }
  private func rebuildMoreMenu() {
    moreMenu.removeAllItems()
    func addItem(_ title: String, _ action: Selector, enabled: Bool = true, key: String = "", represented: Any? = nil) {
      let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
      item.target = self
      item.isEnabled = enabled
      item.representedObject = represented
      moreMenu.addItem(item)
    }

    if isNarrowToolbar {
      let outlineItem = NSMenuItem(title: "목차", action: nil, keyEquivalent: "")
      let outlineSub = NSMenu(title: "목차")
      outlineSub.autoenablesItems = false
      if currentMode == .nativeReflow, !reader.outline.isEmpty {
        for node in reader.outline {
          let title = String(repeating: "  ", count: min(5, max(0, (node.headingLevel ?? 1)-1))) + String(node.displayText.prefix(120))
          let sub = NSMenuItem(title: title, action: #selector(outlineMenuSelected(_:)), keyEquivalent: "")
          sub.target = self; sub.representedObject = node.id; sub.isEnabled = true
          outlineSub.addItem(sub)
        }
        outlineItem.isEnabled = true
      } else {
        let none = NSMenuItem(title: "목차 없음", action: nil, keyEquivalent: "")
        none.isEnabled = false
        outlineSub.addItem(none)
        outlineItem.isEnabled = false
      }
      outlineItem.submenu = outlineSub
      moreMenu.addItem(outlineItem)
      addItem("검색", #selector(triggerFind), enabled: currentMode == .originalPages || reader.canPerformFind(), key: "f")
      if currentMode == .originalPages && allowsModeSwitch {
        addItem("본문", #selector(reflowMode), enabled: allowsModeSwitch)
      }
      moreMenu.addItem(.separator())
    }

    let liveEnabled = !isReadOnlyState && currentMode == .nativeReflow
    addItem("원문 보기", #selector(sourceSelected), enabled: liveEnabled)
    addItem("원문 강조", #selector(highlightSelected), enabled: liveEnabled)
    addItem("질문하기", #selector(askSelected), enabled: liveEnabled)
    addItem("편집기 위치로", #selector(locateSelected), enabled: liveEnabled)
    addItem("편집기 결과 확인", #selector(editorReceipt), enabled: liveEnabled)
    addItem("최근 편집", #selector(lastEdit), enabled: liveEnabled)
    addItem("계정 상태", #selector(account), enabled: liveEnabled)
    addItem("계정 관리", #selector(manageAccountExplicitly), enabled: homepage != nil)
    moreMenu.addItem(.separator())

    addItem("돌아가기", #selector(returnFromReference), enabled: currentMode == .nativeReflow && (reader.canReturnFromReference || (canReturnFromCrossProject?() ?? false)))
    addItem("확대", #selector(zoomIn), enabled: true)
    addItem("축소", #selector(zoomOut), enabled: true)
    addItem("맞춤", #selector(fitPage), enabled: true)
    if currentMode == .nativeReflow {
      addItem("검토 표시", #selector(markSelected), enabled: true)
      addItem("검토 표시 취소", #selector(undoReviewExplicitly), enabled: reviewCount > 0)
      addItem("검토 표시 지우기", #selector(clearReviewExplicitly), enabled: reviewCount > 0)
    }
    moreMenu.addItem(.separator())

    addItem("새로고침", #selector(refreshDocument), enabled: allowsRefresh)
    addItem("오프라인 저장", #selector(saveOfflineExplicitly), enabled: saveOffline.isEnabled)
    addItem("저장 목록 새로고침", #selector(refreshSavedExplicitly), enabled: storageAvailable && !storageBusy && !exportBusy)

    let savedItem = NSMenuItem(title: "저장 문서 열기", action: nil, keyEquivalent: "")
    let savedSub = NSMenu(title: "저장 문서 열기")
    savedSub.autoenablesItems = false
    if savedEntries.isEmpty {
      let empty = NSMenuItem(title: "저장된 문서 없음", action: nil, keyEquivalent: "")
      empty.isEnabled = false
      savedSub.addItem(empty)
      savedItem.isEnabled = false
    } else {
      for entry in savedEntries {
        let sub = NSMenuItem(title: entry.title, action: #selector(openSavedMenuEntry(_:)), keyEquivalent: "")
        sub.target = self; sub.representedObject = entry.identity
        sub.isEnabled = storageAvailable && !storageBusy && !exportBusy
        savedSub.addItem(sub)
      }
      savedItem.isEnabled = storageAvailable && !storageBusy && !exportBusy
    }
    savedItem.submenu = savedSub
    moreMenu.addItem(savedItem)
    addItem("작업 취소", #selector(cancelStorageExplicitly), enabled: storageBusy || exportBusy)
    addItem("PDF 내보내기", #selector(exportPDFExplicitly), enabled: exportPDF.isEnabled)
    moreMenu.addItem(.separator())

    let accountInfo = NSMenuItem(title: "계정: \(accountStatus.stringValue)", action: nil, keyEquivalent: "")
    accountInfo.isEnabled = false
    moreMenu.addItem(accountInfo)
    let diagInfo = NSMenuItem(title: "최근 진단: \(notice.stringValue)", action: nil, keyEquivalent: "")
    diagInfo.isEnabled = false
    moreMenu.addItem(diagInfo)
  }

  private func invalidateControlLayout(in root: NSView? = nil) {
    func invalidate(_ view: NSView) {
      if view is NativeChromeControlRow || view === notice { view.invalidateIntrinsicContentSize(); view.needsLayout = true }
      for child in view.subviews { invalidate(child) }
    }
    if let root {
      invalidate(root)
    } else {
      invalidate(stack)
      invalidate(overlayStack)
    }
  }
  func refreshLocalControls() {
    invalidateControlLayout()
    updateOfflineControls()
    updateAppearanceControls()
    updatePageNavigation()
  }
  private func updateAppearanceControls() {
    for (index, button) in themeButtons.enumerated() {
      let selected = index == selectedThemeIndex
      button.state = selected ? .on : .off
      button.designRole = selected ? .primary : .standard
      button.preferencesOverride = window.map { NativeAppDesign.Preferences.current(appearance: $0.effectiveAppearance) }
    }
    let currentSize = Int(reader.textAppearance.fontSize.rounded())
    fontSizeLabel.stringValue = "\(currentSize)pt"
    decreaseFontButton.isEnabled = currentSize > 12
    increaseFontButton.isEnabled = currentSize < 32
    aaButton?.designRole = isDisplayPopoverOpen ? .primary : .standard
    aaButton?.state = isDisplayPopoverOpen ? .on : .off
    updateDisplayPopoverAppearance()
  }
  func setSavedDocuments(_ entries: [NativeReaderRecoveryStore.Entry]) {
    savedEntries = entries; savedDocuments.removeAllItems(); savedDocuments.addItems(withTitles: entries.map(\.title)); invalidateControlLayout(); updateOfflineControls()
  }
  func presentRecoveredDrafts(_ values: [NativeReaderRecoveredDraft]) {
    recoveredDrafts = values; recoveredDraftPicker.removeAllItems()
    for (index, _) in values.enumerated() { recoveredDraftPicker.addItem(withTitle: "복원된 초안 \(index+1)") }
    recoveredDraftRow.isHidden = values.isEmpty; recoveredDraftSelected()
    refreshStatusBannerVisibility()
  }
  func presentAccount(_ state: NativeReaderAccountState) {
    accountStatus.stringValue = state.signedIn ? (state.planEnabled ? "계정 연결됨" : "이용 가능한 플랜이 없습니다") : "설정된 홈페이지에서 로그인하세요."
    homepage = state.homepage; invalidateControlLayout(); rebuildMoreMenu()
  }
  @objc func outlineSelected() { guard currentMode == .nativeReflow, let id = contents.selectedItem?.representedObject as? String else { return }; _ = reader.navigate(toNodeID: id); updateNavigation() }
  @objc func outlineMenuSelected(_ sender: NSMenuItem) {
    guard currentMode == .nativeReflow, let id = sender.representedObject as? String else { return }
    if let item = contents.itemArray.first(where: { $0.representedObject as? String == id }) { contents.select(item) }
    _ = reader.navigate(toNodeID: id); updateNavigation()
  }
  @objc func returnFromReference() {
    guard currentMode == .nativeReflow else { return }
    if reader.canReturnFromReference { _ = reader.returnFromReference() }
    else { _ = onReturnFromCrossProject?() }
    updateNavigation()
  }
  private func syncWindowAppearance() {
    if currentMode == .originalPages && !allowsModeSwitch {
      if window?.appearance != nil { window?.appearance = nil }
    } else {
      switch selectedThemeIndex {
      case 1:
        if window?.appearance?.name != .darkAqua { window?.appearance = NSAppearance(named: .darkAqua) }
      case 2:
        // Automatic mode already clears window?.appearance in applyTheme(index: 2);
        // preserve any explicit window.appearance while Automatic is active.
        break
      default:
        if window?.appearance?.name != .aqua { window?.appearance = NSAppearance(named: .aqua) }
      }
    }
    refreshChromeForAppearance()
  }
  private func refreshChromeForAppearance() {
    let views: [NSView?] = [
      window?.contentView, toolbarView, offlineBadgeSurface, modeSegmentSurface,
      capsule, statusBanner, noticeBanner, noticeDismissButton, findField, original, originalScroll
    ]
    for view in views { view?.needsDisplay = true }
    findField.textColor = NativeChrome.color(\.ink)
    findField.placeholderAttributedString = NSAttributedString(
      string: "PDF에서 검색",
      attributes: [.foregroundColor: NativeChrome.color(\.secondaryInk), .font: NativeAppDesign.Typography.font(.control)])
    offlineBadgeLabel.textColor = NativeChrome.color(\.ink)
    pageCounterLabel.textColor = NativeChrome.color(\.ink)
    updateDisplayPopoverAppearance()
  }
  private func automaticAppearanceChanged() {
    refreshChromeForAppearance()
    guard currentMode == .nativeReflow else { return }
    let prior = reader.textAppearance
    do { try resolveAutomaticAppearance(); if prior != reader.textAppearance { onAppearance?(); updateAppearanceControls() } }
    catch { setNotice("화면 표시 설정을 적용할 수 없습니다.") }
  }
  /// Called before a new Reflow preparation too: Original PDF deliberately
  /// ignores color events, so its retained text key is not the current theme.
  func resolveAutomaticAppearance() throws {
    guard selectedThemeIndex == 2, let window else { return }
    var value = reader.textAppearance
    value.theme = window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
    guard value != reader.textAppearance else { return }
    try reader.setAppearance(value)
  }
  @objc func selectLightTheme() { applyTheme(index: 0) }
  @objc func selectDarkTheme() { applyTheme(index: 1) }
  @objc func selectAutomaticTheme() { applyTheme(index: 2) }
  private func applyTheme(index: Int) {
    guard currentMode == .nativeReflow else { return }
    let previousIndex = selectedThemeIndex
    let previousAppearance = window?.appearance
    selectedThemeIndex = index
    var value = reader.textAppearance
    // The concrete render key always contains resolved colors, while Automatic
    // inherits only this window's effective appearance (never changes the OS).
    switch index {
    case 1: window?.appearance = NSAppearance(named: .darkAqua); value.theme = .dark
    case 2: window?.appearance = nil; value.theme = window?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
    default: window?.appearance = NSAppearance(named: .aqua); value.theme = .light
    }
    do { try reader.setAppearance(value); onAppearance?(); refreshLocalControls() }
    catch {
      selectedThemeIndex = previousIndex
      window?.appearance = previousAppearance
      updateAppearanceControls()
      setNotice("화면 표시 설정을 적용할 수 없습니다.")
    }
  }
  @objc func decreaseFontSize() { stepFontSize(delta: -1) }
  @objc func increaseFontSize() { stepFontSize(delta: 1) }
  private func stepFontSize(delta: Int) {
    guard currentMode == .nativeReflow else { return }
    let sizes: [CGFloat] = [12, 14, 16, 18, 24, 32]
    let current = reader.textAppearance.fontSize
    let targetSize: CGFloat
    if delta > 0 {
      targetSize = sizes.first(where: { $0 > current + 0.5 }) ?? 32
    } else {
      targetSize = sizes.last(where: { $0 < current - 0.5 }) ?? 12
    }
    var value = reader.textAppearance
    value.fontSize = targetSize
    do { try reader.setAppearance(value); onAppearance?(); refreshLocalControls() }
    catch { setNotice("화면 표시 설정을 적용할 수 없습니다.") }
  }
  @objc func markSelected() { guard currentMode == .nativeReflow else { return }; onMarkReview?() }
  @objc func undoReviewExplicitly() { onUndoReview?() }
  @objc func clearReviewExplicitly() { onClearReview?() }
  @objc func savedDocumentSelected() { updateOfflineControls() }
  @objc func exportPDFExplicitly() { if !fixtureMode { onExportPDF?() } }
  @objc func saveOfflineExplicitly() { onSaveOffline?() }
  @objc func refreshSavedExplicitly() { onListOffline?() }
  @objc func openSavedExplicitly() { let i = savedDocuments.indexOfSelectedItem; guard savedEntries.indices.contains(i) else { return }; onOpenOffline?(savedEntries[i].identity) }
  @objc func openSavedMenuEntry(_ sender: NSMenuItem) {
    guard let identity = sender.representedObject as? NativeDocumentIdentity else { return }
    onOpenOffline?(identity)
  }
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
  @discardableResult func handleReaderEscape() -> Bool {
    if currentMode == .nativeReflow, reader.hideFindBar() {
      return true
    }
    if isDisplayPopoverOpen {
      closeDisplayPopover()
      return true
    }
    if let binding = capsule.binding, !capsule.isHidden {
      capsule.onDismiss?(binding)
      return true
    }
    return false
  }
  override func cancelOperation(_ sender: Any?) {
    if handleReaderEscape() { return }
    super.cancelOperation(sender)
  }
  func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
    updateToolbarLayout(forWidth: frameSize.width)
    return frameSize
  }
  func windowDidResize(_ notification: Notification) {
    if isAdjustingWindowHeightForDock { return }
    if !isAdjustingWindowHeightForDock, let window {
      if let prev = lastObservedWindowHeight, abs(window.frame.size.height - prev) >= 1 {
        capsuleDockWindowHeightDelta = 0
        if capsuleDocked {
          capsuleDockUserResizedHeight = true
        }
      }
      lastObservedWindowHeight = window.frame.size.height
    }
    updateToolbarLayout()
    onCapsuleLayout?()
  }
  deinit {
    removeDisplayPopoverMonitor()
  }
  func windowWillClose(_ notification: Notification) { closeDisplayPopover(); cancelFind(); hideCapsule(); onClose?() }
}

extension NativeReaderHostWindow: NativeReaderFindActionHost {
  var isReaderFindHostHidden: Bool { reader.isHidden }
}

extension NativeReaderHostWindow: NativeReaderCancelActionHost {}

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
