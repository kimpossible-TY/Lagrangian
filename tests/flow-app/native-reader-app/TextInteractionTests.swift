import AppKit
import CoreText

struct TextTestError: Error, CustomStringConvertible {
    let description: String
}
@MainActor func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw TextTestError(description: message) }
}
@MainActor func rejects(_ label: String, _ operation: () throws -> Void) throws {
    do { try operation() } catch { return }
    throw TextTestError(description: "Expected rejection: " + label)
}
@MainActor func tick() { RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.003)) }

// Hand-authored oracle. These literals/ranges were not computed by the view, map,
// importer or layout manager. UTF16, scalar, UTF8 and grapheme units are separate.
let oracleTexts = [
    "Native contract",
    "한글 한글 e\u{301} 😀 👩‍👩‍👧‍👦 office ffi abc אבג 123.",
    "Plain bold emphasis link and 𝑥2+𝑦.", "Repeated paragraph.", "Repeated paragraph.",
    "∫01𝑥2d𝑥=13(1)", "NameValueAlpha10Merged", "Figure\u{a0}1: Blue rectangle", "Term", "Note", "Next",
    "See Equation\u{a0}1 and Figure\u{a0}1."
]
let oracleUnicode: [(String, [UInt32], [Int], [Int], [Int])] = [
    ("한글", [0xD55C, 0xAE00], [0,3,6], [0,1,2], [0,1,2]),
    ("한글", [0x1112,0x1161,0x11AB,0x1100,0x1173,0x11AF], [0,3,6,9,12,15,18], [0,1,2,3,4,5,6], [0,3,6]),
    ("e\u{301}", [101,769], [0,1,3], [0,1,2], [0,2]),
    ("😀", [128512], [0,4], [0,2], [0,2]),
    ("👩‍👩‍👧‍👦", [128105,8205,128105,8205,128103,8205,128102], [0,4,7,11,14,18,21,25], [0,2,3,5,6,8,9,11], [0,11])
]
let unicodeBlockBoundaries = [0,1,2,3,6,9,10,12,13,15,16,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51]

