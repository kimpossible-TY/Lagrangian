import AppKit

/// A single viewport over immutable PDF pages. PDFKit objects stay in their
/// serial worker. Display selection is never a semantic/source selection.
@MainActor final class NativeReaderOriginalPageView: NSView {
    let store: NativeOriginalPageStore
    var onPaint: ((NativeOriginalPageStore.PaintAcknowledgment) -> Void)?
    var onHold: ((Bool) -> Void)?
    var onFailure: ((Error) -> Void)?
    var openURI: ((URL) -> Void)?
    var goTo: ((Int, CGPoint) -> Void)?
    var copyText: (String) -> Bool = { _ in false }
    private var task: Task<Void, Never>?
    private var operation = 0
    private var disposed = false
    private(set) var paintCount = 0
    private var ready = false
    var isPreparedForPaint: Bool { ready }
    private var dragStart: (point: CGPoint, snapshot: UUID, page: Int, operation: Int)?
    private var pendingOffset: CGPoint?
    private var links = [NativeOriginalPDFAccess.Link]()
    private(set) var selected: NativeOriginalDisplaySelection?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    init(viewID: UUID) {
        store = NativeOriginalPageStore(viewID: viewID)
        super.init(frame: NSRect(x: 0, y: 0, width: 640, height: 560))
        setAccessibilityLabel("Original PDF page; source actions unavailable")
        setAccessibilityRole(.group)
    }
    required init?(coder: NSCoder) { nil }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill(); dirtyRect.fill()
        guard !disposed, !isHidden, ready, let context = NSGraphicsContext.current?.cgContext else { return }
        do {
            let receipt = try store.paint(in: context)
            if let selected {
                NSColor.selectedTextBackgroundColor.withAlphaComponent(0.3).setFill()
                try store.viewRect(forPageRect: selected.pageBounds).fill()
            }
            paintCount += 1; onPaint?(receipt)
        } catch { onFailure?(error) }
    }
    func installed() { selected = nil; ready = false; render() }
    func render() {
        task?.cancel(); operation += 1; let epoch = operation
        guard !disposed, let accepted = store.accepted else { return }
        do {
            let ticket = try store.beginRender()
            task = Task { [weak self] in
                do {
                    let raster = try await accepted.access.render(page: ticket.pageIndex, scale: ticket.rasterScale)
                    let links = try await accepted.access.links(page: ticket.pageIndex)
                    try Task.checkCancellation()
                    guard let self, !self.disposed, self.operation == epoch else { return }
                    try self.store.adoptRender(raster, for: ticket)
                    self.links = links; self.ready = true
                    let size = accepted.binding.pages[ticket.pageIndex].displaySize
                    if self.enclosingScrollView != nil {
                        self.setFrameSize(CGSize(width: size.width * self.store.displayedScale, height: size.height * self.store.displayedScale))
                        self.enclosingScrollView?.layoutSubtreeIfNeeded()
                        if let offset = self.pendingOffset, let scroll = self.enclosingScrollView {
                            let clip = scroll.contentView, scale = self.store.displayedScale
                            clip.scroll(to: CGPoint(x: min(max(0, offset.x * scale), max(0, self.frame.width - clip.bounds.width)),
                                y: min(max(0, offset.y * scale), max(0, self.frame.height - clip.bounds.height))))
                            scroll.reflectScrolledClipView(clip); self.pendingOffset = nil
                        }
                    }
                    self.needsDisplay = true
                } catch { if !Task.isCancelled { self?.onFailure?(error) } }
            }
        } catch { onFailure?(error) }
    }
    private func checkRaster(page: Int, scale: Double) throws {
        guard let accepted = store.accepted, accepted.binding.pages.indices.contains(page), scale.isFinite, (0.1...8).contains(scale) else { throw NativeOriginalPageError.geometry }
        let size = accepted.binding.pages[page].displaySize
        let w = ceil(size.width * scale), h = ceil(size.height * scale)
        guard w > 0, h > 0, w <= 8192, h <= 8192, w * h <= 4 * 1024 * 1024 else { throw NativeOriginalPageError.budget }
    }
    func jump(to page: Int) throws {
        guard let accepted = store.accepted, accepted.binding.pages.indices.contains(page) else { throw NativeOriginalPageError.geometry }
        let scale = store.fitsWidth ? min(8, max(0.1, store.viewportWidth / accepted.binding.pages[page].displaySize.width)) : store.scale
        pendingOffset = nil
        try checkRaster(page: page, scale: scale); try store.jump(to: page); ready = false; render()
    }
    func zoom(_ value: Double?) throws {
        guard let accepted = store.accepted else { throw NativeOriginalPageError.stale }
        let scale = value ?? min(8, max(0.1, store.viewportWidth / accepted.binding.pages[store.pageIndex].displaySize.width))
        pendingOffset = nil
        try checkRaster(page: store.pageIndex, scale: scale); try store.setScale(value); ready = false; render()
    }
    func resizeViewport(_ newSize: NSSize) {
        guard !disposed, newSize.width >= 32, newSize.width <= 8192, newSize.width != store.viewportWidth, store.selection == nil else { return }
        do {
            try store.resize(width: newSize.width)
            if store.accepted != nil { ready = false; render() }
        } catch { onFailure?(error) }
    }
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if enclosingScrollView == nil { resizeViewport(newSize) }
    }
    func select(page: Int, range: Range<Int>) async throws {
        guard !disposed, let accepted = store.accepted, page == store.pageIndex else { throw NativeOriginalPageError.stale }
        let epoch = operation
        let value = try await accepted.access.selection(page: page, rangeUTF16: range)
        try Task.checkCancellation()
        guard !disposed, operation == epoch, store.accepted?.id == accepted.id else { throw NativeOriginalPageError.stale }
        try hold(value)
    }
    private func hold(_ value: NativeOriginalDisplaySelection) throws {
        try store.hold(value, ticket: UUID()); selected = value; onHold?(true); needsDisplay = true
    }
    func releaseSelection() {
        if let ticket = store.selection?.0 { store.release(ticket: ticket) }
        selected = nil; onHold?(false); needsDisplay = true
    }
    func copyDisplay() -> Bool { guard let selected else { return false }; return copyText(selected.displayText) }
    func search(_ query: String) async throws -> [NativeOriginalDisplaySelection] {
        guard !disposed, let accepted = store.accepted else { throw NativeOriginalPageError.stale }
        let epoch = operation
        let result = try await accepted.access.search(query)
        try Task.checkCancellation()
        guard !disposed, operation == epoch, store.accepted?.id == accepted.id else { throw NativeOriginalPageError.stale }
        return result
    }
    func activate(_ link: NativeOriginalPDFAccess.Link) throws {
        guard !disposed, let accepted = store.accepted, link.snapshotID == accepted.id,
              link.pageIndex == store.pageIndex, store.selection == nil else { throw NativeOriginalPageError.stale }
        switch link.action {
        case .uri(let url):
            guard NativeOriginalPDFAccess.safeURL(url) else { throw NativeOriginalPageError.unsupported("unsafe-url") }
            openURI?(url)
        case .goTo(let page, let point):
            guard accepted.binding.pages.indices.contains(page), point.x.isFinite, point.y.isFinite,
                  accepted.binding.pages[page].cropBox.contains(point) else { throw NativeOriginalPageError.geometry }
            try jump(to: page); goTo?(page, point)
        }
    }
    override func mouseDown(with event: NSEvent) {
        guard ready, !disposed, let accepted = store.accepted else { return }
        window?.makeFirstResponder(self)
        dragStart = (convert(event.locationInWindow, from: nil), accepted.id, store.pageIndex, operation)
    }
    override func mouseUp(with event: NSEvent) {
        let drag = dragStart; dragStart = nil
        guard ready, !disposed, let drag, let accepted = store.accepted, drag.snapshot == accepted.id,
              drag.page == store.pageIndex, drag.operation == operation else { return }
        let start = drag.point
        let end = convert(event.locationInWindow, from: nil)
        let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(start.x - end.x), height: abs(start.y - end.y))
        do {
            let pdf = try store.pageRect(forViewRect: rect)
            if rect.width < 3 && rect.height < 3 {
                if let link = links.first(where: { $0.bounds.contains(pdf.origin) }) { try activate(link) }
                return
            }
            task?.cancel(); operation += 1; let epoch = operation, page = store.pageIndex
            task = Task { [weak self] in
                do {
                    let value = try await accepted.access.selection(page: page, rectangle: pdf)
                    try Task.checkCancellation()
                    guard let self, self.operation == epoch, self.store.accepted?.id == accepted.id else { return }
                    try self.hold(value)
                } catch { if !Task.isCancelled { self?.onFailure?(error) } }
            }
        } catch { onFailure?(error) }
    }
    override func keyDown(with event: NSEvent) {
        do {
            switch event.charactersIgnoringModifiers ?? "" {
            case "c" where event.modifierFlags.contains(.command): _ = copyDisplay()
            case "+", "=": try zoom(store.displayedScale * 1.25)
            case "-": try zoom(store.displayedScale / 1.25)
            case "\u{1b}": releaseSelection()
            default:
                if event.keyCode == 124 || event.keyCode == 125 { try jump(to: store.pageIndex + 1) }
                else if event.keyCode == 123 || event.keyCode == 126 { try jump(to: max(0, store.pageIndex - 1)) }
                else { super.keyDown(with: event) }
            }
        } catch { onFailure?(error) }
    }
    struct Recovery: Codable {
        let identity: NativeDocumentIdentity
        let fingerprint: String
        let digest: String
        let page: Int
        let scale: Double?
        var offsetX: Double? = nil // Unscaled page-display points, optional schema-1 defaults.
        var offsetY: Double? = nil
    }
    func recovery() throws -> Recovery {
        guard let accepted = store.accepted else { throw NativeOriginalPageError.stale }
        var value = Recovery(identity: accepted.binding.identity, fingerprint: accepted.binding.inputFingerprint,
            digest: accepted.binding.pdfSHA256, page: store.pageIndex, scale: store.fitsWidth ? nil : store.scale)
        if let clip = enclosingScrollView?.contentView {
            value.offsetX = max(0, clip.bounds.origin.x / store.displayedScale)
            value.offsetY = max(0, clip.bounds.origin.y / store.displayedScale)
        }
        return value
    }
    func restore(_ recovery: Recovery) throws {
        guard let accepted = store.accepted, recovery.identity == accepted.binding.identity,
              recovery.fingerprint == accepted.binding.inputFingerprint, recovery.digest == accepted.binding.pdfSHA256,
              accepted.binding.pages.indices.contains(recovery.page),
              recovery.scale == nil || (recovery.scale!.isFinite && (0.1...8).contains(recovery.scale!)),
              [recovery.offsetX, recovery.offsetY].allSatisfy({ $0 == nil || ($0!.isFinite && (0...4096).contains($0!)) }) else { throw NativeOriginalPageError.stale }
        try store.jump(to: recovery.page); try store.setScale(recovery.scale)
        pendingOffset = CGPoint(x: recovery.offsetX ?? 0, y: recovery.offsetY ?? 0); ready = false; render()
    }
    func cancel() { task?.cancel(); operation += 1; store.cancel() }
    func dispose() {
        cancel(); disposed = true; releaseSelection()
        let access = store.accepted?.access
        store.dispose(); Task { await access?.dispose() }
    }
}
