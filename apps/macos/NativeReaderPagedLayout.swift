import AppKit
import CoreText
import CryptoKit
import PDFKit

struct NativeObjectContext: Equatable, Codable {
    enum Theme: String, Codable { case light, dark }
    enum Mode: String, Codable { case reflow, paged }
    let identity: NativeDocumentIdentity
    let snapshotGeneration: Int
    let generation: Int
    let width: Double
    let fontSize: Double
    let fontName: String // "system" or an exact installed PostScript font name.
    let theme: Theme
    let mode: Mode
    let pageHeight: Double
    func validate() throws {
        guard snapshotGeneration >= 0, generation >= 0, width.isFinite, (64...8192).contains(width),
              fontSize.isFinite, (8...96).contains(fontSize), pageHeight.isFinite,
              (128...16384).contains(pageHeight), !fontName.isEmpty, fontName.utf8.count <= 256 else { throw NativeObjectError.invalidGeometry }
    }
    var key: String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        // Invalid contexts are rejected before work/adoption; even diagnostic
        // cache-key access for NaN/Infinity must never trap the process.
        encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        return SHA256.hash(data: try! encoder.encode(self)).map { String(format: "%02x", $0) }.joined()
    }
}

struct NativeMathLayout: Codable {
    struct Context: Codable { let revision: String; let generation: Int; let theme: String }
    struct Fragment: Codable { let svg: String; let width: Double; let ascent: Double; let descent: Double }
    let version: Int
    let inputHash: String
    let context: Context
    let font: String
    let fontSize: Double
    let width: Double
    let whole: Fragment
    let fragments: [Fragment]
    let diagnostics: [String]

    static func decode(_ data: Data, math: NativeMath, context c: NativeObjectContext, width: Double) throws -> Self {
        guard data.count <= 8 * 1024 * 1024 else { throw NativeObjectError.budget }
        let result = try JSONDecoder().decode(Self.self, from: data)
        guard result.context.generation == c.generation else { throw NativeObjectError.stale }
        return try result.rebinding(math: math, context: c, width: width)
    }

    /// Disk generations are local to the previous view. Validate every stable
    /// input before binding validated metrics to this view's layout generation.
    func rebinding(math: NativeMath, context c: NativeObjectContext, width: Double) throws -> Self {
        try c.validate()
        let result = self
        let hash = SHA256.hash(data: Data(math.mathML.utf8)).map { String(format: "%02x", $0) }.joined()
        guard result.version == 1, result.inputHash == hash, result.font == "MathJaxNewcm",
              result.width == width, result.fontSize == c.fontSize,
              result.context.revision == c.identity.revision, result.context.generation >= 0,
              result.context.theme == c.theme.rawValue else { throw NativeObjectError.stale }
        guard !result.fragments.isEmpty, result.fragments.count <= 256,
              ([result.whole] + result.fragments).allSatisfy({ f in
                  [f.width, f.ascent, f.descent].allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 100000 } &&
                  f.width > 0 && f.ascent + f.descent > 0 && f.svg.utf8.count <= 8 * 1024 * 1024
              }) else { throw NativeObjectError.invalidGeometry }
        guard diagnostics.isEmpty, width.isFinite, (16...8192).contains(width),
              ([whole] + fragments).reduce(0, { $0 + $1.svg.utf8.count }) <= 8 * 1024 * 1024 else { throw NativeObjectError.budget }
        return Self(version: version, inputHash: inputHash,
            context: Context(revision: c.identity.revision, generation: c.generation, theme: c.theme.rawValue),
            font: font, fontSize: fontSize, width: width, whole: whole, fragments: fragments, diagnostics: diagnostics)
    }
}

struct NativeObjectPaintItem {
    enum Paint { case vector(NativeVectorScene), text(CTLine), cell(Bool) }
    let nodeID: String
    let frame: CGRect
    let ascent: CGFloat
    let paint: Paint
    func moved(x: CGFloat, y: CGFloat) -> Self {
        Self(nodeID: nodeID, frame: frame.offsetBy(dx: x, dy: y), ascent: ascent, paint: paint)
    }
}

// AX handoff data uses the shared node (math hierarchy, anchors, cell spans,
// headers, link, alt) and logical reading order, independently of visual paths.
// NA02 owns NSAccessibility elements and keyboard/pointer event dispatch.
struct NativeObjectRegion {
    let blockID: String
    let node: NativeReaderNode
    let frames: [CGRect]
    let readingOrder: Int
    var role: String {
        switch node.kind {
        case .math: return "formula"
        case .table: return "table"
        case .row: return "row"
        case .cell: return node.cell?.header == true ? (["row", "rowgroup"].contains(node.cell?.scope ?? "") ? "rowHeader" : "columnHeader") : "cell"
        case .image: return "image"
        case .link: return "link"
        default: return "group"
        }
    }
    func moved(x: CGFloat, y: CGFloat) -> Self {
        Self(blockID: blockID, node: node, frames: frames.map { $0.offsetBy(dx: x, dy: y) }, readingOrder: readingOrder)
    }
}

struct NativeObjectPlan {
    let context: NativeObjectContext
    let items: [NativeObjectPaintItem]
    let regions: [NativeObjectRegion]
    let size: CGSize
    let pageCount: Int
    let diagnostics: [String]
    let cost: Int
    var blockCosts: [String: Int] = [:]

    func hit(_ point: CGPoint) -> NativeObjectRegion? {
        regions.filter { $0.frames.contains { $0.contains(point) } }
            .min { a, b in
                // Deepest semantic leaf wins; a formula fragment snaps to its
                // complete shared node, never a glyph path or half surrogate.
                if a.node.children.isEmpty != b.node.children.isEmpty { return a.node.children.isEmpty }
                return a.frames.reduce(0) { $0 + $1.width * $1.height } < b.frames.reduce(0) { $0 + $1.width * $1.height }
            }
    }

    func linkTarget(at point: CGPoint) -> String? {
        guard let leaf = hit(point) else { return nil }
        return regions.first { r in r.node.kind == .link && r.node.orderedNodes.contains { $0.id == leaf.node.id } }?.node.link
    }

    func formulaSelection(nodeID: String, in document: NativeReaderDocument, ticket: UUID = UUID()) throws -> NativeReaderSelection {
        guard document.identity == context.identity, document.generation == context.snapshotGeneration,
              let region = regions.first(where: { $0.node.id == nodeID && $0.node.kind == .math }) else { throw NativeObjectError.stale }
        let n = region.node
        let selection = NativeReaderSelection(ticket: ticket, blockID: region.blockID,
            rangeUTF16: n.rangeUTF16[0]..<n.rangeUTF16[1], exact: n.canonicalText)
        try selection.validate(in: document)
        return selection // Display text only; verified Typst comes from NA04.
    }
}

// One view owns one store. begin/cancel/dispose invalidate even identical width
// jobs. Native workers call isCancelled; late uncooperative helpers still cannot
// adopt. Cost and entry limits apply before retaining an immutable result.
@MainActor final class NativeObjectPlanStore {
    struct Ticket: Equatable { let serial: Int; let key: String }
    private var serial = 0
    private var current: Ticket?
    private var disposed = false
    private var cache = [(String, NativeObjectPlan)]()
    private(set) var accepted: NativeObjectPlan?
    let maxEntries: Int
    let maxCost: Int
    init(maxEntries: Int = 4, maxCost: Int = 16 * 1024 * 1024) {
        self.maxEntries = max(0, min(maxEntries, 16)); self.maxCost = max(0, maxCost)
    }
    func begin(_ context: NativeObjectContext) throws -> Ticket {
        guard !disposed else { throw NativeObjectError.cancelled }
        try context.validate()
        serial += 1; let t = Ticket(serial: serial, key: context.key); current = t; return t
    }
    func cached(_ context: NativeObjectContext) -> NativeObjectPlan? {
        guard !disposed, let i = cache.firstIndex(where: { $0.0 == context.key }) else { return nil }
        let hit = cache.remove(at: i); cache.append(hit); return hit.1
    }
    func adopt(_ plan: NativeObjectPlan, for ticket: Ticket) throws {
        guard !disposed, current == ticket, plan.context.key == ticket.key else { throw NativeObjectError.stale }
        guard plan.cost <= maxCost else { throw NativeObjectError.budget }
        accepted = plan
        cache.removeAll { $0.0 == ticket.key }; cache.append((ticket.key, plan))
        while cache.count > maxEntries || cache.reduce(0, { $0 + $1.1.cost }) > maxCost { cache.removeFirst() }
    }
    func cancel() { serial += 1; current = nil }
    func dispose() { cancel(); disposed = true; cache.removeAll(); accepted = nil }
    var cachedCount: Int { cache.count }
}

