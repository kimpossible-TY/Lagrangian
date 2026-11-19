import AppKit

/// A single viewport over immutable PDF pages. PDFKit objects stay in their
/// serial worker. Display selection is never a semantic/source selection.
@MainActor final class NativeReaderOriginalPageView: NSView {
    let store: NativeOriginalPageStore
    var onPaint: ((NativeOriginalPageStore.PaintAcknowledgment) -> Void)?
    var onHold: ((Bool) -> Void)?
    var onInteraction: (() -> Void)?
    // Selection intent and navigation supersede pending Find before any await.
    func invalidateInteraction() {
        selectionOperation += 1
        onInteraction?()
    }
    var onFailure: ((Error) -> Void)?
    var openURI: ((URL) -> Void)?
    var goTo: ((Int, CGPoint) -> Void)?
    var copyText: (String) -> Bool = { _ in false }
    private var task: Task<Void, Never>?
    private var operation = 0
    private var selectionOperation = 0
    private var selectionTask: Task<Void, Never>?
    fileprivate struct PageKey: Equatable {
        let snapshot: UUID; let page: Int; let generation: Int; let operation: Int
    }
    private var pendingReveal: (PageKey, CGRect)?
    private var pageText: String?
    private var pageAX: NativeOriginalPageAXText?
    private var focusedLink: Int?
    private var textFailure: String?
    fileprivate var pageKey: PageKey? {
        guard !disposed, let accepted = store.accepted else { return nil }
        return PageKey(snapshot: accepted.id, page: store.pageIndex, generation: store.viewGeneration, operation: operation)
    }
    fileprivate func current(_ key: PageKey) -> Bool { ready && !isHidden && pageKey == key }
    fileprivate func text(for key: PageKey) -> String? { current(key) ? pageText : nil }
    private func updateAccessibility() {
        guard let key = pageKey, ready, pageText != nil else { pageAX = nil; return }
        pageAX = NativeOriginalPageAXText(reader: self, key: key, links: links)
        NSAccessibility.post(element: self, notification: .layoutChanged)
    }
    override func accessibilityChildren() -> [Any]? { guard let pageAX, let key = pageKey, current(key) else { return [] }; return [pageAX] }
    override func accessibilityVisibleChildren() -> [Any]? { accessibilityChildren() }
    override func accessibilityValue() -> Any? { guard let key = pageKey else { return nil }; return text(for: key) }
    override func accessibilityHelp() -> String? { textFailure ?? "Current PDF page display text; Typst source actions unavailable" }
    fileprivate func screenRect(_ bounds: CGRect, key: PageKey) -> NSRect {
        guard current(key), let rect = try? store.viewRect(forPageRect: bounds), let window else { return .zero }
        return window.convertToScreen(convert(rect, to: nil))
    }
    fileprivate func requestSelection(_ range: NSRange, key: PageKey) {
        guard current(key), let text = pageText, range.location != NSNotFound, range.location >= 0, range.length >= 0,
              range.location <= text.utf16.count, range.length <= text.utf16.count - range.location else { return }
        if range.length == 0 { releaseSelection(); return }
        invalidateInteraction()
        selectionTask?.cancel()
        selectionTask = Task { [weak self] in
            guard let self, !Task.isCancelled, current(key) else { return }
            do { try await select(page: key.page, range: range.location..<NSMaxRange(range)) }
            catch { if !Task.isCancelled, current(key) { onFailure?(error) } }
        }
    }
    fileprivate func focusLink(_ index: Int, key: PageKey) {
        guard current(key), links.indices.contains(index) else { return }
        focusedLink = index
        reveal(links[index].bounds, key: key)
        needsDisplay = true
    }
    fileprivate func isLinkFocused(_ index: Int, key: PageKey) -> Bool { current(key) && focusedLink == index }
    private func scrollViewport(to origin: CGPoint) {
        guard let scroll = enclosingScrollView else { return }
        let clip = scroll.contentView
        clip.scroll(to: CGPoint(x: min(max(0, origin.x), max(0, frame.width - clip.bounds.width)),
                                y: min(max(0, origin.y), max(0, frame.height - clip.bounds.height))))
        scroll.reflectScrolledClipView(clip)
    }
    private func reveal(_ bounds: CGRect, key: PageKey) {
        guard pageKey == key, !isHidden, [bounds.minX, bounds.minY, bounds.width, bounds.height].allSatisfy(\.isFinite),
              let crop = store.accepted?.binding.pages[key.page].cropBox else { return }
        let clipped = bounds.intersection(crop)
        guard !clipped.isNull else { return }
        pendingOffset = nil; pendingReveal = (key, clipped)
        applyReveal()
    }
    private func applyReveal() {
        guard ready, let pending = pendingReveal else { return }
        guard current(pending.0) else { pendingReveal = nil; return }
        guard let clip = enclosingScrollView?.contentView, let rect = try? store.viewRect(forPageRect: pending.1) else { return }
        var origin = clip.bounds.origin
        if rect.minX < clip.bounds.minX { origin.x = rect.minX }
        else if rect.maxX > clip.bounds.maxX { origin.x = rect.maxX - clip.bounds.width }
        if rect.minY < clip.bounds.minY { origin.y = rect.minY }
        else if rect.maxY > clip.bounds.maxY { origin.y = rect.maxY - clip.bounds.height }
        scrollViewport(to: origin); pendingReveal = nil
    }
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
        invalidateInteraction()
        task?.cancel(); selectionTask?.cancel(); selectionOperation += 1
        operation += 1; let epoch = operation
        ready = false; pageAX = nil; pageText = nil; focusedLink = nil; textFailure = nil
        guard !disposed, let accepted = store.accepted else { return }
        do {
            let ticket = try store.beginRender()
            task = Task { [weak self] in
                do {
                    let raster = try await accepted.access.render(page: ticket.pageIndex, scale: ticket.rasterScale)
                    let links = try await accepted.access.links(page: ticket.pageIndex)
                    var text: String? = nil; var textFailure: String? = nil
                    do { text = try await accepted.access.pageText(page: ticket.pageIndex) }
                    catch { textFailure = "Current-page PDF text unavailable: " + String(describing: error).prefix(120) }
                    try Task.checkCancellation()
                    guard let self, !self.disposed, self.operation == epoch else { return }
                    try self.store.adoptRender(raster, for: ticket)
                    self.links = links; self.pageText = text; self.textFailure = textFailure; self.ready = true
                    let size = accepted.binding.pages[ticket.pageIndex].displaySize
                    if self.enclosingScrollView != nil {
                        self.setFrameSize(CGSize(width: size.width * self.store.displayedScale, height: size.height * self.store.displayedScale))
                        self.enclosingScrollView?.layoutSubtreeIfNeeded()
                        if let offset = self.pendingOffset, self.enclosingScrollView != nil {
                            let scale = self.store.displayedScale
                            self.scrollViewport(to: CGPoint(x: offset.x * scale, y: offset.y * scale))
                            self.pendingOffset = nil
                        }
                    }
                    self.updateAccessibility(); self.applyReveal()
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
        invalidateInteraction()
        guard let accepted = store.accepted, accepted.binding.pages.indices.contains(page) else { throw NativeOriginalPageError.geometry }
        let scale = store.fitsWidth ? min(8, max(0.1, store.viewportWidth / accepted.binding.pages[page].displaySize.width)) : store.scale
        pendingOffset = nil; pendingReveal = nil
        try checkRaster(page: page, scale: scale); try store.jump(to: page); ready = false; render()
    }
    func zoom(_ value: Double?) throws {
        invalidateInteraction()
        guard let accepted = store.accepted else { throw NativeOriginalPageError.stale }
        let scale = value ?? min(8, max(0.1, store.viewportWidth / accepted.binding.pages[store.pageIndex].displaySize.width))
        pendingOffset = nil; pendingReveal = nil
        try checkRaster(page: store.pageIndex, scale: scale); try store.setScale(value); ready = false; render()
    }
    func resizeViewport(_ newSize: NSSize) {
        guard !disposed, newSize.width >= 32, newSize.width <= 8192, newSize.width != store.viewportWidth else { return }
        invalidateInteraction()
        guard store.selection == nil else { return }
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
        selectionOperation += 1; let selectionEpoch = selectionOperation
        let value = try await accepted.access.selection(page: page, rangeUTF16: range)
        try Task.checkCancellation()
        guard !disposed, operation == epoch, selectionOperation == selectionEpoch, store.pageIndex == page,
              store.accepted?.id == accepted.id else { throw NativeOriginalPageError.stale }
        try hold(value)
    }
    private func hold(_ value: NativeOriginalDisplaySelection) throws {
        try store.hold(value, ticket: UUID()); selected = value; onHold?(true)
        if let key = pageKey { reveal(value.pageBounds, key: key) }
        if let pageAX { NSAccessibility.post(element: pageAX, notification: .selectedTextChanged) }
        needsDisplay = true
    }
    func releaseSelection() {
        invalidateInteraction()
        selectionTask?.cancel(); selectionOperation += 1
        if let ticket = store.selection?.0 { store.release(ticket: ticket) }
        selected = nil; onHold?(false); needsDisplay = true
    }
    func copyDisplay() -> Bool { guard !disposed, ready, let selected, selected.snapshotID == store.accepted?.id, selected.pageIndex == store.pageIndex else { return false }; return copyText(selected.displayText) }
    func search(_ query: String) async throws -> [NativeOriginalDisplaySelection] {
        guard !disposed, !isHidden, let accepted = store.accepted else { throw NativeOriginalPageError.stale }
        let epoch = operation, selectionEpoch = selectionOperation
        let result = try await accepted.access.search(query)
        try Task.checkCancellation()
        guard !disposed, !isHidden, selectionOperation == selectionEpoch, operation == epoch, store.accepted?.id == accepted.id else { throw NativeOriginalPageError.stale }
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
            try jump(to: page)
            if let key = pageKey { reveal(CGRect(x: point.x, y: point.y, width: 1, height: 1), key: key) }
            goTo?(page, point)
        }
    }
    override func mouseDown(with event: NSEvent) {
        guard ready, !disposed, let accepted = store.accepted else { return }
        invalidateInteraction()
        selectionTask?.cancel()
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
            invalidateInteraction()
            selectionTask?.cancel(); selectionOperation += 1
            let epoch = operation, selectionEpoch = selectionOperation, page = store.pageIndex
            selectionTask = Task { [weak self] in
                do {
                    let value = try await accepted.access.selection(page: page, rectangle: pdf)
                    try Task.checkCancellation()
                    guard let self, !self.disposed, self.operation == epoch, self.selectionOperation == selectionEpoch,
                          self.store.pageIndex == page, self.store.accepted?.id == accepted.id else { return }
                    try self.hold(value)
                } catch { if !Task.isCancelled { self?.onFailure?(error) } }
            }
        } catch { onFailure?(error) }
    }
    override func keyDown(with event: NSEvent) {
        do {
            if event.keyCode == 48, let key = pageKey, current(key), !links.isEmpty {
                let step = event.modifierFlags.contains(.shift) ? -1 : 1
                let next = (focusedLink ?? (step > 0 ? -1 : links.count)) + step
                if !links.indices.contains(next) {
                    focusedLink = nil
                    if step > 0 { window?.selectNextKeyView(self) } else { window?.selectPreviousKeyView(self) }
                } else { focusLink(next, key: key) }
                return
            }
            if [36, 49].contains(event.keyCode), let key = pageKey, current(key), let index = focusedLink, links.indices.contains(index) {
                try activate(links[index]); return
            }
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "a", let key = pageKey, let text = text(for: key) {
                requestSelection(NSRange(location: 0, length: text.utf16.count), key: key); return
            }
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
    func cancel() {
        invalidateInteraction()
        task?.cancel(); selectionTask?.cancel(); selectionOperation += 1; operation += 1
        pendingReveal = nil; pendingOffset = nil; pageAX = nil; pageText = nil; links = []; focusedLink = nil
        store.cancel()
    }
    func dispose() {
        cancel(); disposed = true; releaseSelection()
        let access = store.accepted?.access
        store.dispose(); Task { await access?.dispose() }
    }
}


/// A single current-page AX projection. It owns no PDFKit objects or source ranges.
@MainActor private final class NativeOriginalPageAXText: NSAccessibilityElement {
    weak var reader: NativeReaderOriginalPageView?
    let key: NativeReaderOriginalPageView.PageKey
    private var links = [NativeOriginalPageAXLink]()
    init(reader: NativeReaderOriginalPageView, key: NativeReaderOriginalPageView.PageKey, links: [NativeOriginalPDFAccess.Link]) {
        self.reader = reader; self.key = key
        super.init(); setAccessibilityParent(reader); setAccessibilityElement(true)
        self.links = links.enumerated().map { NativeOriginalPageAXLink(reader: reader, key: key, link: $0.element, index: $0.offset, parent: self) }
    }
    private var current: Bool { reader?.current(key) == true }
    override func accessibilityRole() -> NSAccessibility.Role? { .textArea }
    override func accessibilityLabel() -> String? { current ? "Original PDF page \(key.page + 1) display text" : nil }
    override func accessibilityValue() -> Any? { reader?.text(for: key) }
    override func isAccessibilityEnabled() -> Bool { current }
    override func accessibilityFrame() -> NSRect {
        guard current, let reader, let crop = reader.store.accepted?.binding.pages[key.page].cropBox else { return .zero }
        return reader.screenRect(crop, key: key)
    }
    override func accessibilityNumberOfCharacters() -> Int { reader?.text(for: key)?.utf16.count ?? 0 }
    override func accessibilityString(for range: NSRange) -> String? {
        guard let text = reader?.text(for: key), range.location != NSNotFound, range.location >= 0, range.length >= 0,
              range.location <= text.utf16.count, range.length <= text.utf16.count - range.location,
              let r = Range(range, in: text) else { return nil }
        return String(text[r])
    }
    override func accessibilitySelectedText() -> String? { current ? reader?.selected?.displayText : nil }
    override func accessibilitySelectedTextRange() -> NSRange {
        guard current, let selection = reader?.selected else { return NSRange(location: 0, length: 0) }
        return NSRange(location: selection.rangeUTF16.lowerBound, length: selection.rangeUTF16.count)
    }
    override func setAccessibilitySelectedTextRange(_ range: NSRange) { reader?.requestSelection(range, key: key) }
    override func accessibilityChildren() -> [Any]? { current ? links : [] }
    override func accessibilityVisibleChildren() -> [Any]? { accessibilityChildren() }
}

@MainActor private final class NativeOriginalPageAXLink: NSAccessibilityElement {
    weak var reader: NativeReaderOriginalPageView?
    let key: NativeReaderOriginalPageView.PageKey
    let link: NativeOriginalPDFAccess.Link
    let index: Int
    init(reader: NativeReaderOriginalPageView, key: NativeReaderOriginalPageView.PageKey, link: NativeOriginalPDFAccess.Link, index: Int, parent: Any) {
        self.reader = reader; self.key = key; self.link = link; self.index = index
        super.init(); setAccessibilityParent(parent); setAccessibilityElement(true)
    }
    private var current: Bool { reader?.current(key) == true }
    override func accessibilityRole() -> NSAccessibility.Role? { .link }
    override func isAccessibilityEnabled() -> Bool { current }
    override func accessibilityLabel() -> String? {
        guard current else { return nil }
        switch link.action { case .uri(let url): return url.absoluteString; case .goTo(let page, _): return "Go to PDF page \(page + 1)" }
    }
    override func accessibilityURL() -> URL? { guard current, case .uri(let url) = link.action else { return nil }; return url }
    override func accessibilityFrame() -> NSRect { reader?.screenRect(link.bounds, key: key) ?? .zero }
    override func isAccessibilityFocused() -> Bool { reader?.isLinkFocused(index, key: key) == true }
    override func setAccessibilityFocused(_ focused: Bool) { if focused { reader?.focusLink(index, key: key) } }
    override func accessibilityPerformPress() -> Bool {
        guard current, let reader else { return false }
        do { try reader.activate(link); return true } catch { return false }
    }
}
