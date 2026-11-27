import AppKit
import CoreText

struct NativeReaderTextAppearance: Equatable {
    enum Theme: String { case light, dark }
    var fontName: String = "system"
    var fontSize: CGFloat = 15
    var zoom: CGFloat = 1
    var theme: Theme = .light
    var effectiveSize: CGFloat { fontSize * zoom }
    func bodyFont(size: CGFloat? = nil) -> NSFont {
        let size = size ?? effectiveSize
        let serif = NSFont(name: "STIXTwoText", size: size)
            ?? NSFont(name: "STIXTwoText-Regular", size: size)
            // Apple's New York is requested through the public serif design;
            // requesting its private name can silently resolve to Times instead.
            ?? NSFont.systemFont(ofSize: size).fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: size) }
            ?? NSFont(name: "Georgia", size: size) ?? NSFont.systemFont(ofSize: size)
        let chosen = fontName == "system" ? serif : (NSFont(name: fontName, size: size) ?? serif)
        let cascade = NSFontDescriptor(name: "AppleSDGothicNeo-Regular", size: size)
        let descriptor = chosen.fontDescriptor.addingAttributes([.cascadeList: [cascade]])
        return NSFont(descriptor: descriptor, size: size) ?? chosen
    }
    func tabularFont(size: CGFloat) -> NSFont {
        let base = bodyFont(size: size)
        let descriptor = base.fontDescriptor.addingAttributes([.featureSettings: [
            [NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
             NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector]]])
        let candidate = NSFont(descriptor: descriptor, size: size) ?? base
        // STIX has tabular digits by default and drops the redundant feature.
        // Other user fonts can ignore it while retaining proportional digits.
        let widths = (0...9).map {
            CTLineGetTypographicBounds(CTLineCreateWithAttributedString(
                NSAttributedString(string: String($0), attributes: [.font: candidate])), nil, nil, nil)
        }
        if let first = widths.first, widths.allSatisfy({ abs($0 - first) < 0.01 }) { return candidate }
        return NSFont.monospacedDigitSystemFont(ofSize: size, weight: .regular)
    }
    // The current semantic wire model has no code node. This style is reusable
    // by presentation code without guessing code from natural-language metadata.
    func codeAttributes(palette: NativeAppDesign.Palette) -> [NSAttributedString.Key: Any] {
        [.font: NSFont.monospacedSystemFont(ofSize: effectiveSize * 0.88, weight: .regular),
         .foregroundColor: palette.ink, .backgroundColor: palette.codeBg]
    }
}

// This key is also the off-thread object preparer's adoption key. Providers only
// return already prepared, cache-bound results; they must never run a compiler,
// process, network request or blocking wait from these callbacks.
struct NativeReaderTextRenderKey: Equatable {
    let identity: NativeDocumentIdentity
    let documentGeneration: Int
    let viewID: UUID
    let layoutGeneration: Int
    let width: CGFloat
    let appearance: NativeReaderTextAppearance
}

struct NativeReaderPreparedTextObject {
    let key: NativeReaderTextRenderKey
    let size: NSSize
    let baseline: CGFloat
    let accessibilityLabel: String
    let draw: (NSRect) -> Void
    var cost: Int = 0
    var mathLayouts: [String: NativeMathLayout] = [:]
    var isPlaceholder = false

    static let largeDocumentThreshold = 128
    static func isObject(_ node: NativeReaderNode) -> Bool {
        [.math, .equation, .table, .figure, .image].contains(node.kind)
    }
    static func attachmentNodes(in document: NativeReaderDocument) -> [NativeReaderNode] {
        func visit(_ node: NativeReaderNode) -> [NativeReaderNode] {
            guard node.visible else { return [] }
            return isObject(node) ? [node] : node.children.flatMap(visit)
        }
        return document.blocks.flatMap(visit)
    }
    static func isLarge(_ document: NativeReaderDocument) -> Bool {
        document.blocks.flatMap(\.orderedNodes).filter(isObject).count > largeDocumentThreshold
    }
    static func initialNodes(in document: NativeReaderDocument) -> [NativeReaderNode] {
        let nodes = attachmentNodes(in: document)
        guard isLarge(document) else { return nodes }
        var count = 0
        return Array(nodes.prefix { node in
            let next = node.orderedNodes.filter(isObject).count
            guard count + next <= largeDocumentThreshold else { return false }
            count += next; return true
        })
    }
    // Deterministic object failures may salvage siblings. Transient/system
    // errors discard staged halves and reach the caller's bounded backoff,
    // except timeouts isolated on the viewport's last allowed attempt;
    // cancellation/staleness abort. Worker batches themselves stay atomic.
    @MainActor static func prepareLazy(_ nodes: [NativeReaderNode],
        provider: ([NativeReaderNode]) async throws -> [String: Self],
        bounded: Bool = false, isolatingTimeout: Bool = false) async throws -> (objects: [String: Self], failures: Set<String>) {
        var timeoutBudget = isolatingTimeout ? 2 * Int(ceil(log2(Double(max(nodes.count, 2))))) + 1 : 0
        func prepare(_ selected: [NativeReaderNode], isolating: Bool = false) async throws -> (objects: [String: Self], failures: Set<String>) {
            try Task.checkCancellation()
            do { return (try await provider(selected), []) }
            catch {
                switch error {
                case let failure as NativeObjectError:
                    guard failure.classification.scope == .deterministic ||
                        (isolatingTimeout && failure == .unsupported("math-helper-timeout")) else { throw error }
                    if isolatingTimeout && failure == .unsupported("math-helper-timeout") {
                        timeoutBudget -= 1
                        guard timeoutBudget > 0 else { throw error }
                    }
                case NativeReaderTextFailure.unsupportedObject, NativeReaderTextFailure.invalidGeometry:
                    break
                default: throw error
                }
                guard selected.count > 1 else {
                    if isolating { return ([:], Set(selected.map(\.id))) }
                    throw error
                }
                let mid = selected.count / 2
                let left = try await prepare(Array(selected[..<mid]), isolating: true)
                let right = try await prepare(Array(selected[mid...]), isolating: true)
                let objects = left.objects.merging(right.objects) { _, new in new }
                if bounded {
                    let cache = NativeReaderLazyObjectCache()
                    cache.insert(objects, protecting: Set(objects.keys))
                    return (cache.objects, left.failures.union(right.failures))
                }
                return (objects, left.failures.union(right.failures))
            }
        }
        return try await prepare(nodes)
    }
    static func label(for node: NativeReaderNode) -> String {
        [node.alt, node.math?.normalizedText, node.displayText].compactMap { $0 }.first { !$0.isEmpty } ?? node.kind.rawValue
    }
    static func placeholder(_ node: NativeReaderNode, key: NativeReaderTextRenderKey) -> Self {
        let inline = node.kind == .math && node.math?.display != true
        let figure = [.image, .figure, .table].contains(node.kind)
        let width = key.width.isFinite ? max(1, min(key.width, inline ? 24 : 240)) : 24
        return Self(key: key, size: NSSize(width: width, height: inline ? 16 : figure ? 120 : 36),
            baseline: 0, accessibilityLabel: label(for: node), draw: { rect in
                NSColor(calibratedWhite: key.appearance.theme == .dark ? 0.65 : 0.35, alpha: 0.12).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
            }, isPlaceholder: true)
    }
    // Optional native substructure interaction, in top-left object-local points.
    // Returned IDs must already exist in this object's accepted semantic subtree.
    var hitNode: ((NSPoint) -> String?)? = nil
    var accessibilityLabelForNode: ((String) -> String?)? = nil
}

// One cache owns retained object cost and recency. TextKit cells are replaced
// with placeholders on eviction so they cannot retain the evicted paint closures.
@MainActor final class NativeReaderLazyObjectCache {
    nonisolated static let maxCost = 16 * 1024 * 1024
    private(set) var objects = [String: NativeReaderPreparedTextObject]()
    private var recency = [String: Int]()
    private var clock = 0
    func copy() -> NativeReaderLazyObjectCache {
        let result = NativeReaderLazyObjectCache()
        result.objects = objects; result.recency = recency; result.clock = clock
        return result
    }
    var cost: Int { objects.values.reduce(0) { $0 + $1.cost } }
    func touch(_ ids: Set<String>) {
        for id in ids.sorted() where objects[id] != nil { clock += 1; recency[id] = clock }
    }
    func insert(_ values: [String: NativeReaderPreparedTextObject], protecting visible: Set<String>) {
        // Admit visible objects first; buffer entries must never consume the
        // space needed by a newly visible attachment.
        let ordered = values.keys.sorted {
            visible.contains($0) == visible.contains($1) ? $0 < $1 : visible.contains($0)
        }
        for id in ordered {
            let value = values[id]!
            guard !value.isPlaceholder, value.cost >= 0, value.cost <= Self.maxCost else { continue }
            while cost - (objects[id]?.cost ?? 0) > Self.maxCost - value.cost {
                guard let victim = objects.keys.filter({ !visible.contains($0) && $0 != id }).min(by: {
                    (recency[$0] ?? 0) < (recency[$1] ?? 0)
                }) else { break }
                objects.removeValue(forKey: victim); recency.removeValue(forKey: victim)
            }
            guard cost - (objects[id]?.cost ?? 0) <= Self.maxCost - value.cost else { continue }
            objects[id] = value; touch([id])
        }
        touch(visible)
    }
}

enum NativeReaderTextFailure: Error, Equatable {
    case unsupportedObject(String), invalidObject(String), staleGeometry, invalidGeometry
}

struct NativeReaderTextGeometry {
    let key: NativeReaderTextRenderKey
    let position: NativeReaderTextPosition
    let rect: NSRect // Top-left AppKit points in bodyTextView coordinates.
}

struct NativeReaderViewportAnchor {
    let identity: NativeDocumentIdentity
    let position: NativeReaderTextPosition
    let offsetY: CGFloat
}

struct NativeReaderCrossProjectPosition: Equatable {
    let anchor: String?
    let blockID: String?
    let scrollOffset: Double
}

struct NativeReaderTextCallbacks {
    // A placeholder-backed reflow can succeed before its objects are ready.
    // Notify the preparation owner even when there is no cache-miss failure.
    var layoutChanged: () -> Void = { }
    var readingPositionChanged: () -> Void = { }
    var selectionChanged: (NativeReaderSelection?) -> Void = { _ in }
    var selectionReleased: (UUID) -> Void = { _ in }
    var sourceRequested: (NativeReaderSourceRequest) -> Void = { _ in }
    var chatRequested: (NativeReaderChatCommand, NativeReaderRequestContext) -> Void = { _, _ in }
    var semanticActivated: (NativeReaderNode, NativeReaderRequestContext) -> Void = { _, _ in }
    var focusChanged: (String?) -> Void = { _ in }
    var statusChanged: (String) -> Void = { _ in }
    // Called only inside the native body draw path after TextKit paints the
    // visible content for this key. Headless evidence is not GUI proof.
    var painted: (NativeReaderTextRenderKey) -> Void = { _ in }
    // Clipboard is injected. Default has no side effects; production integration
    // can explicitly bind a user action to the system clipboard.
    var copyText: (String) -> Bool = { _ in false }
}

