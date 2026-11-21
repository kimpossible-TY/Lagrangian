import AppKit

// The tree contains real NSAccessibility elements, never an HTML/ARIA mirror.
// Instances are layout-key scoped; callers retaining old AX children cannot act
// on a replacement document or reuse coordinates after a reflow.
@MainActor final class NativeReaderAXElement: NSAccessibilityElement {
    let node: NativeReaderNode
    let blockID: String
    weak var reader: NativeReaderTextView?
    private let key: NativeReaderTextRenderKey
    private var children: [NativeReaderAXElement] = []
    init(node: NativeReaderNode, blockID: String, reader: NativeReaderTextView, parent: Any, key: NativeReaderTextRenderKey) {
        self.node = node
        self.blockID = blockID
        self.reader = reader
        self.key = key
        super.init()
        setAccessibilityParent(parent)
        setAccessibilityElement(true)
        children = node.children.map { NativeReaderAXElement(node: $0, blockID: blockID, reader: reader, parent: self, key: key) }
    }
    private var current: Bool { reader?.renderKey == key && reader?.isDisposed == false }
    override func accessibilityRole() -> NSAccessibility.Role? {
        switch node.kind {
        case .heading: return NSAccessibility.Role(rawValue: "AXHeading")
        case .link: return .link
        case .image: return .image
        case .table: return .table
        case .row: return .row
        case .cell: return .cell
        case .text, .equationNumber: return .staticText
        default: return .group
        }
    }
    override func accessibilityRoleDescription() -> String? {
        if node.kind == .math { return "mathematical expression" }
        if node.kind == .annotation { return "annotation" }
        return accessibilityRole()!.description(with: nil)
    }
    override func accessibilityLabel() -> String? {
        guard current else { return nil }
        return reader?.objectAccessibilityLabel(nodeID: node.id) ?? node.alt ?? node.displayText
    }
    override func accessibilityValue() -> Any? {
        guard current else { return nil }
        if node.kind == .heading { return node.headingLevel }
        return node.displayText
    }
    override func accessibilityHelp() -> String? {
        if node.kind == .math { return node.math?.mathML }
        if node.kind == .annotation { return node.annotationTargets.joined(separator: ", ") }
        return nil
    }
    override func accessibilityURL() -> URL? { current ? node.link.flatMap(URL.init(string:)) : nil }
    override func accessibilityChildren() -> [Any]? { current ? children : [] }
    override func accessibilityVisibleChildren() -> [Any]? { current ? children.filter { $0.node.visible } : [] }
    override func isAccessibilityEnabled() -> Bool { current }
    override func isAccessibilityFocused() -> Bool { current && reader?.focusedNodeID == node.id }
    override func setAccessibilityFocused(_ focused: Bool) {
        guard current, focused else { return }
        // Logical AX focus does not activate a window or invoke an action.
        reader?.focusAccessibilityNode(node.id)
    }
    override func accessibilityFrame() -> NSRect {
        guard current, let reader = reader else { return .zero }
        let rect = reader.rects(blockID: blockID, logical: node.rangeUTF16[0]..<node.rangeUTF16[1]).reduce(NSRect.null) { $0.union($1) }
        guard !rect.isNull else { return .zero }
        return reader.screenRect(rect)
    }
    override func accessibilityPerformPress() -> Bool {
        guard current, [.link, .annotation, .heading].contains(node.kind) else { return false }
        return reader?.activate(nodeID: node.id) ?? false
    }
    override func accessibilitySelectedText() -> String? {
        guard current, let selection = reader?.store.selection,
              let fragment = selection.fragments.first(where: { $0.blockID == blockID }) else { return nil }
        let start = max(fragment.rangeUTF16.lowerBound, node.rangeUTF16[0])
        let end = min(fragment.rangeUTF16.upperBound, node.rangeUTF16[1])
        guard end >= start, let range = Range(NSRange(location: start - node.rangeUTF16[0], length: end - start), in: node.displayText) else { return nil }
        return String(node.displayText[range])
    }
    override func accessibilitySelectedTextRange() -> NSRange {
        guard current, let fragment = reader?.store.selection?.fragments.first(where: { $0.blockID == blockID }) else { return NSRange(location: 0, length: 0) }
        let start = max(fragment.rangeUTF16.lowerBound, node.rangeUTF16[0])
        let end = min(fragment.rangeUTF16.upperBound, node.rangeUTF16[1])
        return end >= start ? NSRange(location: start - node.rangeUTF16[0], length: end - start) : NSRange(location: 0, length: 0)
    }
    override func setAccessibilitySelectedTextRange(_ range: NSRange) {
        guard current, range.location != NSNotFound, range.location >= 0, range.length >= 0,
              range.location <= node.displayText.utf16.count, range.length <= node.displayText.utf16.count - range.location else { return }
        try? reader?.select(from: .init(blockID: blockID, utf16: node.rangeUTF16[0] + range.location, affinity: .upstream),
                            to: .init(blockID: blockID, utf16: node.rangeUTF16[0] + NSMaxRange(range), affinity: .downstream))
    }
    override func accessibilityNumberOfCharacters() -> Int { current ? node.displayText.utf16.count : 0 }
    override func accessibilityString(for range: NSRange) -> String? {
        guard current, range.location != NSNotFound, range.location >= 0, range.length >= 0,
              range.location <= node.displayText.utf16.count, range.length <= node.displayText.utf16.count - range.location,
              let range = Range(range, in: node.displayText) else { return nil }
        return String(node.displayText[range])
    }
}