// Native semantic pagination, not compiler-page coordinates. A compiler-page
// glyph/delta contract is absent from schema 1; do not claim print-page parity.
// Inject async math metrics by (node, availableWidth), for example
// { node, width in try await worker.calculate(node.math!, context: c, width: width) }.
// Adopt the immutable result on the view's MainActor store, then draw synchronously.
enum NativeReaderPagedLayout {
    typealias MathBatchProvider = ([(id: String, math: NativeMath, width: Double)], NativeObjectContext) async throws -> [String: NativeMathLayout]
    typealias MathProvider = (NativeReaderNode, Double) async throws -> NativeMathLayout
    static func layout(document: NativeReaderDocument, context: NativeObjectContext,
                       assets: [String: Data], mathBatch: MathBatchProvider? = nil, math: @escaping MathProvider,
                       cancelled: @escaping () -> Bool = { false }) async throws -> NativeObjectPlan {
        try await layout(document: document, blockIDs: Set(document.blocks.map(\.id)), context: context,
            assets: assets, mathBatch: mathBatch, math: math, cancelled: cancelled)
    }

    // Top-level block IDs select whole blocks. Descendant IDs select only that
    // subtree, allowing an attachment window even within one long paragraph.
    static func layout(document: NativeReaderDocument, blockIDs: Set<String>, context: NativeObjectContext,
                       assets: [String: Data], mathBatch: MathBatchProvider? = nil, math: @escaping MathProvider,
                       cancelled: @escaping () -> Bool = { false }) async throws -> NativeObjectPlan {
        if cancelled() || Task.isCancelled { throw NativeObjectError.cancelled }
        try document.validate()
        guard document.identity == context.identity, document.generation == context.snapshotGeneration else { throw NativeObjectError.stale }
        try context.validate()
        let font: NSFont
        if context.fontName == "system" { font = NSFont.systemFont(ofSize: context.fontSize) }
        else {
            guard let exact = NSFont(name: context.fontName, size: context.fontSize), exact.fontName == context.fontName else {
                throw NativeObjectError.unsupported("font-unavailable")
            }; font = exact
        }
        let builder = NativeObjectBuilder(context: context, font: font, assets: assets,
            descriptors: Dictionary(uniqueKeysWithValues: document.assets.map { ($0.id, $0) }), math: math, cancelled: cancelled)
        return try await builder.build(document, blockIDs: blockIDs, mathBatch: mathBatch)
    }
}

