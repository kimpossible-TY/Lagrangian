// NR10 standalone headless CoreText proof. No app registration, GUI, transport or source writer.
// swiftc -swift-version 5 -warnings-as-errors -target arm64-apple-macosx13.0 <this> -o <temp>
// <binary> <native.json> <expect.json> <fresh report directory>
import Foundation
import CoreText
import CoreGraphics
import CryptoKit

struct Failure: Error, CustomStringConvertible { let description: String }
func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    if try !condition() { throw Failure(description: message) }
}
func sha(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
func write(_ value: Any, _ url: URL) throws {
    try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]).write(to: url)
}
struct IdentityValue: Codable, Equatable { let value: String; let origin: String; let source: String }
struct Identity: Codable, Equatable { let document: IdentityValue; let service: IdentityValue; let revision: IdentityValue; let input: IdentityValue }
struct Maps: Codable, Equatable { let scalars: [UInt32]; let cpToUTF8: [Int]; let cpToUTF16: [Int] }
struct Inline: Codable { let role: String; let rangeUTF16: [Int]; let attributes: [String: String] }
struct ObjectNode: Codable { let id: String; let kind: String; let fallback: String; let capability: String; let normalizedText: String; let resources: [String]; let cells: [String]; let captions: [String] }
struct Block: Codable {
    let id: String; let parent: String; let order: Int; let section: String; let role: String
    let text: String; let display: String; let offsets: Maps; let inlines: [Inline]; let objects: [ObjectNode]; let anchors: [String]; let sourceCorrespondence: String
}
struct Provenance: Codable { let fixtureSHA256: String; let oracleSHA256: String; let compilerExit: Int; let artifacts: [String: String] }
struct Model: Codable { let proofSchema: Int; let requiredCapabilities: [String]; let identity: Identity; let generation: Int; let blocks: [Block]; let anchors: [String: Int]; let provenance: Provenance }
struct UnicodeOracle: Codable {
    let text: String; let scalars: [UInt32]; let cpToUTF16: [Int]; let cpToUTF8: [Int]
    let graphemeCP: [Int]; let graphemeUTF16: [Int]; let graphemeUTF8: [Int]
}
struct WhitespaceOracle: Codable {
    let source: String; let display: String; let scalars: [UInt32]; let cpToUTF16: [Int]; let cpToUTF8: [Int]
    let graphemeCP: [Int]; let graphemeUTF16: [Int]; let graphemeUTF8: [Int]; let loss: String
}
struct CopyOracle: Codable { let startBlock: Int; let startUTF16: Int; let endBlock: Int; let endUTF16: Int; let text: String; let reverseText: String }
struct EmphasisOracle: Codable { let block: Int; let text: String; let rangeUTF16: [Int] }
struct LinkOracle: Codable { let block: Int; let target: String; let text: String }
struct Oracle: Codable {
    let oracleOrigin: String; let reviewStatus: String; let roles: [String]; let texts: [String]; let anchors: [String: Int]
    let crossBlockCopy: CopyOracle; let emphasis: EmphasisOracle; let link: LinkOracle
    let whitespace: [WhitespaceOracle]; let unsupported: [String]; let tableCells: [String]; let figureCaption: String; let unicode: [UnicodeOracle]
    let caretEquivalence: String; let coordinateSystem: String
}
func maps(_ s: String) -> Maps {
    var u8 = [0], u16 = [0]
    for c in s.unicodeScalars { let v = String(c); u8.append(u8.last! + v.utf8.count); u16.append(u16.last! + v.utf16.count) }
    return Maps(scalars: s.unicodeScalars.map(\.value), cpToUTF8: u8, cpToUTF16: u16)
}
func graphemes(_ s: String) -> (cp: [Int], u8: [Int], u16: [Int]) {
    var cp = [0], u8 = [0], u16 = [0]
    for c in s { let v = String(c); cp.append(cp.last! + v.unicodeScalars.count); u8.append(u8.last! + v.utf8.count); u16.append(u16.last! + v.utf16.count) }
    return (cp, u8, u16)
}
func exact(_ a: String, _ b: String) -> Bool { Array(a.unicodeScalars) == Array(b.unicodeScalars) }
func substring(_ s: String, _ start: Int, _ end: Int) throws -> String {
    let legal = graphemes(s).u16
    try require(start <= end && legal.contains(start) && legal.contains(end), "illegal selection endpoint")
    return (s as NSString).substring(with: NSRange(location: start, length: end - start))
}
func copy(_ blocks: [Block], _ a: (Int, Int), _ b: (Int, Int)) throws -> String {
    let (start, end) = a.0 < b.0 || (a.0 == b.0 && a.1 <= b.1) ? (a,b) : (b,a)
    try require(start.0 >= 0 && end.0 < blocks.count, "copy block bounds")
    return try (start.0...end.0).map { i in
        try substring(blocks[i].text, i == start.0 ? start.1 : 0, i == end.0 ? end.1 : blocks[i].text.utf16.count)
    }.joined(separator: "\n")
}
func importModel(_ data: Data) throws -> Model {
    try require(data.count <= 4_000_000, "bounded import")
    let m = try JSONDecoder().decode(Model.self, from: data)
    try require(m.proofSchema == 1 && m.generation > 0 && !m.blocks.isEmpty && m.blocks.count <= 128, "schema/generation/blocks")
    try require(Set(m.requiredCapabilities).isSubset(of: ["native-text", "unsupported-placeholders"]), "unknown required capability")
    try require(m.provenance.compilerExit == 0, "compiler failure")
    try require(m.identity.input.value == m.provenance.fixtureSHA256 && m.identity.revision.value == m.provenance.artifacts["compiled/document.html"], "compiler/input provenance mismatch")
    var ids = Set<String>()
    for (i,b) in m.blocks.enumerated() {
        try require(["heading", "paragraph", "math", "table", "figure"].contains(b.role), "unknown required block role")
        try require(b.order == i && ids.insert(b.id).inserted && b.parent == "document", "ordered unique block")
        try require(exact(b.text, b.display) && b.offsets == maps(b.text), "display or scalar offset corruption")
        for v in b.inlines {
            try require(["p", "h1", "h2", "em", "strong", "a", "span", "br", "math", "table", "figure"].contains(v.role), "unknown required inline")
            try require(v.rangeUTF16.count == 2, "inline range shape")
            _ = try substring(b.text, v.rangeUTF16[0], v.rangeUTF16[1])
        }
        for o in b.objects {
            try require(["math", "table", "figure"].contains(o.kind) && o.capability == "unsupported" && b.text.contains(o.fallback), "unknown/silent object")
        }
    }
    for (_, i) in m.anchors { try require(m.blocks.indices.contains(i), "anchor bounds") }
    return m
}
struct Layout {
    let identity: Identity; let generation: Int; let inputDigest: String; var complete: Bool
    let width: Double; let fontSize: Double; let lines: [[String: Any]]; let lineCount: Int; let caretCount: Int; let rawInteriorHits: Int
    let fonts: [[String: Any]]; let paintDigest: String
}
// Complete importer + geometry adoption is atomic. This object never owns server publication.
struct Accepted {
    var model: Model; var layout: Layout; var digest: String
    mutating func adopt(_ data: Data, _ candidate: Layout, requested: Identity, generation: Int, layoutGeneration: Int = 1) throws {
        let imported = try importModel(data)
        try require(imported.identity == requested && candidate.identity == requested, "stale document/service/revision/input")
        try require(imported.generation == generation && candidate.generation == layoutGeneration, "stale generation")
        try require(candidate.complete && candidate.inputDigest == sha(data), "incomplete or mismatched geometry")
        try require(candidate.width > 0 && candidate.fontSize > 0 && candidate.lineCount > 0, "layout failure")
        model = imported; layout = candidate; digest = sha(data)
    }
}
func rectJSON(_ r: CGRect) -> [Double] { [Double(r.origin.x), Double(r.origin.y), Double(r.width), Double(r.height)] }
func shape(_ m: Model, _ data: Data, width: Double, size: Double, oracle: Oracle, layoutGeneration: Int = 1) throws -> Layout {
    try require(width.isFinite && size.isFinite && width > 0 && size > 0, "layout input failure")
    let base = CTFontCreateWithName("Helvetica" as CFString, CGFloat(size), nil)
    var records = [[String: Any]](), fontRecords = [String: [String: Any]]()
    var painted = [(CTLine, CGFloat)](), baseline: CGFloat = 0, caretCount = 0, rawInterior = 0
    for (bi,b) in m.blocks.enumerated() {
        let attributed = NSMutableAttributedString(string: b.text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): base, NSAttributedString.Key(kCTLigatureAttributeName as String): 1])
        for span in b.inlines where span.role == "em" {
            if let italic = CTFontCreateCopyWithSymbolicTraits(base, CGFloat(size), nil, .traitItalic, .traitItalic) {
                attributed.addAttribute(NSAttributedString.Key(kCTFontAttributeName as String), value: italic, range: NSRange(location: span.rangeUTF16[0], length: span.rangeUTF16[1] - span.rangeUTF16[0]))
            }
        }
        let typesetter = CTTypesetterCreateWithAttributedString(attributed)
        let legal = graphemes(b.text).u16
        var position = 0
        while position < b.text.utf16.count {
            let suggested = position + CTTypesetterSuggestLineBreak(typesetter, position, CGFloat(width))
            guard let end = legal.filter({ $0 > position && $0 <= suggested }).last ?? legal.first(where: { $0 > position }) else { throw Failure(description: "reflow made no progress") }
            let line = CTTypesetterCreateLine(typesetter, CFRange(location: position, length: end - position))
            let lineRange = CTLineGetStringRange(line)
            try require(lineRange.location == position && lineRange.length == end-position, "shape range loss")
            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            let advance = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
            try require(advance.isFinite && advance - CTLineGetTrailingWhitespaceWidth(line) <= width + 0.01, "line exceeds advance width block=\(bi) range=\(position)..<\(end) advance=\(advance) trailing=\(CTLineGetTrailingWhitespaceWidth(line)) width=\(width)")
            let lineLegal = legal.filter { $0 >= position && $0 <= end }
            var stops = [(Int, CGFloat, String)]()
            for offset in lineLegal {
                var secondary: CGFloat = 0
                let primary = CTLineGetOffsetForStringIndex(line, offset, &secondary)
                stops.append((offset, primary, "primary"))
                if abs(primary-secondary) > 0.01 { stops.append((offset, secondary, "secondary")) }
            }
            let advanceRect = CGRect(x: 0, y: -descent, width: advance, height: ascent+descent)
            let ink = CTLineGetImageBounds(line, nil)
            func legalHit(_ point: CGPoint) -> Int? {
                guard point.x >= 0 && point.x <= CGFloat(advance) && point.y >= -descent && point.y <= ascent else { return nil }
                return stops.min(by: { abs($0.1-point.x) < abs($1.1-point.x) })?.0
            }
            var hits = [[String: Any]]()
            for (offset,x,affinity) in stops {
                let equivalence = Set(stops.filter { abs($0.1-x) <= 0.01 }.map { $0.0 })
                let raw = CTLineGetStringIndexForPosition(line, CGPoint(x: x, y: 0))
                // CoreText returns a string insertion index, which may bisect a grapheme.
                // Such raw values are observations only. Public candidates are legal stops.
                if raw >= position && raw <= end && !legal.contains(raw) { rawInterior += 1 }
                let resolved = legalHit(CGPoint(x: x, y: 0))
                try require(resolved != nil && equivalence.contains(resolved!) && equivalence.contains(offset), "caret/hit mismatch")
                if legal.contains(raw) {
                    try require(equivalence.contains(raw), "raw CoreText hit differs outside exact caret equivalence")
                }
                if raw > position && raw < end && !legal.contains(raw) {
                    guard let lower = legal.last(where: { $0 < raw }), let upper = legal.first(where: { $0 > raw }) else { throw Failure(description: "raw hit outside grapheme") }
                    try require(equivalence.contains(lower) || equivalence.contains(upper), "raw hit not in equivalent adjacent grapheme")
                }
                hits.append(["utf16": offset, "x": Double(x), "affinity": affinity, "rawCoreTextHit": raw, "legalHit": resolved!, "equivalentUTF16": equivalence.sorted()])
                caretCount += 1
            }
            for point in [CGPoint(x: -1, y: 0), CGPoint(x: advance+1, y: 0), CGPoint(x: 0, y: ascent+1), CGPoint(x: 0, y: -descent-1)] {
                try require(legalHit(point) == nil, "out-of-advance hit was accepted")
            }
            // Glyph/run bounds are observations, never substituted for advance/caret bounds.
            let c = oracle.crossBlockCopy
            let copyStart = bi == c.startBlock ? c.startUTF16 : 0
            let copyEnd = bi == c.endBlock ? c.endUTF16 : b.text.utf16.count
            let copySelected = bi >= c.startBlock && bi <= c.endBlock
            let selectionRange = copySelected && max(position,copyStart) < min(end,copyEnd) ? [max(position,copyStart),min(end,copyEnd)] : []
            var runs = [[String: Any]]()
            for run in CTLineGetGlyphRuns(line) as! [CTRun] {
                let range = CTRunGetStringRange(run)
                let attrs = CTRunGetAttributes(run) as NSDictionary
                let font = attrs[kCTFontAttributeName] as! CTFont
                let name = CTFontCopyPostScriptName(font) as String
                let descriptor = CTFontCopyFontDescriptor(font)
                let fontURL = CTFontDescriptorCopyAttribute(descriptor, kCTFontURLAttribute) as? URL
                let requestedFont = attributed.attribute(NSAttributedString.Key(kCTFontAttributeName as String), at: range.location, effectiveRange: nil) as! CTFont
                let requestedName = CTFontCopyPostScriptName(requestedFont) as String
                if fontRecords[name] == nil {
                var fontEntry: [String: Any] = ["postScriptName": name, "sizePt": Double(CTFontGetSize(font)), "requestedPostScriptName": requestedName, "fallback": name != requestedName]
                if let url = fontURL { fontEntry["file"] = url.path; if let bytes = try? Data(contentsOf: url) { fontEntry["sha256"] = sha(bytes) } }
                fontRecords[name] = fontEntry
                }
                let count = CTRunGetGlyphCount(run)
                var glyphs = [CGGlyph](repeating: 0, count: count), indices = [CFIndex](repeating: 0, count: count), points = [CGPoint](repeating: .zero, count: count)
                CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
                CTRunGetStringIndices(run, CFRange(location: 0, length: 0), &indices)
                CTRunGetPositions(run, CFRange(location: 0, length: 0), &points)
                var advances = [CGSize](repeating: .zero, count: count)
                CTRunGetAdvances(run, CFRange(location: 0, length: 0), &advances)
                let clusterEnds = Array(Set(indices + [range.location+range.length])).sorted()
                // Selection fragment intersection for each legal grapheme and shaped run.
                var fragments = [[String: Any]]()
                for pair in zip(lineLegal, lineLegal.dropFirst()) where max(pair.0, range.location) < min(pair.1, range.location+range.length) {
                    let contributing = indices.indices.filter { j in
                        let clusterEnd = clusterEnds.first(where: { $0 > indices[j] }) ?? range.location+range.length
                        return max(pair.0,indices[j]) < min(pair.1,clusterEnd)
                    }
                    try require(!contributing.isEmpty, "selection has no glyph fragment")
                    let left = contributing.map { points[$0].x }.min()!
                    let right = contributing.map { points[$0].x + advances[$0].width }.max()!
                    fragments.append(["selectionUTF16": [pair.0,pair.1], "crossBlockCopySelected": copySelected && pair.0 >= copyStart && pair.1 <= copyEnd, "shapeIntersectionUTF16": [max(pair.0,range.location), min(pair.1,range.location+range.length)], "glyphIndicesInRun": contributing, "glyphAdvanceBoundsPt": [Double(left),Double(-descent),Double(right-left),Double(ascent+descent)], "policy": "intersecting glyph-cluster coverage; ligature glyph may be shared by multiple legal selections, never a source range"])

                }
                runs.append(["rangeUTF16": [range.location,range.location+range.length], "font": name, "rtl": CTRunGetStatus(run).contains(.rightToLeft), "glyphIDs": glyphs.map(Int.init), "glyphStringIndicesUTF16": indices, "glyphPositionsPt": points.map { [Double($0.x),Double($0.y)] }, "inkBoundsPt": rectJSON(CTRunGetImageBounds(run, nil, CFRange(location: 0,length: 0))), "fragments": fragments])
            }
            records.append(["block": bi, "id": b.id, "rangeUTF16": [position,end], "baselinePt": [0,Double(baseline)], "crossBlockCopySelectionUTF16": selectionRange, "advanceBoundsPt": rectJSON(advanceRect), "inkBoundsPt": rectJSON(ink), "trailingWhitespaceAdvancePt": CTLineGetTrailingWhitespaceWidth(line), "carets": hits, "runs": runs])
            painted.append((line,baseline)); baseline -= CGFloat(size*1.6); position = end
        }
        baseline -= CGFloat(size*0.4)
    }
    let height = Int(ceil(-baseline + CGFloat(size*2)))
    guard let context = CGContext(data: nil, width: Int(width), height: height, bitsPerComponent: 8, bytesPerRow: Int(width)*4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let pixels = context.data else { throw Failure(description: "headless paint allocation failed") }
    context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0,y: 0,width: Int(width),height: height))
    context.setFillColor(CGColor(gray: 0, alpha: 1))
    for (line,y) in painted { context.textPosition = CGPoint(x: 0,y: CGFloat(height)-CGFloat(size*1.2)+y); CTLineDraw(line,context) }
    let paint = Data(bytes: pixels, count: context.bytesPerRow*height)
    try require(paint.contains(where: { $0 != 255 }), "empty headless paint")
    return Layout(identity: m.identity, generation: layoutGeneration, inputDigest: sha(data), complete: true, width: width, fontSize: size, lines: records, lineCount: records.count, caretCount: caretCount, rawInteriorHits: rawInterior, fonts: fontRecords.keys.sorted().map { fontRecords[$0]! }, paintDigest: sha(paint))
}