extension NativeReaderTextView {
    var accessibilityLogicalSelectionRange: NSRange {
        guard let document = store.document else { return NSRange(location: 0, length: 0) }
        if let selection = store.selection, let first = selection.fragments.first, let last = selection.fragments.last {
            let a = logicalDocumentOffset(blockID: first.blockID, local: first.rangeUTF16.lowerBound, document: document)
            let b = logicalDocumentOffset(blockID: last.blockID, local: last.rangeUTF16.upperBound, document: document)
            return NSRange(location: a, length: max(0, b - a))
        }
        if let position = try? textMap?.logical(at: bodyTextView.selectedRange().location, affinity: bodyTextView.selectionAffinity) {
            return NSRange(location: logicalDocumentOffset(blockID: position.blockID, local: position.utf16, document: document), length: 0)
        }
        return NSRange(location: 0, length: 0)
    }
    func logicalDocumentOffset(blockID: String, local: Int, document: NativeReaderDocument) -> Int {
        var base = 0
        for block in document.blocks {
            if block.id == blockID { return base + local }
            base += block.displayText.utf16.count + 1
        }
        return base
    }
    func logicalDocumentPosition(_ offset: Int, affinity: NSSelectionAffinity) -> NativeReaderTextPosition? {
        guard let document = store.document, offset >= 0, offset <= logicalText.utf16.count else { return nil }
        var base = 0
        for block in document.blocks {
            let end = base + block.displayText.utf16.count
            if offset <= end { return .init(blockID: block.id, utf16: offset - base, affinity: affinity) }
            base = end + 1
        }
        return nil
    }
    func selectAccessibilityLogicalRange(_ range: NSRange) {
        guard range.location != NSNotFound, range.location >= 0, range.length >= 0,
              range.location <= logicalText.utf16.count, range.length <= logicalText.utf16.count - range.location,
              let start = logicalDocumentPosition(range.location, affinity: .upstream),
              let end = logicalDocumentPosition(NSMaxRange(range), affinity: .downstream) else { return }
        try? select(from: start, to: end)
    }
    func logicalSubstring(_ range: NSRange) -> String? {
        guard range.location != NSNotFound, range.location >= 0, range.length >= 0,
              range.location <= logicalText.utf16.count, range.length <= logicalText.utf16.count - range.location,
              let range = Range(range, in: logicalText) else { return nil }
        return String(logicalText[range])
    }
    func screenRect(_ rect: NSRect) -> NSRect {
        let converted = bodyTextView.convert(rect, to: nil)
        return bodyTextView.window?.convertToScreen(converted) ?? converted
    }
    func accessibilityFrameForLogicalRange(_ range: NSRange) -> NSRect {
        guard range.location != NSNotFound, range.location >= 0, range.length >= 0,
              range.location <= logicalText.utf16.count, range.length <= logicalText.utf16.count - range.location,
              let start = logicalDocumentPosition(range.location, affinity: .upstream),
              let end = logicalDocumentPosition(NSMaxRange(range), affinity: .downstream),
              let map = textMap else { return .zero }
        if range.length == 0, let caret = try? caretGeometry(at: start) { return screenRect(caret.rect) }
        let a = try? map.presentation(of: start), b = try? map.presentation(of: end)
        guard let first = a, let last = b, let manager = bodyTextView.layoutManager, let container = bodyTextView.textContainer else { return .zero }
        let glyph = manager.glyphRange(forCharacterRange: NSRange(location: first, length: max(0, last - first)), actualCharacterRange: nil)
        let rect = manager.boundingRect(forGlyphRange: glyph, in: container).offsetBy(dx: bodyTextView.textContainerOrigin.x, dy: bodyTextView.textContainerOrigin.y)
        return screenRect(rect)
    }
    func focusAccessibilityNode(_ nodeID: String) {
        // Kept in the view owner so AX never creates action/selection authority.
        setLogicalAccessibilityFocus(nodeID)
    }
}