private final class NativeObjectBuilder {
    typealias Item = NativeObjectPaintItem
    struct Piece { let node: NativeReaderNode; let paint: Item.Paint; let width: CGFloat; let ascent: CGFloat; let descent: CGFloat }
    struct Box { var items = [Item](); var regions = [NativeObjectRegion](); var height: CGFloat = 0 }
    let context: NativeObjectContext, font: NSFont, assets: [String: Data], descriptors: [String: NativeReaderAsset]
    let math: NativeReaderPagedLayout.MathProvider
    let cancelled: () -> Bool
    var order = [String: Int](), diagnostics = [String](), cost = 0, steps = 0
    var decodedAssets = [String: NativeVectorScene]()
    var collectingMath = false
    var mathRequests = [(id: String, math: NativeMath, width: Double)]()
    var batchedMath: [String: NativeMathLayout]?
    init(context: NativeObjectContext, font: NSFont, assets: [String: Data], descriptors: [String: NativeReaderAsset],
         math: @escaping NativeReaderPagedLayout.MathProvider, cancelled: @escaping () -> Bool) {
        self.context = context; self.font = font; self.assets = assets; self.descriptors = descriptors; self.math = math; self.cancelled = cancelled
    }
    func check() throws {
        steps += 1
        if cancelled() || Task.isCancelled { throw NativeObjectError.cancelled }
        if steps > 200000 || cost > 16 * 1024 * 1024 { throw NativeObjectError.budget }
    }
    func region(_ node: NativeReaderNode, block: String, frames: [CGRect]) -> NativeObjectRegion {
        NativeObjectRegion(blockID: block, node: node, frames: frames, readingOrder: order[node.id]!)
    }
    func build(_ document: NativeReaderDocument, blockIDs: Set<String>, mathBatch: NativeReaderPagedLayout.MathBatchProvider?) async throws -> NativeObjectPlan {
        let nodes = document.blocks.flatMap(\.orderedNodes)
        order = Dictionary(uniqueKeysWithValues: nodes.enumerated().map { ($0.element.id, $0.offset) })
        var roots = [(node: NativeReaderNode, block: String)]()
        func select(_ node: NativeReaderNode, root: String) throws {
            try check()
            guard node.visible else { return }
            if blockIDs.contains(node.id) { roots.append((node, root)) }
            else { for child in node.children { try select(child, root: root) } }
        }
        for node in document.blocks { try select(node, root: node.id) }
        var items = [Item](), regions = [NativeObjectRegion](), y: CGFloat = 16, pages = 1
        var blockCosts = [String: Int]()
        let width = CGFloat(context.width) - 32, pageHeight = CGFloat(context.pageHeight)
        if let mathBatch {
            // Reuse the exact block/table/equation width policy in a metric-only
            // pass; no assets or SVGs are decoded until batch results arrive.
            collectingMath = true
            for entry in roots { _ = try await block(entry.node, root: entry.block, width: width) }
            collectingMath = false
            try check()
            batchedMath = mathRequests.isEmpty ? [:] : try await mathBatch(mathRequests, context)
            guard Set(batchedMath!.keys) == Set(mathRequests.map(\.id)) else { throw NativeObjectError.stale }
            cost = 0; steps = 0; diagnostics = []
        }
        for entry in roots {
            try check()
            let before = cost
            // A subtree cache entry must carry its own conservative asset cost
            // even when this plan shares a decoded scene with an earlier root.
            let sharedAssets = Set(entry.node.orderedNodes.compactMap(\.assetID)).reduce(0) { total, id in
                total + (decodedAssets[id].map { (assets[id]?.count ?? 0) * 16 + $0.decodedCost } ?? 0)
            }
            let box = try await block(entry.node, root: entry.block, width: width)
            cost += box.items.count * 256 + box.regions.count * 256
            try check()
            blockCosts[entry.node.id] = cost - before + sharedAssets
            if context.mode == .paged {
                guard box.height <= pageHeight - 32 else { throw NativeObjectError.unsupported("oversized-page-object") }
                let bottom = CGFloat(pages - 1) * (pageHeight + 16) + pageHeight - 16
                if y + box.height > bottom { pages += 1; y = CGFloat(pages - 1) * (pageHeight + 16) + 16 }
            }
            items += box.items.map { $0.moved(x: 16, y: y) }
            regions += box.regions.map { $0.moved(x: 16, y: y) }
            y += box.height + CGFloat(context.fontSize) * 0.6
        }
        try check()
        return NativeObjectPlan(context: context, items: items, regions: regions.sorted { $0.readingOrder < $1.readingOrder },
            size: CGSize(width: context.width, height: context.mode == .paged ? CGFloat(pages) * (pageHeight + 16) : y + 16),
            pageCount: pages, diagnostics: Array(Set(diagnostics)).sorted(), cost: cost, blockCosts: blockCosts)
    }
    func textAttributes(traits: CTFontSymbolicTraits = [], link: String? = nil) throws -> [NSAttributedString.Key: Any] {
        let base = CTFontCreateWithName(font.fontName as CFString, font.pointSize, nil)
        let chosen: CTFont
        if traits.isEmpty { chosen = base }
        else {
            guard let styled = CTFontCreateCopyWithSymbolicTraits(base, font.pointSize, nil, traits, [.boldTrait, .italicTrait]),
                  CTFontGetSymbolicTraits(styled).isSuperset(of: traits) else { throw NativeObjectError.unsupported("font-style-unavailable") }
            chosen = styled
        }
        let ink = link == nil ? CGColor(gray: context.theme == .dark ? 1 : 0, alpha: 1) :
            CGColor(red: context.theme == .dark ? 0.4 : 0.1, green: context.theme == .dark ? 0.65 : 0.3, blue: 0.9, alpha: 1)
        var attributes: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): chosen,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): ink]
        if link != nil { attributes[NSAttributedString.Key(kCTUnderlineStyleAttributeName as String)] = NSUnderlineStyle.single.rawValue }
        return attributes
    }
    func textLine(_ text: String) throws -> CTLine {
        CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: try textAttributes()))
    }
    func image(_ node: NativeReaderNode, width: CGFloat) throws -> (NativeVectorScene, CGFloat, CGFloat) {
        if collectingMath {
            return (NativeVectorScene(viewBox: CGRect(x: 0, y: 0, width: 1, height: 1), shapes: []), 1, 1)
        }
        guard let id = node.assetID, let descriptor = descriptors[id], let data = assets[id] else { throw NativeObjectError.unsupported("asset-missing") }
        let scene: NativeVectorScene
        if let cached = decodedAssets[id] { scene = cached }
        else {
            cost += data.count * 16; try check()
            scene = try NativeReaderObjectRenderer.verifiedAsset(descriptor, bytes: data, dark: context.theme == .dark,
                pixelBudget: 16 * 1024 * 1024 - cost)
            cost += scene.decodedCost; try check(); decodedAssets[id] = scene
        }
        if let layout = node.imageLayout {
            let size = try layout.size(naturalWidth: Double(scene.intrinsicSize.width), naturalHeight: Double(scene.intrinsicSize.height), fontSize: context.fontSize)
            // Explicit authored size is not a responsive max-width. Inline
            // overflow stays indivisible and is diagnosed by the flow owner.
            return (scene, CGFloat(size.width), CGFloat(size.height))
        }
        let w = min(width, scene.intrinsicSize.width), h = scene.intrinsicSize.height * w / scene.intrinsicSize.width
        return (scene, w, h)
    }
    func flow(_ node: NativeReaderNode, root: String, width: CGFloat) async throws -> Box {
        var box = Box(), line = [Piece](), x: CGFloat = 0
        func flush() {
            guard !line.isEmpty else { return }
            let a = line.map(\.ascent).max()!, d = line.map(\.descent).max()!
            var px: CGFloat = 0
            for p in line {
                box.items.append(Item(nodeID: p.node.id, frame: CGRect(x: px, y: box.height + a - p.ascent, width: p.width, height: p.ascent + p.descent), ascent: p.ascent, paint: p.paint))
                px += p.width
            }
            box.height += max(a + d, CGFloat(context.fontSize)) + 2; line.removeAll(); x = 0
        }
        func add(_ p: Piece) {
            if x + p.width > width && !line.isEmpty { flush() }
            if p.width > width { diagnostics.append("indivisible-inline-overflow:" + p.node.id) }
            line.append(p); x += p.width
        }
        func visit(_ n: NativeReaderNode, traits: CTFontSymbolicTraits = [], link: String? = nil) async throws {
            try check()
            guard n.visible else { return }
            switch n.kind {
            case .break: flush()
            case .math:
                if collectingMath {
                    mathRequests.append((n.id, n.math!, Double(width)))
                    return
                }
                let response: NativeMathLayout
                if let batchedMath {
                    guard let value = batchedMath[n.id] else { throw NativeObjectError.stale }
                    response = value
                } else { response = try await math(n, Double(width)) }
                // Validate provider output as strictly as JSON decode, including
                // exact requested width/context/input, even for injected adapters.
                let expectedHash = SHA256.hash(data: Data(n.math!.mathML.utf8)).map { String(format: "%02x", $0) }.joined()
                guard response.context.revision == context.identity.revision, response.context.generation == context.generation,
                      response.context.theme == context.theme.rawValue, response.width == Double(width),
                      response.fontSize == context.fontSize, response.inputHash == expectedHash, response.version == 1,
                      response.font == "MathJaxNewcm", !response.fragments.isEmpty, response.fragments.count <= 256 else { throw NativeObjectError.stale }
                diagnostics += response.diagnostics.map { $0 + ":" + n.id }
                // Keep an entire formula together when it fits the remaining
                // line; otherwise break only at helper-authorized top-level ops.
                let fragments = response.whole.width <= Double(width - x) ? [response.whole] : response.fragments
                for f in fragments {
                    try check()
                    guard [f.width, f.ascent, f.descent].allSatisfy({ $0.isFinite && $0 >= 0 && $0 < 100000 }), f.width > 0 else { throw NativeObjectError.invalidGeometry }
                    cost += f.svg.utf8.count * 16
                    try check()
                    let scene = try NativeVectorScene.decode(Data(f.svg.utf8), dark: context.theme == .dark, pixelBudget: 16 * 1024 * 1024 - cost, targetSize: CGSize(width: f.width, height: f.ascent + f.descent))
                    cost += scene.decodedCost; try check()
                    add(Piece(node: n, paint: .vector(scene), width: f.width, ascent: f.ascent, descent: f.descent))
                }
            case .text, .equationNumber:
                let string = n.displayText as NSString
                var offset = 0
                while offset < string.length {
                    try check()
                    let rest = string.substring(from: offset)
                    let attributes = try textAttributes(traits: traits, link: link)
                    let attributed = NSAttributedString(string: rest, attributes: attributes)
                    let typesetter = CTTypesetterCreateWithAttributedString(attributed)
                    var count = CTTypesetterSuggestLineBreak(typesetter, 0, Double(max(0, width - x)))
                    if count == 0 && !line.isEmpty { flush(); continue }
                    if count == 0 { count = (rest as NSString).rangeOfComposedCharacterSequence(at: 0).length }
                    let text = (rest as NSString).substring(to: count)
                    let ct = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
                    var a: CGFloat = 0, d: CGFloat = 0
                    let w = CTLineGetTypographicBounds(ct, &a, &d, nil)
                    cost += text.utf8.count
                    add(Piece(node: n, paint: .text(ct), width: w, ascent: a, descent: d))
                    offset += count
                    if offset < string.length { flush() }
                }
            case .strong: for child in n.children { try await visit(child, traits: traits.union(.boldTrait), link: link) }
            case .emphasis: for child in n.children { try await visit(child, traits: traits.union(.italicTrait), link: link) }
            case .link: for child in n.children { try await visit(child, traits: traits, link: n.link) }
            case .image:
                let (scene, w, h) = try image(n, width: width)
                if n.imageLayout?.placement == .block { flush() }
                add(Piece(node: n, paint: .vector(scene), width: w, ascent: h, descent: 0))
                if n.imageLayout?.placement == .block { flush() }
            case .table, .tableHead, .tableBody, .row: throw NativeObjectError.unsupported("nested-table-layout")
            default: for child in n.children { try await visit(child, traits: traits, link: link) }
            }
        }
        try await visit(node); flush()
        // Derive parent hit/AX boxes from descendant native geometry, preserving
        // logical order and the original shared scalar/range maps.
        let ownFrames = Dictionary(grouping: box.items, by: \.nodeID).mapValues { $0.map(\.frame) }
        func collect(_ n: NativeReaderNode) throws -> [CGRect] {
            try check()
            var frames = ownFrames[n.id] ?? []
            for child in n.children { frames += try collect(child) }
            // Container AX frames are unions; leaf formula fragments retain
            // individual rectangles for whole-formula hit/selection snapping.
            if !n.children.isEmpty && !frames.isEmpty { frames = [frames.reduce(CGRect.null) { $0.union($1) }] }
            cost += frames.count * MemoryLayout<CGRect>.stride
            try check()
            if !frames.isEmpty { box.regions.append(region(n, block: root, frames: frames)) }
            return frames
        }
        _ = try collect(node)
        return box
    }
    func block(_ node: NativeReaderNode, root: String, width: CGFloat) async throws -> Box {
        try check()
        if node.kind == .table { return try await table(node, root: root, width: width) }
        if node.kind == .image {
            let (scene, w, h) = try image(node, width: width)
            let frame = CGRect(x: 0, y: 0, width: w, height: h)
            return Box(items: [Item(nodeID: node.id, frame: frame, ascent: h, paint: .vector(scene))], regions: [region(node, block: root, frames: [frame])], height: h)
        }
        if node.kind == .figure || node.kind == .group && node.children.contains(where: { [.figure, .table].contains($0.kind) }) {
            var result = Box()
            for child in node.children where child.visible {
                let box = try await block(child, root: root, width: width)
                result.items += box.items.map { $0.moved(x: 0, y: result.height) }
                result.regions += box.regions.map { $0.moved(x: 0, y: result.height) }
                result.height += box.height + 4
            }
            result.regions.append(region(node, block: root, frames: result.items.map(\.frame))); return result
        }
        if node.kind == .equation, let number = node.children.first(where: { $0.kind == .equationNumber }) {
            let label = try textLine(number.displayText)
            let reserved = CGFloat(CTLineGetTypographicBounds(label, nil, nil, nil)) + CGFloat(context.fontSize)
            guard reserved < width else { throw NativeObjectError.invalidGeometry }
            var result = Box()
            for child in node.children {
                let isNumber = child.id == number.id
                let box = try await flow(child, root: root, width: isNumber ? reserved : width - reserved)
                let dx = isNumber ? width - reserved + CGFloat(context.fontSize) : 0
                result.items += box.items.map { $0.moved(x: dx, y: 0) }
                result.regions += box.regions.map { $0.moved(x: dx, y: 0) }
                result.height = max(result.height, box.height)
            }
            result.regions.append(region(node, block: root, frames: result.items.map(\.frame))); return result
        }
        return try await flow(node, root: root, width: width)
    }
    func table(_ node: NativeReaderNode, root: String, width: CGFloat) async throws -> Box {
        let rows = node.orderedNodes.filter { $0.kind == .row }
        guard !rows.isEmpty, rows.count <= 1000 else { throw NativeObjectError.unsupported("table-shape") }
        struct Cell { let node: NativeReaderNode; let row: Int; let col: Int; let rs: Int; let cs: Int }
        var cells = [Cell](), occupied = Set<Int>(), columns = 0
        // Bounded 1000x1000 occupancy prevents overlap and keeps rowspan slots.
        for (r, row) in rows.enumerated() {
            var c = 0
            for n in row.children {
                try check()
                guard n.kind == .cell, let spec = n.cell, spec.scope == nil || ["col", "colgroup", "row", "rowgroup"].contains(spec.scope!) else { throw NativeObjectError.unsupported("table-child") }
                while c < 1000 && occupied.contains(r * 1000 + c) { c += 1 }
                guard c + spec.columnSpan <= 1000, r + spec.rowSpan <= rows.count else { throw NativeObjectError.unsupported("table-span") }
                for y in r..<(r + spec.rowSpan) {
                    for x in c..<(c + spec.columnSpan) {
                        try check()
                        guard occupied.insert(y * 1000 + x).inserted else { throw NativeObjectError.unsupported("table-overlap") }
                    }
                }
                cells.append(Cell(node: n, row: r, col: c, rs: spec.rowSpan, cs: spec.columnSpan))
                c += spec.columnSpan; columns = max(columns, c)
            }
        }
        guard columns > 0 else { throw NativeObjectError.invalidGeometry }
        let columnWidth = width / CGFloat(columns), pad: CGFloat = 6
        guard columnWidth > pad * 2 else { throw NativeObjectError.unsupported("table-too-narrow") }
        var heights = Array(repeating: CGFloat(context.fontSize) + 2 * pad, count: rows.count), boxes = [Box]()
        for cell in cells {
            let box = try await flow(cell.node, root: root, width: columnWidth * CGFloat(cell.cs) - 2 * pad)
            boxes.append(box)
            let available = heights[cell.row..<(cell.row + cell.rs)].reduce(0, +)
            if box.height + 2 * pad > available {
                heights[cell.row + cell.rs - 1] += box.height + 2 * pad - available
            }
        }
        var y = [CGFloat(0)]
        for h in heights { y.append(y.last! + h) }
        var result = Box()
        for (i, cell) in cells.enumerated() {
            let frame = CGRect(x: CGFloat(cell.col) * columnWidth, y: y[cell.row], width: CGFloat(cell.cs) * columnWidth, height: y[cell.row + cell.rs] - y[cell.row])
            result.items.append(Item(nodeID: cell.node.id, frame: frame, ascent: 0, paint: .cell(cell.node.cell!.header)))
            result.items += boxes[i].items.map { $0.moved(x: frame.minX + pad, y: frame.minY + pad) }
            result.regions += boxes[i].regions.filter { $0.node.id != cell.node.id }.map { $0.moved(x: frame.minX + pad, y: frame.minY + pad) }
            result.regions.append(region(cell.node, block: root, frames: [frame]))
        }
        for n in node.orderedNodes where [.table, .tableHead, .tableBody, .row].contains(n.kind) {
            let ids = Set(n.orderedNodes.map(\.id))
            result.regions.append(region(n, block: root, frames: result.items.filter { ids.contains($0.nodeID) }.map(\.frame)))
        }
        result.height = y.last!; return result
    }
}

