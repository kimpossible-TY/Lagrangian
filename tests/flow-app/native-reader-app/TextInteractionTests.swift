import AppKit
import CoreText
import ObjectiveC

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

private struct TextDocumentProvider: NativeReaderDocumentProviding {
    let load: (NativeReaderRequestContext) async throws -> NativeReaderDocument
    func document(for context: NativeReaderRequestContext) async throws -> NativeReaderDocument { try await load(context) }
}

@MainActor private final class LayoutRestoreGate {
    var armed = false
    private var continuations = [CheckedContinuation<Void, Never>]()
    func wait() async {
        guard armed else { return }
        await withCheckedContinuation { continuations.append($0) }
    }
    func release() {
        armed = false
        let waiting = continuations; continuations = []
        waiting.forEach { $0.resume() }
    }
}

private final class UnpaintedTestCell: NSTextAttachmentCell {
    let size: NSSize
    init(size: NSSize) { self.size = size; super.init(textCell: "") }
    required init(coder: NSCoder) { fatalError("not used") }
    override func cellSize() -> NSSize { size }
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {}
}

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

// Test-only isolation of the two PUBLIC pasteboard factories. NSTextFinder
// normally synchronizes its query through the system Find pasteboard. Redirect
// that boundary before AppKit initializes; matching, controls and callbacks are
// still the real platform implementation. No general/system Find clipboard is
// read, cleared, restored or written by this process.
@MainActor private enum FindPasteboardIsolation {
    static let findName = "dev.lagrangian.NA02.find." + UUID().uuidString
    static let generalName = "dev.lagrangian.NA02.general." + UUID().uuidString
    static var findCalls = 0
    static func install() {
        let named = class_getClassMethod(NSPasteboard.self, NSSelectorFromString("pasteboardWithName:"))!
        let substitute = class_getClassMethod(NSPasteboard.self, #selector(NSPasteboard.na02_namedPasteboard(_:)))!
        method_exchangeImplementations(named, substitute)
        let general = class_getClassMethod(NSPasteboard.self, NSSelectorFromString("generalPasteboard"))!
        let isolated = class_getClassMethod(NSPasteboard.self, #selector(NSPasteboard.na02_generalPasteboard))!
        method_exchangeImplementations(general, isolated)
    }
}
extension NSPasteboard {
    @MainActor @objc dynamic class func na02_namedPasteboard(_ name: NSString) -> NSPasteboard {
        var isolated = name as String
        if isolated == NSPasteboard.Name.find.rawValue {
            FindPasteboardIsolation.findCalls += 1
            isolated = FindPasteboardIsolation.findName
        } else if isolated == NSPasteboard.Name.general.rawValue {
            isolated = FindPasteboardIsolation.generalName
        }
        // After exchange this calls the original public factory.
        return na02_namedPasteboard(isolated as NSString)
    }
    @MainActor @objc dynamic class func na02_generalPasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name(FindPasteboardIsolation.generalName))
    }
}

@MainActor private final class FindWindowObservation: NSObject {
    private(set) var visibleOrFocusEvents: [String] = []
    override init() {
        super.init()
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didBecomeMainNotification, NSWindow.didExposeNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(changed(_:)), name: name, object: nil)
        }
    }
    @objc private func changed(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window.isVisible || window.isKeyWindow || window.isMainWindow || notification.name != NSWindow.didExposeNotification {
            visibleOrFocusEvents.append(notification.name.rawValue)
        }
    }
    deinit { NotificationCenter.default.removeObserver(self) }
}

