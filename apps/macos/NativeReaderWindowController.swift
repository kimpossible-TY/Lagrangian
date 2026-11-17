import AppKit

/// NA02/03 replace the shell presentation through this seam, including actual draw acknowledgment.
@MainActor protocol NativeReaderDocumentPresenting: AnyObject {
  func present(_ document: NativeReaderDocument, progress: @escaping (NativeReadProgress) -> Void)
  func cancel()
}

/// Owns one view's adoption and presentation lifetime, never the shared service.
@MainActor final class NativeReaderWindowController {
  typealias Target = (Profile) async throws -> NativeDocumentIdentity
  private let provider: NativeReaderDocumentProviding
  private let target: Target
  private let presenter: NativeReaderDocumentPresenting
  let store = NativeReaderDocumentStore()
  private var task: Task<Void, Never>?
  private var requestID: UUID?
  private var requestTicket: ReadingOperationTicket?

  init(provider: NativeReaderDocumentProviding, target: @escaping Target,
       presenter: NativeReaderDocumentPresenting? = nil) {
    self.provider = provider
    self.target = target
    self.presenter = presenter ?? NativeReaderShellWindow()
  }

  func open(_ profile: Profile, progress: @escaping (NativeReadProgress) -> Void) -> () -> Void {
    cancel()
    let id = UUID()
    requestID = id
    let ticket = ReadingOperationTicket()
    requestTicket = ticket
    task = Task { [weak self] in
      guard let self else { return }
      do {
        let generation = try self.store.beginRequest()
        let identity = try await self.target(profile)
        try Task.checkCancellation()
        guard self.requestID == id, !ticket.isCancelled else { return }
        let context = NativeReaderRequestContext(requestID: id, viewID: self.store.viewID,
                                                generation: generation, target: identity)
        let document = try await self.provider.document(for: context)
        try Task.checkCancellation()
        guard self.requestID == id, !ticket.isCancelled else { return }
        try self.store.adopt(document, for: context)
        progress(.accepted)
        guard self.requestID == id, !ticket.isCancelled, !Task.isCancelled else { return }
        self.presenter.present(document) { [weak self] event in
          guard self?.requestID == id, !ticket.isCancelled else { return }
          progress(event)
        }
      } catch is CancellationError {
        // Cancellation cannot close a shared service or publish a stale failure.
      } catch {
        guard self.requestID == id, !ticket.isCancelled, !Task.isCancelled else { return }
        progress(.failed("네이티브 문서를 표시할 수 없습니다: \(error.localizedDescription)"))
      }
    }
    return { [weak self] in
      ticket.cancel()
      Task { @MainActor in self?.cancel(request: id) }
    }
  }

  private func cancel(request: UUID) {
    guard requestID == request else { return }
    cancel()
  }

  func cancel() {
    requestID = nil
    requestTicket?.cancel()
    requestTicket = nil
    store.cancel()
    task?.cancel()
    task = nil
    presenter.cancel()
  }

  func dispose() { cancel(); store.dispose() }
}

/// Explicit fixture input only. Does not impersonate a service response or establish source authority.
struct NativeReaderFixtureProvider: NativeReaderDocumentProviding {
  let url: URL
  func load() async throws -> NativeReaderDocument {
    try await Task.detached {
      let size = try self.url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
      guard size > 0, size <= 32 * 1024 * 1024 else { throw NativeReaderContractError.invalidDocument }
      let document = try NativeReaderDocument.decode(Data(contentsOf: self.url))
      guard document.identity.scope == .fixture else { throw NativeReaderContractError.wrongTarget }
      return document
    }.value
  }
  func document(for context: NativeReaderRequestContext) async throws -> NativeReaderDocument {
    let fixture = try await load()
    guard fixture.identity == context.target else { throw NativeReaderContractError.wrongTarget }
    return NativeReaderDocument(schemaVersion: fixture.schemaVersion, identity: fixture.identity,
      generation: context.generation, requiredCapabilities: fixture.requiredCapabilities,
      blocks: fixture.blocks, assets: fixture.assets, diagnostics: fixture.diagnostics)
  }
}

/// An honest early shell: accepted metadata and ordinary text, with unavailable object bodies omitted.
/// It never emits .painted: native text/object renderers and their draw acknowledgment arrive in NA06.
@MainActor final class NativeReaderShellWindow: NSWindowController, NativeReaderDocumentPresenting,
                                               NSWindowDelegate {
  private let show: Bool
  private var progress: ((NativeReadProgress) -> Void)?
  let body = NSTextView()
  let notice = NSTextField(wrappingLabelWithString: "")

  init(show: Bool = true) { self.show = show; super.init(window: nil) }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func loadWindow() {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 840, height: 720),
      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
    window.title = "Lagrangian · 네이티브 문서"
    window.isReleasedWhenClosed = false
    window.delegate = self
    window.minSize = NSSize(width: 420, height: 320)
    notice.textColor = .secondaryLabelColor
    notice.setAccessibilityLabel("네이티브 문서 지원 상태")
    body.isEditable = false
    body.isSelectable = true
    body.font = .systemFont(ofSize: 18)
    body.textContainerInset = NSSize(width: 24, height: 24)
    body.autoresizingMask = [.width]
    body.isVerticallyResizable = true
    body.isHorizontallyResizable = false
    body.textContainer?.widthTracksTextView = true
    body.setAccessibilityLabel("네이티브 셸 문서 텍스트")
    let scroll = NSScrollView()
    scroll.hasVerticalScroller = true
    scroll.documentView = body
    let stack = NSStackView(views: [notice, scroll])
    stack.orientation = .vertical
    stack.alignment = .width
    stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
    stack.translatesAutoresizingMaskIntoConstraints = false
    window.contentView!.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
      stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
      stack.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor),
      scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 200),
    ])
    self.window = window
  }

  func present(_ document: NativeReaderDocument, progress: @escaping (NativeReadProgress) -> Void) {
    self.progress = progress
    if window == nil { loadWindow() }
    let ordinary: Set<NativeReaderNode.Kind> = [.text, .paragraph, .heading, .strong, .emphasis,
                                               .link, .group, .break]
    let blocks = document.blocks.filter { block in block.orderedNodes.allSatisfy { ordinary.contains($0.kind) } }
    body.string = blocks.map(\.displayText).joined(separator: "\n\n")
    notice.stringValue = "\(document.identity.documentID) · \(document.identity.revision)\n격리된 의미 문서 셸입니다. 전체 텍스트 상호작용·수식·표·그림 렌더러는 아직 연결되지 않았습니다."
    window?.contentView?.layoutSubtreeIfNeeded()
    progress(.windowInitialized)
    if show, NSApp.activationPolicy() != .prohibited { showWindow(nil) }
    progress(.failed("의미 문서는 수락했지만 전체 네이티브 Reader 렌더러가 아직 연결되지 않았습니다."))
  }

  func cancel() { progress = nil }
  func windowWillClose(_ notification: Notification) {
    let callback = progress
    progress = nil
    callback?(.failed("문서 창을 닫았습니다."))
  }
}