// Original compiler pages are a separate, whole-PDF supplement. These local
// correlations never establish backend accepted-publication/source authority.
// No PDFView, action dispatcher, URL initializer, form editing or JS is exposed.
struct NativeOriginalPageGeometry: Codable, Equatable {
    let index: Int
    let mediaBox: CGRect
    let cropBox: CGRect
    let rotation: Int
    var displaySize: CGSize { rotation == 90 || rotation == 270 ? CGSize(width: cropBox.height, height: cropBox.width) : cropBox.size }
}
struct NativeOriginalPageBinding: Codable, Equatable {
    let identity: NativeDocumentIdentity
    let inputFingerprint: String
    let snapshotGeneration: Int
    let requestGeneration: Int
    let viewID: UUID
    let viewGeneration: Int
    let publicationSequence: Int
    let pdfSHA256: String
    let pages: [NativeOriginalPageGeometry] // Ordered, zero-based, PDF points.
    func validate() throws {
        guard [identity.documentID, identity.serviceID, identity.revision].allSatisfy({ (1...128).contains($0.utf8.count) }),
              [inputFingerprint, pdfSHA256].allSatisfy({ $0.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil }),
              [snapshotGeneration, requestGeneration, viewGeneration, publicationSequence].allSatisfy({ $0 >= 0 }),
              !pages.isEmpty, pages.count <= 2048 else { throw NativeOriginalPageError.binding }
        for (i, p) in pages.enumerated() {
            guard p.index == i, [0, 90, 180, 270].contains(p.rotation), validPDFRect(p.mediaBox), validPDFRect(p.cropBox),
                  p.mediaBox.contains(p.cropBox) else { throw NativeOriginalPageError.geometry }
        }
    }
}
struct NativeOriginalPageSupplement {
    let binding: NativeOriginalPageBinding
    let data: Data
}
enum NativeOriginalPageError: Error, Equatable {
    case binding, stale, cancelled, budget, geometry, invalidPDF, encrypted, heldSelection
    case unsupported(String)
}
private func validPDFRect(_ r: CGRect) -> Bool {
    [r.minX, r.minY, r.width, r.height].allSatisfy { $0.isFinite && abs($0) <= 4096 } && r.width > 0 && r.height > 0
}
struct NativeOriginalPageLimits {
    var bytes = 16 * 1024 * 1024
    var pixels = 16 * 1024 * 1024 // RGBA allocation is charged at four bytes/pixel.
    var characters = 250000
    var graphObjects = 100000
    var lazy = false // Legacy component proof remains bounded/eager; production uses lazy.
}
struct NativeOriginalPageRaster {
    let geometry: NativeOriginalPageGeometry
    let text: String // PDFKit display text, never Typst source.
    let offsets: NativeTextOffsets
    let pdfCharacterCount: Int
    let characterBounds: [CGRect] // PDFKit-native index/space; no glyph-cluster claim.
    let pageToDisplay: CGAffineTransform // Bottom-left crop/rotation transform.
    let image: CGImage
}
struct NativeOriginalDisplaySelection: Equatable {
    let snapshotID: UUID
    let pageIndex: Int
    let rangeUTF16: Range<Int>
    let displayText: String
    let pageBounds: CGRect
    @MainActor func copyDisplayText(to pasteboard: NSPasteboard) -> Bool {
        pasteboard.clearContents()
        return pasteboard.writeObjects([displayText as NSString])
    }
    func verifiedSourceAnchor() throws -> String { throw NativeOriginalPageError.unsupported("pdf-source-mapping-unavailable") }
}
struct NativeOriginalPageRender {
    let snapshotID: UUID
    let pageIndex: Int
    let rasterScale: Double
    let image: CGImage
    fileprivate init(snapshotID: UUID, pageIndex: Int, rasterScale: Double, image: CGImage) {
        self.snapshotID = snapshotID; self.pageIndex = pageIndex; self.rasterScale = rasterScale; self.image = image
    }
}
private func renderOriginalPDFPage(_ page: PDFPage, geometry: NativeOriginalPageGeometry, scale: Double,
                                   maximumPixels: Int, cancelled: () -> Bool) throws -> CGImage {
    guard scale.isFinite, (0.1...8).contains(scale), maximumPixels > 0, maximumPixels <= 16 * 1024 * 1024 else { throw NativeOriginalPageError.budget }
    let size = geometry.displaySize, w = Int(ceil(size.width * scale)), h = Int(ceil(size.height * scale))
    guard w > 0, h > 0, w <= 8192, h <= 8192, w <= maximumPixels / h else { throw NativeOriginalPageError.budget }
    if cancelled() { throw NativeOriginalPageError.cancelled }
    guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw NativeOriginalPageError.budget }
    context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: w, height: h))
    context.scaleBy(x: CGFloat(w) / size.width, y: CGFloat(h) / size.height)
    page.displaysAnnotations = false // Presentation only; no document write/action dispatch.
    page.draw(with: .cropBox, to: context)
    if cancelled() { throw NativeOriginalPageError.cancelled }
    guard let image = context.makeImage() else { throw NativeOriginalPageError.invalidPDF }
    return image
}