private final class NativeReaderTextObjectCell: NSTextAttachmentCell {
    let prepared: NativeReaderPreparedTextObject
    let didPaint: (NativeReaderTextRenderKey) -> Void
    init(_ prepared: NativeReaderPreparedTextObject, didPaint: @escaping (NativeReaderTextRenderKey) -> Void) {
        self.prepared = prepared
        self.didPaint = didPaint
        super.init(textCell: "")
    }
    required init(coder: NSCoder) { fatalError("Programmatic native reader only") }
    override func cellSize() -> NSSize { prepared.size }
    override func cellBaselineOffset() -> NSPoint { NSPoint(x: 0, y: -prepared.baseline) }
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        guard let body = controlView as? NativeReaderBodyTextView,
              body.reader?.renderKey == prepared.key, body.reader?.isDisposed == false else { return }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: cellFrame).addClip()
        prepared.draw(cellFrame)
        NSGraphicsContext.restoreGraphicsState()
        didPaint(prepared.key)
    }
}

// NSScrollView owns the platform's embedded bar, including Done/button-driven
// visibility changes which do not pass through our keyboard entry point.
final class NativeReaderFindScrollView: NSScrollView {
    weak var reader: NativeReaderTextView?
    override var isFindBarVisible: Bool {
        didSet { if oldValue != isFindBarVisible { reader?.findBarVisibilityChanged() } }
    }
    override func tile() {
        super.tile()
        guard isFindBarVisible, findBarPosition == .aboveHorizontalRuler,
              let bar = findBarView, bar.frame.maxY > 0 else { return }
        let barHeight = bar.frame.maxY
        contentView.automaticallyAdjustsContentInsets = false
        contentView.contentInsets = NSEdgeInsets()
        contentView.frame = NSRect(x: 0, y: barHeight, width: bounds.width, height: max(32, bounds.height - barHeight))
    }
}

// NSTextView supplies real TextKit/CoreText shaping, bidi visual navigation,
// ligature carets, native responder commands and the native AX text API.
private let nativeHeadingRule = NSAttributedString.Key("NativeReaderHeadingRule")
private let nativeReaderLink = NSAttributedString.Key("NativeReaderLink")