func run() throws {
    let args = CommandLine.arguments
    try require(args.count == 4, "usage: RepresentationProof native.json expect.json fresh-report-directory")
    let input = URL(fileURLWithPath: args[1]), oracleURL = URL(fileURLWithPath: args[2]), out = URL(fileURLWithPath: args[3], isDirectory: true)
    try require(!FileManager.default.fileExists(atPath: out.path), "report directory must be fresh")
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let data = try Data(contentsOf: input), oracleData = try Data(contentsOf: oracleURL)
    let model = try importModel(data), oracle = try JSONDecoder().decode(Oracle.self, from: oracleData)
    try require(sha(oracleData) == model.provenance.oracleSHA256, "oracle provenance mismatch")
    let root = input.deletingLastPathComponent()
    try require(sha(try Data(contentsOf: root.appendingPathComponent("source/main.typ"))) == model.provenance.fixtureSHA256, "fixture provenance mismatch")
    for (path, hash) in model.provenance.artifacts {
        try require(!path.contains("..") && !path.hasPrefix("/"), "artifact traversal")
        try require(sha(try Data(contentsOf: root.appendingPathComponent(path))) == hash, "compiler artifact provenance mismatch")
    }
    try require(sha(try Data(contentsOf: root.appendingPathComponent("compiled/document.html"))) == model.identity.revision.value, "accepted revision mismatch")
    try require(model.identity.service.origin == "synthetic-fixture", "service origin misrepresented")
    try require(model.blocks.map(\.role) == oracle.roles && model.blocks.count == oracle.texts.count, "logical block order")
    for (b,text) in zip(model.blocks,oracle.texts) { try require(exact(b.text,text), "canonical/display scalar loss") }
    for (a,i) in oracle.anchors { try require(model.anchors[a] == i, "anchor lost") }
    let em = oracle.emphasis
    try require(model.blocks[em.block].inlines.contains { $0.role == "em" && $0.rangeUTF16 == em.rangeUTF16 }, "emphasis range")
    try require(exact(try substring(model.blocks[em.block].text,em.rangeUTF16[0],em.rangeUTF16[1]),em.text), "emphasis text")
    try require(model.blocks[oracle.link.block].inlines.contains { $0.role == "a" && $0.attributes["href"] == oracle.link.target }, "link target")
    let objects = model.blocks.flatMap(\.objects)
    try require(objects.map(\.kind) == oracle.unsupported, "unsupported object order")
    try require(objects.first(where: { $0.kind == "table" })?.cells == oracle.tableCells, "table content lost")
    try require(objects.first(where: { $0.kind == "figure" })?.captions.contains(where: { $0.contains(oracle.figureCaption) }) == true, "figure caption lost")
    let sourceBytes = try Data(contentsOf: root.appendingPathComponent("source/main.typ"))
    for w in oracle.whitespace {
        try require(sourceBytes.range(of: Data(w.source.utf8)) != nil, "authored whitespace bytes missing")
        let wm = maps(w.source), wg = graphemes(w.source)
        try require(wm.scalars == w.scalars && wm.cpToUTF8 == w.cpToUTF8 && wm.cpToUTF16 == w.cpToUTF16, "raw whitespace scalar/unit oracle")
        try require(wg.cp == w.graphemeCP && wg.u8 == w.graphemeUTF8 && wg.u16 == w.graphemeUTF16, "raw CRLF/tab grapheme oracle")
        try require(model.blocks.contains { exact($0.text,w.display) }, "whitespace display oracle")
        try require(!exact(w.source,w.display) && !w.loss.isEmpty, "loss must be explicit")
    }
    var excluded = 0
    for u in oracle.unicode {
        let matching = model.blocks.filter { exact($0.text,u.text) }
        try require(!matching.isEmpty, "Unicode fixture absent")
        let actual = maps(u.text), g = graphemes(u.text)
        try require(actual.scalars == u.scalars && actual.cpToUTF16 == u.cpToUTF16 && actual.cpToUTF8 == u.cpToUTF8, "independent scalar/offset oracle mismatch")
        try require(g.cp == u.graphemeCP && g.u8 == u.graphemeUTF8 && g.u16 == u.graphemeUTF16, "independent grapheme oracle mismatch")
        for i in 0...u.text.utf16.count where !g.u16.contains(i) {
            do { _ = try substring(u.text,i,i); throw Failure(description: "mid-grapheme accepted") }
            catch let e as Failure { try require(e.description == "illegal selection endpoint", "endpoint rejection failed") }
            excluded += 1
        }
        for (cp,utf16) in actual.cpToUTF16.enumerated() {
            let bytes = Array(u.text.utf8)[0..<actual.cpToUTF8[cp]]
            let prefix = String(decoding: bytes,as: UTF8.self)
            try require(prefix.utf16.count == utf16 && prefix.unicodeScalars.count == cp, "UTF8/UTF16 round trip")
        }
    }
    let c = oracle.crossBlockCopy
    var matrix = [[String: Any]](), layouts = [Layout]()
    for width in [320.0,640.0,960.0] { for size in [14.0,20.0,28.0] {
        let layout = try shape(model,data,width: width,size: size,oracle: oracle,layoutGeneration: layouts.count+1)
        try require(exact(try copy(model.blocks,(c.startBlock,c.startUTF16),(c.endBlock,c.endUTF16)),c.text), "cross-block copy")
        try require(exact(try copy(model.blocks,(c.endBlock,c.endUTF16),(c.startBlock,c.startUTF16)),c.reverseText), "backward copy")
        try require(model.anchors == oracle.anchors.merging(model.anchors) { expected,_ in expected }, "anchor preservation")
        let name = "layout-\(Int(width))-\(Int(size)).json"
        try write(["identity": try JSONSerialization.jsonObject(with: JSONEncoder().encode(layout.identity)), "layoutGeneration": layout.generation, "documentGeneration": model.generation, "widthPt": width, "fontSizePt": size, "originAxis": oracle.coordinateSystem, "caretEquivalence": oracle.caretEquivalence, "fontFallback": layout.fonts, "paintSHA256": layout.paintDigest, "bitmapScale": "1 pixel/pt for headless artifact only", "lines": layout.lines],out.appendingPathComponent(name))
        matrix.append(["widthPt": width,"fontSizePt": size,"lines": layout.lineCount,"carets": layout.caretCount,"rawMidGraphemeHitsExcluded": layout.rawInteriorHits,"exit": 0,"geometry": name])
        layouts.append(layout)
    } }
    try require(layouts[2].lineCount > layouts[8].lineCount, "actual reflow not observed")
    try require(layouts.flatMap(\.lines).contains { ($0["trailingWhitespaceAdvancePt"] as? Double ?? 0) > 0 }, "no whitespace advance observation")
    try require(layouts.flatMap(\.lines).contains { ($0["advanceBoundsPt"] as? [Double]) != ($0["inkBoundsPt"] as? [Double]) }, "ink/advance conflated")
    var accepted = Accepted(model: model,layout: layouts[0],digest: sha(data)), negatives = [[String: Any]]()
    try accepted.adopt(data,layouts[0],requested: model.identity,generation: 1)
    let original = accepted.digest, originalPaint = accepted.layout.paintDigest
    func negative(_ name: String, _ action: () throws -> Void) throws {
        var rejected = false
        do { try action() } catch { rejected = true }
        try require(rejected && accepted.digest == original && accepted.layout.paintDigest == originalPaint && accepted.model.identity == model.identity, "last complete accepted not retained: " + name)
        negatives.append(["case": name,"rejected": true,"lastAcceptedPreserved": true,"exit": 0])
    }
    let raw = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    func mutation(_ change: (inout [String: Any]) -> Void) throws -> Data { var value = raw; change(&value); return try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) }
    for field in ["document","service","revision","input"] {
        let changed = try mutation { value in var ident = value["identity"] as! [String: Any]; var part = ident[field] as! [String: Any]; part["value"] = "different-" + field; ident[field] = part; value["identity"] = ident }
        try negative("stale-"+field) { try accepted.adopt(changed,layouts[0],requested: model.identity,generation: 1) }
    }
    try negative("old-generation") { try accepted.adopt(data,layouts[0],requested: model.identity,generation: 2) }
    try negative("old-layout-generation-after-resize") { try accepted.adopt(data,layouts[0],requested: model.identity,generation: 1,layoutGeneration: 2) }
    let next = try mutation { $0["generation"] = 2 }
    try negative("late-geometry-after-new-import") { try accepted.adopt(next,layouts[0],requested: model.identity,generation: 2) }
    try negative("malformed-json") { try accepted.adopt(Data("{".utf8),layouts[0],requested: model.identity,generation: 1) }
    let unknown = try mutation { v in var b = v["blocks"] as! [[String: Any]]; b[0]["role"] = "unknown-required"; v["blocks"] = b }
    try negative("unknown-node") { try accepted.adopt(unknown,layouts[0],requested: model.identity,generation: 1) }
    let unknownCapability = try mutation { $0["requiredCapabilities"] = ["unknown-required"] }
    try negative("unknown-required-capability") { try accepted.adopt(unknownCapability,layouts[0],requested: model.identity,generation: 1) }
    var incomplete = layouts[0]; incomplete.complete = false
    try negative("incomplete-layout") { try accepted.adopt(data,incomplete,requested: model.identity,generation: 1) }
    let schema = try mutation { $0["proofSchema"] = 99 }
    try negative("unknown-schema") { try accepted.adopt(schema,layouts[0],requested: model.identity,generation: 1) }
    let compilerFailure = try mutation { v in var p = v["provenance"] as! [String: Any]; p["compilerExit"] = 1; v["provenance"] = p }
    try negative("compiler-failure") { try accepted.adopt(compilerFailure,layouts[0],requested: model.identity,generation: 1) }
    let badProvenance = try mutation { v in var p = v["provenance"] as! [String: Any]; var a = p["artifacts"] as! [String: String]; a["compiled/document.html"] = "wrong-compiler-artifact"; p["artifacts"] = a; v["provenance"] = p }
    try negative("compiler-provenance-mismatch") { try accepted.adopt(badProvenance,layouts[0],requested: model.identity,generation: 1) }
    let lost = try mutation { v in var b = v["blocks"] as! [[String: Any]]; b[2]["text"] = "lost"; v["blocks"] = b }
    try negative("import-offset-corruption") { try accepted.adopt(lost,layouts[0],requested: model.identity,generation: 1) }
    try negative("layout-failure") { _ = try shape(model,data,width: -1,size: 14,oracle: oracle) }
    let otherBytes = try mutation { $0["generation"] = 1; $0["extra"] = "different bytes" }
    try negative("geometry-input-digest-mismatch") { try accepted.adopt(otherBytes,layouts[0],requested: model.identity,generation: 1) }
    let nextModel = try importModel(next)
    let nextLayout = try shape(nextModel,next,width: 640,size: 20,oracle: oracle,layoutGeneration: 10)
    try accepted.adopt(next,nextLayout,requested: nextModel.identity,generation: 2,layoutGeneration: 10)
    var lateRejected = false
    do { try accepted.adopt(data,layouts[0],requested: nextModel.identity,generation: 2,layoutGeneration: 10) } catch { lateRejected = true }
    try require(lateRejected && accepted.digest == sha(next) && accepted.layout.paintDigest == nextLayout.paintDigest && accepted.model.generation == 2, "successful new snapshot overwritten by late old geometry")
    negatives.append(["case": "late-old-result-after-successful-transition", "rejected": true, "lastAcceptedPreserved": true,"exit": 0])
    try write(["status": "technical-pass", "exit": 0, "coverage": "real compiler normalized output; standalone CoreText shaping/paint/caret only", "inputSHA256": sha(data), "oracleSHA256": sha(oracleData), "oracleOrigin": oracle.oracleOrigin,"oracleFinalReview": oracle.reviewStatus,"matrix": matrix,"negativeCases": negatives,"excludedIllegalEndpoints": excluded,"limitations": ["PM/CodeTester independent oracle review pending","No GUI, VoiceOver, TextKit interaction, source authority or live service verified","math/table/figure placeholders; native fidelity unsupported","ligature glyphs and fallback are observations only; scalar spelling remains exact"]],out.appendingPathComponent("summary.json"))
    print("{\"status\":\"technical-pass\",\"matrix\":9,\"negativeCases\":\(negatives.count),\"excludedIllegalEndpoints\":\(excluded),\"exit\":0}")
}
do { try run() } catch {
    let failure: [String: Any] = ["status": "failed", "exit": 1, "error": String(String(describing: error).prefix(500))]
    if let bytes = try? JSONSerialization.data(withJSONObject: failure, options: [.sortedKeys]) { FileHandle.standardError.write(bytes); FileHandle.standardError.write(Data([10])) }
    exit(1)
}