struct NativeOriginalPreparedPages {
    let id: UUID
    let binding: NativeOriginalPageBinding
    let pages: [NativeOriginalPageRaster]
    let preparationWasMainThread: Bool
    let access: NativeOriginalPDFAccess
    let transforms: [CGAffineTransform]
    fileprivate init(id: UUID, binding: NativeOriginalPageBinding, pages: [NativeOriginalPageRaster], preparationWasMainThread: Bool, access: NativeOriginalPDFAccess, transforms: [CGAffineTransform]) {
        self.id = id; self.binding = binding; self.pages = pages; self.preparationWasMainThread = preparationWasMainThread; self.access = access; self.transforms = transforms
    }
}

// Each prepared PDF has a private serial actor. No mutable PDFKit object crosses
// this boundary, including selections/annotations/actions/pages/documents.
actor NativeOriginalPDFAccess {
    private let document: PDFDocument
    private let id: UUID
    private var texts = [(Int, String)]()
    private var renders = [(Int, Double, NativeOriginalPageRender)]()
    private var renderedPages = Set<Int>()
    private(set) var renderCount = 0, evictions = 0, peakRasterBytes = 0, peakTextBytes = 0
    private var closed = false
    func dispose() { closed = true; texts.removeAll(); renders.removeAll() }
    func metrics() -> [String: Int] { ["renderCount": renderCount, "renderedPages": renderedPages.count, "evictions": evictions, "peakRasterBytes": peakRasterBytes, "peakTextBytes": peakTextBytes, "cachedPages": renders.count, "textPages": texts.count] }
    private func text(at index: Int) throws -> String {
        guard !closed, geometries.indices.contains(index), let page = document.page(at: index) else { throw NativeOriginalPageError.cancelled }
        if let entry = texts.first(where: { $0.0 == index }) { return entry.1 }
        guard page.numberOfCharacters <= 250000 else { throw NativeOriginalPageError.budget }
        let value = page.string ?? ""
        guard value.utf16.count <= 250000 else { throw NativeOriginalPageError.budget }
        let cost = value.utf8.count
        guard cost <= 1024 * 1024 else { throw NativeOriginalPageError.budget }
        while !texts.isEmpty && (texts.count >= 8 || texts.reduce(cost, { $0 + $1.1.utf8.count }) > 1024 * 1024) { texts.removeFirst(); evictions += 1 }
        texts.append((index, value)); peakTextBytes = max(peakTextBytes, texts.reduce(0, { $0 + $1.1.utf8.count }))
        return value
    }
    /// Bounded display text for one current page. Selection still goes through
    /// validate/selection, including PDFKit-index and exact extraction checks.
    func pageText(page index: Int) throws -> String { try text(at: index) }
    private let geometries: [NativeOriginalPageGeometry]
    fileprivate init(document: PDFDocument, id: UUID, texts: [String], geometries: [NativeOriginalPageGeometry]) {
        self.document = document; self.id = id; self.geometries = geometries
    }
    func render(page index: Int, scale: Double, maximumPixels: Int = 4 * 1024 * 1024) throws -> NativeOriginalPageRender {
        guard !closed, geometries.indices.contains(index), let page = document.page(at: index) else { throw NativeOriginalPageError.geometry }
        try Task.checkCancellation()
        if let hit = renders.first(where: { $0.0 == index && $0.1 == scale }) { return hit.2 }
        let image = try renderOriginalPDFPage(page, geometry: geometries[index], scale: scale, maximumPixels: maximumPixels, cancelled: { Task.isCancelled })
        let result = NativeOriginalPageRender(snapshotID: id, pageIndex: index, rasterScale: scale, image: image)
        let cost = image.bytesPerRow * image.height
        guard cost <= 16 * 1024 * 1024 else { throw NativeOriginalPageError.budget }
        while !renders.isEmpty && (renders.count >= 3 || renders.reduce(cost, { $0 + $1.2.image.bytesPerRow * $1.2.image.height }) > 16 * 1024 * 1024) { renders.removeFirst(); evictions += 1 }
        renders.append((index, scale, result)); renderCount += 1; renderedPages.insert(index)
        peakRasterBytes = max(peakRasterBytes, renders.reduce(0, { $0 + $1.2.image.bytesPerRow * $1.2.image.height }))
        return result
    }
    private func validate(page index: Int, range: Range<Int>) throws -> PDFPage {
        if Task.isCancelled { throw NativeOriginalPageError.cancelled }
        guard !closed, geometries.indices.contains(index), let page = document.page(at: index),
              page.numberOfCharacters == (try text(at: index)).utf16.count else { throw NativeOriginalPageError.unsupported("pdf-text-index-unverified") }
        let text = try text(at: index)
        var endpoints = Set([0]), position = 0
        for c in text { position += String(c).utf16.count; endpoints.insert(position) }
        guard !range.isEmpty, endpoints.contains(range.lowerBound), endpoints.contains(range.upperBound) else { throw NativeOriginalPageError.unsupported("pdf-selection-boundary") }
        return page
    }
    func selection(page index: Int, rangeUTF16 range: Range<Int>) throws -> NativeOriginalDisplaySelection {
        let page = try validate(page: index, range: range)
        let ns = NSRange(location: range.lowerBound, length: range.count)
        let expected = (try text(at: index) as NSString).substring(with: ns)
        guard let selection = page.selection(for: ns), let selected = selection.string, selected == expected else {
            throw NativeOriginalPageError.unsupported("pdf-selection-ambiguous")
        }
        let bounds = selection.bounds(for: page)
        guard !bounds.isNull, [bounds.minX, bounds.minY, bounds.width, bounds.height].allSatisfy(\.isFinite) else { throw NativeOriginalPageError.geometry }
        return NativeOriginalDisplaySelection(snapshotID: id, pageIndex: index, rangeUTF16: range, displayText: selected, pageBounds: bounds)
    }
    func selection(page index: Int, rectangle: CGRect) throws -> NativeOriginalDisplaySelection {
        guard !closed, geometries.indices.contains(index), let page = document.page(at: index), validPDFRect(rectangle),
              page.bounds(for: .cropBox).intersects(rectangle), let selected = page.selection(for: rectangle),
              selected.numberOfTextRanges(on: page) == 1 else { throw NativeOriginalPageError.unsupported("pdf-rectangle-selection") }
        let range = selected.range(at: 0, on: page)
        guard range.location != NSNotFound, range.length > 0, range.location <= Int.max - range.length else { throw NativeOriginalPageError.invalidPDF }
        return try selection(page: index, rangeUTF16: range.location..<(range.location + range.length))
    }
    struct Link {
        enum Action { case uri(URL), goTo(Int, CGPoint) }
        let snapshotID: UUID
        let pageIndex: Int
        let bounds: CGRect
        let action: Action
    }
    static func safeURL(_ url: URL) -> Bool {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              ["https", "http", "mailto"].contains(c.scheme?.lowercased() ?? ""),
              c.user == nil, c.password == nil, url.absoluteString.utf8.count <= 4096,
              !(url.absoluteString.removingPercentEncoding ?? url.absoluteString).unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else { return false }
        if c.scheme?.lowercased() == "mailto" { return !c.path.isEmpty && c.query == nil && c.fragment == nil }
        return !(c.host ?? "").isEmpty
    }
    func links(page index: Int) throws -> [Link] {
        guard !closed, geometries.indices.contains(index), let page = document.page(at: index), page.annotations.count <= 256 else { throw NativeOriginalPageError.budget }
        var result = [Link]()
        for annotation in page.annotations where annotation.type == "Link" {
            try Task.checkCancellation()
            let bounds = annotation.bounds
            guard validPDFRect(bounds), page.bounds(for: .cropBox).intersects(bounds) else { throw NativeOriginalPageError.geometry }
            let directDestination = annotation.action == nil && annotation.value(forAnnotationKey: PDFAnnotationKey(rawValue: "A")) == nil ? annotation.destination : nil
            if let action = annotation.action as? PDFActionURL, let url = action.url {
                guard Self.safeURL(url) else { continue }
                result.append(Link(snapshotID: id, pageIndex: index, bounds: bounds, action: .uri(url)))
            } else if let destination = (annotation.action as? PDFActionGoTo)?.destination ?? directDestination,
                      let target = destination.page {
                let targetIndex = document.index(for: target), point = destination.point
                guard geometries.indices.contains(targetIndex), point.x.isFinite, point.y.isFinite,
                      geometries[targetIndex].cropBox.contains(point) else { continue }
                result.append(Link(snapshotID: id, pageIndex: index, bounds: bounds, action: .goTo(targetIndex, point)))
            }
        }
        return result // Never PDFView.performAction; caller must explicitly activate.
    }
    func search(_ query: String, maximum: Int = 256) throws -> [NativeOriginalDisplaySelection] {
        guard !closed, !query.isEmpty, query.utf16.count <= 256, (1...256).contains(maximum) else { throw NativeOriginalPageError.budget }
        var found = [NativeOriginalDisplaySelection](), scanned = 0
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        for index in geometries.indices {
            try Task.checkCancellation()
            let value = try text(at: index) as NSString
            scanned += value.length
            guard scanned <= 4 * 1024 * 1024, ProcessInfo.processInfo.systemUptime < deadline else { throw NativeOriginalPageError.budget }
            var start = 0
            while start < value.length {
                let range = value.range(of: query, options: .literal, range: NSRange(location: start, length: value.length - start))
                if range.location == NSNotFound { break }
                guard found.count < maximum else { throw NativeOriginalPageError.budget }
                found.append(try selection(page: index, rangeUTF16: range.location..<(range.location + range.length)))
                start = range.location + range.length
            }
        }
        return found
    }

}