extension NativeReaderTextView {
    func presentationOffsetForLogical(_ index: Int) -> Int? {
        guard let position = logicalDocumentPosition(index, affinity: .downstream) else { return nil }
        return try? textMap?.presentation(of: position)
    }
    func logicalRangeForPresentation(_ range: NSRange) -> NSRange {
        guard let map = textMap, let normalized = try? map.normalized(range, affinity: .downstream),
              let start = try? map.logical(at: normalized.location, affinity: .upstream),
              let end = try? map.logical(at: NSMaxRange(normalized), affinity: .downstream) else { return NSRange(location: NSNotFound, length: 0) }
        let a = logicalDocumentOffset(blockID: start.blockID, local: start.utf16, document: map.document)
        let b = logicalDocumentOffset(blockID: end.blockID, local: end.utf16, document: map.document)
        return NSRange(location: a, length: max(0, b - a))
    }
    func logicalGraphemeRange(at index: Int) -> NSRange {
        guard let map = textMap, let position = logicalDocumentPosition(index, affinity: .upstream),
              let block = map.document.blocks.first(where: { $0.id == position.blockID }),
              let start = try? map.snapped(position) else { return NSRange(location: NSNotFound, length: 0) }
        let end = block.graphemeBoundariesUTF16.first(where: { $0 > start.utf16 }) ?? start.utf16
        return NSRange(location: logicalDocumentOffset(blockID: block.id, local: start.utf16, document: map.document), length: end - start.utf16)
    }
    func logicalStyleRange(at index: Int) -> NSRange {
        guard let storage = bodyTextView.textStorage, let offset = presentationOffsetForLogical(index), offset < storage.length else { return NSRange(location: NSNotFound, length: 0) }
        var range = NSRange(location: 0, length: 0)
        _ = storage.attributes(at: offset, effectiveRange: &range)
        return logicalRangeForPresentation(range)
    }
    func logicalAttributedSubstring(_ range: NSRange) -> NSAttributedString? {
        guard let text = logicalSubstring(range) else { return nil }
        let result = NSMutableAttributedString(string: text)
        guard let map = textMap, let storage = bodyTextView.textStorage else { return result }
        for span in map.spans {
            let global = NSRange(location: logicalDocumentOffset(blockID: span.blockID, local: span.logical.lowerBound, document: map.document), length: span.logical.count)
            let overlap = NSIntersectionRange(range, global)
            guard overlap.length > 0, span.presentation.location < storage.length else { continue }
            let attributes = storage.attributes(at: span.presentation.location, effectiveRange: nil).filter { $0.key != .attachment }
            result.addAttributes(attributes, range: NSRange(location: overlap.location - range.location, length: overlap.length))
        }
        return result
    }
    func logicalRangeAtScreenPoint(_ point: NSPoint) -> NSRange {
        guard let key = renderKey, let document = store.document else { return NSRange(location: NSNotFound, length: 0) }
        let windowPoint = bodyTextView.window?.convertPoint(fromScreen: point) ?? point
        let local = bodyTextView.convert(windowPoint, from: nil)
        guard let position = try? hitTestText(at: local, key: key) else { return NSRange(location: NSNotFound, length: 0) }
        return logicalGraphemeRange(at: logicalDocumentOffset(blockID: position.blockID, local: position.utf16, document: document))
    }
}
