import AppKit
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

private final class MathLog: @unchecked Sendable {
    private let lock = NSLock()
    private var records = [NativeMathExecution]()
    func append(_ v: NativeMathExecution) { lock.lock(); records.append(v); lock.unlock() }
    var values: [NativeMathExecution] { lock.lock(); defer { lock.unlock() }; return records }
}
private actor Calls {
    var requests = 0
    func hit() { requests += 1 }
}
// Deliberate failed draw adapter. It reserves exactly the original attachment
// geometry but paints nothing; it must never satisfy the transcript oracle.
private final class MissingMathCell: NSTextAttachmentCell {
    let reserved: NSSize, offset: NSPoint
    init(_ cell: NSTextAttachmentCell) { reserved = cell.cellSize(); offset = cell.cellBaselineOffset(); super.init(textCell: "") }
    required init(coder: NSCoder) { fatalError("test only") }
    override func cellSize() -> NSSize { reserved }
    override func cellBaselineOffset() -> NSPoint { offset }
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {}
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?, characterIndex charIndex: Int) {}
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?, characterIndex charIndex: Int, layoutManager: NSLayoutManager) {}
}

@main struct ChatMathTests {
    static var assertions = 0
    static func check(_ value: Bool, _ name: String) throws {
        assertions += 1
        if !value { throw NSError(domain: "NA10: " + name, code: 1) }
    }
    static func save(_ value: Any, _ url: URL) throws {
        try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]).write(to: url)
    }
    static func png(_ image: CGImage, _ url: URL) throws {
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        try check(CGImageDestinationFinalize(dest), "PNG write")
    }
    static func ink(_ image: CGImage) -> Int {
        let bitmap = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        bitmap.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let p = bitmap.data!.assumingMemoryBound(to: UInt8.self)
        return stride(from: 3, to: bitmap.bytesPerRow * bitmap.height, by: 4).filter { p[$0] > 40 }.count
    }
    static func fractionTopology(_ image: CGImage) throws -> [String: Int] {
        let w = image.width, h = image.height
        let bitmap = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        bitmap.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let p = bitmap.data!.assumingMemoryBound(to: UInt8.self)
        var rows = [Int](), longest = [Int]()
        for y in 0..<h {
            var count = 0, run = 0, best = 0
            for x in 0..<w {
                if p[y * w * 4 + x * 4 + 3] > 100 { count += 1; run += 1; best = max(best, run) }
                else { run = 0 }
            }
            rows.append(count); longest.append(best)
        }
        let bar = longest.indices.max(by: { longest[$0] < longest[$1] })!
        let above = rows.prefix(max(0, bar - 2)).reduce(0, +)
        let below = rows.suffix(max(0, h - bar - 3)).reduce(0, +)
        try check(longest[bar] >= Int(Double(w) * 0.65), "native fraction continuous rule")
        try check(above > 10 && below > 10, "native fraction has separate ink on both sides of rule")
        return ["aboveRuleInk": above, "belowRuleInk": below, "ruleSpan": longest[bar]]
    }
    static func paint(_ scene: NativeVectorScene, _ size: CGSize) throws -> CGImage {
        let w = Int(ceil(size.width * 2)), h = Int(ceil(size.height * 2))
        let bitmap = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        bitmap.scaleBy(x: 2, y: 2); bitmap.translateBy(x: 0, y: CGFloat(h) / 2); bitmap.scaleBy(x: 1, y: -1)
        scene.draw(in: bitmap, rect: CGRect(origin: .zero, size: size))
        return bitmap.makeImage()!
    }
    @MainActor static func wait(_ predicate: () -> Bool) async throws {
        for _ in 0..<1500 {
            if predicate() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw NSError(domain: "NA10 wait timeout", code: 2)
    }
    static func rejected(_ label: String, expected: NativeObjectError, _ body: () async throws -> Void) async throws {
        do { try await body() } catch { try check(error as? NativeObjectError == expected, label + " exact failure"); return }
        throw NSError(domain: "NA10 accepted negative: " + label, code: 3)
    }
    @MainActor static func transcriptPaint(_ out: URL, _ config: [String: String]) async throws {
        let identity = NativeDocumentIdentity(documentID: "paint", serviceID: "reader:1:1", revision: "paint", scope: .fixture)
        let request = NativeReaderRequestContext(requestID: UUID(), viewID: UUID(), generation: 1, target: identity)
        let calls = Calls()
        let attachment = try NativeReaderAttachment(data: JSONSerialization.data(withJSONObject:
            ["url":"http://127.0.0.1:12345/", "documentID":"paint", "service":["pid":1, "startedAt":1]]))
        let network = NativeReaderNetwork(send: { _, _ in await calls.hit(); throw URLError(.unsupportedURL) },
            stream: { _ in AsyncThrowingStream { $0.finish() } })
        let actions = NativeReaderActions(transport: NativeReaderTransport(attachment: attachment, network: network))
        let worker = NativeMathWorker(node: URL(fileURLWithPath: config["node"]!), helper: URL(fileURLWithPath: config["helper"]!), runtime: URL(fileURLWithPath: config["runtime"]!))
        let markdown = "Fraction $\\frac{1}{2}$, root \\(\\sqrt{x}\\), script $a_1^2$, AMS $$\\begin{pmatrix}1&2\\\\3&4\\end{pmatrix}$$, Unicode $Ж+α$."
        let state = NativeReaderConversation(state: .init(context: request, conversationID: UUID(), version: 1, sequence: 1,
            messages: [.init(id: UUID(), role: .assistant, markdown: markdown, complete: true)]), draft: "", status: "completed", attached: true)
        var reports = [[String: Any]]()
        for dark in [false, true] {
            let theme = dark ? "dark" : "light"
            let view = NativeReaderChatView(actions: actions, context: request, authorize: {})
            let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 800, height: 520), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = view
            defer { view.dispose(); window.close() }
            try view.configureMath(worker: worker, context: NativeObjectContext(identity: identity, snapshotGeneration: 1,
                generation: 1, width: 800, fontSize: 20, fontName: "system", theme: dark ? .dark : .light, mode: .reflow, pageHeight: 800))
            view.present(state)
            try await wait { view.preparedFormulaCount == 5 || view.mathFailure != nil }
            try check(view.preparedFormulaCount == 5, "transcript real preparation " + theme)
            view.layoutSubtreeIfNeeded()
            let answer = view.answer, scroll = answer.enclosingScrollView!, clip = scroll.contentView
            scroll.layoutSubtreeIfNeeded(); answer.layoutSubtreeIfNeeded()
            let manager = answer.layoutManager!, container = answer.textContainer!
            manager.ensureLayout(for: container)
            let original = NSAttributedString(attributedString: answer.textStorage!)
            var regions = [CGRect]()
            original.enumerateAttribute(.attachment, in: NSRange(location: 0, length: original.length)) { value, range, _ in
                guard let a = value as? NSTextAttachment, let cell = a.attachmentCell as? NSTextAttachmentCell else { return }
                let glyph = manager.glyphIndexForCharacter(at: range.location)
                let line = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
                let point = manager.location(forGlyphAt: glyph)
                // NSLayoutManager's attachment glyph location already includes
                // the cell's baseline offset. Subtract only the native cell
                // height to obtain its flipped document draw rect.
                let size = cell.cellSize(), offset = cell.cellBaselineOffset()
                let rect = CGRect(x: line.minX + point.x + offset.x + answer.textContainerOrigin.x,
                    y: line.minY + point.y - size.height + answer.textContainerOrigin.y,
                    width: size.width, height: size.height)
                regions.append(answer.convert(rect, to: clip))
            }
            let bodyRange = (original.string as NSString).range(of: "Fraction ")
            let bodyGlyphs = manager.glyphRange(forCharacterRange: bodyRange, actualCharacterRange: nil)
            let bodyRect = manager.boundingRect(forGlyphRange: bodyGlyphs, in: container)
                .offsetBy(dx: answer.textContainerOrigin.x, dy: answer.textContainerOrigin.y)
            regions.append(answer.convert(bodyRect, to: clip))
            func rectJSON(_ r: CGRect) -> [String: Double] { ["x":r.minX,"y":r.minY,"width":r.width,"height":r.height] }
            try save(["view":rectJSON(view.bounds),"answer":rectJSON(answer.frame),"clip":rectJSON(clip.bounds),
                "container":["width":container.containerSize.width,"height":container.containerSize.height],"regions":regions.map(rectJSON)], out.appendingPathComponent("geometry-" + theme + ".json"))
            func capture(_ name: String) throws -> NSBitmapImageRep {
                view.layoutSubtreeIfNeeded(); manager.ensureLayout(for: container)
                guard let rep = clip.bitmapImageRepForCachingDisplay(in: clip.bounds) else { throw NativeObjectError.invalidGeometry }
                clip.cacheDisplay(in: clip.bounds, to: rep)
                let url = out.appendingPathComponent(name + "-" + theme + ".png")
                try png(rep.cgImage!, url)
                // Verify the persisted PNG bytes, not AppKit's mutable cache.
                return NSBitmapImageRep(data: try Data(contentsOf: url))!
            }
            let actual = try capture("transcript")
            // The same clip/view hierarchy supplies the background reference and
            // all mutants. No image/glyph is synthesized into a success bitmap.
            answer.textStorage!.setAttributedString(NSAttributedString(string: ""))
            let blank = try capture("empty")
            answer.textStorage!.setAttributedString(NSAttributedString(string: "Assistant\n", attributes: [.font:NSFont.boldSystemFont(ofSize:14), .foregroundColor:NSColor.labelColor]))
            let heading = try capture("heading-only")
            let brokenText = NSMutableAttributedString(attributedString: original)
            original.enumerateAttribute(.attachment, in: NSRange(location: 0, length: original.length)) { value, range, _ in
                if let a = value as? NSTextAttachment, let cell = a.attachmentCell as? NSTextAttachmentCell {
                    let missing = NSTextAttachment(); missing.attachmentCell = MissingMathCell(cell)
                    brokenText.addAttribute(.attachment, value: missing, range: range)
                }
            }
            answer.textStorage!.setAttributedString(brokenText)
            let broken = try capture("broken-attachment")
            func verify(_ sample: NSBitmapImageRep) -> [String: Any] {
                let sx = Double(sample.pixelsWide) / clip.bounds.width, sy = Double(sample.pixelsHigh) / clip.bounds.height
                var counts = [Int](), topology = false, within = regions.count == 6
                var fractionEvidence = [String: Int]()
                for (i, rect) in regions.enumerated() {
                    let local = rect.offsetBy(dx: -clip.bounds.minX, dy: -clip.bounds.minY)
                    let x0 = Int(floor(local.minX*sx)), y0 = Int(floor(local.minY*sy))
                    let x1 = Int(ceil(local.maxX*sx)), y1 = Int(ceil(local.maxY*sy))
                    guard x0 >= 0, y0 >= 0, x1 <= sample.pixelsWide, y1 <= sample.pixelsHigh, x1 > x0, y1 > y0 else { within = false; counts.append(0); continue }
                    var rows = [Int](), runs = [Int]()
                    for y in y0..<y1 {
                        var count = 0, run = 0, best = 0
                        for x in x0..<x1 {
                            let a = sample.colorAt(x:x,y:y)!.usingColorSpace(.deviceRGB)!
                            let b = blank.colorAt(x:x,y:y)!.usingColorSpace(.deviceRGB)!
                            // Alpha composite first, then compare signed RGB
                            // luminance to the identical empty-view background.
                            func luma(_ c: NSColor) -> Double {
                                let bg = dark ? 0.0 : 1.0, alpha = c.alphaComponent
                                return (0.2126*c.redComponent + 0.7152*c.greenComponent + 0.0722*c.blueComponent)*alpha + bg*(1-alpha)
                            }
                            let delta = dark ? luma(a)-luma(b) : luma(b)-luma(a)
                            if delta > 0.25 { count += 1; run += 1; best = max(best,run) } else { run = 0 }
                        }
                        rows.append(count); runs.append(best)
                    }
                    counts.append(rows.reduce(0,+))
                    if i == 0, let bar = runs.indices.max(by: { runs[$0] < runs[$1] }) {
                        let above = rows.prefix(max(0,bar-Int(sy))).reduce(0,+)
                        let below = rows.suffix(max(0,rows.count-bar-Int(sy)-1)).reduce(0,+)
                        topology = runs[bar] >= Int(Double(x1-x0)*0.55) && above >= Int(5*sx*sy) && below >= Int(5*sx*sy)
                        fractionEvidence = ["aboveRuleInk":above,"belowRuleInk":below,"ruleSpan":runs[bar]]
                    }
                }
                return ["pass":within && counts.count == 6 && counts.allSatisfy { $0 >= Int(5*sx*sy) } && topology,
                    "foregroundCounts":counts,"fractionTopology":topology,"fraction":fractionEvidence,"insideClip":within,"scaleX":sx,"scaleY":sy]
            }
            let success = verify(actual), emptyResult = verify(blank), headingResult = verify(heading), brokenResult = verify(broken)
            let report: [String: Any] = ["theme":theme,"actual":success,"empty":emptyResult,"headingOnly":headingResult,"brokenAttachment":brokenResult,
                "regionKinds":["fraction","root","script","AMS","Unicode","body text (heading excluded)"],
                "coordinateSystem":"clip-relative top-left NSBitmapImageRep rows; explicit pixel/view scale; alpha-composited signed foreground/background contrast"]
            reports.append(report); try save(reports, out.appendingPathComponent("transcript-pixel-proof.json"))
            try check(success["pass"] as? Bool == true, "actual production transcript foreground/topology " + theme)
            for mutant in [emptyResult,headingResult,brokenResult] { try check(mutant["pass"] as? Bool == false, "mutant must fail " + theme) }
            try check(!window.isVisible && !window.isKeyWindow && !window.isMainWindow, "offscreen window never ordered or activated")
        }
        try check(await calls.requests == 0, "paint/mutants dispatch zero actions")
    }
    @MainActor static func main() async throws {
        let args = CommandLine.arguments
        let out = URL(fileURLWithPath: args[1]), oracleURL = URL(fileURLWithPath: args[2])
        let config = try JSONSerialization.jsonObject(with: Data(contentsOf: out.appendingPathComponent("config.json"))) as! [String: String]
        let oracle = try JSONSerialization.jsonObject(with: Data(contentsOf: oracleURL)) as! [String: Any]
        let app = NSApplication.shared; app.setActivationPolicy(.prohibited)
        if args.count > 3, args[3] == "view-only" { try await transcriptPaint(out, config); return }
        let identity = NativeDocumentIdentity(documentID: "chat-math", serviceID: "reader:1:1", revision: "na10", scope: .fixture)
        let request = NativeReaderRequestContext(requestID: UUID(), viewID: UUID(), generation: 1, target: identity)
        func context(_ width: Double = 320, _ font: Double = 20, _ dark: Bool = false, _ generation: Int = 1) -> NativeObjectContext {
            NativeObjectContext(identity: identity, snapshotGeneration: 1, generation: generation, width: width,
                fontSize: font, fontName: "system", theme: dark ? .dark : .light, mode: .reflow, pageHeight: 800)
        }
        let log = MathLog()
        func worker(_ helper: String? = nil, _ timeout: Double = 10) -> NativeMathWorker {
            NativeMathWorker(node: URL(fileURLWithPath: config["node"]!), helper: URL(fileURLWithPath: helper ?? config["helper"]!),
                runtime: URL(fileURLWithPath: config["runtime"]!), timeout: timeout, record: { log.append($0) })
        }
        let real = worker()
        var paints = [[String: Any]]()
        var fractions = [[String: Int]](), legacyPaints = [[String: Any]]()
        for item in oracle["cases"] as! [[String: Any]] {
            for dark in [false, true] {
                let id = item["id"] as! String, c = context(320, 20, dark)
                let prepared = try await real.prepare(tex: item["tex"] as! String, display: item["display"] as! Bool, context: c)
                let count = ink(prepared.image)
                if id == "fraction" { fractions.append(try fractionTopology(prepared.image)) }
                try check(count > 30, "actual native ink " + id)
                try check(prepared.math.normalizedText.contains(item["semantic"] as! String), "semantic " + id)
                let wb = item["widthEm"] as! [Double], hb = item["heightEm"] as! [Double]
                try check((wb[0]...wb[1]).contains(prepared.size.width / 20), "independent width " + id)
                try check((hb[0]...hb[1]).contains(prepared.size.height / 20), "independent height " + id)
                try png(prepared.image, out.appendingPathComponent("paint-\(id)-\(dark).png"))
                paints.append(["case": id, "dark": dark, "ink": count, "width": prepared.size.width,
                    "height": prepared.size.height, "semantic": prepared.math.normalizedText])
            }
        }
        // Independent scale invariance and real legacy inline zero-descent cases.
        for width in [320.0, 640, 960] {
            for font in [14.0, 18, 24] {
                let c = context(width, font)
                let p = try await real.prepare(tex: "\\frac{1}{2}", display: false, context: c)
                try check(p.size.width > font * 0.5 && p.size.width < font * 1.5, "fraction native scale")
                for mml in ["<math display=\"inline\"><mi>x</mi></math>", "<math><mi>Ж</mi></math>"] {
                    let m = NativeMath(mathML: mml, normalizedText: mml.contains("Ж") ? "Ж" : "x", display: false)
                    let layout = try await real.calculate(m, context: c, width: width)
                    let f = layout.whole
                    let scene = try NativeVectorScene.decode(Data(f.svg.utf8), dark: false)
                    try check(!scene.shapes.isEmpty && f.descent >= 0, "legacy inline native glyph")
                    let image = try paint(scene, CGSize(width: f.width, height: f.ascent + f.descent))
                    let pixels = ink(image)
                    try check(pixels > 10, "real legacy inline/Cyrillic native paint")
                    let name = "legacy-\(m.normalizedText)-\(width)-\(font).png"
                    try png(image, out.appendingPathComponent(name))
                    legacyPaints.append(["mathML": mml, "width": width, "font": font, "ink": pixels, "file": name])
                }
            }
        }
        let oversized = String(repeating: "x", count: 80001) + "$x$"
        try check(NativeReaderAnswerPart.tokens(oversized).map(\.original).joined() == oversized, "oversize literal copy never truncates")
        for policy in oracle["policy"] as! [[String: Any]] {
            let raw = policy["markdown"] as! String, tokens = NativeReaderAnswerPart.tokens(raw)
            let math = tokens.compactMap { token -> String? in if case .math(let s) = token.part { return s }; return nil }
            try check(math == policy["math"] as! [String], "delimiter/code/escape policy")
            try check(tokens.filter { if case .math = $0.part { return true }; return false }.map(\.display) == policy["display"] as! [Bool], "display policy")
            try check(tokens.map(\.original).joined() == raw, "exact original scalars")
        }

        let calls = Calls()
        let network = NativeReaderNetwork(send: { _, _ in await calls.hit(); throw URLError(.unsupportedURL) },
            stream: { _ in AsyncThrowingStream { $0.finish(throwing: URLError(.unsupportedURL)) } })
        let attachment = try NativeReaderAttachment(data: JSONSerialization.data(withJSONObject:
            ["url":"http://127.0.0.1:12345/", "documentID":"chat-math", "service":["pid":1, "startedAt":1]]))
        let actions = NativeReaderActions(transport: NativeReaderTransport(attachment: attachment, network: network))
        var authorized = 0
        let view = NativeReaderChatView(actions: actions, context: request, authorize: { authorized += 1 })
        try view.configureMath(worker: real, context: context())
        let conversation = UUID(), message = UUID()
        func record(_ text: String, _ complete: Bool = true, _ version: Int = 1, _ sequence: Int = 1,
                    _ id: UUID? = nil, _ ctx: NativeReaderRequestContext? = nil) -> NativeReaderConversation {
            NativeReaderConversation(state: NativeReaderChatState(context: ctx ?? request, conversationID: id ?? conversation,
                version: version, sequence: sequence, messages: [.init(id: message, role: .assistant, markdown: text, complete: complete)]),
                draft: "server draft", status: complete ? "completed" : "streaming", attached: true)
        }
        let text = "Fraction $\\frac{1}{2}$, root \\(\\sqrt{x}\\), script $a_1^2$, AMS $$\\begin{pmatrix}1&2\\\\3&4\\end{pmatrix}$$, Ж $Ж+α$."
        view.present(record(text, false))
        try await Task.sleep(nanoseconds: 50_000_000)
        try check(view.mathPreparationCount == 0 && view.preparedFormulaCount == 0, "streaming never prepares math")
        view.present(record(text, true, 2, 2))
        for _ in 0..<10 { view.present(record(text, true, 2, 2)) }
        try check(view.mathPreparationCount == 1, "coalesce repeated presentation")
        try await wait { view.preparedFormulaCount == 5 || view.mathFailure != nil }
        try check(view.preparedFormulaCount == 5, "real helper to native attributed view")
        let whole = NSRange(location: 0, length: view.answer.textStorage!.length)
        try check(view.answer.ordinaryText(in: whole) == "Assistant\n" + text + "\n", "ordinary copy retains authored TeX")
        try check(view.answer.accessibilityValue()?.contains("fraction(1, 2)") == true, "headless AX hierarchy")
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.declareTypes([.string], owner: nil); view.answer.setSelectedRange(whole)
        try check(view.answer.writeSelection(to: board, type: .string), "private pasteboard write")
        try check(board.string(forType: .string) == view.answer.ordinaryText(in: whole), "private pasteboard exact")
        var attachments = 0
        view.answer.textStorage!.enumerateAttribute(.attachment, in: whole) { value, _, _ in
            if let a = value as? NSTextAttachment, let cell = a.attachmentCell as? NSTextAttachmentCell, cell.image != nil { attachments += 1 }
        }
        try check(attachments == 5, "five native image attachment cells")
        // N5: equal copy attributes must not merge adjacent token identities.
        let adjacent = NativeReaderChatView(actions: actions, context: request, authorize: {})
        try adjacent.configureMath(worker: real, context: context())
        let cases = [("\\(x\\)\\(x\\)", 2), ("\\(x\\)\\(x\\)\\(x\\)", 3), ("\\(x\\) prose \\(y\\)\\(x\\)", 3)]
        for (index, item) in cases.enumerated() {
            adjacent.present(record(item.0, true, index + 1, index + 1, UUID()))
            try await wait { adjacent.preparedFormulaCount == item.1 }
            let storage = adjacent.answer.textStorage!
            let all = NSRange(location: 0, length: storage.length)
            let full = "Assistant\n" + item.0 + "\n"
            try check(adjacent.answer.ordinaryText(in: all) == full, "N5 adjacent equal formulas full copy count/order")
            adjacent.answer.setSelectedRange(all); board.clearContents()
            try check(adjacent.answer.writeSelection(to: board,type:.string) && board.string(forType:.string)==full,"N5 full native private copy count/order")
            var positions = [Int]()
            for i in 0..<storage.length where storage.attribute(.attachment, at: i, effectiveRange: nil) != nil { positions.append(i) }
            try check(positions.count == item.1, "N5 actual prepared attachments")
            for (token, location) in positions.enumerated() {
                let range = NSRange(location: location, length: 1)
                let expected = index == 2 && token == 1 ? "\\(y\\)" : "\\(x\\)"
                adjacent.answer.setSelectedRange(range); board.clearContents()
                try check(adjacent.answer.writeSelection(to: board, type: .string) && board.string(forType: .string) == expected, "N5 partial private copy boundary")
            }
            if index == 1 {
                let two = NSRange(location: positions[1], length: 2)
                try check(adjacent.answer.ordinaryText(in: two) == "\\(x\\)\\(x\\)", "N5 adjacent subset count/order")
            }
        }
        adjacent.dispose()
        try await transcriptPaint(out, config)
        try view.configureMath(worker: real, context: context(640, 24, true, 2))
        try await wait { view.preparedFormulaCount == 5 || view.mathFailure != nil }
        try check(view.preparedFormulaCount == 5 && view.mathPreparationCount == 2, "theme/font/width/generation invalidate")
        view.present(record("old $x$", true, 1, 1))
        try check(view.preparedFormulaCount == 5, "stale version/sequence ignored")
        let other = NativeReaderRequestContext(requestID: UUID(), viewID: request.viewID, generation: 2, target: identity)
        view.present(record("wrong $x$", true, 3, 3, nil, other))
        try check(view.preparedFormulaCount == 5, "context mismatch ignored")
        view.composer.string = "Newer local draft"
        view.textDidChange(Notification(name: NSText.didChangeNotification))
        view.present(record(text, true, 2, 2))
        try check(view.composer.string == "Newer local draft", "draft survives math redisplay")
        // Let the draft debounce be cancelled before it can call an action.
        view.dispose()
        try check(await calls.requests == 0 && authorized == 0, "presentation/copy/AX/resize zero action/provider dispatch")

        let slow = worker(config["slow"], 2)
        let reused = NativeReaderChatView(actions: actions, context: request, authorize: {})
        try reused.configureMath(worker: slow, context: context())
        var ticks = 0
        let timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { _ in ticks += 1 }
        reused.present(record("$x$"))
        try await Task.sleep(nanoseconds: 150_000_000)
        try check(ticks >= 3, "UI runloop continues during slow child")
        reused.present(record("new streaming", false, 1, 1, UUID()))
        try await Task.sleep(nanoseconds: 150_000_000)
        try check(reused.preparedFormulaCount == 0 && reused.answer.string.contains("new streaming"), "view reuse cancels old computation")
        try reused.configureMath(worker: real, context: context())
        reused.present(record("$\\frac{1}{2}$", true, 2, 2))
        try await wait { reused.preparedFormulaCount == 1 }
        reused.present(record("$\\notACommand{x}$", true, 3, 3))
        try await Task.sleep(nanoseconds: 500_000_000)
        try check(reused.preparedFormulaCount == 0 && reused.answer.string.contains("\\notACommand"), "malformed remains literal, no successful fallback")
        try check(reused.answer.accessibilityValue()?.contains("Math unavailable") == true, "bounded failure AX")
        try reused.configureMath(worker: slow, context: context())
        reused.present(record("$x$", true, 4, 4)); reused.dispose()
        try await Task.sleep(nanoseconds: 120_000_000)
        try check(reused.preparedFormulaCount == 0 && !reused.sendButton.isEnabled, "dispose blocks late adoption")
        timer.invalidate()
        try await rejected("timeout", expected: .unsupported("math-helper-timeout")) { _ = try await worker(config["slow"], 0.1).prepare(tex: "x", display: false, context: context()) }
        try await rejected("stdout budget", expected: .budget) { _ = try await worker(config["flood"]).prepare(tex: "x", display: false, context: context()) }
        try await rejected("resident memory", expected: .budget) { _ = try await worker(config["memory"]).prepare(tex: "x", display: false, context: context()) }
        let pending = Task { try await slow.prepare(tex: "x", display: false, context: context()) }
        try await Task.sleep(nanoseconds: 50_000_000); pending.cancel()
        try await rejected("cancel", expected: .cancelled) { _ = try await pending.value }
        try await rejected("input budget", expected: .budget) { _ = try await real.prepare(tex: String(repeating: "x", count: 65537), display: false, context: context()) }
        try check(app.activationPolicy() == .prohibited && app.windows.allSatisfy { !$0.isVisible }, "no activation or GUI")
        try save(paints, out.appendingPathComponent("native-paint.json"))
        try save(fractions, out.appendingPathComponent("fraction-native-topology.json"))
        try save(legacyPaints, out.appendingPathComponent("legacy-mathml-native-paint.json"))
        try JSONEncoder().encode(log.values).write(to: out.appendingPathComponent("worker-executions.json"))
        try save(["assertions": assertions, "paintCases": paints.count, "skips": 0, "uiTicks": ticks,
            "actions": await calls.requests, "inference": 0, "headlessAX": true, "gui": false,
            "transcriptThemes": 2, "transcriptMutantsRejected": 6, "finding": "PM-CHAT-PAINT-01"], out.appendingPathComponent("native-results.json"))
    }
}