enum NativeOriginalPreparationPhase: Equatable { case inspected, page(Int), ready }

actor NativeOriginalPagePreparer {
    private var active = 0
    func prepare(_ supplement: NativeOriginalPageSupplement, expected: NativeOriginalPageBinding,
                 limits: NativeOriginalPageLimits = NativeOriginalPageLimits(),
                 progress: @escaping @Sendable (NativeOriginalPreparationPhase) -> Void = { _ in }) async throws -> NativeOriginalPreparedPages {
        guard active < 2 else { throw NativeOriginalPageError.unsupported("pdf-preparer-busy") }
        try supplement.binding.validate(); try expected.validate()
        guard supplement.binding == expected else { throw NativeOriginalPageError.binding }
        guard limits.bytes > 0, limits.bytes <= 16 * 1024 * 1024, limits.pixels > 0, limits.pixels <= 16 * 1024 * 1024,
              limits.characters > 0, limits.characters <= 250000, limits.graphObjects > 0, limits.graphObjects <= 100000,
              (limits.lazy || supplement.binding.pages.count <= 32),
              !supplement.data.isEmpty, supplement.data.count <= limits.bytes else { throw NativeOriginalPageError.budget }
        active += 1; defer { active -= 1 }
        let cancellation = NativeOriginalCancellation()
        return try await withTaskCancellationHandler(operation: {
            let result = try await Task.detached(priority: .userInitiated) {
                try Self.calculate(supplement, limits: limits, cancellation: cancellation, progress: progress)
            }.value
            if Task.isCancelled { throw NativeOriginalPageError.cancelled }
            return result
        }, onCancel: { cancellation.cancel() })
    }
    private nonisolated static func calculate(_ s: NativeOriginalPageSupplement, limits: NativeOriginalPageLimits,
                                              cancellation: NativeOriginalCancellation, progress: @Sendable (NativeOriginalPreparationPhase) -> Void) throws -> NativeOriginalPreparedPages {
        func check() throws { if cancellation.cancelled { throw NativeOriginalPageError.cancelled } }
        try check()
        let sha = SHA256.hash(data: s.data).map { String(format: "%02x", $0) }.joined()
        guard sha == s.binding.pdfSHA256 else { throw NativeOriginalPageError.binding }
        let tail = s.data.suffix(64).reversed().drop(while: { [UInt8(9), 10, 12, 13, 32].contains($0) }).reversed()
        guard s.data.starts(with: Data("%PDF-".utf8)), Array(Array(tail).suffix(5)) == Array("%%EOF".utf8),
              let provider = CGDataProvider(data: s.data as CFData), let raw = CGPDFDocument(provider) else { throw NativeOriginalPageError.invalidPDF }
        guard !raw.isEncrypted else { throw NativeOriginalPageError.encrypted }
        guard raw.numberOfPages == s.binding.pages.count else { throw NativeOriginalPageError.geometry }
        try NativeOriginalPDFSafety.scan(raw, maximum: limits.graphObjects, allowLinks: limits.lazy, cancelled: { cancellation.cancelled })
        progress(.inspected); try check()
        guard let document = PDFDocument(data: s.data), !document.isEncrypted, !document.isLocked,
              document.pageCount == s.binding.pages.count else { throw NativeOriginalPageError.invalidPDF }
        let id = UUID(); var pages = [NativeOriginalPageRaster](), transforms = [CGAffineTransform](), pixels = 0, characters = 0
        for expected in s.binding.pages {
            progress(.page(expected.index)); try check()
            guard let p = document.page(at: expected.index) else { throw NativeOriginalPageError.invalidPDF }
            let actual = NativeOriginalPageGeometry(index: expected.index, mediaBox: p.bounds(for: .mediaBox), cropBox: p.bounds(for: .cropBox), rotation: p.rotation)
            guard actual == expected else { throw NativeOriginalPageError.geometry }
            transforms.append(p.transform(for: .cropBox))
            if limits.lazy { continue }
            let size = actual.displaySize, w = Int(ceil(size.width)), h = Int(ceil(size.height))
            guard w > 0, h > 0, w <= limits.pixels / h, pixels <= limits.pixels - w * h else { throw NativeOriginalPageError.budget }
            pixels += w * h
            let text = p.string ?? "", count = p.numberOfCharacters
            guard count <= limits.characters, text.utf16.count <= limits.characters, characters <= limits.characters - max(count, text.utf16.count) else { throw NativeOriginalPageError.budget }
            characters += max(count, text.utf16.count)
            var boxes = [CGRect]()
            for index in 0..<count {
                try check(); let box = p.characterBounds(at: index)
                guard box.isNull || [box.minX, box.minY, box.width, box.height].allSatisfy({ $0.isFinite && abs($0) <= 8192 }) else { throw NativeOriginalPageError.geometry }
                boxes.append(box)
            }
            let image = try renderOriginalPDFPage(p, geometry: actual, scale: 1, maximumPixels: limits.pixels,
                cancelled: { cancellation.cancelled })
            pages.append(NativeOriginalPageRaster(geometry: actual, text: text, offsets: NativeTextOffsets(text), pdfCharacterCount: count,
                characterBounds: boxes, pageToDisplay: p.transform(for: .cropBox), image: image))
        }
        progress(.ready); try check()
        return NativeOriginalPreparedPages(id: id, binding: s.binding, pages: pages, preparationWasMainThread: Thread.isMainThread,
            access: NativeOriginalPDFAccess(document: document, id: id, texts: pages.map(\.text), geometries: s.binding.pages), transforms: transforms)
    }
}
private final class NativeOriginalCancellation: @unchecked Sendable {
    private let lock = NSLock(); private var value = false
    func cancel() { lock.lock(); value = true; lock.unlock() }
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
}