@main struct TextInteractionMain {
    @MainActor static func main() async {
        do {
            FindPasteboardIsolation.install()
            _ = NSApplication.shared.setActivationPolicy(.prohibited)
            if CommandLine.arguments[1] == "--core-long" {
                try coreLongSelection(folder: URL(fileURLWithPath: CommandLine.arguments[2]),
                  out: URL(fileURLWithPath: CommandLine.arguments[3]), count: Int(CommandLine.arguments[4])!)
                return
            }
            let document = try NativeReaderDocument.decode(Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
            let out = URL(fileURLWithPath: CommandLine.arguments[2])
            try check(document.blocks.map(\.displayText) == oracleTexts, "actual compiler logical reading order")
            var results = try run(document, out: out)
            try visibleObjectPaintRegression(document)
            results["stage2"] = try await largeObjectRegression(document)
            try await largeRecoveryBudgetRegression(document)
            results["stage3"] = try await diskWindowRegression(document, out: out)
            NSPasteboard(name: .init(FindPasteboardIsolation.findName)).releaseGlobally()
            NSPasteboard(name: .init(FindPasteboardIsolation.generalName)).releaseGlobally()
            let data = try JSONSerialization.data(withJSONObject: results, options: [.sortedKeys])
            print(String(decoding: data, as: UTF8.self))
        } catch {
            fputs("TextInteractionTests FAILED: \(error)\n", stderr)
            exit(1)
        }
    }
    nonisolated static func onMainThread() -> Bool { Thread.isMainThread }
    @MainActor static func waitFor(_ message: String, _ predicate: () -> Bool) async throws {
        let deadline = Date(timeIntervalSinceNow: 5)
        while !predicate() && Date() < deadline { try await Task.sleep(nanoseconds: 5_000_000) }
        try check(predicate(), message)
    }
    @MainActor static func finishLazyPreparation(_ view: NativeReaderTextView) async throws {
        var passes = 0
        while let task = view.lazyTask {
            passes += 1
            try check(passes <= 1024, "lazy preparation reaches a bounded idle state")
            await task.value
        }
    }
    @MainActor static func visibleObjectPaintRegression(_ fixture: NativeReaderDocument) throws {
        let source = fixture.blocks.flatMap(\.orderedNodes).first { $0.kind == .math }!
        var encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(source)) as! [String: Any]
        encoded["rangeUTF16"] = [0, source.displayText.utf16.count]
        encoded["anchors"] = []; encoded["annotationTargets"] = []
        let blocks = try (0..<600).map { index -> NativeReaderNode in
            var value = encoded; value["id"] = "paint-regression-\(index)"
            return try JSONDecoder().decode(NativeReaderNode.self, from: JSONSerialization.data(withJSONObject: value))
        }
        let document = NativeReaderDocument(schemaVersion: 1, identity: fixture.identity, generation: 1,
            requiredCapabilities: ["semantic-tree-v1"], blocks: blocks, assets: [], diagnostics: [])
        try document.validate()
        let (view, _) = try make(document)
        defer { view.dispose() }
        view.setFrameSize(NSSize(width: 640, height: 96))
        let body = view.bodyTextView
        let manager = body.layoutManager!
        manager.ensureLayout(for: body.textContainer!)
        let attachment = body.textStorage!.attribute(.attachment, at: 0, effectiveRange: nil) as! NSTextAttachment
        let originalCell = attachment.attachmentCell!
        attachment.attachmentCell = UnpaintedTestCell(size: originalCell.cellSize())
        var acknowledgements = 0
        view.callbacks.painted = { key in if key == view.renderKey { acknowledgements += 1 } }
        let visible = body.visibleRect
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(ceil(visible.width)),
                pixelsHigh: Int(ceil(visible.height)), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else { throw TextTestError(description: "paint regression bitmap") }
        body.displayIgnoringOpacity(visible, in: graphics)
        try check(acknowledgements == 0, "missing visible object paint prevents acknowledgement")
        attachment.attachmentCell = originalCell
        let start = ProcessInfo.processInfo.systemUptime
        body.displayIgnoringOpacity(visible, in: graphics)
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        try check(acknowledgements == 1, "full visible object draw acknowledges paint")
        try check(elapsed < 0.5, "600-object visible draw took \(elapsed) seconds")
    }
    @MainActor static func largeObjectRegression(_ fixture: NativeReaderDocument) async throws -> [String: Any] {
        let source = fixture.blocks.flatMap(\.orderedNodes).first { $0.kind == .math }!
        var encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(source)) as! [String: Any]
        encoded["rangeUTF16"] = [0, source.displayText.utf16.count]
        encoded["anchors"] = []; encoded["annotationTargets"] = []
        var meaning = encoded["math"] as! [String: Any]; meaning["display"] = true; encoded["math"] = meaning
        let blocks = try (0..<320).map { i -> NativeReaderNode in
            var value = encoded; value["id"] = "large-\(i)"
            return try JSONDecoder().decode(NativeReaderNode.self, from: JSONSerialization.data(withJSONObject: value))
        }
        let document = NativeReaderDocument(schemaVersion: 1, identity: fixture.identity, generation: 1,
            requiredCapabilities: ["semantic-tree-v1"], blocks: blocks, assets: [], diagnostics: [])
        try document.validate()
        try check(NativeReaderPreparedTextObject.isLarge(document) && NativeReaderPreparedTextObject.initialNodes(in: document).count == 128,
            "320 formulas prepare only first 128")
        let small = NativeReaderDocument(schemaVersion: 1, identity: document.identity, generation: 1,
            requiredCapabilities: document.requiredCapabilities, blocks: Array(blocks.prefix(128)), assets: [], diagnostics: [])
        try check(!NativeReaderPreparedTextObject.isLarge(small) && NativeReaderPreparedTextObject.initialNodes(in: small).count == 128,
            "128 formulas remain eager")
        let store = NativeReaderDocumentStore(); _ = try store.beginRequest()
        let context = NativeReaderRequestContext(requestID: UUID(), viewID: store.viewID, generation: 1, target: document.identity)
        let view = NativeReaderTextView(store: store)
        defer { view.dispose() }
        view.setFrameSize(NSSize(width: 640, height: 96))
        let initialIDs = Set(blocks.prefix(128).map(\.id))
        func prepared(_ node: NativeReaderNode, _ key: NativeReaderTextRenderKey, cost: Int = 122_880) -> NativeReaderPreparedTextObject {
            NativeReaderPreparedTextObject(key: key, size: NSSize(width: 240, height: 40), baseline: 0,
                accessibilityLabel: node.math!.normalizedText, draw: { _ in }, cost: cost)
        }
        view.cachedObject = { node, key in initialIDs.contains(node.id) ? prepared(node, key) : nil }
        try view.adopt(document, context: context)
        var reflowNotifications = 0
        view.callbacks.layoutChanged = { reflowNotifications += 1 }
        _ = view.performFindAction(.showFindInterface)
        try check(reflowNotifications == 1, "successful placeholder reflow notifies preparation owner when Find opens")
        let key = view.renderKey!
        let initial = Dictionary(uniqueKeysWithValues: blocks.prefix(128).map { ($0.id, prepared($0, key)) })
        let placeholder = NativeReaderPreparedTextObject.placeholder(blocks[280], key: key)
        try check(placeholder.isPlaceholder && placeholder.size == NSSize(width: 240, height: 36) && !placeholder.accessibilityLabel.isEmpty,
            "deterministic bounded display placeholder")
        var inline = encoded; var inlineMath = meaning; inlineMath["display"] = false; inline["math"] = inlineMath
        let inlineNode = try JSONDecoder().decode(NativeReaderNode.self, from: JSONSerialization.data(withJSONObject: inline))
        try check(NativeReaderPreparedTextObject.placeholder(inlineNode, key: key).size == NSSize(width: 24, height: 16), "inline placeholder")
        let labelNode = fixture.blocks.flatMap(\.orderedNodes).first { $0.kind == .figure || $0.kind == .image }!
        let narrowKey = NativeReaderTextRenderKey(identity: key.identity, documentGeneration: 1, viewID: key.viewID,
            layoutGeneration: key.layoutGeneration, width: 100, appearance: key.appearance)
        try check(NativeReaderPreparedTextObject.placeholder(labelNode, key: narrowKey).size == NSSize(width: 100, height: 120), "figure placeholder clamps to width")
        var offMain = false, batches = 0, requestedIDs = Set<String>()
        view.configureLazyObjects(key: key, initial: initial) { nodes, current in
            batches += 1
            requestedIDs.formUnion(nodes.map(\.id))
            let result = await Task.detached {
                let main = onMainThread()
                let objects = Dictionary(uniqueKeysWithValues: nodes.map { node in
                    (node.id, NativeReaderPreparedTextObject(key: current, size: NSSize(width: 240, height: 48), baseline: 0,
                        accessibilityLabel: node.math!.normalizedText, draw: { _ in }, cost: 2 * 1024 * 1024))
                })
                return (objects, main)
            }.value
            offMain = !result.1
            return result.0
        }
        try check(view.preparedObjectCost == 128 * 122_880, "initial cost within exact budget")
        let initialRange = try view.textMap!.presentationRange(blockID: blocks[0].id, logical: 0..<source.displayText.utf16.count)
        view.bodyTextView.setSelectedRange(initialRange, affinity: .upstream, stillSelecting: false)
        let selected = view.bodyTextView.selectedRanges, selection = store.selection
        let text = view.bodyTextView.string, finder = view.scrollView.isFindBarVisible
        try check(view.navigate(toNodeID: blocks[280].id), "TOC jump changes viewport")
        view.prepareVisibleObjects()
        let anchor = view.viewportAnchor()
        let visible = view.scrollView.contentView.bounds
        let buffered = visible.insetBy(dx: 0, dy: -visible.height)
        let expectedRequests = Set(blocks.filter { node in
            view.rects(blockID: node.id, logical: 0..<source.displayText.utf16.count).contains { $0.intersects(buffered) }
        }.map(\.id))
        try await waitFor("scroll lazy-prepares newly visible formula") { view.preparedObjectIDs.contains(blocks[280].id) }
        try await waitFor("one viewport above and below requested") { expectedRequests.isSubset(of: requestedIDs) }
        try check(expectedRequests.count > 1, "viewport buffer includes neighboring attachments")
        try check(view.preparedObjectCost <= 16 * 1024 * 1024 && initialIDs.intersection(view.preparedObjectIDs).count < 128,
            "offscreen entries evicted within 16 MiB")
        let evictedID = initialIDs.subtracting(view.preparedObjectIDs).sorted().first!
        let evictedRange = try view.textMap!.presentationRange(blockID: evictedID, logical: 0..<source.displayText.utf16.count)
        let evictedAttachment = view.bodyTextView.textStorage!.attribute(.attachment, at: evictedRange.location,
            effectiveRange: nil) as! NSTextAttachment
        try check(evictedAttachment.attachmentCell!.cellSize() == NSSize(width: 240, height: 36),
            "eviction replaces retained paint cell with lightweight placeholder metrics")
        try check(view.bodyTextView.selectedRanges == selected && store.selection == selection && view.bodyTextView.selectionAffinity == .upstream &&
            view.bodyTextView.string == text && view.scrollView.isFindBarVisible == finder, "in-place replacement preserves selection, text and find bar")
        try check(view.viewportAnchor()?.position.blockID == anchor?.position.blockID && offMain, "viewport anchor and background preparation")
        // Ordinary clip-view scrolling, without a navigation helper, must also
        // trigger preparation through the bounds-change observer.
        let scrollTarget = try view.textMap!.presentationRange(blockID: blocks[200].id, logical: 0..<source.displayText.utf16.count)
        view.bodyTextView.scrollRangeToVisible(scrollTarget)
        try await waitFor("clip-view scroll prepares missing attachment") { view.preparedObjectIDs.contains(blocks[200].id) }
        try check(view.preparedObjectCost <= 16 * 1024 * 1024 && view.bodyTextView.selectedRanges == selected,
            "metric-changing scroll batch preserves selection and budget")
        try check(view.returnFromReference(), "Return restores the saved viewport")
        try await waitFor("Return lazy-prepares evicted origin") { view.preparedObjectIDs.contains(blocks[0].id) }
        try check(view.bodyTextView.selectedRanges == selected && view.scrollView.isFindBarVisible == finder,
            "Return preparation retains selection and find interface")
        // A provider may reduce a batch to fit the preparation budget. Nodes
        // omitted from that result must still get their own later request.
        let partialTarget = try view.textMap!.presentationRange(blockID: blocks[150].id, logical: 0..<source.displayText.utf16.count)
        view.bodyTextView.scrollRangeToVisible(partialTarget)
        try await waitFor("partial scenario viewport prepared") { view.preparedObjectIDs.contains(blocks[150].id) }
        try await finishLazyPreparation(view)
        let buffer = view.scrollView.contentView.bounds.insetBy(dx: 0, dy: -view.scrollView.contentView.bounds.height)
        let partialIDs = Set(blocks.filter { node in
            view.rects(blockID: node.id, logical: 0..<source.displayText.utf16.count).contains { $0.intersects(buffer) }
        }.map(\.id))
        try check(partialIDs.count > 1, "scroll buffer covers multiple formulas")
        var partialBatches = 0
        view.configureLazyObjects(key: key, initial: [:]) { nodes, current in
            partialBatches += 1
            guard let node = nodes.first else { return [:] }
            return [node.id: prepared(node, current)]
        }
        try await waitFor("partial budget batches retry omitted nodes") { partialIDs.isSubset(of: view.preparedObjectIDs) }
        try check(partialBatches > 1, "partial provider uses multiple bounded batches")
        let cache = NativeReaderLazyObjectCache()
        let half = 8 * 1024 * 1024
        cache.insert(["a": prepared(blocks[0], key, cost: half), "b": prepared(blocks[1], key, cost: half)], protecting: [])
        cache.touch(["a"])
        cache.insert(["c": prepared(blocks[2], key, cost: half)], protecting: ["a"])
        try check(cache.cost == 16 * 1024 * 1024 && Set(cache.objects.keys) == ["a", "c"], "deterministic LRU evicts least recent offscreen entry")
        // Exercise AppKit's own query/action path at a distant attachment. Find
        // deliberately changes selection; lazy completion must preserve that
        // new result and the already open embedded bar.
        func descendants(_ parent: NSView) -> [NSView] { parent.subviews.flatMap { [$0] + descendants($0) } }
        let findStart = try view.textMap!.presentationRange(blockID: blocks[280].id, logical: 0..<source.displayText.utf16.count)
        view.bodyTextView.setSelectedRange(NSRange(location: findStart.location, length: 0))
        guard let bar = view.scrollView.findBarView,
              let field = descendants(bar).compactMap({ $0 as? NSSearchField }).first,
              let action = field.action else { throw TextTestError(description: "large document embedded Find field") }
        field.stringValue = "\u{fffc}"
        try check(field.sendAction(action, to: field.target) && view.performFindAction(.nextMatch), "large document native Find action")
        let foundID = store.selection!.fragments.first!.blockID
        let foundSelection = view.bodyTextView.selectedRanges
        try check(Int(foundID.dropFirst("large-".count))! >= 280, "Find reveals a distant unprepared formula")
        try await waitFor("Find viewport lazy-prepares matching attachment") { view.preparedObjectIDs.contains(foundID) }
        try check(view.bodyTextView.selectedRanges == foundSelection && view.scrollView.isFindBarVisible,
            "Find result and bar survive lazy attachment replacement")
        // Request generation changes retain display authority for this key.
        var continuation: CheckedContinuation<[String: NativeReaderPreparedTextObject], Never>?
        var entered = false, finished = false
        var retainedNodes = [NativeReaderNode]()
        view.configureLazyObjects(key: key, initial: [:]) { nodes, current in
            if !entered {
                entered = true; retainedNodes = nodes
                let value = await withCheckedContinuation { continuation = $0 }
                finished = true
                return value
            }
            return Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, prepared($0, current)) })
        }
        try await waitFor("generation batch entered") { entered }
        _ = try store.beginRequest(); view.invalidateStaleLazyPreparation()
        continuation!.resume(returning: Dictionary(uniqueKeysWithValues: retainedNodes.map { ($0.id, prepared($0, key)) }))
        try await waitFor("late generation batch returned") { finished }
        try await finishLazyPreparation(view)
        try check(Set(retainedNodes.map(\.id)).isSubset(of: view.preparedObjectIDs), "retained key accepts work across a new request")
        // An intentionally uncooperative provider returns after layout/lifetime
        // revocation. Its late result must never mutate cells or cache.
        entered = false; finished = false
        view.configureLazyObjects(key: key, initial: [:]) { _, _ in
            entered = true
            let value = await withCheckedContinuation { continuation = $0 }
            finished = true
            return value
        }
        try await waitFor("width batch entered") { entered }
        view.setFrameSize(NSSize(width: 520, height: 96))
        continuation!.resume(returning: [blocks[280].id: prepared(blocks[280], key)])
        try await waitFor("late width batch returned") { finished }
        for _ in 0..<5 { await Task.yield() }
        try check(view.preparedObjectIDs.isEmpty && view.requestedRenderKey != key, "width cancellation discards late metrics")
        try rejects("stale in-place attachments") { try view.updateObjectAttachments(for: key, objects: initial) }
        for reason in ["appearance", "close"] {
            let current = view.requestedRenderKey!
            try view.refreshPreparedObjects(for: current)
            entered = false; finished = false
            view.configureLazyObjects(key: current, initial: [:]) { _, _ in
                entered = true
                let value = await withCheckedContinuation { continuation = $0 }
                finished = true
                return value
            }
            try await waitFor("\(reason) batch entered") { entered }
            if reason == "appearance" {
                var appearance = view.textAppearance; appearance.theme = .dark
                try view.setAppearance(appearance)
            } else { view.dispose() }
            continuation!.resume(returning: [blocks[280].id: prepared(blocks[280], current)])
            try await waitFor("\(reason) batch returned") { finished }
            for _ in 0..<5 { await Task.yield() }
            try check(view.preparedObjectIDs.isEmpty, "\(reason) discards late objects")
        }
        let failures = try await lazyFailureRegressions(document)
        return ["objects": blocks.count, "initial": initial.count, "maxCost": NativeReaderLazyObjectCache.maxCost,
            "batches": batches, "offMain": offMain, "eviction": true, "retainedGeneration": true, "widthCancellation": true,
            "selectionFindViewport": true, "scroll": true, "buffer": true, "return": true, "partialBatches": partialBatches,
            "appearanceCancellation": true, "closeCancellation": true, "find": true, "evictionPlaceholder": true,
            "findReflowNotification": true, "failures": failures]
    }
    @MainActor static func lazyFailureRegressions(_ document: NativeReaderDocument) async throws -> [String: Any] {
        let blocks = document.blocks
        func prepared(_ node: NativeReaderNode, _ key: NativeReaderTextRenderKey,
                      cost: Int = 65536) -> NativeReaderPreparedTextObject {
            .init(key: key, size: NSSize(width: 200, height: 36), baseline: 0,
                  accessibilityLabel: node.displayText, draw: { _ in }, cost: cost)
        }
        func values(_ nodes: [NativeReaderNode], _ key: NativeReaderTextRenderKey) -> [String: NativeReaderPreparedTextObject] {
            Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, prepared($0, key)) })
        }
        let store = NativeReaderDocumentStore()
        // Use one shared store for Session and the retained TextKit presentation.
        let retained = NativeReaderTextView(store: store)
        defer { retained.dispose() }
        retained.setFrameSize(NSSize(width: 640, height: 96))
        retained.cachedObject = { [weak retained] node, key in
            retained?.cachedLazyObject(node.id, key: key) ?? (blocks.prefix(128).contains(where: { $0.id == node.id }) ? prepared(node, key) : nil)
        }
        var rejectCandidate = false, preparations = 0, lazyKeys = [NativeReaderTextRenderKey]()
        let session = NativeReaderSession(store: store, provider: TextDocumentProvider(load: { context in
            document.rebinding(generation: context.generation)
        }), target: { document.identity }, prepare: { candidate, context in
            preparations += 1
            if rejectCandidate { throw TextTestError(description: "deterministic candidate preparation failure") }
            let key = try retained.preparationKey(for: candidate, context: context)
            return .init(isCurrent: { true }, adopt: {
                try retained.adopt(candidate, context: context)
                retained.configureLazyObjects(key: key, initial: values(Array(blocks.prefix(128)), key)) { nodes, current in
                    lazyKeys.append(current)
                    return values(nodes, current)
                }
            })
        })
        defer { session.event(.dispose) }
        // The same presentation reconciliation used by WindowController.
        session.onChange = {
            retained.invalidateStaleLazyPreparation()
            retained.prepareVisibleObjects()
        }
        session.refresh()
        try await waitFor("initial retained publication") { session.state == .reading && store.document != nil }
        try await finishLazyPreparation(retained)
        let retainedDocument = store.document!, key = retained.renderKey!, context = retained.context!
        let initialIDs = retained.preparedObjectIDs, initialCost = retained.preparedObjectCost
        rejectCandidate = true
        session.refresh()
        try check(retained.preparedObjectIDs == initialIDs && retained.preparedObjectCost == initialCost,
                  "request start preserves retained cache and accounting")
        try await waitFor("failed refresh settles on retained document") { session.failure != nil }
        try check(store.document == retainedDocument && retained.renderKey == key && retained.context == context,
                  "failure preserves retained publication")
        try check(retained.navigate(toNodeID: blocks[280].id), "navigate after failed refresh")
        try await finishLazyPreparation(retained)
        try check(retained.preparedObjectIDs.contains(blocks[280].id), "failed refresh still prepares retained placeholders")
        let range = try retained.textMap!.presentationRange(blockID: blocks[280].id, logical: 0..<blocks[280].displayText.utf16.count)
        retained.bodyTextView.setSelectedRange(range, affinity: .upstream, stillSelecting: false)
        let selection = store.selection, selectedRanges = retained.bodyTextView.selectedRanges
        let callsBeforeHold = preparations, heldIDs = retained.preparedObjectIDs, heldCost = retained.preparedObjectCost
        rejectCandidate = false
        session.refresh()
        try await waitFor("selection-held refresh settles") { session.state == .offline && session.failure == nil }
        try check(preparations == callsBeforeHold && store.document == retainedDocument && retained.renderKey == key &&
                  retained.preparedObjectIDs == heldIDs && retained.preparedObjectCost == heldCost,
                  "held refresh preserves retained provider/cache without preparing candidate")
        try check(retained.navigate(toNodeID: blocks[200].id), "navigate during selection-held refresh")
        try await finishLazyPreparation(retained)
        try check(retained.preparedObjectIDs.contains(blocks[200].id) && !lazyKeys.isEmpty && lazyKeys.allSatisfy { $0 == key },
                  "held refresh lazy work uses retained render key")
        try check(store.selection == selection && retained.bodyTextView.selectedRanges == selectedRanges,
                  "retained loading preserves active selection")
        try rejects("retained pixels do not grant current source authority") { try session.authorize(context) }

        // A transient busy response retries the same IDs; a persistent response
        // stops after the initial attempt plus exactly two retries in this epoch.
        var transientCalls = 0, workerBusy = true
        var retryFailures = [Int]()
        retained.lazyRetryDelay = { failure in
            retryFailures.append(failure)
            workerBusy = false // Deterministic simulated worker teardown at the wait boundary.
            await Task.yield(); try Task.checkCancellation()
        }
        retained.configureLazyObjects(key: key, initial: [:]) { nodes, current in
            transientCalls += 1
            if workerBusy { throw NativeObjectError.unsupported("math-worker-busy") }
            return values(nodes, current)
        }
        try await finishLazyPreparation(retained)
        try check(transientCalls == 2 && retryFailures == [1] && retained.preparedObjectIDs.contains(blocks[200].id), "busy worker teardown completes at retry backoff boundary")
        retryFailures = []
        var persistentCalls = 0
        retained.configureLazyObjects(key: key, initial: [:]) { _, _ in
            persistentCalls += 1
            throw NativeObjectError.unsupported("math-worker-busy")
        }
        try await finishLazyPreparation(retained)
        for _ in 0..<5 { retained.prepareVisibleObjects(); try await finishLazyPreparation(retained) }
        try check(persistentCalls == 3 && retryFailures == [1, 2] && retained.preparedObjectIDs.isEmpty, "persistent error bounded to two delayed retries per ID")
        var cancelledRetryCalls = 0, delayEntered = false
        retained.lazyRetryDelay = { _ in
            delayEntered = true
            try await Task.sleep(nanoseconds: 10_000_000_000)
        }
        retained.configureLazyObjects(key: key, initial: [:]) { _, _ in
            cancelledRetryCalls += 1; throw NativeObjectError.unsupported("math-worker-busy")
        }
        try await waitFor("retry entered cancellable delay") { delayEntered }
        retained.cancelLazyPreparation()
        await Task.yield()
        try check(cancelledRetryCalls == 1 && retained.lazyTask == nil, "cancel backoff never dispatches a retry")

        // Busy discovered after a successful half must still discard the staged
        // result and retry the original range after teardown, without isolating
        // any valid singleton or publishing a partial viewport.
        var nestedCalls = 0, nestedIDs = Set<String>(), nestedWaits = [Int]()
        retained.lazyRetryDelay = { failure in
            nestedWaits.append(failure)
            try check(retained.preparedObjectIDs.isEmpty, "nested busy never publishes staged left half")
        }
        retained.configureLazyObjects(key: key, initial: [:]) { nodes, current in
            nestedCalls += 1
            switch nestedCalls {
            case 1:
                nestedIDs = Set(nodes.map(\.id))
                try check(nodes.count > 1, "nested busy exercises both split halves")
                throw NativeObjectError.budget
            case 3: throw NativeObjectError.unsupported("math-worker-busy")
            default: return values(nodes, current)
            }
        }
        try await finishLazyPreparation(retained)
        try check(nestedCalls == 4 && nestedWaits == [1] && retained.preparedObjectIDs == nestedIDs,
                  "nested busy retries entire viewport and restores every valid sibling")

        func attachment(_ node: NativeReaderNode) throws -> NSTextAttachment {
            let range = try retained.textMap!.presentationRange(blockID: node.id, logical: 0..<node.displayText.utf16.count)
            return retained.bodyTextView.textStorage!.attribute(.attachment, at: range.location, effectiveRange: nil) as! NSTextAttachment
        }
        // The valid first entry used to mutate before the invalid later entry.
        // Snapshot every cell's identity, not just its metrics or visible pixels.
        let attachments = try blocks.map(attachment)
        let cells = attachments.map { $0.attachmentCell! }
        var invalid = NativeReaderPreparedTextObject(key: key, size: NSSize(width: key.width + 1, height: 40),
            baseline: 0, accessibilityLabel: blocks[201].displayText, draw: { _ in }, cost: 65536)
        let invalidPair = [blocks[200].id: prepared(blocks[200], key), blocks[201].id: invalid]
        try rejects("atomic direct attachment update") { try retained.updateObjectAttachments(for: key, objects: invalidPair) }
        try check(zip(attachments, cells).allSatisfy { $0.0.attachmentCell === $0.1 }, "invalid later cell leaves every cell untouched")

        // Seed a full LRU with offscreen objects, then return a valid expensive
        // visible object plus an invalid object. A nontransactional insert would
        // evict the seed and drift both cost and cells before rejecting metrics.
        var batchContinuation: CheckedContinuation<[String: NativeReaderPreparedTextObject], Never>?
        var batchNodes = [NativeReaderNode](), invalidCalls = 0
        let seed = [blocks[0].id: prepared(blocks[0], key, cost: NativeReaderLazyObjectCache.maxCost)]
        retained.configureLazyObjects(key: key, initial: seed) { nodes, _ in
            invalidCalls += 1; batchNodes = nodes
            return await withCheckedContinuation { batchContinuation = $0 }
        }
        try await waitFor("invalid batch entered") { batchContinuation != nil }
        let batchTask = retained.lazyTask!
        let beforeIDs = retained.preparedObjectIDs, beforeCost = retained.preparedObjectCost
        let beforeCells = attachments.map { $0.attachmentCell! }
        let beforeSelection = retained.bodyTextView.selectedRanges, beforeText = retained.bodyTextView.string
        try check(!batchNodes.isEmpty, "invalid batch has visible missing objects")
        // Invalid offscreen output must be checked even if the LRU would omit it.
        invalid.cost = NativeReaderLazyObjectCache.maxCost + 1
        batchContinuation!.resume(returning: [batchNodes[0].id: prepared(batchNodes[0], key, cost: 1024 * 1024), blocks[319].id: invalid])
        await batchTask.value
        try check(retained.preparedObjectIDs == beforeIDs && retained.preparedObjectCost == beforeCost &&
                  retained.cachedLazyObject(blocks[0].id, key: key)?.cost == NativeReaderLazyObjectCache.maxCost,
                  "invalid batch leaves LRU entries and exact cost unchanged")
        try check(zip(attachments, beforeCells).allSatisfy { $0.0.attachmentCell === $0.1 } &&
                  retained.bodyTextView.selectedRanges == beforeSelection && retained.bodyTextView.string == beforeText,
                  "invalid batch leaves all cells and selection/text unchanged")
        try check(invalidCalls == 1 && retained.lazyTask == nil, "invalid result is rejected without transient retry")
        // Typed object failures isolate both halves, including a failure at
        // index zero. Every successful sibling replaces and paints its cell.
        let objectErrors: [Error] = [NativeObjectError.budget, NativeObjectError.invalidGeometry,
            NativeObjectError.unsupported("indivisible-math-overflow"), NativeReaderTextFailure.unsupportedObject("fixture")]
        for failure in objectErrors {
            for failedIndex in [0, 1, -1] {
                var requested = [NativeReaderNode](), failedID: String?, calls = 0
                var painted = Set<String>()
                retained.configureLazyObjects(key: key, initial: [:]) { nodes, current in
                    calls += 1
                    if requested.isEmpty {
                        requested = nodes
                        let resolvedIndex = failedIndex == -1 ? nodes.count - 1 : failedIndex
                        try check(nodes.count > 1 && nodes.count > resolvedIndex, "viewport contains both split halves")
                        failedID = nodes[resolvedIndex].id
                    }
                    if nodes.contains(where: { $0.id == failedID }) { throw failure }
                    return Dictionary(uniqueKeysWithValues: nodes.map { node in
                        let value = NativeReaderPreparedTextObject(key: current,
                            size: NSSize(width: 200, height: 36), baseline: 0,
                            accessibilityLabel: node.displayText, draw: { rect in
                                painted.insert(node.id)
                                NSColor.black.setFill(); rect.fill()
                            }, cost: 65536)
                        return (node.id, value)
                    })
                }
                try await finishLazyPreparation(retained)
                let expected = Set(requested.map(\.id)).subtracting([failedID!])
                try check(!expected.isEmpty && retained.preparedObjectIDs == expected,
                          "one failed node cannot poison valid siblings: \(failure), index \(failedIndex)")
                try check(retained.preparedObjectCost <= NativeReaderLazyObjectCache.maxCost,
                          "isolated viewport respects lazy cache budget")
                let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 240, pixelsHigh: 40,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
                for node in requested where expected.contains(node.id) {
                    let cell = try attachment(node).attachmentCell!
                    cell.draw(withFrame: NSRect(x: 0, y: 0, width: 240, height: 40), in: retained.bodyTextView)
                }
                NSGraphicsContext.restoreGraphicsState()
                try check(painted == expected, "all valid sibling attachments paint instead of placeholders")
                let settledCalls = calls
                for _ in 0..<5 { retained.prepareVisibleObjects(); try await finishLazyPreparation(retained) }
                try check(calls == settledCalls && calls <= 2 * requested.count + 2,
                          "isolated singleton failure never spins")
            }
        }
        for failure in [CancellationError(), NativeObjectError.cancelled, NativeObjectError.stale,
                        NativeReaderTextFailure.staleGeometry] as [Error] {
            var calls = 0
            retained.configureLazyObjects(key: key, initial: [:]) { _, _ in calls += 1; throw failure }
            try await finishLazyPreparation(retained)
            for _ in 0..<3 { retained.prepareVisibleObjects(); try await finishLazyPreparation(retained) }
            try check(calls == 1 && retained.preparedObjectIDs.isEmpty,
                      "cancelled/stale viewport aborts without bisection or retry")
            // A successful left half must not publish when the right half
            // subsequently discovers cancellation or an obsolete context.
            calls = 0
            retained.configureLazyObjects(key: key, initial: [:]) { nodes, current in
                calls += 1
                if calls == 1 {
                    try check(nodes.count > 1, "nested abort requires a split viewport")
                    throw NativeObjectError.budget
                }
                if calls == 2 { return values(nodes, current) }
                throw failure
            }
            try await finishLazyPreparation(retained)
            for _ in 0..<3 { retained.prepareVisibleObjects(); try await finishLazyPreparation(retained) }
            try check(calls == 3 && retained.preparedObjectIDs.isEmpty,
                      "nested cancelled/stale range aborts without partial publication or retry")
        }
        return ["failedRefresh": true, "heldRefresh": true, "transientCalls": transientCalls,
                "persistentCalls": persistentCalls, "backoffFailures": [1, 2], "backoffCancellation": true, "busyRelease": true, "atomicBatch": true, "atomicCells": true]
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
    @MainActor static func findRegression(_ document: NativeReaderDocument) throws -> [String: Any] {
        let windowObservation = FindWindowObservation()
        try check(NSApplication.shared.activationPolicy() == .prohibited, "native Find test activation remains prohibited")
        let windowsBefore = NSApplication.shared.windows.count
        let (view, context) = try make(document)
        defer { view.dispose() }
        let content = view.bodyTextView.string
        let logical = view.logicalText.unicodeScalars.map(\.value)
        var sourceCalls = 0, chatCalls = 0, copyCalls = 0
        var focus: [String?] = []
        view.callbacks.sourceRequested = { _ in sourceCalls += 1 }
        view.callbacks.chatRequested = { _, _ in chatCalls += 1 }
        view.callbacks.copyText = { _ in copyCalls += 1; return false }
        view.callbacks.focusChanged = { focus.append($0) }
        func key(_ text: String, code: UInt16, flags: NSEvent.ModifierFlags) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                windowNumber: 0, context: nil, characters: text, charactersIgnoringModifiers: text,
                isARepeat: false, keyCode: code)!
        }
        func descendants(_ parent: NSView) -> [NSView] { parent.subviews.flatMap { [$0] + descendants($0) } }
        try check(view.window == nil && !view.scrollView.isFindBarVisible, "initial find view detached/closed")
        let geometry = try view.caretGeometry(at: .init(blockID: document.blocks[1].id, utf16: 10, affinity: .downstream))
        view.bodyTextView.keyDown(with: key("f", code: 3, flags: .command))
        tick()
        try check(view.scrollView.isFindBarVisible, "body CmdF shows platform embedded find bar")
        guard let bar = view.scrollView.findBarView,
              let field = descendants(bar).compactMap({ $0 as? NSSearchField }).first,
              let action = field.action else { throw TextTestError(description: "platform find bar/search field/action not created") }
        try check(bar.isDescendant(of: view.scrollView), "find bar embedded in native scroll view")
        try rejects("find bar viewport revokes geometry") { try view.validateGeometry(geometry) }
        func query(_ text: String) throws {
            field.stringValue = text
            try check(field.sendAction(action, to: field.target), "platform search field target/action")
            tick()
            try check(view.performKeyEquivalent(with: key("g", code: 5, flags: .command)), "native find after search field query callback")
            tick()
        }
        try query("Repeated")
        try check(view.store.selection?.fragments.first?.blockID == document.blocks[3].id && view.plainSelectedText == "Repeated", "platform find first repeated prose")
        let firstTicket = view.store.selection!.ticket
        try check(view.performKeyEquivalent(with: key("g", code: 5, flags: .command)), "container CmdG route without menu")
        tick()
        try check(view.store.selection?.fragments.first?.blockID == document.blocks[4].id && view.plainSelectedText == "Repeated", "native find next")
        view.releaseSelection(ticket: firstTicket)
        try check(view.store.selection?.fragments.first?.blockID == document.blocks[4].id, "late prior find ticket cannot release current result")
        try check(view.bodyTextView.performKeyEquivalent(with: key("g", code: 5, flags: [.command, .shift])), "body ShiftCmdG route")
        tick()
        try check(view.store.selection?.fragments.first?.blockID == document.blocks[3].id, "native find previous")
        for (text, range) in [("한글 e\u{301}", 3..<12), ("e\u{301}", 10..<12), ("😀", 13..<15), ("👩‍👩‍👧‍👦", 16..<27)] {
            try query(text)
            try check(view.store.selection?.fragments.first?.rangeUTF16 == range && view.store.selection?.fragments.first?.blockID == document.blocks[1].id, "native Unicode find exact range: " + text)
            try view.store.selection!.validate(in: document)
        }
        try query("\u{fffc}")
        try check(view.store.selection?.fragments.first?.exact == "𝑥2+𝑦", "find attachment selects complete logical formula span")
        try view.store.selection!.validate(in: document)
        try check(!view.performFindAction(.replace) && !view.performFindAction(.showReplaceInterface), "native find stays read-only")
        try query("👩")
        try check(view.store.selection?.fragments.first?.rangeUTF16 == 16..<27, "partial ZWJ find snaps entire legal grapheme")
        try query("\u{301}")
        try check(view.store.selection?.fragments.first?.rangeUTF16 == 10..<12, "combining-only find snaps complete grapheme")
        try check(view.store.document == document && view.bodyTextView.string == content && view.logicalText.unicodeScalars.map(\.value) == logical, "find cannot mutate accepted/presentation Unicode")
        try check(sourceCalls == 0 && chatCalls == 0 && copyCalls == 0, "find never infers source or invokes external actions")
        let request = view.requestSource(.excerpt)!
        try check(!view.acceptSourceResult(.init(context: context, selectionTicket: request.selection.ticket, status: .unmapped, verifiedText: "must not copy", destinationAnchor: nil), for: request) && copyCalls == 0, "find result remains source-unmapped")
        let generation = try view.store.beginRequest()
        let replacement = NativeReaderDocument(schemaVersion: document.schemaVersion, identity: document.identity, generation: generation,
            requiredCapabilities: document.requiredCapabilities, blocks: document.blocks, assets: document.assets, diagnostics: document.diagnostics)
        let replacementContext = NativeReaderRequestContext(requestID: UUID(), viewID: context.viewID, generation: generation, target: context.target)
        try rejects("find result holds publication") { try view.adopt(replacement, context: replacementContext) }
        let ticket = view.store.selection!.ticket
        try check(view.performKeyEquivalent(with: key("\u{1b}", code: 53, flags: [])), "container Escape route")
        tick()
        try check(!view.scrollView.isFindBarVisible && view.store.selection?.ticket == ticket && !focus.isEmpty, "Escape collapses bar, returns logical body focus and retains explicit selection hold")
        try check(view.performKeyEquivalent(with: key("f", code: 3, flags: .command)), "container CmdF route")
        tick()
        view.bodyTextView.cancelOperation(nil)
        try check(!view.scrollView.isFindBarVisible, "native cancel responder hides embedded bar")
        let finderItem = NSMenuItem(title: "Find", action: #selector(NSResponder.performTextFinderAction(_:)), keyEquivalent: "")
        finderItem.tag = NSTextFinder.Action.showFindInterface.rawValue
        view.bodyTextView.performTextFinderAction(finderItem)
        try check(view.scrollView.isFindBarVisible, "standard native finder responder action")
        view.bodyTextView.keyDown(with: key("\u{1b}", code: 53, flags: []))
        try check(!view.scrollView.isFindBarVisible, "body Escape keyDown route")
        view.releaseSelection(ticket: ticket)
        try view.adopt(replacement, context: replacementContext)
        try check(view.store.document == replacement, "explicit matching find selection release permits publication")
        view.cancel()
        try check(!view.performFindAction(.showFindInterface) && !view.performFindAction(.nextMatch), "cancelled find cannot revive view")
        _ = view.performKeyEquivalent(with: key("f", code: 3, flags: .command))
        try check(!view.scrollView.isFindBarVisible, "cancelled CmdF cannot reopen bar")
        let windows = NSApplication.shared.windows
        let windowEvidence = windows.map { ["class": String(describing: type(of: $0)), "visible": String($0.isVisible), "key": String($0.isKeyWindow), "main": String($0.isMainWindow)] }
        // AppKit lazily allocates its hidden find overlay. It is neither an
        // attached reader window nor a global FindPanel, and must stay hidden.
        try check(windowObservation.visibleOrFocusEvents.isEmpty, "native Find never displays or focuses a window during callbacks")
        try check(view.window == nil && windows.allSatisfy { !$0.isVisible && !$0.isKeyWindow && !$0.isMainWindow && String(describing: type(of: $0)) == "_NSTextFinderOverlayWindow" }, "headless find never shows/focuses a window or creates a global FindPanel")
        return ["status": "pass", "privateFindPasteboardCalls": FindPasteboardIsolation.findCalls,
            "windowsCreated": windows.count - windowsBefore, "windowObjects": windowEvidence,
            "visibleWindows": windows.filter(\.isVisible).count, "globalFindPanels": 0,
            "visibleOrFocusEvents": windowObservation.visibleOrFocusEvents,
            "focusScope": "Logical responder callback verified without window; real field-editor focus/key-window traversal remains GUI Dogfood gate"]
    }

    @MainActor static func run(_ document: NativeReaderDocument, out: URL) throws -> [String: Any] {
        let find = try findRegression(document)
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
                    let effectiveSize = view.textAppearance.effectiveSize
                    let pad: CGFloat = width <= 640 ? 20 : 28
                    let expected = min(min(720, max(680, effectiveSize * 45)), width - 2 * pad)
                    try check(abs(key.width - expected) <= 0.5, "body width")
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
        // Real initial preparation/adoption handshake, without any object owner
        // implementation or mutable candidate database inside the text view.
        let coldStore = NativeReaderDocumentStore()
        _ = try coldStore.beginRequest()
        let coldView = NativeReaderTextView(store: coldStore)
        let coldContext = NativeReaderRequestContext(requestID: UUID(), viewID: coldStore.viewID, generation: 1, target: document.identity)
        let coldKey = try coldView.preparationKey(for: document, context: coldContext)
        try rejects("initial cache miss") { try coldView.adopt(document, context: coldContext) }
        try check(coldStore.document == nil, "cache miss cannot adopt canonical candidate")
        let retriedColdKey = try coldView.preparationKey(for: document, context: coldContext)
        try check(retriedColdKey == coldKey, "cache miss retry retains preparation key")
        coldView.cachedObject = { node, _ in unitObject(node, coldKey) }
        try coldView.adopt(document, context: coldContext)
        try check(coldView.renderKey == coldKey, "initial prepared key is adoptable")
        coldView.dispose()

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
        try check(view.renderKey == obsoleteKey && view.textMap != nil && view.lastFailure?.contains("unsupportedObject") == true, "missing cache retains accepted display until current-key preparation")
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
        try rejects("cancelled candidate completion") { try view.adopt(candidate, context: nextContext) }
        try rejects("cancelled candidate preparation") { _ = try view.preparationKey(for: candidate, context: nextContext) }
        try rejects("cancel geometry") { try view.validateGeometry(latestGeometry) }
        view.dispose()
        try rejects("dispose adoption") { try view.adopt(candidate, context: nextContext) }
        try check(!view.copyPlainText() && !view.activate(nodeID: link.id) && view.requestSource(.excerpt) == nil, "disposed actions inert")
        badView.dispose()
        tick()
        return ["find": find, "matrix": matrix, "unicodeAssertions": unicodeAssertions, "input": "pass", "copy": "pass", "accessibility": "pass",
                "reflow": "pass", "lifetime": "pass", "negative": "pass", "objectScope": "unit injections only; actual NA03 fidelity unverified", "skips": 0]
    }
}


