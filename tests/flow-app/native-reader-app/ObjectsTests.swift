import AppKit
import CoreText
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

// Headless executable: no NSApplication, windows, account or live services.
private final class ExecutionLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries = [NativeMathExecution]()
    func append(_ value: NativeMathExecution) { lock.lock(); entries.append(value); lock.unlock() }
    var values: [NativeMathExecution] { lock.lock(); defer { lock.unlock() }; return entries }
}

@main struct ObjectsTests {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw NSError(domain: "NA03: " + message, code: 1) }
    }
    static func sha(_ value: String) -> String { SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined() }
    static func write(_ value: Any, _ url: URL) throws { try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]).write(to: url) }
    static func expectFailure(_ name: String, _ body: () throws -> Void) throws {
        do { try body() } catch { return }
        throw NSError(domain: "NA03 negative did not reject: " + name, code: 2)
    }
    static func expectAsyncFailure(_ name: String, _ body: () async throws -> Void) async throws {
        do { try await body() } catch { return }
        throw NSError(domain: "NA03 async negative did not reject: " + name, code: 2)
    }
    static func requestID(_ c: NativeObjectContext, _ n: NativeReaderNode, _ width: Double) -> String {
        sha(c.key + ":" + n.id + ":" + String(width))
    }
    static func request(_ c: NativeObjectContext, _ n: NativeReaderNode, _ width: Double) -> [String: Any] {
        ["mathML": n.math!.mathML, "width": width, "fontSize": c.fontSize, "font": "MathJaxNewcm",
         "context": ["revision": c.identity.revision, "generation": c.generation, "theme": c.theme.rawValue]]
    }
    static func dummy(_ c: NativeObjectContext, _ n: NativeReaderNode, _ width: Double) throws -> NativeMathLayout {
        let f: [String: Any] = ["svg": "<svg viewBox=\"0 0 1 1\"><rect width=\"1\" height=\"1\"/></svg>", "width": 1, "ascent": 1, "descent": 0]
        let data: [String: Any] = ["version": 1, "inputHash": sha(n.math!.mathML), "context": request(c, n, width)["context"]!,
                                  "font": "MathJaxNewcm", "fontSize": c.fontSize, "width": width, "whole": f, "fragments": [f], "diagnostics": []]
        return try NativeMathLayout.decode(JSONSerialization.data(withJSONObject: data), math: n.math!, context: c, width: width)
    }
    static func bitmap(_ size: CGSize, dark: Bool) throws -> CGContext {
        let w = Int(ceil(size.width)), h = Int(ceil(size.height))
        guard w > 0, h > 0, w * h < 16000000, let ctx = CGContext(data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: 4 * w, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw NativeObjectError.budget
        }
        ctx.setFillColor(CGColor(gray: dark ? 0 : 1, alpha: 1)); ctx.fill(CGRect(origin: .zero, size: size))
        ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)
        return ctx
    }
    static func pixels(_ ctx: CGContext, dark: Bool) -> (ink: Int, blue: Int, red: Int) {
        let data = ctx.data!.assumingMemoryBound(to: UInt8.self)
        var ink = 0, blue = 0, red = 0
        for i in stride(from: 0, to: ctx.bytesPerRow * ctx.height, by: 4) {
            let r = Int(data[i]), g = Int(data[i + 1]), b = Int(data[i + 2])
            if dark ? max(r, g, b) > 20 : min(r, g, b) < 235 { ink += 1 }
            if b > r + 20 && b > g + 20 { blue += 1 }
            if r > g + 20 && r > b + 20 { red += 1 }
        }
        return (ink, blue, red)
    }
    static func savePNG(_ ctx: CGContext, _ url: URL) throws {
        guard let image = ctx.makeImage(), let out = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw NativeObjectError.invalidGeometry }
        CGImageDestinationAddImage(out, image, nil)
        try require(CGImageDestinationFinalize(out), "PNG finalize")
    }
    @MainActor static func main() async throws {
        let mode = CommandLine.arguments[1], root = URL(fileURLWithPath: CommandLine.arguments[2])
        let oracle = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3]))) as! [String: Any]
        if mode == "fraction" {
            let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("fraction-oracle.json"))) as! [String: Any]
            let f = raw["whole"] as! [String: Any], expected = oracle["indivisibleMath20"] as! [String: Any]
            let scene = try NativeVectorScene.decode(Data((f["svg"] as! String).utf8), dark: false)
            let scale: CGFloat = 4, font: CGFloat = 20
            let ascent = CGFloat(f["ascent"] as! Double), descent = CGFloat(f["descent"] as! Double)
            let ctx = try bitmap(CGSize(width: 256, height: 256), dark: false)
            let frame = CGRect(x: 10, y: 10, width: CGFloat(f["width"] as! Double) * scale, height: (ascent + descent) * scale)
            scene.draw(in: ctx, rect: frame)
            let axis = (10 + ascent * scale) - CGFloat(expected["axisEm"] as! Double) * font * scale
            let thickness = CGFloat(expected["ruleThicknessEm"] as! Double) * font * scale
            var above = 0, below = 0, rule = 0
            let data = ctx.data!.assumingMemoryBound(to: UInt8.self)
            for row in 0..<256 { for column in 0..<256 {
                let i = row * ctx.bytesPerRow + 4 * column
                if data[i] < 128 {
                    let y = CGFloat(row)
                    if y < axis - thickness { above += 1 }
                    else if y > axis + thickness { below += 1 }
                    else { rule += 1 }
                }
            } }
            try savePNG(ctx, root.appendingPathComponent("fraction-native.png"))
            try write(["above": above, "below": below, "rule": rule, "axis": axis, "thickness": thickness], root.appendingPathComponent("fraction-paint-attempt.json"))
            try require(above > 10 && below > 10 && rule > 10, "native fraction topology")
            let result = ["aboveRuleInk": above, "belowRuleInk": below, "ruleInk": rule]
            print(String(decoding: try JSONSerialization.data(withJSONObject: result), as: UTF8.self)); return
        }
        let doc = try NativeReaderDocument.decode(Data(contentsOf: root.appendingPathComponent("native.json")))
        var assets = [String: Data]()
        for a in doc.assets { assets[a.id] = try Data(contentsOf: root.appendingPathComponent("assets/" + a.id)) }
        let widths = oracle["widths"] as! [Double], fonts = oracle["fonts"] as! [Double]
        var contexts = [NativeObjectContext]()
        for w in widths { for f in fonts { for theme in [NativeObjectContext.Theme.light, .dark] { for m in [NativeObjectContext.Mode.reflow, .paged] {
            contexts.append(NativeObjectContext(identity: doc.identity, snapshotGeneration: doc.generation, generation: contexts.count + 1,
                width: w, fontSize: f, fontName: "system", theme: theme, mode: m, pageHeight: 800))
        } } } }
        if mode == "requests" {
            var requests = [[String: Any]](), seen = Set<String>()
            for c in contexts {
                _ = try await NativeReaderPagedLayout.layout(document: doc, context: c, assets: assets, math: { n, width in
                    let id = requestID(c, n, width)
                    if seen.insert(id).inserted { requests.append(["id": id, "input": request(c, n, width)]) }
                    return try dummy(c, n, width)
                })
            }
            try write(requests, root.appendingPathComponent("requests.json")); return
        }
        try require(mode == "verify", "mode")
        var matrix = [[String: Any]](), plans = [NativeObjectPlan](), broken = 0
        for c in contexts {
            let layoutStart = ProcessInfo.processInfo.systemUptime
            let plan = try await NativeReaderPagedLayout.layout(document: doc, context: c, assets: assets, math: { n, width in
                let data = try Data(contentsOf: root.appendingPathComponent("math/" + requestID(c, n, width) + ".json"))
                return try NativeMathLayout.decode(data, math: n.math!, context: c, width: width)
            })
            let layoutTime = ProcessInfo.processInfo.systemUptime - layoutStart
            plans.append(plan)
            try require(plan.regions.map(\.readingOrder) == plan.regions.map(\.readingOrder).sorted(), "AX logical order")
            for r in plan.regions where r.node.kind == .math {
                let selection = try plan.formulaSelection(nodeID: r.node.id, in: doc)
                try selection.validate(in: doc)
                try require(selection.fragments[0].exact == r.node.canonicalText, "whole formula display copy")
                try require(r.node.math!.mathML.contains("<"), "AX hierarchy")
                for frame in r.frames {
                    let hit = plan.hit(CGPoint(x: frame.midX, y: frame.midY))
                    try require(hit?.node.id == r.node.id, "native formula fragment hit")
                }
                if Set(r.frames.map { Int($0.minY) }).count > 1 { broken += 1 }
                try require(r.frames.allSatisfy { $0.maxX <= CGFloat(c.width) - 15 }, "inline fits")
            }
            let cells = plan.regions.filter { $0.node.kind == .cell }
            try require(cells.count == 9, "all cells handed to AX")
            let mass = cells.first { $0.node.canonicalText == "Mass" }!, ten = cells.first { $0.node.canonicalText == "10" }!
            try require(mass.frames[0].height > ten.frames[0].height * 1.9, "rowspan geometry")
            let merged = cells.first { $0.node.canonicalText == "Merged" }!
            try require(abs(merged.frames[0].width - (c.width - 32)) < 0.001, "colspan geometry")
            try require(cells.filter { $0.role == "columnHeader" }.count == 3, "header semantics")
            try require(plan.regions.contains { $0.node.kind == .caption && $0.node.canonicalText == oracle["figureCaption"] as! String }, "caption handoff")
            try require(plan.regions.contains { $0.node.kind == .equationNumber && !$0.node.canonicalText.isEmpty }, "number handoff")
            let bitmap = try bitmap(plan.size, dark: c.theme == .dark)
            let paintStart = ProcessInfo.processInfo.systemUptime
            NativeReaderObjectRenderer.draw(plan, in: bitmap)
            let paintTime = ProcessInfo.processInfo.systemUptime - paintStart
            let counts = pixels(bitmap, dark: c.theme == .dark)
            try require(counts.ink > 100 && counts.blue >= 1000, "native ink/blue area")
            let name = "\(Int(c.width))-\(Int(c.fontSize))-\(c.theme)-\(c.mode)"
            try savePNG(bitmap, root.appendingPathComponent(name + ".png"))
            matrix.append(["case": name, "contextKey": c.key, "inkPixels": counts.ink, "bluePixels": counts.blue,
                           "layoutMs": layoutTime * 1000, "paintMs": paintTime * 1000, "height": plan.size.height, "pageCount": plan.pageCount, "regions": plan.regions.count,
                           "diagnostics": plan.diagnostics, "scope": "native semantic pagination; not compiler page fidelity"])
        }
        try require(broken > 0, "native inline breaking exercised")
        // Independently authored geometry: translate(10,10) scale(2) maps
        // rect(3,6,12,6) -> (16,22,24,12), area 288. No golden PNG oracle.
        let vector = "<svg viewBox=\"0 0 100 80\"><g transform=\"translate(10,10)\"><g transform=\"scale(2)\"><rect x=\"3\" y=\"6\" width=\"12\" height=\"6\" fill=\"#2060c0\"/></g></g><g transform=\"rotate(90,70,50)\"><circle cx=\"70\" cy=\"50\" r=\"5\" fill=\"#c02020\"/></g></svg>"
        let scene = try NativeVectorScene.decode(Data(vector.utf8), dark: false)
        let ctx = try bitmap(CGSize(width: 100, height: 80), dark: false)
        scene.draw(in: ctx, rect: CGRect(x: 0, y: 0, width: 100, height: 80))
        let vc = pixels(ctx, dark: false)
        try require(vc.blue == (oracle["vector"] as! [String: Any])["blueArea"] as! Int, "independent transformed blue area")
        try require(vc.red >= 70 && vc.red <= 100, "rotated circle area")
        let transformed = scene.shapes[0].path.boundingBox.applying(scene.shapes[0].transform)
        let expected = ((oracle["vector"] as! [String: Any])["blueRect"] as! [Double])
        try require([transformed.minX, transformed.minY, transformed.width, transformed.height] == expected.map { CGFloat($0) }, "transform coordinates")
        try savePNG(ctx, root.appendingPathComponent("vector-oracle.png"))
        // Primitive/resource/geometry negatives reject atomically; no fallback.
        for svg in ["<svg viewBox=\"0 0 10 10\"><script/></svg>",
                    "<svg viewBox=\"0 0 10 10\"><use href=\"file:///private/a\"/></svg>",
                    "<svg viewBox=\"0 0 10 10\"><path d=\"M0 0A1 1 0 0 0 2 2\"/></svg>",
                    "<svg viewBox=\"0 0 10 10\"><rect width=\"1\" height=\"1\" fill=\"url(https://example.org)\"/></svg>",
                    "<svg viewBox=\"0 0 10 10\"><text>x</text></svg>",
                    "<svg viewBox=\"0 0 10 10\"><rect width=\"1\" height=\"1\" transform=\"skewX(20)\"/></svg>",
                    "<svg viewBox=\"0 0 10 10\"><g opacity=\"0.5\"><rect width=\"1\" height=\"1\"/></g></svg>",
                    "<svg viewBox=\"0 0 10 10\"><g transform=\"scale(100000000)\"><rect width=\"1\" height=\"1\" transform=\"scale(100000000)\"/></g></svg>",
                    "<svg viewBox=\"0 0 10 10\"><rect width=\"1\" height=\"1\" fill-opacity=\"2\"/></svg>",
                    "<!DOCTYPE svg><svg viewBox=\"0 0 10 10\"/>"] {
            try expectFailure("SVG", { _ = try NativeVectorScene.decode(Data(svg.utf8), dark: false) })
        }
        let first = contexts[0], firstPlan = plans[0]
        let noMath: NativeReaderPagedLayout.MathProvider = { _, _ in throw NativeObjectError.unsupported("test") }
        try await expectAsyncFailure("cancel", { _ = try await NativeReaderPagedLayout.layout(document: doc, context: first, assets: assets, math: noMath, cancelled: { true }) })
        var calls = 0
        try await expectAsyncFailure("cooperative mid-layout cancellation", {
            _ = try await NativeReaderPagedLayout.layout(document: doc, context: first, assets: assets, math: { n, w in try dummy(first, n, w) }, cancelled: { calls += 1; return calls > 10 })
        })
        let badFont = NativeObjectContext(identity: first.identity, snapshotGeneration: first.snapshotGeneration, generation: first.generation,
            width: first.width, fontSize: first.fontSize, fontName: "NA03MissingFont", theme: first.theme, mode: first.mode, pageHeight: first.pageHeight)
        try await expectAsyncFailure("unsupported font", { _ = try await NativeReaderPagedLayout.layout(document: doc, context: badFont, assets: assets, math: noMath) })
        // Typography owned by NA02 is rejected here rather than flattened.
        var styledJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(doc)) as! [String: Any]
        var styledBlocks = styledJSON["blocks"] as! [[String: Any]]
        styledBlocks[0]["kind"] = "strong"; styledBlocks[0].removeValue(forKey: "headingLevel")
        styledJSON["blocks"] = styledBlocks
        let styledDoc = try NativeReaderDocument.decode(JSONSerialization.data(withJSONObject: styledJSON))
        try await expectAsyncFailure("unhandled text style", {
            _ = try await NativeReaderPagedLayout.layout(document: styledDoc, context: first, assets: assets, math: noMath)
        })
        let store = NativeObjectPlanStore(maxEntries: 2)
        let invalid = NativeObjectContext(identity: first.identity, snapshotGeneration: first.snapshotGeneration, generation: first.generation,
            width: .nan, fontSize: first.fontSize, fontName: "system", theme: first.theme, mode: first.mode, pageHeight: first.pageHeight)
        _ = invalid.key
        try expectFailure("nonfinite context", { _ = try store.begin(invalid) })
        let oldTicket = try store.begin(first)
        let newTicket = try store.begin(contexts[1])
        try expectFailure("late helper", { try store.adopt(firstPlan, for: oldTicket) })
        try store.adopt(plans[1], for: newTicket)
        try require(store.accepted?.context == contexts[1], "late result preserved current")
        store.cancel()
        try expectFailure("cancelled helper", { try store.adopt(plans[1], for: newTicket) })
        for p in plans.prefix(4) { try store.adopt(p, for: store.begin(p.context)) }
        try require(store.cachedCount == 2 && store.cached(first) == nil, "bounded LRU")
        try require(store.cached(contexts[3]) != nil, "correct complete cache key")
        let tiny = NativeObjectPlanStore(maxCost: 1)
        try expectFailure("cost", { try tiny.adopt(firstPlan, for: tiny.begin(first)) })
        store.dispose()
        try expectFailure("disposed helper", { _ = try store.begin(first) })
        let n = doc.blocks.flatMap(\.orderedNodes).first { $0.kind == .math }!
        let id = requestID(first, n, first.width - 32)
        let data = try Data(contentsOf: root.appendingPathComponent("math/" + id + ".json"))
        try expectFailure("late helper decode", { _ = try NativeMathLayout.decode(data, math: n.math!, context: contexts[1], width: first.width - 32) })
        try expectFailure("width helper decode", { _ = try NativeMathLayout.decode(data, math: n.math!, context: first, width: 999) })
        if let asset = doc.assets.first {
            try expectFailure("digest", { _ = try NativeReaderObjectRenderer.verifiedAsset(asset, bytes: Data("wrong".utf8), dark: false) })
        }
        let config = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("worker-config.json"))) as! [String: String]
        let executionLog = ExecutionLog()
        let worker = NativeMathWorker(node: URL(fileURLWithPath: config["node"]!), helper: URL(fileURLWithPath: config["helper"]!), runtime: URL(fileURLWithPath: config["runtime"]!), record: { executionLog.append($0) })
        let calculated = try await worker.calculate(n.math!, context: first, width: first.width - 32)
        try require(calculated.inputHash == sha(n.math!.mathML), "production async helper actual runtime")
        let directPlan = try await NativeReaderPagedLayout.layout(document: doc, context: first, assets: assets,
            math: { node, width in try await worker.calculate(node.math!, context: first, width: width) })
        try require(directPlan.items.map(\.frame) == firstPlan.items.map(\.frame), "end-to-end production async layout")
        // These child scripts are explicitly fake failure adapters; the real
        // runtime success above and real late-output decode remain separate.
        let delay = root.appendingPathComponent("delay-helper.mjs")
        try "setTimeout(() => process.stdout.write('{}'), 5000);".write(to: delay, atomically: true, encoding: .utf8)
        let slow = NativeMathWorker(node: URL(fileURLWithPath: config["node"]!), helper: delay, runtime: URL(fileURLWithPath: config["runtime"]!), record: { executionLog.append($0) })
        let started = ProcessInfo.processInfo.systemUptime
        let pending = Task { try await slow.calculate(n.math!, context: first, width: first.width - 32) }
        try await Task.sleep(nanoseconds: 200000000); pending.cancel()
        do { _ = try await pending.value; throw NSError(domain: "cancel accepted", code: 3) }
        catch NativeObjectError.cancelled { }
        try require(ProcessInfo.processInfo.systemUptime - started < 2, "bounded subprocess cancellation")
        let deadline = NativeMathWorker(node: URL(fileURLWithPath: config["node"]!), helper: delay, runtime: URL(fileURLWithPath: config["runtime"]!), timeout: 0.1, record: { executionLog.append($0) })
        do { _ = try await deadline.calculate(n.math!, context: first, width: first.width - 32); throw NSError(domain: "timeout accepted", code: 3) }
        catch NativeObjectError.unsupported("math-helper-timeout") { }
        let flood = root.appendingPathComponent("flood-helper.mjs")
        try "process.stdout.write('x'.repeat(9*1024*1024));".write(to: flood, atomically: true, encoding: .utf8)
        let bounded = NativeMathWorker(node: URL(fileURLWithPath: config["node"]!), helper: flood, runtime: URL(fileURLWithPath: config["runtime"]!), record: { executionLog.append($0) })
        do { _ = try await bounded.calculate(n.math!, context: first, width: first.width - 32); throw NSError(domain: "flood accepted", code: 3) }
        catch NativeObjectError.budget { }
        let processRecords = try JSONSerialization.jsonObject(with: JSONEncoder().encode(executionLog.values))
        try write(processRecords, root.appendingPathComponent("native-worker-executions.json"))
        let result: [String: Any] = ["matrix": matrix, "inlineBrokenCases": broken, "vectorBlueArea": vc.blue, "negativeFailures": 0,
            "verified": ["native vector paths", "whole-formula display selection", "semantic AX handoff", "merged/header table", "native inline flow", "bounded cache/cancel/stale"],
            "unverified": ["GUI/VoiceOver", "macOS13 runtime", "verified Typst source copy", "print-page fidelity", "complete CeTZ/decorations", "offline product runtime delivery"]]
        print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self))
    }
}