// CoreGraphics inspects reachable dictionaries without evaluating PDF actions or
// decompressing page content. PDFKit is constructed only after this preflight.
private final class NativeOriginalPDFSafety {
    private struct Address: Hashable { let kind: Int; let value: UInt }
    private var visited = Set<Address>(), count = 0
    private var pending = [(CGPDFObjectRef, String?, Int)]()
    private let maximum: Int, cancelled: () -> Bool
    private let allowLinks: Bool
    init(maximum: Int, allowLinks: Bool, cancelled: @escaping () -> Bool) { self.maximum = maximum; self.allowLinks = allowLinks; self.cancelled = cancelled }
    static func scan(_ document: CGPDFDocument, maximum: Int, allowLinks: Bool = false, cancelled: @escaping () -> Bool) throws {
        let scanner = NativeOriginalPDFSafety(maximum: maximum, allowLinks: allowLinks, cancelled: cancelled)
        guard let catalog = document.catalog else { throw NativeOriginalPageError.invalidPDF }
        try scanner.dictionary(catalog, depth: 0)
        // PDF parent/destination/structure references form a graph. Walk it
        // iteratively: long legal reference chains are not syntax nesting.
        while let item = scanner.pending.popLast() { try scanner.object(item.0, key: item.1, depth: item.2) }
    }
    private final class Context {
        let scanner: NativeOriginalPDFSafety, depth: Int
        var error: Error?
        init(_ scanner: NativeOriginalPDFSafety, _ depth: Int) { self.scanner = scanner; self.depth = depth }
    }
    private func dictionary(_ dictionary: CGPDFDictionaryRef, depth: Int) throws {
        guard allowLinks || depth <= 128 else { throw NativeOriginalPageError.unsupported("pdf-graph-depth-budget") }
        guard visited.insert(Address(kind: 1, value: UInt(bitPattern: dictionary.rawValue))).inserted else { return }
        var width = 0, height = 0
        if CGPDFDictionaryGetInteger(dictionary, "Width", &width), CGPDFDictionaryGetInteger(dictionary, "Height", &height) {
            guard width > 0, height > 0, width <= 8192, height <= 8192, width <= (16 * 1024 * 1024) / height else { throw NativeOriginalPageError.budget }
        }
        let context = Context(self, depth)
        CGPDFDictionaryApplyFunction(dictionary, { key, object, opaque in
            let c = Unmanaged<Context>.fromOpaque(opaque!).takeUnretainedValue()
            guard c.error == nil else { return }
            do { try c.scanner.enqueue(object, key: String(cString: key), depth: c.depth + 1) } catch { c.error = error }
        }, Unmanaged.passUnretained(context).toOpaque())
        if let error = context.error { throw error }
    }
    private func enqueue(_ object: CGPDFObjectRef, key: String?, depth: Int) throws {
        guard pending.count < maximum else { throw NativeOriginalPageError.budget }
        pending.append((object, key, depth))
    }
    private func object(_ object: CGPDFObjectRef, key: String?, depth: Int) throws {
        if cancelled() { throw NativeOriginalPageError.cancelled }
        count += 1
        guard count <= maximum else { throw NativeOriginalPageError.unsupported("pdf-graph-object-budget") }
        guard allowLinks || depth <= 128 else { throw NativeOriginalPageError.unsupported("pdf-graph-depth-budget") }
        let type = CGPDFObjectGetType(object)
        if let key = key, ["OpenAction", "AA", "JS", "JavaScript", "AcroForm", "XFA", "EmbeddedFiles", "EF", "AF", "FFilter"].contains(key) {
            throw NativeOriginalPageError.unsupported("pdf-active-content")
        }
        if key == "URI", !allowLinks { throw NativeOriginalPageError.unsupported("pdf-action") }
        if key == "UserUnit" {
            var value: CGPDFReal = 0
            guard CGPDFObjectGetValue(object, .real, &value), value == 1 else { throw NativeOriginalPageError.unsupported("pdf-nonstandard-user-unit") }
        }
        if key == "F", [.string, .dictionary].contains(type) { throw NativeOriginalPageError.unsupported("pdf-external-file") }
        switch type {
        case .name:
            var pointer: UnsafePointer<CChar>?
            guard CGPDFObjectGetValue(object, .name, &pointer), let value = pointer else { throw NativeOriginalPageError.invalidPDF }
            let name = String(cString: value)
            if key == "S", name == "URI", !allowLinks { throw NativeOriginalPageError.unsupported("pdf-action") }
            if key == "S", ["JavaScript", "Launch", "GoToR", "GoToE", "Named", "SubmitForm", "ResetForm", "ImportData", "Rendition", "Movie", "Sound"].contains(name) {
                throw NativeOriginalPageError.unsupported("pdf-action")
            }
            if key == "Type", ["Filespec", "EmbeddedFile"].contains(name) { throw NativeOriginalPageError.unsupported("pdf-external-file") }
            if key == "Subtype", ["Widget", "FileAttachment", "RichMedia", "Movie", "Sound", "Screen", "3D"].contains(name) { throw NativeOriginalPageError.unsupported("pdf-active-annotation") }
        case .dictionary:
            var d: CGPDFDictionaryRef?; guard CGPDFObjectGetValue(object, .dictionary, &d), let d = d else { throw NativeOriginalPageError.invalidPDF }
            try dictionary(d, depth: depth)
        case .array:
            var a: CGPDFArrayRef?; guard CGPDFObjectGetValue(object, .array, &a), let a = a else { throw NativeOriginalPageError.invalidPDF }
            guard visited.insert(Address(kind: 2, value: UInt(bitPattern: a.rawValue))).inserted else { return }
            let n = CGPDFArrayGetCount(a); guard n <= maximum else { throw NativeOriginalPageError.budget }
            for i in 0..<n { var o: CGPDFObjectRef?; guard CGPDFArrayGetObject(a, i, &o), let o = o else { throw NativeOriginalPageError.invalidPDF }; try self.enqueue(o, key: nil, depth: depth + 1) }
        case .stream:
            var s: CGPDFStreamRef?; guard CGPDFObjectGetValue(object, .stream, &s), let s = s else { throw NativeOriginalPageError.invalidPDF }
            guard let dictionary = CGPDFStreamGetDictionary(s) else { throw NativeOriginalPageError.invalidPDF }
            try self.dictionary(dictionary, depth: depth)
        default: break
        }
    }
}