@MainActor private func coreLongSelection(folder: URL, out: URL, count: Int) throws {
    let document = try NativeReaderDocument.decode(Data(contentsOf: folder.appendingPathComponent("fixture-\(count)/native.json")))
    let expectedLines = (1...count).map { String(format: "Paragraph %03d alpha.", $0) }
    let expected = expectedLines.joined(separator: "\n")
    try check(document.blocks.map(\.displayText) == expectedLines, "independent actual compiler paragraph oracle")
    var rows = [[String: Any]](), failures = 0
    let board = NSPasteboard(name: .init("dev.lagrangian.core-review.copy." + UUID().uuidString))
    defer { board.releaseGlobally() }
    for entry in ["selectAll", "setSelectedRange", "setSelectedRanges", "AXSelectedTextRange", "drag", "shift"] {
        for prior in [false, true] {
            let view = NativeReaderTextView(store: NativeReaderDocumentStore())
            let owner = view.store
            let generation = try owner.beginRequest()
            let context = NativeReaderRequestContext(requestID: UUID(), viewID: owner.viewID, generation: generation, target: document.identity)
            let candidate = document.rebinding(generation: generation)
            try view.adopt(candidate, context: context)
            let body = view.bodyTextView, full = NSRange(location: 0, length: expected.utf16.count)
            if prior { body.setSelectedRange(NSRange(location: 0, length: expectedLines[0].utf16.count)) }
            var sourceCalls = 0, chatCalls = 0
            view.callbacks.sourceRequested = { _ in sourceCalls += 1 }
            view.callbacks.chatRequested = { _, _ in chatCalls += 1 }
            view.callbacks.copyText = { text in board.clearContents(); return board.setString(text, forType: .string) }
            board.clearContents(); _ = board.setString("PRIVATE-MARKER", forType: .string)
            switch entry {
            case "selectAll": body.selectAll(nil)
            case "setSelectedRange": body.setSelectedRange(full)
            case "setSelectedRanges": body.setSelectedRanges([NSValue(range: full)], affinity: .downstream, stillSelecting: false)
            case "AXSelectedTextRange": body.setAccessibilitySelectedTextRange(full)
            case "shift": body.setSelectedRange(NSRange(location: 0, length: 0)); body.moveToEndOfDocumentAndModifySelection(nil)
            default:
                let first = NativeReaderTextPosition(blockID: document.blocks[0].id, utf16: 0, affinity: .upstream)
                let last = NativeReaderTextPosition(blockID: document.blocks.last!.id, utf16: document.blocks.last!.displayText.utf16.count, affinity: .downstream)
                let a = try view.caretGeometry(at: first), b = try view.caretGeometry(at: last)
                view.pointerDown(at: NSPoint(x: a.rect.minX, y: a.rect.midY))
                view.pointerDragged(at: NSPoint(x: b.rect.minX, y: b.rect.midY))
                view.pointerUp(at: NSPoint(x: b.rect.minX, y: b.rect.midY))
            }
            body.copy(nil)
            let request = view.requestSource(.excerpt); view.openChat()
            let selection = owner.selection
            var remoteRejected = false
            do { try selection?.validate(in: candidate) } catch NativeReaderContractError.invalidSelection { remoteRejected = true }
            let success = body.selectedRange() == full && view.plainSelectedText == expected &&
                body.accessibilitySelectedTextRange() == full && body.accessibilitySelectedText() == expected &&
                board.string(forType: .string) == expected && selection?.fragments.count == count &&
                (count <= 32 ? request != nil && sourceCalls == 1 && chatCalls == 1 && !remoteRejected : request == nil && sourceCalls == 0 && chatCalls == 0 && remoteRejected)
            if !success { failures += 1 }
            rows.append(["entry": entry, "priorShort": prior, "pass": success, "selectedUTF16": [body.selectedRange().location, body.selectedRange().length],
                "expectedUTF16": [0, full.length], "fragments": selection?.fragments.count ?? 0, "sourceCalls": sourceCalls, "chatCalls": chatCalls,
                "copyExact": board.string(forType: .string) == expected, "remoteRejected": remoteRejected])
            if let ticket = selection?.ticket { view.releaseSelection(ticket: ticket) }
            view.dispose()
        }
    }
    let report: [String: Any] = ["blocks": count, "attempts": rows.count, "failures": failures, "rows": rows, "visibleWindows": NSApp.windows.filter(\.isVisible).count]
    try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: out)
    try check(failures == 0, "F4/LS01 ordinary selection/copy/AX/guard failures: \(failures)")
    print("F4/LS01 \(count) blocks: \(rows.count) attempts pass")
}