@main struct TextInteractionMain {
    @MainActor static func main() {
        do {
            _ = NSApplication.shared.setActivationPolicy(.prohibited)
            let document = try NativeReaderDocument.decode(Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
            let out = URL(fileURLWithPath: CommandLine.arguments[2])
            try check(document.blocks.map(\.displayText) == oracleTexts, "actual compiler logical reading order")
            let results = try run(document, out: out)
            let data = try JSONSerialization.data(withJSONObject: results, options: [.sortedKeys])
            print(String(decoding: data, as: UTF8.self))
        } catch {
            fputs("TextInteractionTests FAILED: \(error)\n", stderr)
            exit(1)
        }
    }
    @MainActor static func make(_ document: NativeReaderDocument, provider: Bool = true) throws -> (NativeReaderTextView, NativeReaderRequestContext) {
        let store = NativeReaderDocumentStore()
        let generation = try store.beginRequest()
        let context = NativeReaderRequestContext(requestID: UUID(), viewID: store.viewID, generation: generation, target: document.identity)
        let view = NativeReaderTextView(store: store)
        if provider { view.cachedObject = unitObject }
        try view.adopt(document, context: context)
        return (view, context)
    }
    // Fake metrics/draw are deliberately unit-scoped. No formula/table/image
    // fidelity is asserted or inferred from their blue rectangles.
    @MainActor static func unitObject(_ node: NativeReaderNode, _ key: NativeReaderTextRenderKey) -> NativeReaderPreparedTextObject? {
        NativeReaderPreparedTextObject(key: key, size: NSSize(width: min(key.width, key.appearance.effectiveSize * 5), height: key.appearance.effectiveSize * 1.5),
            baseline: key.appearance.effectiveSize * 0.25, accessibilityLabel: "Unit object " + node.kind.rawValue,
            draw: { rect in NSColor.systemBlue.setFill(); NSBezierPath(rect: rect.insetBy(dx: 1, dy: 1)).fill() },
            hitNode: { _ in node.id }, accessibilityLabelForNode: { id in node.orderedNodes.contains(where: { $0.id == id }) ? "Unit semantics " + id : nil })
    }
    @MainActor static func paint(_ view: NativeReaderTextView, file: URL?) throws -> Int {
        let body = view.bodyTextView
        body.layoutManager?.ensureLayout(for: body.textContainer!)
        let rect = body.bounds
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(ceil(rect.width)), pixelsHigh: Int(ceil(rect.height)),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0), let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else { throw TextTestError(description: "bitmap context") }
        body.displayIgnoringOpacity(rect, in: graphics)
        tick()
        guard let bytes = bitmap.bitmapData else { throw TextTestError(description: "bitmap data") }
        var ink = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let p = bytes + y * bitmap.bytesPerRow + x * 4
                if view.textAppearance.theme == .light ? (p[0] < 230 || p[1] < 230 || p[2] < 230) : (p[0] > 25 || p[1] > 25 || p[2] > 25) { ink += 1 }
            }
        }
        if let file = file { try bitmap.representation(using: .png, properties: [:])!.write(to: file) }
        return ink
    }
    @MainActor static func run(_ document: NativeReaderDocument, out: URL) throws -> [String: Any] {
        var matrix: [[String: Any]] = []
        var unicodeAssertions = 0
        for width: CGFloat in [320,640,960] {
            for font: CGFloat in [14,20,28] {
                for theme in [NativeReaderTextAppearance.Theme.light, .dark] {
                    let (view, _) = try make(document)
                    var painted = false
                    view.callbacks.painted = { key in if key == view.renderKey { painted = true } }
                    view.setFrameSize(NSSize(width: width, height: 480))
                    try view.setAppearance(.init(fontSize: font, zoom: 1, theme: theme))
                    try check(!painted, "layout must not acknowledge paint")
                    let key = view.renderKey!
                    try check(key.width <= width && key.width > width - 70, "body width")
                    try check(view.bodyTextView.isEditable == false, "read-only native body")
                    try check(view.logicalText.unicodeScalars.map(\.value) == oracleTexts.joined(separator: "\n").unicodeScalars.map(\.value), "exact scalar preservation")
                    for item in oracleUnicode {
                        let offsets = NativeTextOffsets(item.0)
                        try check(offsets.scalars == item.1 && offsets.cpToUTF8 == item.2 && offsets.cpToUTF16 == item.3, "independent units oracle")
                        unicodeAssertions += 1
                    }
                    let block = document.blocks[1]
                    // Written range oracle: NFD 3..<9, combining 10..<12,
                    // astral 13..<15, family 16..<27; UTF16 total is 51.
                    try check(block.graphemeBoundariesUTF16 == unicodeBlockBoundaries, "independent complete grapheme boundary oracle")
                    for range in [3..<9, 10..<12, 13..<15, 16..<27] {
                        try view.select(from: .init(blockID: block.id, utf16: range.lowerBound, affinity: .upstream),
                                        to: .init(blockID: block.id, utf16: range.upperBound, affinity: .downstream))
                        try check(view.store.selection?.fragments[0].rangeUTF16 == range, "native selection logical range")
                        unicodeAssertions += 1
                    }
                    for offset in block.graphemeBoundariesUTF16 {
                        for affinity in [NSSelectionAffinity.upstream, .downstream] {
                            let position = NativeReaderTextPosition(blockID: block.id, utf16: offset, affinity: affinity)
                            let caret = try view.caretGeometry(at: position)
                            let resolved = try view.resolve(caret)
                            try check(resolved == position && caret.rect.height > 0 && caret.rect.minX >= 0, "caret reverse coordinate and affinity")
                            let hit = try view.hitTestText(at: NSPoint(x: caret.rect.minX, y: caret.rect.midY), key: key, affinity: affinity)
                            try check(document.blocks.first(where: { $0.id == hit.blockID })!.graphemeBoundariesUTF16.contains(hit.utf16), "hit uses legal grapheme")
                            unicodeAssertions += 1
                        }
                    }
                    let before = view.bodyTextView.string
                    let ink = try paint(view, file: matrix.isEmpty ? out.appendingPathComponent("native-text-light.png") : nil)
                    try check(painted && ink > 100, "actual native draw/ack/ink")
                    try check(view.bodyTextView.string == before, "draw does not mutate logical presentation")
                    matrix.append(["width": width, "font": font, "theme": theme.rawValue, "inkPixels": ink, "painted": painted])
                    view.dispose()
                }
            }
        }
        let (view, context) = try make(document)
        let block = document.blocks[1]
        let map = view.textMap!
        let styled = document.blocks[2]
        let strong = styled.orderedNodes.first { $0.kind == .strong }!
        let emphasis = styled.orderedNodes.first { $0.kind == .emphasis }!
        let strongIndex = try map.presentation(of: .init(blockID: styled.id, utf16: strong.rangeUTF16[0], affinity: .downstream))
        let emphasisIndex = try map.presentation(of: .init(blockID: styled.id, utf16: emphasis.rangeUTF16[0], affinity: .downstream))
        let boldFont = view.bodyTextView.textStorage!.attribute(.font, at: strongIndex, effectiveRange: nil) as! NSFont
        let italicFont = view.bodyTextView.textStorage!.attribute(.font, at: emphasisIndex, effectiveRange: nil) as! NSFont
        try check(NSFontManager.shared.traits(of: boldFont).contains(.boldFontMask), "native bold style")
        try check(NSFontManager.shared.traits(of: italicFont).contains(.italicFontMask), "native emphasis style")
        let privatePasteboard = NSPasteboard(name: NSPasteboard.Name("dev.lagrangian.NA02." + UUID().uuidString))
        defer { privatePasteboard.releaseGlobally() }
        view.callbacks.copyText = { text in privatePasteboard.clearContents(); return privatePasteboard.setString(text, forType: .string) }
        try view.select(from: .init(blockID: block.id, utf16: 3, affinity: .upstream), to: .init(blockID: document.blocks[3].id, utf16: 8, affinity: .downstream))
        let expectedCopy = "한글 e\u{301} 😀 👩‍👩‍👧‍👦 office ffi abc אבג 123.\nPlain bold emphasis link and 𝑥2+𝑦.\nRepeated"
        view.bodyTextView.copy(nil)
        try check(privatePasteboard.string(forType: .string)?.unicodeScalars.map(\.value) == expectedCopy.unicodeScalars.map(\.value), "cross-block plain native copy")
        let formula = document.blocks[2].orderedNodes.first { $0.kind == .math }!
        let formulaRange = try map.presentationRange(blockID: document.blocks[2].id, logical: formula.rangeUTF16[0]..<formula.rangeUTF16[1])
        try check(formulaRange.length == 1 && formula.displayText.utf16.count > 1, "attachment logical/presentation range differs")
        view.bodyTextView.setSelectedRange(formulaRange)
        try check(view.store.selection?.fragments.first?.exact == "𝑥2+𝑦", "whole inline formula exact plain selection")
        let excerpt = view.requestSource(.excerpt)!
        let unverified = NativeReaderSourceResult(context: context, selectionTicket: excerpt.selection.ticket, status: .unmapped, verifiedText: "MUST NOT COPY", destinationAnchor: nil)
        try check(!view.acceptSourceResult(unverified, for: excerpt), "unmapped never succeeds")
        try check(view.lastFailure?.contains("unmapped") == true, "source rejection remains visible")
        for status in [NativeReaderSourceResult.Status.ambiguous, .stale, .unsupported, .uncertain, .rejected] {
            let request = view.requestSource(.excerpt)!
            try check(!view.acceptSourceResult(.init(context: context, selectionTicket: request.selection.ticket, status: status, verifiedText: "BAD", destinationAnchor: nil), for: request), "nonverified source result")
        }
        try check(privatePasteboard.string(forType: .string) == expectedCopy, "reject preserves clipboard")
        let verified = view.requestSource(.excerpt)!
        try check(view.acceptSourceResult(.init(context: context, selectionTicket: verified.selection.ticket, status: .verified, verifiedText: "$x^2 + y$", destinationAnchor: nil), for: verified), "existing-owner verified Typst excerpt")
        try check(privatePasteboard.string(forType: .string) == "$x^2 + y$", "only owner returned source copied")

        // Real native responder methods and actual NSEvent mouse entry points.
        let start = try map.presentation(of: .init(blockID: block.id, utf16: 10, affinity: .downstream))
        view.bodyTextView.setSelectedRange(NSRange(location: start, length: 0))
        view.bodyTextView.moveRightAndModifySelection(nil)
        try check(view.store.selection?.fragments.first?.exact == "e\u{301}", "native keyboard grapheme selection")
        view.bodyTextView.moveRight(nil)
        let caretRange = view.bodyTextView.selectedRange()
        try check(caretRange.length == 0, "native arrow collapses selection")
        let bidiStart = try map.presentation(of: .init(blockID: block.id, utf16: 44, affinity: .downstream))
        view.bodyTextView.setSelectedRange(NSRange(location: bidiStart, length: 0), affinity: .downstream, stillSelecting: false)
        view.bodyTextView.moveRightAndModifySelection(nil)
        // AppKit's bidi visual/logical arrow preference can differ by host. From
        // the interior caret only the independently authored adjacent א or ב is
        // a legal single-character selection; either must copy in logical order.
        let bidiPiece = view.store.selection?.fragments.first?.exact
        try check(bidiPiece == "א" || bidiPiece == "ב", "native bidi adjacent grapheme")
        try view.select(from: .init(blockID: block.id, utf16: 43, affinity: .upstream), to: .init(blockID: block.id, utf16: 46, affinity: .downstream))
        try check(view.copyPlainText() && privatePasteboard.string(forType: .string) == "אבג", "bidi copy retains logical order")
        let ligatureStart = try map.presentation(of: .init(blockID: block.id, utf16: 35, affinity: .downstream))
        view.bodyTextView.setSelectedRange(NSRange(location: ligatureStart, length: 0))
        for _ in 0..<3 { view.bodyTextView.moveForwardAndModifySelection(nil) }
        try check(view.store.selection?.fragments.first?.exact == "ffi", "ligature logical caret positions")
        var focused: [String?] = []
        view.callbacks.focusChanged = { focused.append($0) }
        _ = view.bodyTextView.becomeFirstResponder()
        try check(!focused.isEmpty, "logical native responder focus")
        let c1 = try view.caretGeometry(at: .init(blockID: block.id, utf16: 13, affinity: .downstream))
        let c2 = try view.caretGeometry(at: .init(blockID: block.id, utf16: 27, affinity: .downstream))
        let down = NSEvent.mouseEvent(with: .leftMouseDown, location: view.bodyTextView.convert(NSPoint(x: c1.rect.minX, y: c1.rect.midY), to: nil), modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        let drag = NSEvent.mouseEvent(with: .leftMouseDragged, location: view.bodyTextView.convert(NSPoint(x: c2.rect.minX, y: c2.rect.midY), to: nil), modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 2, clickCount: 1, pressure: 1)!
        view.bodyTextView.mouseDown(with: down)
        view.bodyTextView.mouseDragged(with: drag)
        try check(view.store.selection != nil, "native mouse selection")
        try view.store.selection!.validate(in: document)
        let tab = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "\t", charactersIgnoringModifiers: "\t", isARepeat: false, keyCode: 48)!
        view.bodyTextView.keyDown(with: tab)
        try check(view.focusedNodeID != nil, "native semantic keyboard focus")
        var sourceEvents = 0, chatEvents = 0, semanticEvents = 0
        view.callbacks.sourceRequested = { _ in sourceEvents += 1 }
        view.callbacks.chatRequested = { command, _ in if case .open = command { chatEvents += 1 } else { fatalError("Implicit Send") } }
        view.callbacks.semanticActivated = { _, _ in semanticEvents += 1 }
        let link = document.blocks.flatMap(\.orderedNodes).first { $0.link == "https://example.org/reader" }!
        try check(view.activate(nodeID: link.id), "explicit link callback")
        try check(sourceEvents == 0 && chatEvents == 0 && semanticEvents == 1, "link has no source/send side effect")
        let linkBlock = document.blocks.first { $0.orderedNodes.contains(where: { $0.id == link.id }) }!
        let linkRects = view.rects(blockID: linkBlock.id, logical: link.rangeUTF16[0]..<link.rangeUTF16[1])
        let linkPoint = NSPoint(x: linkRects[0].midX, y: linkRects[0].midY)
        view.pointerDown(at: linkPoint)
        view.pointerUp(at: linkPoint)
        try check(semanticEvents == 2 && sourceEvents == 0 && chatEvents == 0, "ordinary native link click delegates explicit action")
        let wordCaret = try view.caretGeometry(at: .init(blockID: block.id, utf16: 30, affinity: .downstream))
        view.pointerDown(at: NSPoint(x: wordCaret.rect.minX, y: wordCaret.rect.midY), clickCount: 2)
        try check(view.store.selection?.fragments.first?.exact == "office", "native double-click word selection")
        view.openChat()
        try check(chatEvents == 1, "explicit Ask opens only")

        // Real AX API calls on NSTextView and NSAccessibilityElement tree.
        try check(view.bodyTextView.accessibilityRole() == .textArea, "native AX text area")
        try check(view.bodyTextView.accessibilityValue()?.unicodeScalars.map(\.value) == oracleTexts.joined(separator: "\n").unicodeScalars.map(\.value), "AX exact logical value")
        let roots = view.bodyTextView.accessibilityChildren() as! [NativeReaderAXElement]
        try check(roots.map(\.node.id) == document.blocks.map(\.id), "AX reading order")
        try check(roots[0].accessibilityRole()?.rawValue == "AXHeading" && (roots[0].accessibilityValue() as? Int) == 2, "AX heading role/level")
        func flatten(_ elements: [NativeReaderAXElement]) -> [NativeReaderAXElement] {
            elements.flatMap { [$0] + flatten(($0.accessibilityChildren() as? [NativeReaderAXElement]) ?? []) }
        }
        let axAll = flatten(roots)
        let axLink = axAll.first { $0.node.id == link.id }!
        try check(axLink.accessibilityRole() == .link && axLink.accessibilityURL()?.absoluteString == "https://example.org/reader", "AX link attributes")
        try check(axLink.accessibilityPerformPress(), "AX explicit press callback")
        try check(sourceEvents == 0 && chatEvents == 1, "AX action never implicitly writes/sends")
        let axAnnotation = axAll.first { $0.node.kind == .annotation }!
        try check(axAnnotation.accessibilityHelp()?.contains("mark:term") == true, "AX annotation target")
        try check(axAnnotation.accessibilityPerformPress(), "AX annotation native activation")
        try check(view.returnFromReference(), "one reference-return origin")
        let axMath = axAll.first { $0.node.kind == .math }!
        try check(axMath.accessibilityHelp()?.contains("<math") == true && axMath.accessibilityLabel()?.contains("Unit object") == true, "MathML and object AX injection")
        roots[1].setAccessibilitySelectedTextRange(NSRange(location: 10, length: 2))
        try check(roots[1].accessibilitySelectedText() == "e\u{301}" && roots[1].accessibilitySelectedTextRange() == NSRange(location: 10, length: 2), "AX block selection API")
        let globalRange = NSRange(location: 16 + 16, length: 11)
        view.bodyTextView.setAccessibilitySelectedTextRange(globalRange)
        try check(view.bodyTextView.accessibilitySelectedText() == "👩‍👩‍👧‍👦" && view.bodyTextView.accessibilitySelectedTextRange() == globalRange, "AX logical attachment-safe global range")
        try check(view.bodyTextView.accessibilityNumberOfCharacters() == oracleTexts.joined(separator: "\n").utf16.count, "AX logical character count")
        try check(view.bodyTextView.accessibilityString(for: globalRange) == "👩‍👩‍👧‍👦", "AX string for logical range")
        try check(view.bodyTextView.accessibilityAttributedString(for: globalRange)?.string == "👩‍👩‍👧‍👦", "AX attributed logical string")
        try check(view.bodyTextView.accessibilityRange(for: globalRange.location + 2) == globalRange, "AX grapheme range for scalar interior")
        try check(view.bodyTextView.accessibilitySelectedTextRanges()?.first?.rangeValue == globalRange, "AX selected ranges in logical units")
        try check(view.bodyTextView.accessibilityFrame(for: NSRange(location: globalRange.location, length: 0)).height > 0, "AX caret geometry")
        let afterFormula = 16 + 51 + 1 + 37
        try check(view.bodyTextView.accessibilityString(for: NSRange(location: afterFormula, length: 8)) == "Repeated", "AX range after attachment uses logical UTF16")
        try check(roots[1].accessibilityFrame().height > 0, "AX actual layout frame")
        axLink.setAccessibilityFocused(true)
        try check(axLink.isAccessibilityFocused(), "AX focus API")

        try view.select(from: .init(blockID: block.id, utf16: 27, affinity: .downstream), to: .init(blockID: block.id, utf16: 16, affinity: .upstream))
        let reverseAffinity = view.bodyTextView.selectionAffinity
        let held = view.store.selection!
        let oldGeometry = try view.caretGeometry(at: .init(blockID: block.id, utf16: 16, affinity: .upstream))
        let oldAX = roots[1]
        let anchor = NativeReaderViewportAnchor(identity: document.identity, position: .init(blockID: document.blocks[8].id, utf16: 0, affinity: .downstream), offsetY: 0)
        view.setFrameSize(NSSize(width: 320, height: 180))
        view.restoreViewport(anchor)
        let savedAnchor = view.viewportAnchor()!
        try view.setAppearance(.init(fontSize: 28, zoom: 1.25, theme: .dark))
        let afterAnchor = view.viewportAnchor()!
        try check(view.store.selection == held && view.bodyTextView.selectionAffinity == reverseAffinity, "reflow preserves logical ticket/fragments/affinity")
        try check(savedAnchor.position.blockID == afterAnchor.position.blockID, "viewport logical block retained")
        try rejects("stale width/font/theme geometry") { try view.validateGeometry(oldGeometry) }
        try check(oldAX.accessibilityChildren()?.isEmpty == true && !oldAX.accessibilityPerformPress(), "old AX revoked")
        try check(view.outline.map(\.displayText) == ["Native contract", "Next"], "outline semantics")
        try check(view.navigate(toAnchor: "reader-0f62bf59acd190972fbe-1"), "native outline anchor")
        try check(view.returnFromReference(), "reference return after reflow")
        let beforeHeightResize = try view.caretGeometry(at: .init(blockID: block.id, utf16: 16, affinity: .downstream))
        view.setFrameSize(NSSize(width: view.frame.width, height: view.frame.height + 20))
        try rejects("height-only resize invalidates geometry") { try view.validateGeometry(beforeHeightResize) }

        // Missing cache on reflow is an explicit unsupported state. It retains
        // the common selection and a presentation-only anchor until preparation.
        let preparedSelection = view.store.selection!
        let preparedAffinity = view.bodyTextView.selectionAffinity
        let preMissingAnchor = view.viewportAnchor()!
        let obsoleteKey = view.renderKey!
        view.cachedObject = nil
        view.setFrameSize(NSSize(width: 640, height: 180))
        try check(view.renderKey == nil && view.lastFailure?.contains("unsupportedObject") == true, "missing object cache visible unsupported state")
        try check(view.store.selection == preparedSelection, "preparation holds logical selection")
        view.setFrameSize(NSSize(width: 960, height: 180))
        let pendingKey = view.requestedRenderKey!
        try rejects("old object preparation key") { try view.refreshPreparedObjects(for: obsoleteKey) }
        view.cachedObject = unitObject
        try view.refreshPreparedObjects(for: pendingKey)
        try check(view.store.selection == preparedSelection && view.bodyTextView.selectionAffinity == preparedAffinity, "matching preparation restores selection and affinity")
        try check(view.viewportAnchor()?.position.blockID == preMissingAnchor.position.blockID, "matching preparation restores viewport anchor")
        var pendingPaint = 0
        view.callbacks.painted = { _ in pendingPaint += 1 }
        try check(pendingPaint == 0, "cache preparation does not acknowledge paint")
        _ = try paint(view, file: nil)
        try check(pendingPaint == 1, "prepared objects acknowledge only real draw")

        // Publication held by the common owner; no duplicated snapshot database.
        let nextGeneration = try view.store.beginRequest()
        let candidate = NativeReaderDocument(schemaVersion: document.schemaVersion, identity: document.identity, generation: nextGeneration,
            requiredCapabilities: document.requiredCapabilities, blocks: document.blocks, assets: document.assets, diagnostics: document.diagnostics)
        let nextContext = NativeReaderRequestContext(requestID: UUID(), viewID: context.viewID, generation: nextGeneration, target: context.target)
        try rejects("held publication") { try view.adopt(candidate, context: nextContext) }
        try check(view.store.document == document && view.store.selection == held, "held accepted snapshot unchanged")
        // Newer selection ticket cannot be cleared by an old release or source ack.
        roots[1].setAccessibilitySelectedTextRange(NSRange(location: 0, length: 1)) // stale AX, no effect
        try view.select(from: .init(blockID: block.id, utf16: 0, affinity: .upstream), to: .init(blockID: block.id, utf16: 2, affinity: .downstream))
        let newer = view.store.selection!
        view.releaseSelection(ticket: held.ticket)
        try check(view.store.selection == newer, "old release cannot clear newer selection")
        try check(!view.acceptSourceResult(.init(context: context, selectionTicket: verified.selection.ticket, status: .verified, verifiedText: "LATE", destinationAnchor: nil), for: verified), "late source result rejected")
        view.releaseSelection(ticket: newer.ticket)
        try view.adopt(candidate, context: nextContext)
        try check(view.store.document?.generation == nextGeneration, "explicit matching release permits publication")

        // Negative ranges, object metrics, key/target/generation and paint lifetime.
        try rejects("negative UTF16") { _ = try view.textMap!.snapped(.init(blockID: block.id, utf16: -1, affinity: .downstream)) }
        try rejects("beyond UTF16") { _ = try view.textMap!.snapped(.init(blockID: block.id, utf16: 9999, affinity: .downstream)) }
        try rejects("overflow range") { _ = try view.textMap!.normalized(NSRange(location: 1, length: Int.max), affinity: .downstream) }
        try rejects("NSNotFound") { _ = try view.textMap!.normalized(NSRange(location: NSNotFound, length: 0), affinity: .downstream) }
        let currentKey = view.renderKey!
        try rejects("NaN point") { _ = try view.hitTestText(at: .init(x: CGFloat.nan, y: 5), key: currentKey) }
        try rejects("negative point") { _ = try view.hitTestText(at: .init(x: -1, y: -1), key: currentKey) }
        try rejects("NaN font") { try view.setAppearance(.init(fontSize: .nan, zoom: 1, theme: .light)) }
        let frameBefore = view.frame
        view.setFrameSize(.init(width: CGFloat.nan, height: 100))
        try check(view.frame == frameBefore, "invalid resize rejected before AppKit")
        let legalPosition = NativeReaderTextPosition(blockID: block.id, utf16: 0, affinity: .downstream)
        let invalidRect = NativeReaderTextGeometry(key: currentKey, position: legalPosition, rect: .init(x: 0, y: 0, width: -1, height: 10))
        try rejects("negative geometry size") { try view.validateGeometry(invalidRect) }
        for raw in [4,5,7,8,11,14,17,18,20,21,23,24,26] {
            let snapped = try view.textMap!.snapped(.init(blockID: block.id, utf16: raw, affinity: .upstream))
            try check(unicodeBlockBoundaries.contains(snapped.utf16) && snapped.utf16 <= raw, "illegal grapheme endpoint snaps upstream")
            let down = try view.textMap!.snapped(.init(blockID: block.id, utf16: raw, affinity: .downstream))
            try check(unicodeBlockBoundaries.contains(down.utf16) && down.utf16 >= raw, "illegal grapheme endpoint snaps downstream")
        }
        let split = NativeReaderSelection(ticket: UUID(), blockID: block.id, rangeUTF16: 13..<14, exact: "😀")
        try rejects("surrogate half in common selection") { try split.validate(in: document) }
        try rejects("unsupported object has no bare math fallback") { _ = try make(document, provider: false) }
        let badStore = NativeReaderDocumentStore()
        _ = try badStore.beginRequest()
        let badView = NativeReaderTextView(store: badStore)
        badView.cachedObject = { node, key in .init(key: key, size: .init(width: CGFloat.infinity, height: 5), baseline: 0, accessibilityLabel: "bad", draw: { _ in }) }
        let badContext = NativeReaderRequestContext(requestID: UUID(), viewID: badStore.viewID, generation: 1, target: document.identity)
        try rejects("invalid prepared metrics") { try badView.adopt(document, context: badContext) }
        try check(badStore.document == nil && badView.lastFailure != nil, "invalid object atomic visible rejection")
        badView.cachedObject = { node, key in
            let wrongKey = NativeReaderTextRenderKey(identity: key.identity, documentGeneration: key.documentGeneration,
                viewID: UUID(), layoutGeneration: key.layoutGeneration, width: key.width, appearance: key.appearance)
            return unitObject(node, wrongKey)
        }
        try rejects("prepared object from another view") { try badView.adopt(document, context: badContext) }
        let alienContext = NativeReaderRequestContext(requestID: UUID(), viewID: UUID(), generation: nextGeneration, target: document.identity)
        try rejects("alien view") { try view.adopt(candidate, context: alienContext) }
        let alienIdentity = NativeDocumentIdentity(documentID: "other", serviceID: document.identity.serviceID, revision: document.identity.revision, scope: .fixture)
        try rejects("alien document") { try view.adopt(candidate, context: .init(requestID: UUID(), viewID: context.viewID, generation: nextGeneration, target: alienIdentity)) }
        try rejects("stale generation") { try view.adopt(document, context: context) }
        let latestGeometry = try view.caretGeometry(at: .init(blockID: block.id, utf16: 0, affinity: .downstream))
        var cancelPaints = 0
        view.callbacks.painted = { _ in cancelPaints += 1 }
        view.cancel()
        _ = try paint(view, file: nil)
        try check(cancelPaints == 0 && view.requestedRenderKey == nil && view.requestSource(.excerpt) == nil, "cancel revokes draw acknowledgment and operations")
        try rejects("cancelled object completion") { try view.refreshPreparedObjects(for: currentKey) }
        try rejects("cancel geometry") { try view.validateGeometry(latestGeometry) }
        view.dispose()
        try rejects("dispose adoption") { try view.adopt(candidate, context: nextContext) }
        try check(!view.copyPlainText() && !view.activate(nodeID: link.id) && view.requestSource(.excerpt) == nil, "disposed actions inert")
        badView.dispose()
        tick()
        return ["matrix": matrix, "unicodeAssertions": unicodeAssertions, "input": "pass", "copy": "pass", "accessibility": "pass",
                "reflow": "pass", "lifetime": "pass", "negative": "pass", "objectScope": "unit injections only; actual NA03 fidelity unverified", "skips": 0]
    }
}