final class NativeReaderBodyTextView: NativeReaderInputTextView {
    private var linkTracking: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let linkTracking { removeTrackingArea(linkTracking) }
        let area = NSTrackingArea(rect: .zero, options: [.inVisibleRect, .activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited], owner: self)
        addTrackingArea(area); linkTracking = area
    }
    override func mouseMoved(with event: NSEvent) { reader?.hoverLink(at: convert(event.locationInWindow, from: nil)) }
    override func mouseExited(with event: NSEvent) { reader?.hoverLink(at: nil) }
    override func resetCursorRects() {
        super.resetCursorRects()
        guard let storage = textStorage, let manager = layoutManager, let container = textContainer else { return }
        storage.enumerateAttribute(nativeReaderLink, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard value != nil else { return }
            manager.enumerateEnclosingRects(forGlyphRange: manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil),
                withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: container) { rect, _ in
                self.addCursorRect(rect.offsetBy(dx: self.textContainerOrigin.x, dy: self.textContainerOrigin.y), cursor: .pointingHand)
            }
        }
    }
    weak var reader: NativeReaderTextView?
    override func setSelectedRange(_ charRange: NSRange, affinity: NSSelectionAffinity, stillSelecting flag: Bool) {
        guard let reader = reader else {
            super.setSelectedRange(charRange, affinity: affinity, stillSelecting: flag)
            return
        }
        guard !reader.isDisposed, let map = reader.textMap,
              let range = try? map.normalized(charRange, affinity: affinity) else { return }
        guard (try? map.selection(for: range)) != nil || range.length == 0 else { return }
        super.setSelectedRange(range, affinity: affinity, stillSelecting: flag)
        reader.bodySelectionChanged()
    }
    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting flag: Bool) {
        guard let reader = reader else { super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: flag); return }
        guard !reader.isDisposed, ranges.count == 1, let map = reader.textMap,
              let range = try? map.normalized(ranges[0].rangeValue, affinity: affinity),
              (try? map.selection(for: range)) != nil || range.length == 0 else { return }
        super.setSelectedRanges([NSValue(range: range)], affinity: affinity, stillSelecting: flag)
        reader.bodySelectionChanged()
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if reader?.handleFindKeyEquivalent(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }
    override func cancelOperation(_ sender: Any?) {
        if reader?.hideFindBar() != true { super.cancelOperation(sender) }
    }
    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(NSResponder.performTextFinderAction(_:)) {
            return reader?.canPerformFind(tag: item.tag) ?? false
        }
        return super.validateUserInterfaceItem(item)
    }
    override func performTextFinderAction(_ sender: Any?) {
        guard let tag = (sender as? NSValidatedUserInterfaceItem)?.tag ?? (sender as? NSControl)?.tag,
              let action = NSTextFinder.Action(rawValue: tag) else { return }
        _ = reader?.performFindAction(action)
    }
    // Calls the inherited NSTextView/NSTextFinder implementation, never the
    // legacy global FindPanel action. Search/matching remains AppKit-owned.
    fileprivate func performNativeFindAction(_ action: NSTextFinder.Action) {
        let item = NSMenuItem(title: "", action: #selector(NSResponder.performTextFinderAction(_:)), keyEquivalent: "")
        item.tag = action.rawValue
        if window != nil && action == .showFindInterface {
            window?.makeFirstResponder(self)
        }
        super.performTextFinderAction(item)
    }
    override func copy(_ sender: Any?) { _ = reader?.copyPlainText() }
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { reader?.bodyFocused() }
        return accepted
    }
    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { reader?.callbacks.focusChanged(nil) }
        return accepted
    }
    override func mouseDown(with event: NSEvent) {
        reader?.pointerDown(at: convert(event.locationInWindow, from: nil), extending: event.modifierFlags.contains(.shift), clickCount: event.clickCount)
    }
    override func mouseDragged(with event: NSEvent) { reader?.pointerDragged(at: convert(event.locationInWindow, from: nil)) }
    override func mouseUp(with event: NSEvent) {
        reader?.pointerUp(at: convert(event.locationInWindow, from: nil))
    }
    override func keyDown(with event: NSEvent) {
        if reader?.handleFindKeyEquivalent(event) == true { return }
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers {
            case "c": copy(nil); return
            case "+", "=": reader?.changeZoom(by: 1.1); return
            case "-": reader?.changeZoom(by: 1 / 1.1); return
            default: break
            }
        }
        if event.keyCode == 48, reader?.focusNextSemantic(backwards: event.modifierFlags.contains(.shift)) == true { return }
        if event.keyCode == 36, reader?.activateFocusedSemantic() == true { return }
        super.keyDown(with: event)
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let reader = reader, !reader.isDisposed, let key = reader.renderKey, key == reader.requestedRenderKey else { return }
        reader.beginBodyDraw()
        super.draw(dirtyRect)
        reader.paintHeadingRules(in: dirtyRect)
        reader.paintLocalReview(in: dirtyRect)
        reader.endBodyDraw(key: key, dirtyRect: dirtyRect)
    }
    override func accessibilityChildren() -> [Any]? { reader?.accessibilityNodes ?? [] }
    override func accessibilityValue() -> String? { reader?.logicalText ?? "" }
    override func accessibilitySelectedText() -> String? { reader?.plainSelectedText }
    // The native parent's UTF16 attributes refer to logical text, not attachment
    // storage. Child AX elements use block-local logical UTF16 ranges.
    override func accessibilityNumberOfCharacters() -> Int { reader?.logicalText.utf16.count ?? 0 }
    override func accessibilitySelectedTextRange() -> NSRange { reader?.accessibilityLogicalSelectionRange ?? NSRange(location: 0, length: 0) }
    override func setAccessibilitySelectedTextRange(_ range: NSRange) { reader?.selectAccessibilityLogicalRange(range) }
    override func accessibilityString(for range: NSRange) -> String? { reader?.logicalSubstring(range) }
    override func accessibilityFrame(for range: NSRange) -> NSRect { reader?.accessibilityFrameForLogicalRange(range) ?? .zero }
    override func accessibilitySelectedTextRanges() -> [NSValue]? { [NSValue(range: accessibilitySelectedTextRange())] }
    override func setAccessibilitySelectedTextRanges(_ ranges: [NSValue]?) {
        guard let ranges = ranges, ranges.count == 1 else { return }
        setAccessibilitySelectedTextRange(ranges[0].rangeValue)
    }
    override func accessibilityAttributedString(for range: NSRange) -> NSAttributedString? {
        reader?.logicalAttributedSubstring(range)
    }
    override func accessibilityRTF(for range: NSRange) -> Data? {
        guard let text = accessibilityAttributedString(for: range) else { return nil }
        return try? text.data(from: NSRange(location: 0, length: text.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
    }
    override func accessibilityRange(for index: Int) -> NSRange { reader?.logicalGraphemeRange(at: index) ?? NSRange(location: NSNotFound, length: 0) }
    override func accessibilityStyleRange(for index: Int) -> NSRange { reader?.logicalStyleRange(at: index) ?? NSRange(location: NSNotFound, length: 0) }
    override func accessibilityLine(for index: Int) -> Int {
        guard let offset = reader?.presentationOffsetForLogical(index) else { return NSNotFound }
        return super.accessibilityLine(for: offset)
    }
    override func accessibilityRange(forLine line: Int) -> NSRange {
        reader?.logicalRangeForPresentation(super.accessibilityRange(forLine: line)) ?? NSRange(location: NSNotFound, length: 0)
    }
    override func accessibilityRange(for point: NSPoint) -> NSRange {
        reader?.logicalRangeAtScreenPoint(point) ?? NSRange(location: NSNotFound, length: 0)
    }
    override func accessibilityVisibleCharacterRange() -> NSRange {
        reader?.logicalRangeForPresentation(super.accessibilityVisibleCharacterRange()) ?? NSRange(location: NSNotFound, length: 0)
    }
    override func accessibilityInsertionPointLineNumber() -> Int { accessibilityLine(for: accessibilitySelectedTextRange().location) }
}

@MainActor final class NativeReaderTextView: NSView, NSTextViewDelegate {
    let store: NativeReaderDocumentStore
    let scrollView = NativeReaderFindScrollView()
    let bodyTextView = NativeReaderBodyTextView(frame: .zero)
    let statusLabel = NSTextField(wrappingLabelWithString: "")
    var callbacks: NativeReaderTextCallbacks
    var cachedObject: ((NativeReaderNode, NativeReaderTextRenderKey) -> NativeReaderPreparedTextObject?)?
    private(set) var textMap: NativeReaderTextMap?
    private(set) var renderKey: NativeReaderTextRenderKey?
    private(set) var context: NativeReaderRequestContext?
    private(set) var textAppearance = NativeReaderTextAppearance()
    private(set) var isDisposed = false
    private(set) var accessibilityNodes: [NativeReaderAXElement] = []
    private(set) var focusedNodeID: String?
    private(set) var lastFailure: String?
    private(set) var layoutGeneration = 0
    private var suppressSelection = false
    private var isCancelled = false
    private var dragAnchor: Int?
    private var dragMoved = false
    private var sourcePending: (request: NativeReaderSourceRequest, serial: Int)?
    private var operationSerial = 0
    private var objectPaints = Set<String>()
    private var objectIDs = Set<String>()
    private var preparedObjects: [String: NativeReaderPreparedTextObject] = [:]
    private var objectRanges = [String: NSRange]()
    private var attachmentNodes = [NativeReaderNode]()
    typealias LazyObjectProvider = ([NativeReaderNode], NativeReaderTextRenderKey) async throws -> [String: NativeReaderPreparedTextObject]
    private var lazyProvider: LazyObjectProvider?
    // The disk-cache owner uses viewport preparation even for small documents.
    var preparesViewedWindowsOnly = false
    var lazyRetryDelay: (Int) async throws -> Void = { failure in
        try await Task.sleep(nanoseconds: UInt64(failure) * 50_000_000)
    }
    private var lazyCache = NativeReaderLazyObjectCache()
    private(set) var lazyTask: Task<Void, Never>?
    private var lazyEpoch = 0
    private var lazyKey: NativeReaderTextRenderKey?
    private var lazyAttempted = Set<String>()
    private var lazyErrorCounts = [String: Int]()
    private var lazyViewportIDs = Set<String>()
    private var lazyVisibleIDs = Set<String>()
    private var viewportObserver: NSObjectProtocol?
    private var designObserver: NSObjectProtocol?
    var preparedObjectCost: Int { lazyCache.cost }
    var preparedObjectIDs: Set<String> { Set(lazyCache.objects.keys) }
    var viewedWindowMathLayouts: [String: NativeMathLayout] {
        let objects = lazyKey == nil ? preparedObjects : lazyCache.objects.filter { lazyViewportIDs.contains($0.key) }
        return objects.values.reduce(into: [:]) { result, object in
            result.merge(object.mathLayouts) { _, new in new }
        }
    }
    var viewedWindowBlockIDs: Set<String> {
        Set(store.document?.blocks.filter { block in
            block.orderedNodes.contains { lazyViewportIDs.contains($0.id) }
        }.map(\.id) ?? [])
    }

    private var paintedKey: NativeReaderTextRenderKey?
    private var pendingViewportAnchor: NativeReaderViewportAnchor?
    private var pendingSelectionAffinity: NSSelectionAffinity?
    private var pendingCaret: NativeReaderTextPosition?
    private var returningAnchor: NativeReaderViewportAnchor?
    private var reviewSelections = [NativeReaderSelection]()
    var canReturnFromReference: Bool { returningAnchor != nil && renderKey != nil && renderKey == requestedRenderKey }
    func setReviewSelections(_ values: [NativeReaderSelection]) throws {
        guard !isDisposed else { throw NativeReaderContractError.disposed }
        if !values.isEmpty {
            guard let document = store.document else { throw NativeReaderContractError.invalidDocument }
            for value in values { try value.validateLocal(in: document) }
        }
        reviewSelections = values; bodyTextView.needsDisplay = true
    }
    fileprivate func paintLocalReview(in dirty: NSRect) {
        guard !isDisposed, !isCancelled, let key = renderKey, key == requestedRenderKey else { return }
        designPalette.reviewInk.setStroke()
        for selection in reviewSelections {
            for fragment in selection.fragments {
                for rect in reviewStrikeSegments(blockID: fragment.blockID, logical: fragment.rangeUTF16) where rect.insetBy(dx: -0.65, dy: -0.65).intersects(dirty) {
                    let line = NSBezierPath(); line.lineWidth = 1.3; line.lineCapStyle = .round
                    line.move(to: NSPoint(x: rect.minX, y: rect.midY)); line.line(to: NSPoint(x: rect.maxX, y: rect.midY)); line.stroke()
                }
            }
        }
    }
    /// Renderer-owned normalized viewport and logical selection; storage retains
    /// its independent 32-fragment/0.5–4 validation, never truncating display state.
    func captureViewport() throws -> (blockID: String?, offset: Double) {
        guard store.document != nil, renderKey != nil, renderKey == requestedRenderKey else { throw NativeReaderTextFailure.staleGeometry }
        let maximum = max(0, bodyTextView.bounds.height - scrollView.contentView.bounds.height)
        return (viewportAnchor()?.position.blockID,
            maximum > 0 ? min(1, max(0, Double(scrollView.contentView.bounds.minY / maximum))) : 0)
    }
    func restorePresentation(offset: Double) throws {
        guard store.document != nil, renderKey != nil, renderKey == requestedRenderKey, let map = textMap,
              offset.isFinite, (0...1).contains(offset) else { throw NativeReaderTextFailure.staleGeometry }
        if let first = store.selection?.fragments.first, let last = store.selection?.fragments.last {
            let start = try map.presentation(of: .init(blockID: first.blockID, utf16: first.rangeUTF16.lowerBound, affinity: .upstream))
            let end = try map.presentation(of: .init(blockID: last.blockID, utf16: last.rangeUTF16.upperBound, affinity: .downstream))
            suppressSelection = true; bodyTextView.setSelectedRange(NSRange(location: start, length: end-start)); suppressSelection = false
        }
        let maximum = max(0, bodyTextView.bounds.height - scrollView.contentView.bounds.height)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: maximum * CGFloat(offset)))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        prepareVisibleObjects()
    }
    func restoreReadingPosition(blockID: String?, offset: Double) throws {
        try restorePresentation(offset: offset)
        if let blockID, viewportAnchor()?.position.blockID != blockID, let identity = renderKey?.identity {
            restoreViewport(.init(identity: identity,
                position: .init(blockID: blockID, utf16: 0, affinity: .downstream), offsetY: 0))
        }
    }
    var logicalText: String { store.document?.blocks.map(\.displayText).joined(separator: "\n") ?? "" }
    /// Read-only current selection geometry, clipped to the actual native viewport.
    /// No selection, source, layout or content authority is changed by this query.
    func visibleSelectionRects(in view: NSView) -> [NSRect] {
        guard !isDisposed, !isCancelled, renderKey != nil, renderKey == requestedRenderKey,
              let selection = store.selection else { return [] }
        let visible = bodyTextView.visibleRect
        return selection.fragments.flatMap { fragment in
            rects(blockID: fragment.blockID, logical: fragment.rangeUTF16).compactMap { rect in
                let clipped = rect.intersection(visible)
                return clipped.isEmpty ? nil : bodyTextView.convert(clipped, to: view)
            }
        }
    }

    /// Conservative actual TextKit used bounds, including attachments, clipped
    /// to the visible viewport. nil means geometry cannot establish empty space.
    /// This query does not alter rendering, selection or source authority.
    func visibleUsedContentBounds(in view: NSView) -> NSRect? {
        guard !isDisposed, !isCancelled, renderKey != nil, renderKey == requestedRenderKey,
              let manager = bodyTextView.layoutManager, let container = bodyTextView.textContainer else { return nil }
        let used = manager.usedRect(for: container).offsetBy(dx: bodyTextView.textContainerOrigin.x,
                                                           dy: bodyTextView.textContainerOrigin.y)
        let clipped = used.intersection(bodyTextView.visibleRect)
        return clipped.isEmpty ? .zero : bodyTextView.convert(clipped, to: view)
    }

    var plainSelectedText: String? { store.selection?.fragments.map(\.exact).joined(separator: "\n") }
    var outline: [NativeReaderNode] { store.document?.blocks.flatMap(\.orderedNodes).filter { $0.kind == .heading && $0.visible } ?? [] }

    init(store: NativeReaderDocumentStore, callbacks: NativeReaderTextCallbacks = .init()) {
        self.store = store
        self.callbacks = callbacks
        super.init(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        scrollView.reader = self
        scrollView.findBarPosition = .aboveHorizontalRuler
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        bodyTextView.reader = self
        bodyTextView.delegate = self
        bodyTextView.usesFindPanel = false
        bodyTextView.usesFindBar = true
        bodyTextView.isIncrementalSearchingEnabled = false
        bodyTextView.isEditable = false
        bodyTextView.isSelectable = true
        bodyTextView.isRichText = true
        bodyTextView.importsGraphics = false
        bodyTextView.isAutomaticLinkDetectionEnabled = false
        bodyTextView.isAutomaticTextReplacementEnabled = false
        bodyTextView.allowsUndo = false
        bodyTextView.isVerticallyResizable = true
        bodyTextView.isHorizontallyResizable = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 24, left: 0, bottom: 104, right: 0)
        applyPaperAppearance()
        bodyTextView.textContainer?.lineFragmentPadding = 0
        // layoutFrames owns the centered measure, including odd viewport widths.
        bodyTextView.textContainer?.widthTracksTextView = false
        bodyTextView.setAccessibilityLabel("Reader body")
        scrollView.contentView.postsBoundsChangedNotifications = true
        viewportObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.prepareVisibleObjects(); self?.callbacks.readingPositionChanged()
            }
        }
        designObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isDisposed else { return }
                self.applyPaperAppearance(); self.reflow(restoring: self.viewportAnchor())
            }
        }
        scrollView.documentView = bodyTextView
        addSubview(scrollView)
        statusLabel.isHidden = true
        addSubview(statusLabel)
        setAccessibilityElement(false)
        layoutFrames()
    }
    required init?(coder: NSCoder) { fatalError("Programmatic native reader only") }
    override var isFlipped: Bool { true }
    override func setFrameSize(_ newSize: NSSize) {
        guard newSize.width.isFinite, newSize.height.isFinite, (64...100000).contains(newSize.width), (32...100000).contains(newSize.height) else { return }
        let changed = frame.size != newSize
        let anchor = viewportAnchor()
        super.setFrameSize(newSize)
        layoutFrames()
        if changed, store.document != nil { reflow(restoring: anchor) }
    }
    // NSWindow's view key-equivalent traversal reaches this container even while
    // the embedded search field/field editor, rather than the body, has focus.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handleFindKeyEquivalent(event) { return true }
        return super.performKeyEquivalent(with: event)
    }
    override func cancelOperation(_ sender: Any?) {
        if !hideFindBar() { super.cancelOperation(sender) }
    }
    func canPerformFind(tag: Int? = nil) -> Bool {
        guard !isDisposed, !isCancelled, !isHiddenOrHasHiddenAncestor, renderKey != nil else { return false }
        guard let tag else { return true }
        guard let action = NSTextFinder.Action(rawValue: tag) else { return false }
        return [.showFindInterface, .hideFindInterface, .nextMatch, .previousMatch].contains(action)
    }
    @discardableResult func handleFindKeyEquivalent(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .control, .option])
        let character = event.charactersIgnoringModifiers?.lowercased()
        let isAscii = character?.first?.isASCII == true
        if modifiers == .command && (character == "f" || (!isAscii && event.keyCode == 3)) { return performFindAction(.showFindInterface) }
        if (character == "g" || (!isAscii && event.keyCode == 5)), modifiers == .command || modifiers == [.command, .shift] {
            return performFindAction(modifiers.contains(.shift) ? .previousMatch : .nextMatch)
        }
        if event.keyCode == 53 && modifiers.isEmpty { return hideFindBar() }
        return false
    }
    @discardableResult func performFindAction(_ action: NSTextFinder.Action) -> Bool {
        guard canPerformFind(tag: action.rawValue) else { return false }
        bodyTextView.performNativeFindAction(action)
        prepareVisibleObjects()
        return true
    }
    @discardableResult func hideFindBar() -> Bool {
        guard scrollView.isFindBarVisible, performFindAction(.hideFindInterface) else { return false }
        // This is a user-requested responder change inside the existing window;
        // the view never creates, shows, activates or orders a window/panel.
        bodyTextView.window?.makeFirstResponder(bodyTextView)
        bodyFocused()
        return true
    }
    fileprivate func findBarVisibilityChanged() {
        guard !isDisposed, !isCancelled, store.document != nil else { return }
        let anchor = viewportAnchor()
        scrollView.tile()
        layoutFrames()
        reflow(restoring: anchor)
    }
    private func layoutFrames() {
        let statusHeight: CGFloat = statusLabel.isHidden ? 0 : 42
        scrollView.frame = NSRect(x: 0, y: statusHeight, width: max(64, bounds.width), height: max(32, bounds.height - statusHeight))
        statusLabel.frame = NSRect(x: 8, y: 0, width: max(48, bounds.width - 16), height: statusHeight)
        bodyTextView.setFrameSize(NSSize(width: scrollView.contentSize.width, height: max(bodyTextView.frame.height, max(32, scrollView.contentSize.height))))
        let available = bodyTextView.bounds.width
        let targetMeasure = min(720, max(680, textAppearance.effectiveSize * 45))
        let minSidePadding: CGFloat = available <= 640 ? 20 : 28
        let columnWidth = max(1, min(targetMeasure, available - 2 * minSidePadding))
        let horizontalInset = floor((available - columnWidth) / 2)
        bodyTextView.textContainerInset = NSSize(width: horizontalInset, height: 8)
        bodyTextView.textContainer?.containerSize = NSSize(width: columnWidth, height: .greatestFiniteMagnitude)
    }
    private func key(for document: NativeReaderDocument) -> NativeReaderTextRenderKey {
        .init(identity: document.identity, documentGeneration: document.generation, viewID: store.viewID,
              layoutGeneration: layoutGeneration, width: ((bodyTextView.textContainer?.containerSize.width ?? 1) * 2).rounded() / 2, appearance: textAppearance)
    }
    // Pure preparation handshake: NA06 can calculate objects off-thread for an
    // incoming candidate before adoption. Failed/missing-cache retries retain
    // this key; width/font/theme/cancel and document revision/generation revoke it.
    // No candidate snapshot is retained here.
    func preparationKey(for document: NativeReaderDocument, context: NativeReaderRequestContext) throws -> NativeReaderTextRenderKey {
        guard !isDisposed else { throw NativeReaderContractError.disposed }
        try document.validate()
        guard context.viewID == store.viewID, context.target == document.identity else { throw NativeReaderContractError.wrongTarget }
        guard context.generation == store.generation, document.generation == store.generation else { throw NativeReaderContractError.staleGeneration }
        return key(for: document)
    }
    /// Retained display authority is independent of the latest transport request.
    /// This never grants source authority or permits a candidate to be adopted.
    func retainedPreparationKey(for document: NativeReaderDocument, context: NativeReaderRequestContext) throws -> NativeReaderTextRenderKey {
        guard !isDisposed, !isCancelled, self.context == context, store.document == document,
              context.viewID == store.viewID, context.target == document.identity,
              context.generation == document.generation else { throw NativeReaderTextFailure.staleGeometry }
        return key(for: document)
    }
    // Adoption remains exclusively in the injected common store. A held candidate
    // is returned to its owner; this view keeps no replacement snapshot database.
    func adopt(_ document: NativeReaderDocument, context: NativeReaderRequestContext) throws {
        guard !isDisposed else { throw NativeReaderContractError.disposed }
        guard store.selection == nil else { throw NativeReaderContractError.selectionHeld }
        let newKey = try preparationKey(for: document, context: context)
        let oldAnchor = store.document?.identity == document.identity ? viewportAnchor() : nil
        do {
            // Composition and metric validation are fallible; keep A's complete
            // publication (including geometry/focus/AX) until B can commit.
            let composition = try compose(document, key: newKey)
            try store.adopt(document, for: context)
            if self.context?.target != document.identity {
                pendingViewportAnchor = nil; pendingCaret = nil
                pendingSelectionAffinity = nil; returningAnchor = nil; focusedNodeID = nil
            }
            returningAnchor = nil; reviewSelections = []
            self.context = context
            cancelLazyPreparation()
            isCancelled = false
            operationSerial += 1
            sourcePending = nil
            install(composition, document: document, key: newKey, anchor: oldAnchor)
        } catch {
            lastFailure = String(describing: error)
            callbacks.statusChanged(lastFailure!)
            throw error
        }
    }
    private struct Composition {
        let text: NSAttributedString
        let spans: [NativeReaderPresentationSpan]
        let objects: [String: NativeReaderPreparedTextObject]
        let objectRanges: [String: NSRange]
    }
    var designPreferences: NativeAppDesign.Preferences {
        var preferences = NativeAppDesign.Preferences.current(appearance: effectiveAppearance)
        preferences.theme = textAppearance.theme == .dark ? .dark : .light
        return preferences
    }
    var designPalette: NativeAppDesign.Palette { NativeAppDesign.palette(designPreferences) }
    private func applyPaperAppearance() {
        let p = designPalette
        scrollView.backgroundColor = p.paper; scrollView.contentView.backgroundColor = p.paper
        bodyTextView.backgroundColor = p.paper; bodyTextView.insertionPointColor = p.accent
        bodyTextView.selectedTextAttributes = [.backgroundColor: p.selection, .foregroundColor: p.ink]
    }
    fileprivate func hoverLink(at point: NSPoint?) {
        guard let key = renderKey, key == requestedRenderKey, let storage = bodyTextView.textStorage,
              let manager = bodyTextView.layoutManager, let container = bodyTextView.textContainer else { return }
        var hovered: String?
        if let point {
            let local = NSPoint(x: point.x - bodyTextView.textContainerOrigin.x, y: point.y - bodyTextView.textContainerOrigin.y)
            let index = manager.characterIndex(for: local, in: container, fractionOfDistanceBetweenInsertionPoints: nil)
            if index < storage.length,
               let id = storage.attribute(nativeReaderLink, at: index, effectiveRange: nil) as? String {
                let glyph = manager.glyphRange(forCharacterRange: NSRange(location: index, length: 1), actualCharacterRange: nil)
                if manager.boundingRect(forGlyphRange: glyph, in: container).contains(local) { hovered = id }
            }
        }
        let p = designPalette
        var runs: [(NSRange, Bool)] = []
        storage.enumerateAttribute(nativeReaderLink, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            if let id = value as? String { runs.append((range, id == hovered)) }
        }
        for (range, active) in runs {
            let underline = active ? p.accentHover : p.accent
            storage.addAttributes([.foregroundColor: active ? p.accentHover : p.accent,
                .underlineColor: underline.withAlphaComponent(designPreferences.increasedContrast ? 1 : (active ? 0.88 : 0.42))], range: range)
        }
        if bodyTextView.window?.isKeyWindow == true {
            if hovered != nil { NSCursor.pointingHand.set() } else { NSCursor.iBeam.set() }
        }
    }
    fileprivate func paintHeadingRules(in dirty: NSRect) {
        guard let storage = bodyTextView.textStorage, let manager = bodyTextView.layoutManager,
              let container = bodyTextView.textContainer else { return }
        designPalette.rule.setFill()
        storage.enumerateAttribute(nativeHeadingRule, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard value != nil, range.length > 0 else { return }
            let glyph = manager.glyphRange(forCharacterRange: NSRange(location: range.location, length: 1), actualCharacterRange: nil)
            let rect = manager.boundingRect(forGlyphRange: glyph, in: container)
            let line = NSRect(x: self.bodyTextView.textContainerOrigin.x, y: self.bodyTextView.textContainerOrigin.y + rect.minY - 14,
                              width: container.containerSize.width, height: 1)
            if line.intersects(dirty) { line.fill() }
        }
    }
    private func compose(_ document: NativeReaderDocument, key: NativeReaderTextRenderKey) throws -> Composition {
        let text = NSMutableAttributedString(string: "")
        var spans: [NativeReaderPresentationSpan] = []
        var objects: [String: NativeReaderPreparedTextObject] = [:]
        var objectRanges = [String: NSRange]()
        let large = preparesViewedWindowsOnly || NativeReaderPreparedTextObject.isLarge(document)
        let p = designPalette
        let foreground = p.ink
        let font = textAppearance.bodyFont()
        let numberFont = textAppearance.tabularFont(size: textAppearance.effectiveSize * 0.87)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = 1.65
        paragraph.paragraphSpacing = textAppearance.effectiveSize * 0.80
        paragraph.hyphenationFactor = 0.0
        let base: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: foreground, .paragraphStyle: paragraph]
        func append(_ node: NativeReaderNode, block: NativeReaderNode, attributes: [NSAttributedString.Key: Any]) throws {
            guard node.visible else { throw NativeReaderTextFailure.unsupportedObject(node.id) }
            var attributes = attributes
            if node.kind == .heading {
                let level = min(6, max(1, node.headingLevel ?? 1))
                let scales: [CGFloat] = [1.80, 1.48, 1.24, 1.08, 1.08, 1.08]
                attributes[.font] = NSFontManager.shared.convert(textAppearance.bodyFont(size: textAppearance.effectiveSize * scales[level - 1]), toHaveTrait: .boldFontMask)
                attributes[.foregroundColor] = level >= 5 ? p.secondaryInk : p.ink
                let style = paragraph.mutableCopy() as! NSMutableParagraphStyle
                style.lineHeightMultiple = [1.25, 1.28, 1.32, 1.38, 1.38, 1.38][level - 1]
                style.paragraphSpacingBefore = textAppearance.effectiveSize * [2.1, 1.85, 1.45, 1.05, 1.05, 1.05][level - 1] + (level == 2 ? 14 : 0)
                style.paragraphSpacing = textAppearance.effectiveSize * [0.65, 0.60, 0.48, 0.40, 0.40, 0.40][level - 1]
                attributes[.paragraphStyle] = style
                if level == 2 { attributes[nativeHeadingRule] = true }
            }
            if node.kind == .strong || node.kind == .emphasis {
                let current = attributes[.font] as? NSFont ?? font
                attributes[.font] = NSFontManager.shared.convert(current, toHaveTrait: node.kind == .strong ? .boldFontMask : .italicFontMask)
            }
            if node.kind == .link {
                // No NSLink attribute: AppKit must never open URLs on our behalf.
                attributes[.foregroundColor] = p.accent
                attributes[nativeReaderLink] = node.id
                attributes[.underlineColor] = p.accent.withAlphaComponent(designPreferences.increasedContrast ? 1 : 0.42)
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            if node.kind == .caption || node.kind == .equationNumber {
                attributes[.foregroundColor] = p.secondaryInk
                attributes[.font] = numberFont
                let style = paragraph.mutableCopy() as! NSMutableParagraphStyle
                style.lineHeightMultiple = 1.50; style.paragraphSpacingBefore = 6; style.paragraphSpacing = 10
                attributes[.paragraphStyle] = style
            }
            if node.kind == .annotation {
                attributes[.backgroundColor] = p.highlight
                if designPreferences.increasedContrast {
                    attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
                    attributes[.underlineColor] = p.highlightEdge
                }
            }
            if node.kind == .break, !node.displayText.contains(where: { $0.isNewline }) {
                text.append(NSAttributedString(string: "\n", attributes: attributes))
                // Importer breaks already carry a canonical newline. Only an
                // empty break needs an additional, unmapped presentation line.
            }
            if let language = node.language { attributes[NSAttributedString.Key(kCTLanguageAttributeName as String)] = language }
            if let direction = node.direction, direction != "auto" {
                let style = (attributes[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
                style.baseWritingDirection = direction == "rtl" ? .rightToLeft : .leftToRight
                attributes[.paragraphStyle] = style
            }
            if [.math, .equation, .table, .figure, .image].contains(node.kind) {
                guard let object = cachedObject?(node, key) ?? (large
                    ? NativeReaderPreparedTextObject.placeholder(node, key: key) : nil) else { throw NativeReaderTextFailure.unsupportedObject(node.id) }
                try validatePreparedObject(object, id: node.id, key: key)
                let blockImage = node.kind == .image && node.imageLayout?.placement == .block
                if blockImage, text.length > 0, !(text.string as NSString).hasSuffix("\n") {
                    text.append(NSAttributedString(string: "\n", attributes: attributes))
                }
                let attachment = NSTextAttachment()
                attachment.attachmentCell = NativeReaderTextObjectCell(object) { [weak self] painted in
                    guard let self = self, self.renderKey == painted else { return }
                    self.objectPaints.insert(node.id)
                }
                let part = NSMutableAttributedString(attachment: attachment)
                part.addAttributes(attributes, range: NSRange(location: 0, length: part.length))
                spans.append(.init(blockID: block.id, logical: node.rangeUTF16[0]..<node.rangeUTF16[1],
                                   presentation: NSRange(location: text.length, length: part.length), isObject: true))
                objectRanges[node.id] = NSRange(location: text.length, length: part.length)
                text.append(part)
                if blockImage { text.append(NSAttributedString(string: "\n", attributes: attributes)) }
                objects[node.id] = object
            } else if node.children.isEmpty {
                let part = NSAttributedString(string: node.displayText, attributes: attributes)
                spans.append(.init(blockID: block.id, logical: node.rangeUTF16[0]..<node.rangeUTF16[1],
                                   presentation: NSRange(location: text.length, length: part.length), isObject: false))
                text.append(part)
            } else {
                func isBlock(_ node: NativeReaderNode) -> Bool {
                    // Span/sup/code also arrive as groups. A group introduces
                    // block boundaries only when it actually contains blocks.
                    if node.kind == .group { return node.children.contains(where: isBlock) }
                    return [.paragraph, .heading, .equation, .table, .figure, .caption].contains(node.kind)
                        || (node.kind == .image && node.imageLayout?.placement == .block)
                }
                var previousWasBlock = false
                var previousWasBreak = false
                for (index, child) in node.children.enumerated() {
                    let childIsBlock = isBlock(child)
                    if node.kind == .group, index > 0, child.kind != .break, !previousWasBreak, previousWasBlock || childIsBlock,
                       !(text.string as NSString).hasSuffix("\n") {
                        text.append(NSAttributedString(string: "\n", attributes: base))
                    }
                    try append(child, block: block, attributes: attributes)
                    previousWasBlock = childIsBlock
                    previousWasBreak = child.kind == .break
                }
            }
        }
        for (index, block) in document.blocks.enumerated() {
            if index > 0 { text.append(NSAttributedString(string: "\n", attributes: base)) }
            try append(block, block: block, attributes: base)
        }
        return Composition(text: text, spans: spans, objects: objects, objectRanges: objectRanges)
    }
    private func install(_ composition: Composition, document: NativeReaderDocument, key: NativeReaderTextRenderKey,
                         anchor: NativeReaderViewportAnchor?) {
        let selectionAffinity = pendingSelectionAffinity ?? bodyTextView.selectionAffinity
        let caret = pendingCaret ?? (store.selection == nil && textMap?.document.identity == document.identity
            ? try? textMap?.logical(at: bodyTextView.selectedRange().location, affinity: selectionAffinity) : nil)
        suppressSelection = true
        renderKey = key
        paintedKey = nil
        objectIDs = Set(composition.objects.keys)
        objectPaints.removeAll()
        preparedObjects = composition.objects
        objectRanges = composition.objectRanges
        attachmentNodes = NativeReaderPreparedTextObject.attachmentNodes(in: document)
        textMap = .init(document: document, spans: composition.spans, length: composition.text.length)
        bodyTextView.textStorage?.setAttributedString(composition.text)
        bodyTextView.appearance = NSAppearance(named: textAppearance.theme == .dark ? .darkAqua : .aqua)
        applyPaperAppearance()
        bodyTextView.window?.invalidateCursorRects(for: bodyTextView)
        if let selection = store.selection, let first = selection.fragments.first, let last = selection.fragments.last,
           let start = try? textMap?.presentation(of: .init(blockID: first.blockID, utf16: first.rangeUTF16.lowerBound, affinity: .upstream)),
           let end = try? textMap?.presentation(of: .init(blockID: last.blockID, utf16: last.rangeUTF16.upperBound, affinity: .downstream)) {
            bodyTextView.setSelectedRange(NSRange(location: start, length: end - start), affinity: selectionAffinity, stillSelecting: false)
        } else if let caret = caret, let offset = try? textMap?.presentation(of: caret) {
            bodyTextView.setSelectedRange(NSRange(location: offset, length: 0), affinity: selectionAffinity, stillSelecting: false)
        } else { bodyTextView.setSelectedRange(NSRange(location: 0, length: 0)) }
        suppressSelection = false
        bodyTextView.layoutManager?.ensureLayout(for: bodyTextView.textContainer!)
        bodyTextView.sizeToFit()
        accessibilityNodes = document.blocks.map { NativeReaderAXElement(node: $0, blockID: $0.id, reader: self, parent: bodyTextView, key: key) }
        clearFailure()
        if let anchor = anchor { restoreViewport(anchor) }
        pendingViewportAnchor = nil
        pendingCaret = nil
        pendingSelectionAffinity = nil
        bodyTextView.needsDisplay = true
    }
    func setAppearance(_ value: NativeReaderTextAppearance) throws {
        guard !isDisposed else { throw NativeReaderContractError.disposed }
        guard value.fontSize.isFinite, value.zoom.isFinite, (8...96).contains(value.fontSize), (0.25...4).contains(value.zoom) else { throw NativeReaderTextFailure.invalidGeometry }
        guard value.fontName == "system" || NSFont(name: value.fontName, size: value.effectiveSize)?.fontName == value.fontName else { throw NativeReaderTextFailure.invalidGeometry }
        guard value != textAppearance else { return }
        let anchor = viewportAnchor()
        textAppearance = value
        layoutFrames()
        reflow(restoring: anchor)
    }
    func changeZoom(by factor: CGFloat) {
        var value = textAppearance
        value.zoom = min(4, max(0.25, value.zoom * factor))
        do { try setAppearance(value) } catch { showFailure(error) }
    }
    private func reflow(restoring anchor: NativeReaderViewportAnchor?) {
        guard let document = store.document, !isDisposed, !isCancelled else { return }
        pendingViewportAnchor = anchor ?? pendingViewportAnchor
        if pendingSelectionAffinity == nil { pendingSelectionAffinity = bodyTextView.selectionAffinity }
        if pendingCaret == nil, store.selection == nil {
            pendingCaret = try? textMap?.logical(at: bodyTextView.selectedRange().location, affinity: bodyTextView.selectionAffinity)
        }
        cancelLazyPreparation()
        layoutGeneration += 1
        do {
            let key = key(for: document)
            install(try compose(document, key: key), document: document, key: key, anchor: pendingViewportAnchor)
            callbacks.layoutChanged()
        } catch {
            // Keep the retained text/map/AX/selection while current-key objects
            // are prepared. Geometry/draw receipts are separately revoked below.
            showFailure(error)
        }
    }
    // Off-thread preparation completion calls this on main; only this exact key
    // may be retried. It does not adopt a document or start object preparation.
    func refreshPreparedObjects(for expected: NativeReaderTextRenderKey) throws {
        guard !isDisposed, !isCancelled, let document = store.document, key(for: document) == expected else { throw NativeReaderTextFailure.staleGeometry }
        install(try compose(document, key: expected), document: document, key: expected, anchor: pendingViewportAnchor ?? viewportAnchor())
    }
    var requestedRenderKey: NativeReaderTextRenderKey? { isDisposed || isCancelled ? nil : store.document.map { key(for: $0) } }
    private func cancelLazyTask() {
        lazyEpoch += 1; lazyTask?.cancel(); lazyTask = nil
    }
    func cancelLazyPreparation() {
        cancelLazyTask()
        lazyProvider = nil; lazyKey = nil
        lazyAttempted = []; lazyErrorCounts = [:]; lazyViewportIDs = []
        lazyVisibleIDs = []
        lazyCache = NativeReaderLazyObjectCache()
    }
    func invalidateStaleLazyPreparation() {
        // Transport generations do not revoke the retained presentation. Only
        // adoption or changed layout/lifetime inputs revoke these prepared pixels.
        if let key = lazyKey, key != renderKey || key != requestedRenderKey { cancelLazyPreparation() }
    }
    func configureLazyObjects(key: NativeReaderTextRenderKey, initial: [String: NativeReaderPreparedTextObject],
                              prepare: @escaping LazyObjectProvider) {
        let cache = NativeReaderLazyObjectCache()
        do {
            for (id, object) in initial { try validatePreparedObject(object, id: id, key: key) }
            cache.insert(initial, protecting: [])
            try updateObjectAttachments(for: key, objects: cache.objects)
        } catch { return }
        cancelLazyPreparation()
        lazyCache = cache
        lazyKey = key; lazyProvider = prepare
        prepareVisibleObjects()
    }
    func cachedLazyObject(_ id: String, key: NativeReaderTextRenderKey) -> NativeReaderPreparedTextObject? {
        guard key == lazyKey else { return nil }
        return lazyCache.objects[id]
    }
    func prepareVisibleObjects() {
        guard !suppressSelection else { return }
        invalidateStaleLazyPreparation()
        guard let key = lazyKey, key == renderKey, key == requestedRenderKey,
              !isDisposed, !isCancelled, !isHiddenOrHasHiddenAncestor, store.document != nil,
              let provider = lazyProvider, let manager = bodyTextView.layoutManager,
              let container = bodyTextView.textContainer else { return }
        let visible = scrollView.contentView.bounds
        let buffer = visible.insetBy(dx: 0, dy: -visible.height)
        func characters(in rect: NSRect) -> NSRange {
            let origin = bodyTextView.textContainerOrigin
            let glyphs = manager.glyphRange(forBoundingRect: rect.offsetBy(dx: -origin.x, dy: -origin.y), in: container)
            return manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        }
        let visibleRange = characters(in: visible), bufferRange = characters(in: buffer)
        var visibleIDs = Set<String>()
        let nearby = attachmentNodes.filter { node in
            guard let range = objectRanges[node.id] else { return false }
            if NSIntersectionRange(range, visibleRange).length > 0 { visibleIDs.insert(node.id) }
            return NSIntersectionRange(range, bufferRange).length > 0
        }
        let ids = Set(nearby.map(\.id))
        lazyVisibleIDs = visibleIDs
        if ids != lazyViewportIDs {
            lazyViewportIDs = ids; lazyAttempted = []; lazyErrorCounts = [:]
            cancelLazyTask()
        }
        lazyCache.touch(ids)
        lazyCache.touch(visibleIDs)
        guard lazyTask == nil else { return }
        let candidates = nearby.filter { lazyCache.objects[$0.id] == nil && !lazyAttempted.contains($0.id) }
        let missing = Array((candidates.filter { visibleIDs.contains($0.id) } + candidates.filter { !visibleIDs.contains($0.id) })
            .prefix(NativeReaderPreparedTextObject.largeDocumentThreshold))
        guard !missing.isEmpty else { return }
        lazyAttempted.formUnion(missing.map(\.id))
        let epoch = lazyEpoch
        let isolatingTimeout = missing.contains { (lazyErrorCounts[$0.id] ?? 0) >= 2 }
        lazyTask = Task { [weak self] in
            var providerReturned = false
            do {
                let result = try await NativeReaderPreparedTextObject.prepareLazy(missing,
                    provider: { try await provider($0, key) }, isolatingTimeout: isolatingTimeout)
                let values = result.objects
                providerReturned = true
                try Task.checkCancellation()
                guard let self, self.lazyEpoch == epoch, self.lazyKey == key,
                      self.renderKey == key, self.requestedRenderKey == key,
                      !self.isDisposed, !self.isCancelled else { return }
                // Validate the entire response, including entries the budget
                // would omit. Stage LRU eviction until every replacement and
                // evicted placeholder has also passed attachment validation.
                for (id, object) in values { try self.validatePreparedObject(object, id: id, key: key) }
                let staged = self.lazyCache.copy()
                staged.insert(values, protecting: self.lazyVisibleIDs)
                let previousIDs = Set(self.lazyCache.objects.keys)
                let currentIDs = Set(staged.objects.keys)
                let changedIDs = previousIDs.symmetricDifference(currentIDs).union(currentIDs.intersection(values.keys))
                try self.updateObjectAttachments(for: key, objects: staged.objects, changedIDs: changedIDs)
                self.lazyCache = staged
                // Retry omissions, but retain attempted IDs for isolated failures
                // and returned-but-unadmitted objects to bound an overfull viewport.
                if !values.isEmpty {
                    self.lazyAttempted.subtract(Set(missing.map(\.id)).subtracting(values.keys).subtracting(result.failures))
                }
                self.lazyTask = nil
                self.callbacks.readingPositionChanged()
                self.prepareVisibleObjects()
            } catch {
                guard let self, self.lazyEpoch == epoch else { return }
                switch error {
                case is CancellationError, NativeReaderTextFailure.staleGeometry:
                    self.lazyTask = nil
                    return
                case let failure as NativeObjectError where failure.classification.scope == .obsolete:
                    self.lazyTask = nil
                    return
                default: break
                }
                if !Task.isCancelled {
                    // Initial attempt plus at most two retries per ID in this
                    // viewport epoch. The last attempt isolates timeout leaves;
                    // other exhausted errors stay placeholders until epoch reset.
                    // Invalid returned results are never retryable.
                    if !providerReturned {
                        for node in missing {
                            let errors = (self.lazyErrorCounts[node.id] ?? 0) + 1
                            self.lazyErrorCounts[node.id] = errors
                            if errors <= 2 { self.lazyAttempted.remove(node.id) }
                        }
                    }
                    let failures = missing.map { self.lazyErrorCounts[$0.id] ?? 3 }.max() ?? 3
                    if !providerReturned && failures <= 2 {
                        do { try await self.lazyRetryDelay(failures); try Task.checkCancellation() }
                        catch { if self.lazyEpoch == epoch { self.lazyTask = nil }; return }
                    }
                    guard self.lazyEpoch == epoch, self.lazyKey == key, !Task.isCancelled else { return }
                    self.lazyTask = nil
                    self.prepareVisibleObjects()
                } else { self.lazyTask = nil }
            }
        }
    }
    private func validatePreparedObject(_ object: NativeReaderPreparedTextObject, id: String,
                                        key: NativeReaderTextRenderKey) throws {
        guard object.key == key, object.size.width.isFinite, object.size.height.isFinite,
              object.size.width > 0, object.size.width <= key.width, object.size.height > 0,
              object.size.height <= 100000, object.baseline.isFinite, object.baseline >= 0,
              object.baseline <= object.size.height, !object.accessibilityLabel.isEmpty,
              object.cost >= 0 else {
            throw NativeReaderTextFailure.invalidObject(id)
        }
    }
    // No attributed-string replacement or finder reset: only attachment cells
    // and their metrics change, preserving ranges, logical map and find state.
    func updateObjectAttachments(for key: NativeReaderTextRenderKey,
                                 objects: [String: NativeReaderPreparedTextObject], changedIDs: Set<String>? = nil) throws {
        guard key == renderKey, key == requestedRenderKey, !isDisposed, !isCancelled,
              let storage = bodyTextView.textStorage,
              let manager = bodyTextView.layoutManager else { throw NativeReaderTextFailure.staleGeometry }
        if let changedIDs, changedIDs.isEmpty { return }
        let updates = try attachmentNodes.filter { changedIDs == nil || changedIDs!.contains($0.id) }.map { node in
            let object = objects[node.id] ?? NativeReaderPreparedTextObject.placeholder(node, key: key)
            try validatePreparedObject(object, id: node.id, key: key)
            return (node, object)
        }
        let anchor = viewportAnchor(), origin = scrollView.contentView.bounds.origin
        let selections = bodyTextView.selectedRanges, affinity = bodyTextView.selectionAffinity
        suppressSelection = true
        defer { suppressSelection = false }
        // Reflow only newly prepared or evicted cells. Replacing every retained
        // cell would invalidate the whole prepared window on each small batch.
        for (node, object) in updates {
            if preparedObjects[node.id]?.isPlaceholder == true && object.isPlaceholder { continue }
            guard let range = objectRanges[node.id],
                  range.length > 0, let attachment = storage.attribute(.attachment, at: range.location, effectiveRange: nil) as? NSTextAttachment else { continue }
            attachment.attachmentCell = NativeReaderTextObjectCell(object) { [weak self] painted in
                guard let self, self.renderKey == painted else { return }; self.objectPaints.insert(node.id)
            }
            preparedObjects[node.id] = object
            manager.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
            manager.invalidateDisplay(forCharacterRange: range)
        }
        bodyTextView.layoutManager?.ensureLayout(for: bodyTextView.textContainer!)
        bodyTextView.sizeToFit()
        bodyTextView.setSelectedRanges(selections, affinity: affinity, stillSelecting: false)
        if let anchor { restoreViewport(anchor) }
        else { scrollView.contentView.scroll(to: origin); scrollView.reflectScrolledClipView(scrollView.contentView) }
        bodyTextView.needsDisplay = true
    }
    func textViewDidChangeSelection(_ notification: Notification) { bodySelectionChanged() }
    func bodySelectionChanged() {
        guard !suppressSelection, !isDisposed, !isCancelled, renderKey != nil, let map = textMap else { return }
        do {
            let normalized = try map.normalized(bodyTextView.selectedRange(), affinity: bodyTextView.selectionAffinity)
            if normalized != bodyTextView.selectedRange() {
                suppressSelection = true
                bodyTextView.setSelectedRange(normalized, affinity: bodyTextView.selectionAffinity, stillSelecting: false)
                suppressSelection = false
            }
            let selection = try map.selection(for: bodyTextView.selectedRange())
            if let selection = selection {
                if store.selection?.fragments == selection.fragments { return }
                try store.holdSelection(selection)
                operationSerial += 1
                sourcePending = nil
                callbacks.selectionChanged(selection)
            } else if let ticket = store.selection?.ticket {
                releaseSelection(ticket: ticket)
            }
        } catch { showFailure(error) }
    }
    func releaseSelection(ticket: UUID) {
        guard !isDisposed, store.selection?.ticket == ticket else { return }
        store.releaseSelection(ticket: ticket)
        sourcePending = nil
        operationSerial += 1
        suppressSelection = true
        bodyTextView.setSelectedRange(NSRange(location: bodyTextView.selectedRange().location, length: 0))
        suppressSelection = false
        callbacks.selectionChanged(nil)
        callbacks.selectionReleased(ticket)
    }
    @discardableResult func copyPlainText() -> Bool {
        guard !isDisposed, !isCancelled, let text = plainSelectedText else { return false }
        return callbacks.copyText(text)
    }
    @discardableResult func requestSource(_ action: NativeReaderSourceAction) -> NativeReaderSourceRequest? {
        guard !isDisposed, !isCancelled, let selection = store.selection, let context = context, context.generation == store.generation else { return nil }
        guard let document = store.document, (try? selection.validate(in: document)) != nil else {
            showStatus("Source actions support at most 32 selected blocks; the full display selection is retained.")
            return nil
        }
        let request = NativeReaderSourceRequest(context: context, selection: selection, action: action, receiptID: UUID())
        operationSerial += 1
        sourcePending = (request, operationSerial)
        callbacks.sourceRequested(request)
        return request
    }
    // Echo fields bind local correlation only. The injected source owner must
    // verify actual server freshness/authority before producing .verified.
    @discardableResult func acceptSourceResult(_ result: NativeReaderSourceResult, for request: NativeReaderSourceRequest) -> Bool {
        guard !isDisposed, let pending = sourcePending, pending.serial == operationSerial,
              pending.request.receiptID == request.receiptID, result.context == context,
              result.context == request.context, result.context.generation == store.generation,
              result.selectionTicket == request.selection.ticket, store.selection?.ticket == result.selectionTicket else { return false }
        sourcePending = nil
        guard result.status == .verified else { showStatus("Source: \(result.status)"); return false }
        if request.action == .excerpt {
            guard let text = result.verifiedText else { showStatus("Source: rejected"); return false }
            guard callbacks.copyText(text) else { showStatus("Copy unavailable"); return false }
        }
        clearFailure()
        return true
    }
    func openChat() {
        guard !isDisposed, !isCancelled, let selection = store.selection, let context = context, context.generation == store.generation else { return }
        guard let document = store.document, (try? selection.validate(in: document)) != nil else {
            showStatus("Chat actions support at most 32 selected blocks; the full display selection is retained.")
            return
        }
        callbacks.chatRequested(.open(selection), context)
    }
    func cancel() {
        cancelLazyPreparation()
        // This store is bound to this viewID, not the shared service. Revoke the
        // common adoption generation before any late presenter callback arrives.
        store.cancel()
        isCancelled = true
        if scrollView.isFindBarVisible { bodyTextView.performNativeFindAction(.hideFindInterface) }
        operationSerial += 1
        sourcePending = nil
        layoutGeneration += 1
        renderKey = nil
        paintedKey = nil
        focusedNodeID = nil
        dragAnchor = nil
        pendingViewportAnchor = nil
        pendingCaret = nil
        pendingSelectionAffinity = nil
    }
    func dispose() {
        guard !isDisposed else { return }
        if let ticket = store.selection?.ticket { releaseSelection(ticket: ticket) }
        cancel()
        isDisposed = true
        bodyTextView.reader = nil
        bodyTextView.delegate = nil
        bodyTextView.isSelectable = false
        accessibilityNodes = []
        callbacks = .init()
        cachedObject = nil
        if let viewportObserver { NotificationCenter.default.removeObserver(viewportObserver) }
        viewportObserver = nil
        if let designObserver { NSWorkspace.shared.notificationCenter.removeObserver(designObserver) }
        designObserver = nil
        preparedObjects = [:]; attachmentNodes = []; objectRanges = [:]
        lazyCache = NativeReaderLazyObjectCache()
    }
    private func showFailure(_ error: Error) { showStatus(String(describing: error)) }
    private func showStatus(_ message: String) {
        lastFailure = message
        statusLabel.stringValue = message
        statusLabel.isHidden = false
        layoutFrames()
        callbacks.statusChanged(message)
    }
    private func clearFailure() {
        lastFailure = nil
        statusLabel.stringValue = ""
        statusLabel.isHidden = true
        layoutFrames()
    }
    fileprivate func beginBodyDraw() { objectPaints.removeAll() }
    fileprivate func endBodyDraw(key: NativeReaderTextRenderKey, dirtyRect: NSRect) {
        guard !isDisposed, key == renderKey, key == requestedRenderKey, paintedKey != key, let manager = bodyTextView.layoutManager,
              let container = bodyTextView.textContainer else { return }
        let origin = bodyTextView.textContainerOrigin
        let used = manager.usedRect(for: container).offsetBy(dx: origin.x, dy: origin.y)
        let visibleContent = used.isEmpty ? bodyTextView.visibleRect : used.intersection(bodyTextView.visibleRect)
        guard !visibleContent.isEmpty, dirtyRect.contains(visibleContent) else { return }
        let visibleGlyphs = manager.glyphRange(forBoundingRect: visibleContent.offsetBy(dx: -origin.x, dy: -origin.y), in: container)
        let visibleChars = manager.characterRange(forGlyphRange: visibleGlyphs, actualGlyphRange: nil)
        let visibleObjects = objectIDs.filter { id in
            guard let range = objectRanges[id] else { return true }
            guard NSIntersectionRange(range, visibleChars).length > 0 else { return false }
            var intersects = false
            let glyphs = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            manager.enumerateEnclosingRects(forGlyphRange: glyphs, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                                            in: container) { rect, stop in
                if rect.offsetBy(dx: origin.x, dy: origin.y).intersects(visibleContent) {
                    intersects = true
                    stop.pointee = true
                }
            }
            return intersects
        }
        guard Set(visibleObjects).isSubset(of: objectPaints) else { return }
        paintedKey = key
        callbacks.painted(key)
    }
}

extension NativeReaderTextView {
    func validateGeometry(_ geometry: NativeReaderTextGeometry) throws {
        guard !isDisposed, renderKey == geometry.key, geometry.key == requestedRenderKey else { throw NativeReaderTextFailure.staleGeometry }
        guard geometry.rect.origin.x.isFinite, geometry.rect.origin.y.isFinite,
              geometry.rect.size.width.isFinite, geometry.rect.size.height.isFinite,
              geometry.rect.size.width >= 0, geometry.rect.size.height > 0 else { throw NativeReaderTextFailure.invalidGeometry }
        guard try textMap?.snapped(geometry.position) == geometry.position else { throw NativeReaderContractError.invalidSelection }
    }
    func caretGeometry(at position: NativeReaderTextPosition) throws -> NativeReaderTextGeometry {
        guard !isDisposed, let map = textMap, let key = renderKey, key == requestedRenderKey,
              let manager = bodyTextView.layoutManager, let container = bodyTextView.textContainer else { throw NativeReaderTextFailure.staleGeometry }
        let position = try map.snapped(position)
        let index = try map.presentation(of: position)
        manager.ensureLayout(for: container)
        if manager.numberOfGlyphs == 0 {
            let font = textAppearance.bodyFont()
            return .init(key: key, position: position, rect: NSRect(origin: bodyTextView.textContainerOrigin,
                size: NSSize(width: 1, height: ceil(font.ascender - font.descender + font.leading))))
        }
        // At soft wraps and bidi transitions an offset can have two visual
        // carets. Affinity chooses the logical side; the geometry token preserves
        // that disambiguator for reverse coordinate operations.
        let anchor = position.affinity == .upstream && index > 0 ? index - 1 : min(index, max(0, map.length - 1))
        let glyph = manager.glyphIndexForCharacter(at: anchor)
        let line = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let origin = bodyTextView.textContainerOrigin
        let points = nativeReaderInsertionPoints(manager, character: anchor).filter { $0.presentationUTF16 == index }
        let chosen = points.first(where: { $0.alternate == (position.affinity == .upstream) }) ?? points.first
        let x = chosen?.x ?? manager.location(forGlyphAt: glyph).x
        let rect = NSRect(x: origin.x + line.minX + x, y: origin.y + line.minY, width: 1, height: max(1, line.height))
        return .init(key: key, position: position, rect: rect)
    }
    func hitTestText(at point: NSPoint, key: NativeReaderTextRenderKey, affinity: NSSelectionAffinity = .downstream) throws -> NativeReaderTextPosition {
        guard !isDisposed, key == renderKey, key == requestedRenderKey, let map = textMap,
              let manager = bodyTextView.layoutManager, let container = bodyTextView.textContainer else { throw NativeReaderTextFailure.staleGeometry }
        guard point.x.isFinite, point.y.isFinite, bodyTextView.bounds.contains(point) else { throw NativeReaderTextFailure.invalidGeometry }
        manager.ensureLayout(for: container)
        if manager.numberOfGlyphs == 0 { return try map.logical(at: 0, affinity: affinity) }
        let origin = bodyTextView.textContainerOrigin
        var fraction: CGFloat = 0
        let index = manager.characterIndex(for: NSPoint(x: point.x - origin.x, y: point.y - origin.y),
                                           in: container, fractionOfDistanceBetweenInsertionPoints: &fraction)
        let anchor = min(index, max(0, map.length - 1))
        let glyph = manager.glyphIndexForCharacter(at: anchor)
        let line = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let points = nativeReaderInsertionPoints(manager, character: anchor)
        let targetX = point.x - origin.x - line.minX
        if let minimum = points.map({ abs($0.x - targetX) }).min() {
            let closest = points.filter { abs(abs($0.x - targetX) - minimum) < 0.01 }
            let chosen = closest.first(where: { $0.alternate == (affinity == .upstream) }) ?? closest.first
            if let candidate = chosen { return try map.logical(at: candidate.presentationUTF16, affinity: affinity) }
        }
        let offset = min(map.length, index + (fraction > 0.5 ? 1 : 0))
        return try map.logical(at: offset, affinity: affinity)
    }
    // Coordinate round-trip with explicit logical/affinity equivalence. At a bidi
    // boundary two carets may share a point; preserve the caller's disambiguator.
    func resolve(_ geometry: NativeReaderTextGeometry) throws -> NativeReaderTextPosition {
        try validateGeometry(geometry)
        let current = try caretGeometry(at: geometry.position)
        guard abs(current.rect.minX - geometry.rect.minX) < 0.5,
              abs(current.rect.minY - geometry.rect.minY) < 0.5 else { throw NativeReaderTextFailure.invalidGeometry }
        return current.position
    }
    func rects(blockID: String, logical: Range<Int>) -> [NSRect] {
        guard renderKey != nil, renderKey == requestedRenderKey, let map = textMap, let range = try? map.presentationRange(blockID: blockID, logical: logical),
              let manager = bodyTextView.layoutManager, let container = bodyTextView.textContainer else { return [] }
        let glyphs = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var result: [NSRect] = []
        manager.enumerateEnclosingRects(forGlyphRange: glyphs, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: container) { rect, _ in
            result.append(rect.offsetBy(dx: self.bodyTextView.textContainerOrigin.x, dy: self.bodyTextView.textContainerOrigin.y))
        }
        return result
    }
    func reviewStrikeSegments(blockID: String, logical: Range<Int>) -> [NSRect] {
        guard renderKey != nil, renderKey == requestedRenderKey, let map = textMap,
              let range = try? map.presentationRange(blockID: blockID, logical: logical),
              let manager = bodyTextView.layoutManager, let container = bodyTextView.textContainer,
              let storage = bodyTextView.textStorage else { return [] }
        let glyphs = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        let origin = bodyTextView.textContainerOrigin
        var result: [NSRect] = []
        manager.enumerateLineFragments(forGlyphRange: glyphs) { lineRect, _, _, lineGlyphs, _ in
            let segment = NSIntersectionRange(glyphs, lineGlyphs)
            guard segment.length > 0 else { return }
            let glyphBounds = manager.boundingRect(forGlyphRange: segment, in: container).offsetBy(dx: origin.x, dy: origin.y)
            guard glyphBounds.width > 0 else { return }
            let baseline = lineRect.minY + manager.location(forGlyphAt: segment.location).y + origin.y
            let characters = manager.characterRange(forGlyphRange: segment, actualGlyphRange: nil)
            var attachment: (NSTextAttachment, NSRange)?
            storage.enumerateAttribute(.attachment, in: characters) { value, range, stop in
                if let value = value as? NSTextAttachment { attachment = (value, range); stop.pointee = true }
            }
            let y: CGFloat
            if let (attachment, range) = attachment, let cell = attachment.attachmentCell {
                // TextKit's attachment glyph location already includes the cell's baseline offset.
                let attachmentGlyph = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                let bottom = lineRect.minY + manager.location(forGlyphAt: attachmentGlyph.location).y + origin.y
                y = bottom - cell.cellSize().height * 0.5
            } else {
                let font = storage.attribute(.font, at: characters.location, effectiveRange: nil) as? NSFont ?? self.bodyTextView.font ?? NSFont.systemFont(ofSize: 13)
                y = min(glyphBounds.maxY, max(glyphBounds.minY, baseline - font.ascender * 0.36))
            }
            result.append(NSRect(x: glyphBounds.minX, y: y, width: glyphBounds.width, height: 0))
        }
        return result
    }
    func nodeRectInDocument(forNodeID id: String) -> NSRect? {
        guard !isDisposed, renderKey != nil, renderKey == requestedRenderKey,
              let block = store.document?.blocks.first(where: { $0.orderedNodes.contains(where: { $0.id == id }) }),
              let node = block.orderedNodes.first(where: { $0.id == id }), node.visible,
              let rect = rects(blockID: block.id, logical: node.rangeUTF16[0]..<node.rangeUTF16[1]).first else { return nil }
        return rect
    }
    func nodeRectInView(forNodeID id: String) -> NSRect? {
        guard let rect = nodeRectInDocument(forNodeID: id) else { return nil }
        return bodyTextView.convert(rect, to: self)
    }
    func currentCrossProjectPosition() -> NativeReaderCrossProjectPosition {
        let blockID = viewportAnchor()?.position.blockID
        let anchor = store.document?.blocks.first(where: { $0.id == blockID })?.anchors.first
        return .init(anchor: anchor, blockID: blockID, scrollOffset: Double(scrollView.contentView.bounds.origin.y))
    }
    @discardableResult func scrollToCrossProjectLocation(anchor: String?, blockID: String?, scrollOffset: Double?) -> Bool {
        guard !isDisposed, renderKey != nil, renderKey == requestedRenderKey else { return false }
        if let anchor, !anchor.isEmpty {
            guard let node = store.document?.blocks.flatMap(\.orderedNodes).first(where: { $0.anchors.contains(anchor) }) else { return false }
            return scrollToNode(id: node.id, recordReturn: false, topAlign: true)
        }
        if let blockID, !blockID.isEmpty {
            let hasPlaceholderObjects = attachmentNodes.contains { preparedObjects[$0.id]?.isPlaceholder ?? true }
            guard scrollToNode(id: blockID, recordReturn: false, topAlign: hasPlaceholderObjects) else { return false }
            guard let scrollOffset, scrollOffset.isFinite else { return true }
            if !hasPlaceholderObjects {
                scrollToCrossProjectOffset(scrollOffset)
            } else {
                let viewportHeight = scrollView.contentView.bounds.height
                let clamped = CGFloat(min(Double(max(0, bodyTextView.bounds.height - viewportHeight)), max(0, scrollOffset)))
                if let block = store.document?.blocks.first(where: { $0.orderedNodes.contains(where: { $0.id == blockID }) }),
                   let node = block.orderedNodes.first(where: { $0.id == blockID }),
                   let rect = rects(blockID: block.id, logical: node.rangeUTF16[0]..<node.rangeUTF16[1]).first {
                    if rect.maxY > clamped && rect.minY < clamped + viewportHeight {
                        scrollToCrossProjectOffset(scrollOffset)
                    }
                    if viewportAnchor()?.position.blockID != blockID {
                        // A partially visible target can still leave an earlier
                        // placeholder as the reflow anchor. Anchor inside the target.
                        scrollToCrossProjectOffset(Double(rect.minY + 1))
                    }
                }
            }
            return true
        }
        guard let scrollOffset, scrollOffset.isFinite else { return false }
        scrollToCrossProjectOffset(scrollOffset)
        return true
    }
    private func scrollToCrossProjectOffset(_ scrollOffset: Double) {
        let maximum = max(0, bodyTextView.bounds.height - scrollView.contentView.bounds.height)
        let offset = CGFloat(min(Double(maximum), max(0, scrollOffset)))
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: offset))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
    func select(from start: NativeReaderTextPosition, to end: NativeReaderTextPosition) throws {
        guard !isDisposed, let map = textMap else { throw NativeReaderTextFailure.staleGeometry }
        let a = try map.presentation(of: start), b = try map.presentation(of: end)
        bodyTextView.setSelectedRange(NSRange(location: min(a, b), length: abs(b - a)), affinity: end.affinity, stillSelecting: false)
    }
    func pointerDown(at point: NSPoint, extending: Bool = false, clickCount: Int = 1) {
        guard let key = renderKey, let position = try? hitTestText(at: point, key: key),
              let offset = try? textMap?.presentation(of: position) else { return }
        let current = bodyTextView.selectedRange()
        dragAnchor = extending ? current.location : offset
        dragMoved = false
        if clickCount >= 2 {
            let range = bodyTextView.selectionRange(forProposedRange: NSRange(location: offset, length: 0), granularity: clickCount == 2 ? .selectByWord : .selectByParagraph)
            bodyTextView.setSelectedRange(range)
        } else {
            bodyTextView.setSelectedRange(NSRange(location: min(dragAnchor!, offset), length: abs(dragAnchor! - offset)))
        }
        bodyFocused()
        // An actual user mouse event can ask its own window for responder focus.
        // No window is created, activated or ordered by the presentation layer.
        bodyTextView.window?.makeFirstResponder(bodyTextView)
    }
    func pointerDragged(at point: NSPoint) {
        guard let anchor = dragAnchor, let key = renderKey,
              let position = try? hitTestText(at: point, key: key),
              let offset = try? textMap?.presentation(of: position) else { return }
        dragMoved = dragMoved || offset != anchor
        bodyTextView.setSelectedRange(NSRange(location: min(anchor, offset), length: abs(anchor - offset)), affinity: position.affinity, stillSelecting: true)
        bodyTextView.scrollRangeToVisible(bodyTextView.selectedRange())
    }
    func pointerUp(at point: NSPoint) {
        guard !isDisposed else { return }
        if !dragMoved && store.selection == nil { activate(at: point) }
        dragAnchor = nil
        dragMoved = false
    }
    func bodyFocused() {
        guard !isDisposed else { return }
        let position = try? textMap?.logical(at: bodyTextView.selectedRange().location, affinity: bodyTextView.selectionAffinity)
        callbacks.focusChanged(position?.blockID)
    }
    private var actionableNodes: [NativeReaderNode] {
        store.document?.blocks.flatMap(\.orderedNodes).filter { $0.visible && [.link, .annotation, .heading].contains($0.kind) } ?? []
    }
    @discardableResult func focusNextSemantic(backwards: Bool = false) -> Bool {
        guard !isDisposed, renderKey != nil else { return false }
        let nodes = actionableNodes
        guard !nodes.isEmpty else { return false }
        let old = nodes.firstIndex { $0.id == focusedNodeID }
        let index = old.map { ($0 + (backwards ? nodes.count - 1 : 1)) % nodes.count } ?? (backwards ? nodes.count - 1 : 0)
        focusedNodeID = nodes[index].id
        callbacks.focusChanged(nodes[index].id)
        if let block = store.document?.blocks.first(where: { $0.orderedNodes.contains(where: { $0.id == nodes[index].id }) }),
           let range = try? textMap?.presentationRange(blockID: block.id, logical: nodes[index].rangeUTF16[0]..<nodes[index].rangeUTF16[1]) {
            bodyTextView.scrollRangeToVisible(range)
            prepareVisibleObjects()
        }
        return true
    }
    @discardableResult func activateFocusedSemantic() -> Bool {
        guard let id = focusedNodeID else { return false }
        return activate(nodeID: id)
    }
    @discardableResult func activate(nodeID: String) -> Bool {
        guard !isDisposed, renderKey != nil, let context = context, context.generation == store.generation,
              let node = store.document?.blocks.flatMap(\.orderedNodes).first(where: { $0.id == nodeID }), node.visible else { return false }
        if node.kind == .link, node.projectRef == nil, let target = node.link, target.hasPrefix("#") { _ = navigate(toAnchor: String(target.dropFirst())) }
        if node.kind == .annotation, let target = node.annotationTargets.first { _ = navigate(toAnchor: target) }
        callbacks.semanticActivated(node, context)
        return true
    }
    func activate(at point: NSPoint) {
        guard let key = renderKey, let position = try? hitTestText(at: point, key: key),
              let block = store.document?.blocks.first(where: { $0.id == position.blockID }) else { return }
        // Prefer actual object-native hit semantics when an adapter supplies them.
        for node in block.orderedNodes {
            guard let object = preparedObjects[node.id], let hit = object.hitNode,
                  let rect = rects(blockID: block.id, logical: node.rangeUTF16[0]..<node.rangeUTF16[1]).first,
                  rect.contains(point), let id = hit(NSPoint(x: point.x - rect.minX, y: point.y - rect.minY)),
                  node.orderedNodes.contains(where: { $0.id == id }) else { continue }
            _ = activate(nodeID: id)
            return
        }
        if let node = block.orderedNodes.reversed().first(where: {
            [.link, .annotation].contains($0.kind) && $0.rangeUTF16[0] <= position.utf16 && position.utf16 < $0.rangeUTF16[1]
        }) { _ = activate(nodeID: node.id) }
    }
    @discardableResult func navigate(toAnchor anchor: String) -> Bool {
        guard let node = store.document?.blocks.flatMap(\.orderedNodes).first(where: { $0.anchors.contains(anchor) }) else { return false }
        return scrollToNode(id: node.id, recordReturn: true, topAlign: false)
    }
    @discardableResult func navigate(toNodeID id: String, topAlign: Bool = false) -> Bool {
        scrollToNode(id: id, recordReturn: true, topAlign: topAlign, topInset: 0)
    }
    private func scrollToNode(id: String, recordReturn: Bool, topAlign: Bool = false, topInset: CGFloat = 24) -> Bool {
        guard !isDisposed, renderKey != nil, renderKey == requestedRenderKey,
              let block = store.document?.blocks.first(where: { $0.orderedNodes.contains(where: { $0.id == id }) }),
              let node = block.orderedNodes.first(where: { $0.id == id }), node.visible,
              let range = try? textMap?.presentationRange(blockID: block.id, logical: node.rangeUTF16[0]..<node.rangeUTF16[1]) else { return false }
        if recordReturn { returningAnchor = viewportAnchor() }
        if topAlign {
            bodyTextView.layoutManager?.ensureLayout(for: bodyTextView.textContainer!)
            if let rect = rects(blockID: block.id, logical: node.rangeUTF16[0]..<node.rangeUTF16[1]).first {
                let maximum = max(0, bodyTextView.bounds.height - scrollView.contentView.bounds.height)
                scrollView.contentView.scroll(to: NSPoint(x: 0, y: min(maximum, max(0, rect.minY - topInset))))
                scrollView.reflectScrolledClipView(scrollView.contentView)
            } else {
                bodyTextView.scrollRangeToVisible(range)
            }
        } else {
            bodyTextView.scrollRangeToVisible(range)
        }
        prepareVisibleObjects()
        focusedNodeID = node.id; callbacks.focusChanged(node.id)
        return true
    }
    @discardableResult func returnFromReference() -> Bool {
        guard let anchor = returningAnchor, !isDisposed, renderKey != nil, renderKey == requestedRenderKey else { return false }
        returningAnchor = nil
        restoreViewport(anchor)
        return true
    }
    func viewportAnchor() -> NativeReaderViewportAnchor? {
        guard let key = renderKey, textMap != nil else { return nil }
        let visible = bodyTextView.visibleRect
        let point = NSPoint(x: min(bodyTextView.bounds.maxX - 1, bodyTextView.textContainerOrigin.x + 1), y: max(0, visible.minY + 1))
        guard let position = try? hitTestText(at: point, key: key), let geometry = try? caretGeometry(at: position) else { return nil }
        return .init(identity: key.identity, position: position, offsetY: visible.minY - geometry.rect.minY)
    }
    func restoreViewport(_ anchor: NativeReaderViewportAnchor) {
        guard anchor.identity == renderKey?.identity, anchor.offsetY.isFinite,
              let geometry = try? caretGeometry(at: anchor.position) else { return }
        let maximum = max(0, bodyTextView.bounds.height - scrollView.contentView.bounds.height)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: min(maximum, max(0, geometry.rect.minY + anchor.offsetY))))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        prepareVisibleObjects()
    }
    func objectAccessibilityLabel(nodeID: String) -> String? {
        if let object = preparedObjects[nodeID] { return object.accessibilityLabel }
        return preparedObjects.values.compactMap { $0.accessibilityLabelForNode?(nodeID) }.first
    }
}

extension NativeReaderTextView {
    func setLogicalAccessibilityFocus(_ nodeID: String) {
        guard !isDisposed, renderKey != nil,
              store.document?.blocks.flatMap(\.orderedNodes).contains(where: { $0.id == nodeID }) == true else { return }
        focusedNodeID = nodeID
        callbacks.focusChanged(nodeID)
    }
}