private final class LayoutWorkerCalls: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func record(_ value: NativeMathExecution) { lock.lock(); defer { lock.unlock() }; count += 1 }
    func value() -> Int { lock.lock(); defer { lock.unlock() }; return count }
}

extension TextInteractionMain {
    @MainActor static func largeRecoveryBudgetRegression(_ fixture: NativeReaderDocument) async throws {
        // Shared pixels are cheap to decode once, but each retained object must
        // carry their full conservative cost. 128 individually valid objects
        // therefore exceed the initial partial-preparation budget together.
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 256, pixelsHigh: 256,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        memset(bitmap.bitmapData!, 255, bitmap.bytesPerRow * bitmap.pixelsHigh)
        let data = bitmap.representation(using: .png, properties: [:])!
        let digest = NativeReaderRecoverySnapshot.digest(data)
        let asset = NativeReaderAsset(id: digest + ".png", sha256: digest,
            mime: "image/png", byteCount: data.count)
        let source = fixture.blocks.flatMap(\.orderedNodes).first { $0.kind == .image }!
        var encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(source)) as! [String: Any]
        encoded["assetID"] = asset.id; encoded.removeValue(forKey: "imageLayout")
        encoded["anchors"] = []; encoded["annotationTargets"] = []
        encoded["rangeUTF16"] = [0, source.displayText.utf16.count]
        let blocks = try (0..<129).map { index -> NativeReaderNode in
            var value = encoded; value["id"] = "recovery-image-\(index)"
            return try JSONDecoder().decode(NativeReaderNode.self, from: JSONSerialization.data(withJSONObject: value))
        }
        let document = NativeReaderDocument(schemaVersion: 1, identity: fixture.identity, generation: 1,
            requiredCapabilities: ["semantic-tree-v1"], blocks: blocks, assets: [asset], diagnostics: [])
        let context = NativeObjectContext(identity: document.identity, snapshotGeneration: 1, generation: 1,
            width: 600, fontSize: 14, fontName: "system", theme: .light, mode: .reflow, pageHeight: 1000)
        let plan = try await NativeReaderPagedLayout.layout(document: document,
            blockIDs: Set(blocks.prefix(128).map(\.id)), context: context, assets: [asset.id: data],
            math: { _, _ in throw TextTestError(description: "image recovery cannot use math worker") })
        try check(plan.blockCosts.count == 128 && plan.blockCosts.values.allSatisfy { $0 < NativeReaderLazyObjectCache.maxCost } &&
                  plan.blockCosts.values.reduce(0, +) > NativeReaderLazyObjectCache.maxCost,
                  "real initial partial objects individually fit but exceed aggregate budget")
        let controller = NativeReaderWindowController(provider: TextDocumentProvider { _ in
            throw TextTestError(description: "recovery cannot load live document")
        }, target: { _ in throw TextTestError(description: "recovery cannot resolve live target") },
            show: false, fixtureMode: true)
        defer { controller.dispose() }
        try await controller.restoreRecovery(.init(document: document, assets: [asset.id: data], restoration: .initial, drafts: []))
        try await finishLazyPreparation(controller.textView)
        try check(controller.store.document?.identity == document.identity && !controller.textView.preparedObjectIDs.isEmpty &&
                  controller.textView.preparedObjectIDs.count < 128 && controller.textView.preparedObjectCost <= NativeReaderLazyObjectCache.maxCost,
                  "large recovery adopts bounded initial paint instead of failing before lazy provider exists")
        try check(controller.textView.navigate(toNodeID: blocks[128].id), "navigate to initially omitted recovery object")
        try await finishLazyPreparation(controller.textView)
        try check(controller.textView.preparedObjectIDs.contains(blocks[128].id) &&
                  controller.textView.preparedObjectCost <= NativeReaderLazyObjectCache.maxCost,
                  "large restored document continues replacing omitted placeholders within budget")
    }

    @MainActor static func diskWindowRegression(_ fixture: NativeReaderDocument, out: URL) async throws -> [String: Any] {
        let source = fixture.blocks.flatMap(\.orderedNodes).first { $0.kind == .math }!
        var encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(source)) as! [String: Any]
        encoded["rangeUTF16"] = [0, source.displayText.utf16.count]
        encoded["anchors"] = []; encoded["annotationTargets"] = []
        var meaning = encoded["math"] as! [String: Any]; meaning["display"] = true; encoded["math"] = meaning
        let blocks = try (0..<320).map { i -> NativeReaderNode in
            var value = encoded; value["id"] = "disk-window-\(i)"
            return try JSONDecoder().decode(NativeReaderNode.self, from: JSONSerialization.data(withJSONObject: value))
        }
        let document = NativeReaderDocument(schemaVersion: 1, identity: fixture.identity, generation: 1,
            requiredCapabilities: ["semantic-tree-v1"], blocks: blocks, assets: [], diagnostics: [])
        let profile = Profile(id: "layout-window", name: "Layout window", root: out.path, entry: "main.typ",
            fonts: [], packages: out.path, port: 12345, publicURL: "", label: "test.layout-window")
        let owner = NativeReaderRecoveryStore(root: out.appendingPathComponent("disk-window"))
        let storage = NativeReaderOfflineStorage(owner: owner)
        let disk = storage.layoutCache!
        try check(disk.root == owner.root.deletingLastPathComponent().appendingPathComponent("layout-cache", isDirectory: true), "offline storage derives shared layout-cache")
        let calls = LayoutWorkerCalls(), environment = ProcessInfo.processInfo.environment
        let runtime = NativeReaderRuntime(node: URL(fileURLWithPath: environment["FLOW_TEST_NODE"] ?? "/opt/homebrew/bin/node"),
            helper: URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("tools/flow-reader/native/math_layout.mjs"),
            runtime: URL(fileURLWithPath: environment["FLOW_TEST_NATIVE_RUNTIME"] ?? "/Volumes/devSSD/Developer/lagrangian-native-20261117/dependencies/mathjax413"), record: { calls.record($0) })
        func provider() -> TextDocumentProvider {
            TextDocumentProvider { context in
                NativeReaderDocument(schemaVersion: document.schemaVersion, identity: context.target, generation: context.generation,
                    requiredCapabilities: document.requiredCapabilities, blocks: blocks, assets: [], diagnostics: [])
            }
        }
        let live = NativeReaderWindowController(provider: provider(), target: { _ in document.identity }, runtime: runtime,
            show: false, fixtureMode: true, offlineStorage: storage)
        _ = live.open(profile) { _ in }
        try await waitFor("live window adopted") { live.session.state == .reading }
        try await finishLazyPreparation(live.textView)
        try check(!live.textView.preparedObjectIDs.isEmpty && live.textView.preparedObjectIDs.count < 128, "initial preparation is viewport-only, even before persistence")
        try check(!live.textView.preparedObjectIDs.contains(blocks[250].id), "unread formula never computed")
        // Visit a distant reading location and persist its actual accepted math.
        let anchor = NativeReaderViewportAnchor(identity: document.identity,
            position: .init(blockID: blocks[180].id, utf16: 0, affinity: .downstream), offsetY: 0)
        live.textView.restoreViewport(anchor)
        try await finishLazyPreparation(live.textView)
        try check(live.textView.preparedObjectIDs.contains(blocks[180].id), "viewed distant window prepared lazily")
        live.persistLayoutWindow(immediate: true); await live.layoutPersistenceTask?.value
        var saved = try await disk.latest(ownerID: [profile.id, profile.root, profile.entry].joined(separator: "\n"))!
        try check(saved.restoration.blockID != blocks[0].id && saved.layouts[blocks[180].id] != nil,
            "last reading position and viewed formula persisted")
        try check(saved.layouts[blocks[250].id] == nil && saved.layouts.count <= 256 && saved.assets.isEmpty,
            "disk excludes unread formulas and unreferenced assets")
        let distantSnapshot = saved
        // Visit enough distinct formulas to evict the first screen from the
        // 256-layout working set, while its prepared pixels remain in TextView.
        // Persist explicitly below so queued scroll notifications cannot cancel
        // the particular save whose completion this regression awaits.
        live.textView.callbacks.readingPositionChanged = {}
        var visited = Set<String>()
        for index in stride(from: 0, to: blocks.count, by: 10) {
            live.textView.restoreViewport(.init(identity: document.identity,
                position: .init(blockID: blocks[index].id, utf16: 0, affinity: .downstream), offsetY: 0))
            try await finishLazyPreparation(live.textView)
            visited.formUnion(live.textView.viewedWindowMathLayouts.keys)
        }
        live.persistLayoutWindow(immediate: true); await live.layoutPersistenceTask?.value
        let afterTour = try await disk.latest(ownerID: saved.ownerID)!
        try check(visited.count > 256 && afterTour.layouts[blocks[0].id] == nil &&
            live.textView.preparedObjectIDs.contains(blocks[0].id), "first prepared screen outlives viewed-layout LRU eviction")
        let beforeReturn = calls.value()
        live.textView.restoreViewport(.init(identity: document.identity,
            position: .init(blockID: blocks[0].id, utf16: 0, affinity: .downstream), offsetY: 0))
        try await finishLazyPreparation(live.textView)
        try check(live.textView.viewedWindowMathLayouts[blocks[0].id] != nil && calls.value() == beforeReturn,
            "returning to retained prepared pixels invokes no worker")
        live.persistLayoutWindow(immediate: true); await live.layoutPersistenceTask?.value
        saved = try await disk.latest(ownerID: saved.ownerID)!
        try check(saved.layouts[blocks[0].id] != nil, "revisited screen formulas restored to disk snapshot (\(saved.restoration.blockID ?? "nil"), \(saved.layouts.count) layouts)")
        live.dispose(); await live.layoutPersistenceTask?.value

        var confirmVersion = false, targetCalls = 0
        let restoreGate = LayoutRestoreGate()
        let before = calls.value()
        let reopened = NativeReaderWindowController(provider: provider(), target: { _ in
            targetCalls += 1
            while !confirmVersion { try await Task.sleep(nanoseconds: 1_000_000) }
            return document.identity
        }, runtime: runtime, invalidate: { await restoreGate.wait() }, show: false, fixtureMode: true, offlineStorage: storage)
        _ = reopened.open(profile) { _ in }
        try await waitFor("cache read-only before version confirmation") {
            reopened.session.isCachedCopy && reopened.store.document != nil && targetCalls == 1
        }
        try await finishLazyPreparation(reopened.textView)
        try check(reopened.session.isReadOnly && reopened.session.isCachedCopy && calls.value() == before,
            "cached visible formulas use zero worker calls before live verification")
        try check(reopened.hostWindow.notice.stringValue == "캐시된 화면 (읽기 전용) · 최신 버전 확인 중...", "cached read-only notice shown during version check")
        try check(reopened.textView.preparedObjectIDs.contains(blocks[0].id), "cached revisited reading window displayed")
        try rejects("cached source/chat mutation denied") { try reopened.session.authorize(reopened.session.context!) }
        let restoredBlock = try reopened.textView.captureViewport().blockID
        confirmVersion = true
        try await waitFor("matching revision promoted") { reopened.session.state == .reading && !reopened.session.isReadOnly }
        try await finishLazyPreparation(reopened.textView)
        try reopened.session.authorize(reopened.session.context!)
        try check(calls.value() == before && !reopened.session.isCachedCopy, "same revision promotes without recomputing cached formulas")
        let revisitedWorkerCalls = calls.value() - before
        let promotedBlock = try reopened.textView.captureViewport().blockID
        try check(promotedBlock == restoredBlock, "promotion preserves restored block")
        reopened.persistLayoutWindow(immediate: true); await reopened.layoutPersistenceTask?.value
        // Reuse the same controller: losing the network, closing and explicitly
        // reading again must restore online authority only after cached adoption.
        let readingPositionChanged = reopened.textView.callbacks.readingPositionChanged
        reopened.textView.callbacks.readingPositionChanged = {}
        await reopened.layoutPersistenceTask?.value
        try await disk.save(distantSnapshot)
        restoreGate.armed = true
        reopened.session.event(.network(false))
        reopened.hostWindow.onClose?()
        confirmVersion = false
        _ = reopened.open(profile) { _ in }
        try await waitFor("cached restore awaits closed-view invalidation") {
            reopened.session.isCachedCopy && reopened.session.state == .loading && targetCalls == 2
        }
        // A layout retry may adopt while the original restore is still awaiting
        // invalidation. It must retain the cached screen and its restoration.
        reopened.session.preparationChanged()
        try await waitFor("same offline controller reopens cached screen") {
            reopened.session.isCachedCopy && reopened.session.state == .offline && reopened.acceptedPaintKey != nil &&
                reopened.session.context == reopened.textView.context &&
                reopened.acceptedPaintKey == reopened.textView.renderKey && reopened.store.document != nil && targetCalls == 2
        }
        try await finishLazyPreparation(reopened.textView)
        try check(reopened.session.isReadOnly && calls.value() == before, "offline-close reopen stays cached read-only before confirmation")
        try check(reopened.textView.preparedObjectIDs.contains(blocks[180].id) &&
            reopened.textView.viewedWindowMathLayouts[blocks[180].id] != nil,
            "layout retry adopts cached restoration before live confirmation")
        restoreGate.release()
        confirmVersion = true
        try await waitFor("same controller restores network and live authority") {
            reopened.session.state == .reading && !reopened.session.isReadOnly && !reopened.session.isCachedCopy
        }
        try await finishLazyPreparation(reopened.textView)
        try reopened.session.authorize(reopened.session.context!)
        try check(calls.value() == before, "same-controller live confirmation reuses revisited formulas")
        reopened.textView.callbacks.readingPositionChanged = readingPositionChanged
        var appearance = reopened.textView.textAppearance
        for field in ["fontSize", "fontName", "theme"] {
            let oldKey = try await disk.latest(ownerID: saved.ownerID)!.key
            let beforeAppearance = calls.value()
            switch field {
            case "fontSize": appearance.fontSize += 2
            case "fontName": appearance.fontName = "Helvetica"
            default: appearance.theme = .dark
            }
            try reopened.textView.setAppearance(appearance)
            try await waitFor("\(field) window reconfigured") { reopened.acceptedPaintKey == reopened.textView.requestedRenderKey }
            try await finishLazyPreparation(reopened.textView)
            try check(calls.value() > beforeAppearance && !reopened.textView.preparedObjectIDs.contains(blocks[250].id), "\(field) recomputes only visible viewport")
            let invalidated = try await disk.load(ownerID: saved.ownerID, key: oldKey) == nil
            try check(invalidated, "\(field) invalidates old disk key")
            reopened.persistLayoutWindow(immediate: true); await reopened.layoutPersistenceTask?.value
        }
        let appearanceKey = try await disk.latest(ownerID: saved.ownerID)!.key
        let window = reopened.hostWindow.window!
        let contentSize = window.contentView!.bounds.size
        // 29235aad caps the reading column at 680–720pt. Shrink below every cap:
        // 680 − 2·28 = 624 < 680 ≤ target for all font sizes and zooms.
        let resizedWidth: CGFloat = 680
        try check(contentSize.width - 56 >= 680 && resizedWidth >= window.minSize.width, "resize starts at the cap and respects minimum size")
        window.setContentSize(NSSize(width: resizedWidth, height: contentSize.height))
        window.contentView!.layoutSubtreeIfNeeded()
        try check((reopened.textView.bodyTextView.textContainer?.containerSize.width ?? 0) < 680, "resized column falls below every measure cap")
        try await waitFor("resized window reconfigured") {
            reopened.textView.requestedRenderKey?.width != CGFloat(appearanceKey.width) &&
                reopened.acceptedPaintKey == reopened.textView.requestedRenderKey
        }
        try await finishLazyPreparation(reopened.textView)
        let widthInvalid = try await disk.load(ownerID: saved.ownerID, key: appearanceKey) == nil
        try check(widthInvalid, "width invalidates old disk key")
        reopened.dispose(); await reopened.layoutPersistenceTask?.value

        let revision = NativeDocumentIdentity(documentID: document.identity.documentID, serviceID: document.identity.serviceID,
            revision: "stage3-new-revision", scope: document.identity.scope)
        // Restore the original geometry so this case isolates revision changes.
        try await disk.save(saved)
        let previous = saved.key
        var verifyNewVersion = false
        let changed = NativeReaderWindowController(provider: provider(), target: { _ in
            while !verifyNewVersion { try await Task.sleep(nanoseconds: 1_000_000) }; return revision
        }, runtime: runtime, show: false, fixtureMode: true, offlineStorage: storage)
        _ = changed.open(profile) { _ in }
        try await waitFor("old revision shown read-only") { changed.session.isCachedCopy && changed.store.document != nil }
        let revisionRetained = try await disk.load(ownerID: saved.ownerID, key: previous) != nil
        try check(revisionRetained, "revision test retains matching geometry until server confirmation")
        verifyNewVersion = true
        try await waitFor("new revision adopted") { changed.session.state == .reading && changed.store.document?.identity == revision }
        try await finishLazyPreparation(changed.textView)
        let revisionInvalid = try await disk.load(ownerID: saved.ownerID, key: previous) == nil
        try check(revisionInvalid, "revision invalidates old disk key")
        try check(!changed.textView.preparedObjectIDs.contains(blocks[250].id), "new revision never precomputes unread window")
        changed.dispose(); await changed.layoutPersistenceTask?.value

        // Small documents use the same window discipline. Closing without an
        // explicit save persists that window, and cached paint needs no runtime.
        let smallBlocks = Array(blocks.prefix(64))
        let smallProvider = TextDocumentProvider { context in
            NativeReaderDocument(schemaVersion: 1, identity: context.target, generation: context.generation,
                requiredCapabilities: ["semantic-tree-v1"], blocks: smallBlocks, assets: [], diagnostics: [])
        }
        let smallDisk = NativeReaderLayoutCache(root: out.appendingPathComponent("small-layout-cache"))
        let small = NativeReaderWindowController(provider: smallProvider, target: { _ in document.identity }, runtime: runtime,
            show: false, fixtureMode: true, layoutCache: smallDisk)
        _ = small.open(profile) { _ in }
        try await waitFor("small viewport adopted") { small.session.state == .reading }
        try await finishLazyPreparation(small.textView)
        try check(!small.textView.preparedObjectIDs.isEmpty && small.textView.preparedObjectIDs.count < smallBlocks.count &&
            !small.textView.preparedObjectIDs.contains(smallBlocks.last!.id), "small document never precomputes unread math")
        small.dispose(); await small.layoutPersistenceTask?.value
        let closed = try await smallDisk.latest(ownerID: saved.ownerID)!
        try check(!closed.layouts.isEmpty && closed.layouts[smallBlocks.last!.id] == nil, "close flushes only viewed layouts")
        var smallVerified = false
        let smallReopen = NativeReaderWindowController(provider: smallProvider, target: { _ in
            while !smallVerified { try await Task.sleep(nanoseconds: 1_000_000) }; return document.identity
        }, show: false, fixtureMode: true, layoutCache: smallDisk)
        _ = smallReopen.open(profile) { _ in }
        try await waitFor("small cached viewport adopted without runtime") { smallReopen.session.isCachedCopy && smallReopen.store.document != nil }
        try await finishLazyPreparation(smallReopen.textView)
        try check(!smallReopen.textView.preparedObjectIDs.isEmpty && smallReopen.session.isReadOnly, "cached small formulas render without a worker")
        smallVerified = true
        try await waitFor("small cached viewport promoted") { smallReopen.session.state == .reading && !smallReopen.session.isReadOnly }
        try await finishLazyPreparation(smallReopen.textView)
        smallReopen.dispose(); await smallReopen.layoutPersistenceTask?.value
        let beforeMismatch = calls.value()
        var mismatchVerified = false
        let mismatch = NativeReaderWindowController(provider: smallProvider, target: { _ in
            while !mismatchVerified { try await Task.sleep(nanoseconds: 1_000_000) }; return document.identity
        }, runtime: runtime, show: false, fixtureMode: true, layoutCache: smallDisk)
        var differentFont = mismatch.textView.textAppearance
        differentFont.fontName = "Helvetica"
        try mismatch.textView.setAppearance(differentFont)
        _ = mismatch.open(profile) { _ in }
        try await waitFor("changed font cached document shown read-only") { mismatch.session.isCachedCopy && mismatch.store.document != nil }
        try await finishLazyPreparation(mismatch.textView)
        let fontMismatchInvalidated = try await smallDisk.load(ownerID: closed.ownerID, key: closed.key) == nil
        try check(fontMismatchInvalidated, "reopen with a different font invalidates old metrics before version confirmation")
        try check(calls.value() > beforeMismatch && !mismatch.textView.preparedObjectIDs.contains(smallBlocks.last!.id), "font mismatch lazily recomputes viewed window only")
        let mismatchCalls = calls.value()
        mismatchVerified = true
        try await waitFor("font mismatch promoted") { mismatch.session.state == .reading && !mismatch.session.isReadOnly }
        try await finishLazyPreparation(mismatch.textView)
        try check(calls.value() == mismatchCalls, "font mismatch promotion reuses newly computed visible math")
        mismatch.dispose(); await mismatch.layoutPersistenceTask?.value
        return ["cachedWorkerCalls": 0, "readOnly": true, "promotion": true, "position": true,
            "revisionInvalidation": true, "widthInvalidation": true, "appearanceInvalidation": true,
            "unreadExcluded": true, "persistedMath": saved.layouts.count, "smallWindow": true,
            "closeFlush": true, "notice": true, "runtimeIndependent": true, "reopenMismatch": true,
            "offlineCloseOnlineReopen": true, "visitedFormulas": visited.count, "revisitedWorkerCalls": revisitedWorkerCalls,
            "revisitedPersisted": true, "cachedRetryBeforeConfirmation": true]
    }
}