// One native view owns this state. A host injects its current expected binding;
// envelope equality is correlation only, not proof of accepted publication.
@MainActor final class NativeOriginalPageStore {
    struct Ticket: Equatable { let id: UUID; let expected: NativeOriginalPageBinding }
    struct RenderTicket: Equatable {
        let id: UUID; let snapshotID: UUID; let pageIndex: Int; let viewGeneration: Int; let rasterScale: Double
    }
    struct PaintAcknowledgment: Equatable {
        let snapshotID: UUID; let viewID: UUID; let viewGeneration: Int
        let pageIndex: Int; let scale: Double; let rasterScale: Double; let pdfSHA256: String
    }
    // HTML content revisions may repeat across distinct saved-input snapshots.
    // Bind one fingerprint per snapshot; ordered publication guards advances.
    private struct Snapshot: Hashable { let service: String; let document: String; let generation: Int }
    let viewID: UUID
    private(set) var viewGeneration = 0
    private var current: Ticket?, lastRequest = -1
    private var renderTicket: RenderTicket?
    private var currentRender: NativeOriginalPageRender?
    private var fingerprints = [(Snapshot, String)]()
    private var sequences = [(String, String, Int, Int)]()
    private(set) var accepted: NativeOriginalPreparedPages?
    private(set) var selection: (UUID, NativeOriginalDisplaySelection)?
    private(set) var pageIndex = 0
    private(set) var scale: Double = 1
    private(set) var fitsWidth = true
    private(set) var viewportWidth: Double = 320
    private(set) var paintAcknowledgment: PaintAcknowledgment?
    private var disposed = false
    init(viewID: UUID) { self.viewID = viewID }
    func begin(expected: NativeOriginalPageBinding) throws -> Ticket {
        try expected.validate()
        guard !disposed, expected.viewID == viewID, expected.viewGeneration == viewGeneration else { throw NativeOriginalPageError.stale }
        // A prepared candidate may be held after async work. Re-preparation may
        // reserve only that exact still-live binding, never a consumed ticket.
        if let current, current.expected == expected, expected.requestGeneration == lastRequest { return current }
        guard expected.requestGeneration > lastRequest else { throw NativeOriginalPageError.stale }
        lastRequest = expected.requestGeneration
        let ticket = Ticket(id: UUID(), expected: expected); current = ticket; return ticket
    }
    func validateAdoption(_ pages: NativeOriginalPreparedPages, for ticket: Ticket) throws {
        guard !disposed, ticket == current, ticket.expected == pages.binding, pages.binding.viewGeneration == viewGeneration else { throw NativeOriginalPageError.stale }
        guard selection == nil else { throw NativeOriginalPageError.heldSelection }
        let b = pages.binding, key = Snapshot(service: b.identity.serviceID, document: b.identity.documentID, generation: b.snapshotGeneration)
        if let previous = fingerprints.first(where: { $0.0 == key }), previous.1 != b.inputFingerprint { throw NativeOriginalPageError.binding }
        if let old = sequences.first(where: { $0.0 == b.identity.serviceID && $0.1 == b.identity.documentID }), (b.publicationSequence < old.2 || b.snapshotGeneration < old.3 ||
            (b.publicationSequence == old.2 && (accepted?.binding.inputFingerprint != b.inputFingerprint || accepted?.binding.pdfSHA256 != b.pdfSHA256 || accepted?.binding.identity != b.identity))) { throw NativeOriginalPageError.stale }
    }
    func adopt(_ pages: NativeOriginalPreparedPages, for ticket: Ticket) throws {
        try validateAdoption(pages, for: ticket)
        let b = pages.binding, key = Snapshot(service: b.identity.serviceID, document: b.identity.documentID, generation: b.snapshotGeneration)
        sequences.removeAll { $0.0 == b.identity.serviceID && $0.1 == b.identity.documentID }
        sequences.append((b.identity.serviceID, b.identity.documentID, b.publicationSequence, b.snapshotGeneration))
        while sequences.count > 32 { sequences.removeFirst() }
        fingerprints.removeAll { $0.0 == key }; fingerprints.append((key, b.inputFingerprint))
        while fingerprints.count > 32 { fingerprints.removeFirst() }
        accepted = pages; current = nil; renderTicket = nil; currentRender = nil
        pageIndex = min(pageIndex, pages.binding.pages.count - 1); paintAcknowledgment = nil
    }
    func hold(_ selected: NativeOriginalDisplaySelection, ticket: UUID) throws {
        guard let accepted = accepted, selected.snapshotID == accepted.id, accepted.binding.pages.indices.contains(selected.pageIndex) else { throw NativeOriginalPageError.stale }
        selection = (ticket, selected)
    }
    func release(ticket: UUID) { if selection?.0 == ticket { selection = nil } }
    func cancel() { current = nil; renderTicket = nil }
    func reset() {
        current = nil; renderTicket = nil; currentRender = nil; accepted = nil; selection = nil; pageIndex = 0; scale = 1; fitsWidth = true
        viewGeneration += 1; paintAcknowledgment = nil
    }
    func dispose() { reset(); disposed = true; fingerprints.removeAll(); sequences.removeAll() }
    private func viewportChanged() { viewGeneration += 1; current = nil; renderTicket = nil; currentRender = nil; paintAcknowledgment = nil }
    func resize(width: Double) throws {
        guard !disposed, width.isFinite, (32...8192).contains(width) else { throw NativeOriginalPageError.geometry }
        guard selection == nil else { throw NativeOriginalPageError.heldSelection }
        viewportWidth = width; viewportChanged()
    }
    func setScale(_ value: Double?) throws {
        guard !disposed, selection == nil else { throw NativeOriginalPageError.heldSelection }
        if let value = value { guard value.isFinite, (0.1...8).contains(value) else { throw NativeOriginalPageError.geometry }; scale = value; fitsWidth = false }
        else { fitsWidth = true }
        viewportChanged()
    }
    func jump(to page: Int) throws {
        guard let accepted = accepted, accepted.binding.pages.indices.contains(page), !disposed else { throw NativeOriginalPageError.geometry }
        guard selection == nil else { throw NativeOriginalPageError.heldSelection }
        pageIndex = page; viewportChanged()
    }
    var displayedScale: Double {
        guard let accepted = accepted else { return scale }
        return fitsWidth ? min(8, max(0.1, viewportWidth / accepted.binding.pages[pageIndex].displaySize.width)) : scale
    }
    func beginRender(backingScale: Double = 1) throws -> RenderTicket {
        guard let accepted = accepted, !disposed, backingScale.isFinite, (1...2).contains(backingScale) else { throw NativeOriginalPageError.stale }
        let factor = displayedScale * backingScale
        guard (0.1...8).contains(factor) else { throw NativeOriginalPageError.budget }
        let ticket = RenderTicket(id: UUID(), snapshotID: accepted.id, pageIndex: pageIndex, viewGeneration: viewGeneration, rasterScale: factor)
        renderTicket = ticket; return ticket
    }
    func adoptRender(_ render: NativeOriginalPageRender, for ticket: RenderTicket) throws {
        guard !disposed, ticket == renderTicket, ticket.snapshotID == accepted?.id, ticket.pageIndex == pageIndex,
              ticket.viewGeneration == viewGeneration, render.snapshotID == ticket.snapshotID,
              render.pageIndex == ticket.pageIndex, render.rasterScale == ticket.rasterScale else { throw NativeOriginalPageError.stale }
        guard let geometry = accepted?.binding.pages[pageIndex],
              render.image.width == Int(ceil(geometry.displaySize.width * ticket.rasterScale)),
              render.image.height == Int(ceil(geometry.displaySize.height * ticket.rasterScale)),
              render.image.width <= (4 * 1024 * 1024) / render.image.height,
              render.image.bytesPerRow <= (16 * 1024 * 1024) / render.image.height else { throw NativeOriginalPageError.budget }
        currentRender = render; renderTicket = nil; paintAcknowledgment = nil
    }
    func viewRect(forPageRect rect: CGRect) throws -> CGRect {
        guard let accepted = accepted else { throw NativeOriginalPageError.stale }
        let page = accepted.binding.pages[pageIndex], r = rect.applying(accepted.transforms[pageIndex]), factor = displayedScale
        return CGRect(x: r.minX * factor, y: (page.displaySize.height - r.maxY) * factor, width: r.width * factor, height: r.height * factor)
    }
    func pageRect(forViewRect rect: CGRect) throws -> CGRect {
        guard let accepted = accepted else { throw NativeOriginalPageError.stale }
        let page = accepted.binding.pages[pageIndex], factor = displayedScale
        let r = CGRect(x: rect.minX / factor, y: page.displaySize.height - rect.maxY / factor, width: rect.width / factor, height: rect.height / factor)
        return r.applying(accepted.transforms[pageIndex].inverted())
    }
    // Only an actual draw call creates an acknowledgment. Preparation/adoption
    // alone never means painted, and this is not a GUI/window/VO acknowledgment.
    @discardableResult func paint(in context: CGContext, origin: CGPoint = .zero) throws -> PaintAcknowledgment {
        guard let accepted = accepted, !disposed else { throw NativeOriginalPageError.stale }
        let page = accepted.binding.pages[pageIndex], factor = displayedScale
        let rect = CGRect(origin: origin, size: CGSize(width: page.displaySize.width * factor, height: page.displaySize.height * factor))
        guard let image = currentRender?.image ?? accepted.pages.first(where: { $0.geometry.index == pageIndex })?.image else { throw NativeOriginalPageError.stale }
        context.saveGState(); context.translateBy(x: rect.minX, y: rect.maxY); context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: rect.size)); context.restoreGState()
        let ack = PaintAcknowledgment(snapshotID: accepted.id, viewID: viewID, viewGeneration: viewGeneration,
            pageIndex: pageIndex, scale: factor, rasterScale: currentRender?.rasterScale ?? 1, pdfSHA256: accepted.binding.pdfSHA256)
        paintAcknowledgment = ack; return ack
    }
    func applyVectorDelta(_ data: Data) throws { throw NativeOriginalPageError.unsupported("engine-diff-v1-not-implemented") }
}
