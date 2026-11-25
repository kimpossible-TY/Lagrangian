import AppKit
import CoreText
import CryptoKit
import ImageIO
import UniformTypeIdentifiers
import PDFKit

// Headless executable: no NSApplication, windows, account or live services.
private final class ExecutionLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries = [NativeMathExecution]()
    func append(_ value: NativeMathExecution) { lock.lock(); entries.append(value); lock.unlock() }
    var values: [NativeMathExecution] { lock.lock(); defer { lock.unlock() }; return entries }
}

private final class OriginalPreparationGate: @unchecked Sendable {
    let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
    private let lock = NSLock(); private var timedOutValue = false
    func progress(_ phase: NativeOriginalPreparationPhase) {
        if phase == .page(1) {
            entered.signal()
            if release.wait(timeout: .now() + 5) != .success { lock.lock(); timedOutValue = true; lock.unlock() }
        }
    }
    func waitUntilEntered() -> Bool { entered.wait(timeout: .now() + 5) == .success }
    var timedOut: Bool { lock.lock(); defer { lock.unlock() }; return timedOutValue }
}

@main struct ObjectsTests {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw NSError(domain: "NA03: " + message, code: 1) }
    }
    static func shaBytes(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func sha(_ value: String) -> String { SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined() }
    static func write(_ value: Any, _ url: URL) throws { try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]).write(to: url) }
    @discardableResult static func expectFailure(_ name: String, _ body: () throws -> Void) throws -> String {
        do { try body() } catch { return String(describing: error) }
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
    static func bitmap(_ size: CGSize, dark: Bool, opaque: Bool = true) throws -> CGContext {
        let w = Int(ceil(size.width)), h = Int(ceil(size.height))
        guard w > 0, h > 0, w * h < 16000000, let ctx = CGContext(data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: 4 * w, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw NativeObjectError.budget
        }
        if opaque {
            ctx.setFillColor(CGColor(gray: dark ? 0 : 1, alpha: 1)); ctx.fill(CGRect(origin: .zero, size: size))
        } else { ctx.clear(CGRect(origin: .zero, size: size)) }
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
    static func sample(_ ctx: CGContext, _ x: Int, _ y: Int) -> [Int] {
        let p = ctx.data!.assumingMemoryBound(to: UInt8.self), i = y * ctx.bytesPerRow + x * 4
        return (0..<3).map { Int(p[i + $0]) }
    }
    static func richChecks(_ scene: NativeVectorScene, name: String, oracle: [String: Any], dark: Bool) throws -> [String: Any] {
        let size = scene.intrinsicSize, ctx = try bitmap(size, dark: dark)
        scene.draw(in: ctx, rect: CGRect(origin: .zero, size: size))
        let counts = pixels(ctx, dark: dark)
        if let area = oracle["blueArea"] as? Int { try require(counts.blue == area, name + " exact blue area") }
        if let minimum = oracle["blueMinimum"] as? Int { try require(counts.blue >= minimum && counts.blue <= oracle["blueMaximum"] as! Int, name + " arc topology") }
        if name == "linear-gradient" || name == "gradient-inherit" {
            let a = sample(ctx, 5, 40), b = sample(ctx, 95, 40)
            try require(a[0] > a[2] + 150 && b[2] > b[0] + 150, "gradient endpoints")
        }
        if name == "radial-gradient" {
            let a = sample(ctx, 50, 40), b = sample(ctx, 95, 40)
            try require(a[0] > a[2] + 150 && b[2] > b[0] + 100, "radial gradient center/edge")
        }
        if name == "group-opacity" {
            let expected = dark ? [128, 0, 0] : oracle["pink"] as! [Int]
            for x in [15, 25, 35] {
                let p = sample(ctx, x, 15)
                try require(zip(p, expected).allSatisfy { abs($0 - $1) <= 3 }, "isolated group opacity including overlap")
            }
            var area = 0
            for y in 0..<80 { for x in 0..<100 {
                let p = sample(ctx, x, y)
                if p[0] > p[1] + 50 && p[0] > p[2] + 50 { area += 1 }
            } }
            try require(area == oracle["unionArea"] as! Int, "group union area")
        }
        if name.hasPrefix("raster-") || name == "inline-png" {
            let probes = [(3, 2, 0), (20, 2, 1), (3, 9, 2), (20, 9, 3)]
            for (x, y, color) in probes {
                let p = sample(ctx, x, y)
                switch color {
                case 0: try require(p[0] > 180 && p[1] < 90 && p[2] < 90, name + " top-left red")
                case 1: try require(p[1] > 180 && p[0] < 90 && p[2] < 90, name + " top-right green")
                case 2: try require(p[2] > 180 && p[0] < 90 && p[1] < 90, name + " bottom-left blue")
                default: try require(p[0] > 180 && p[1] > 180 && p[2] < 90, name + " bottom-right yellow")
                }
            }
        }
        var areas = [0, 0, 0, 0]
        if name.hasPrefix("raster-") || name == "inline-png" {
            for y in 0..<12 { for x in 0..<24 {
                let p = sample(ctx, x, y)
                if p[0] > p[1] + 80 && p[0] > p[2] + 80 { areas[0] += 1 }
                if p[1] > p[0] + 80 && p[1] > p[2] + 80 { areas[1] += 1 }
                if p[2] > p[0] + 80 && p[2] > p[1] + 80 { areas[2] += 1 }
                if min(p[0], p[1]) > p[2] + 80 && abs(p[0] - p[1]) < 80 { areas[3] += 1 }
            } }
            let tolerance = name == "raster-jpg" ? 12 : 0
            try require(areas.allSatisfy { abs($0 - 72) <= tolerance }, name + " independently authored quadrant areas")
        }
        return ["name": name, "theme": dark ? "dark" : "light", "blue": counts.blue, "ink": counts.ink, "quadrantAreas": areas, "decodedCost": scene.decodedCost]
    }
    @MainActor static func main() async throws {
        let mode = CommandLine.arguments[1], root = URL(fileURLWithPath: CommandLine.arguments[2])
        let oracle = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3]))) as! [String: Any]
        if mode == "symbol-overflow" {
            do { try symbolOverflow(root: root) }
            catch { fputs("symbol overflow oracle failed: \(error)\n", stderr); exit(1) }
            return
        }
        if mode == "pde-svg" {
            let cases = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("pde-svg-cases.json"))) as! [[String: Any]]
            var results = [[String: Any]]()
            for item in cases {
                let scene = try NativeVectorScene.decode(Data((item["svg"] as! String).utf8), dark: false)
                try require(scene.image != nil, "nested SVG and PNG use validated rich renderer")
                let ctx = try bitmap(CGSize(width: 100, height: 80), dark: false)
                scene.draw(in: ctx, rect: CGRect(x: 0, y: 0, width: 100, height: 80))
                let boxes = item["rects"] as! [[Int]]
                try savePNG(ctx, root.appendingPathComponent("pde-" + (item["name"] as! String) + ".png"))
                for y in 0..<80 { for x in 0..<100 {
                    let p = sample(ctx, x, y)
                    let blue = p[2] > p[0] + 20 && p[2] > p[1] + 20
                    let expected = boxes.contains { b in x >= b[0] && x < b[0] + b[2] && y >= b[1] && y < b[1] + b[3] }
                    try require(blue == expected, "PDE SVG independent pixel mask: " + (item["name"] as! String) + " at \(x),\(y): \(p)")
                } }
                results.append(["name": item["name"]!, "bluePixels": pixels(ctx, dark: false).blue])
            }
            let invalid = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("pde-svg-invalid.json"))) as! [String]
            for svg in invalid {
                try expectFailure("PDE SVG invalid") { _ = try NativeVectorScene.decode(Data(svg.utf8), dark: false) }
            }
            for css in ["width:20px;height:10px", "width:15pt;height:7.5pt", "width:1.25em;height:0.625em"] {
                let svg = "<svg style=\"\(css);overflow:visible\" viewBox=\"0 0 40 20\"><rect width=\"40\" height=\"20\"/></svg>"
                let scene = try NativeVectorScene.decode(Data(svg.utf8), dark: false)
                try require(scene.intrinsicSize == CGSize(width: 20, height: 10), "CSS viewport intrinsic geometry")
            }
            let alphaCases = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("pde-svg-alpha.json"))) as! [[String: Any]]
            for item in alphaCases {
                let scene = try NativeVectorScene.decode(Data((item["svg"] as! String).utf8), dark: false)
                let ctx = try bitmap(CGSize(width: 100, height: 80), dark: false, opaque: false)
                scene.draw(in: ctx, rect: CGRect(x: 0, y: 0, width: 100, height: 80))
                let rgba = item["rgba"] as! [Double]
                // Read uncomposited alpha directly: CoreSVG and CoreGraphics
                // use different RGB color spaces, which affect RGB-over-white
                // comparisons but cannot change this independent alpha oracle.
                let actual = sample(ctx, 20, 20)
                let alphaByte = Int(ctx.data!.assumingMemoryBound(to: UInt8.self)[20 * ctx.bytesPerRow + 20 * 4 + 3])
                let expectedAlpha = Int((rgba[3] * 255).rounded())
                try require(abs(alphaByte - expectedAlpha) <= 1,
                            "hex alpha native pixel: " + (item["name"] as! String) + " \(alphaByte) expected \(expectedAlpha)")
                let dominant = rgba[0] == 1 ? 0 : 2
                try require(actual[dominant] > actual[1] + 20 && actual[dominant] > actual[2 - dominant] + 20,
                            "hex alpha native paint override: " + (item["name"] as! String))
                if item["rich"] as? Bool == true {
                    try require(scene.image != nil, "hex alpha nested SVG uses native raster consumer")
                } else {
                    guard let shape = scene.shapes.last else { throw NSError(domain: "NA03 hex alpha native shape missing", code: 1) }
                    let alpha = (item["name"] as! String).hasPrefix("fill") ? shape.fill!.alpha : shape.stroke!.alpha
                    try require(abs(alpha - rgba[3]) < 1e-12, "hex alpha exact native geometry")
                }
            }
            for paint in ["fill", "stroke"] {
                for suffix in ["-direct", "-opaque"] {
                    try require(alphaCases.contains { ($0["name"] as? String)?.hasPrefix(paint + "-defs-use-") == true &&
                        ($0["name"] as? String)?.hasSuffix(suffix) == true }, "defs/use alpha pixel coverage")
                }
            }
            let embedded = Data((cases.first { ($0["name"] as? String) == "png-over-1mib" }!["svg"] as! String).utf8)
            try require(embedded.count > 1024 * 1024, "embedded SVG exceeds old 1 MiB limit")
            let embeddedLimit = 6 * 1024 * 1024
            var atLimit = embedded
            atLimit.append(Data(repeating: 32, count: embeddedLimit - embedded.count))
            let boundary = try NativeVectorScene.decode(atLimit, dark: false)
            try require(boundary.image != nil && boundary.decodedCost <= 16 * 1024 * 1024, "embedded byte boundary decodes within pixel cap")
            atLimit.append(32)
            try expectFailure("embedded encoded byte cap") { _ = try NativeVectorScene.decode(atLimit, dark: false) }
            let plain = "<svg viewBox=\"0 0 100 80\"><rect width=\"20\" height=\"10\"/></svg>"
            let plainBytes = Data(plain.utf8)
            _ = try NativeVectorScene.decode(plainBytes, dark: false, pixelBudget: plainBytes.count * 16)
            try expectFailure("plain SVG proportional byte budget") {
                _ = try NativeVectorScene.decode(plainBytes, dark: false, pixelBudget: plainBytes.count * 16 - 1)
            }
            try expectFailure("embedded caller pixel budget") {
                _ = try NativeVectorScene.decode(embedded, dark: false, pixelBudget: 10000)
            }
            for svg in [embedded, Data("<svg viewBox=\"0 0 100 80\"><g opacity=\"0.5\"><rect width=\"20\" height=\"10\"/></g></svg>".utf8)] {
                for budget in [16 * 1024 * 1024, Int.max] {
                    try expectFailure("decoded pixel hard cap") {
                        _ = try NativeVectorScene.decode(svg, dark: false, pixelBudget: budget, targetSize: CGSize(width: 1100, height: 1100))
                    }
                }
            }
            try write(["cases": results, "rejected": invalid.count, "alphaCases": alphaCases.count,
                       "byteAndPixelLimitsChecked": true], root.appendingPathComponent("pde-svg-results.json"))
            return
        }
        if mode == "raw-import" { try await rawImport(root: root, oracle: oracle); return }
        if mode == "original-pages" { try await originalPages(root: root, oracle: oracle); return }
        if mode == "input-refresh" { try await inputRefresh(root: root); return }
        if mode == "assets" {
            let source = root.appendingPathComponent("source")
            let ctx = try bitmap(CGSize(width: 24, height: 12), dark: false)
            // Author-defined pixel quadrants; no renderer output is used as input.
            let colors = [CGColor(red: 1, green: 0, blue: 0, alpha: 1), CGColor(red: 0, green: 1, blue: 0, alpha: 1),
                          CGColor(red: 0, green: 0, blue: 1, alpha: 1), CGColor(red: 1, green: 1, blue: 0, alpha: 1)]
            for i in 0..<4 { ctx.setFillColor(colors[i]); ctx.fill(CGRect(x: (i % 2) * 12, y: (i / 2) * 6, width: 12, height: 6)) }
            for (ext, type) in [("png", UTType.png.identifier), ("jpg", UTType.jpeg.identifier), ("gif", UTType.gif.identifier)] {
                guard let dest = CGImageDestinationCreateWithURL(source.appendingPathComponent("pattern." + ext) as CFURL, type as CFString, 1, nil) else { throw NativeObjectError.unsupported("test-raster-encoder") }
                CGImageDestinationAddImage(dest, ctx.makeImage()!, [kCGImageDestinationLossyCompressionQuality: 1] as CFDictionary)
                try require(CGImageDestinationFinalize(dest), "fixture image encode")
            }
            let animated = CGImageDestinationCreateWithURL(source.appendingPathComponent("animated.gif") as CFURL, UTType.gif.identifier as CFString, 2, nil)!
            for _ in 0..<2 { CGImageDestinationAddImage(animated, ctx.makeImage()!, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]] as CFDictionary) }
            try require(CGImageDestinationFinalize(animated), "animated control encode")
            return
        }
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
            for r in plan.regions where r.node.kind == .image {
                try require(plan.hit(CGPoint(x: r.frames[0].midX, y: r.frames[0].midY))?.node.id == r.node.id, "image semantic hit")
                try require(r.role == "image" && r.node.alt != nil, "image AX original node")
                let name = r.node.alt ?? ""
                func pixel(_ x: Int, _ y: Int) -> [Int] { sample(bitmap, Int(r.frames[0].minX) + x, Int(r.frames[0].minY) + y) }
                if ["internal-use", "clip", "arc", "symbol-glyph", "internal-href", "viewport-units"].contains(name) {
                    let point = name == "symbol-glyph" ? (11, 15) : name == "internal-href" ? (45, 15) : name == "arc" ? (20, 20) : (15, 15)
                    let p = pixel(point.0, point.1)
                    try require(p[2] > p[0] + 40 && p[2] > p[1] + 40, name + " at native matrix frame")
                }
                if name == "linear-gradient" || name == "gradient-inherit" {
                    let a = pixel(5, 40), b = pixel(95, 40)
                    try require(a[0] > a[2] + 150 && b[2] > b[0] + 150, "matrix gradient topology")
                }
                if name == "radial-gradient" {
                    let a = pixel(50, 40), b = pixel(95, 40)
                    try require(a[0] > a[2] + 150 && b[2] > b[0] + 100, "matrix radial topology")
                }
                if name == "group-opacity" {
                    let expected = c.theme == .dark ? [128, 0, 0] : [255, 128, 128]
                    try require(zip(pixel(25, 15), expected).allSatisfy { abs($0 - $1) <= 3 }, "matrix isolated opacity")
                }
                if name.hasPrefix("raster-") || name == "inline-png" {
                    let a = pixel(3, 2), b = pixel(20, 2), d = pixel(3, 9), e = pixel(20, 9)
                    try require(a[0] > 180 && a[1] < 90 && b[1] > 180 && b[0] < 90 && d[2] > 180 && d[0] < 90 && e[0] > 180 && e[1] > 180 && e[2] < 90, "matrix raster orientation/colors")
                }
                if name == "viewport-units" { try require(r.frames[0].width == 100 && r.frames[0].height == 80, "SVG point viewport distinct from user coordinates") }
                if r.node.alt == "inline-png" {
                    let following = plan.items.filter { $0.frame.minX >= r.frames[0].maxX && abs($0.frame.maxY - r.frames[0].maxY) < 8 }
                    try require(!following.isEmpty, "inline image stays in native text line")
                    // A red interior sample must be painted at the actual native
                    // layout frame; semantic-only or nonempty placeholders fail.
                    let p = sample(bitmap, Int(r.frames[0].minX + 3), Int(r.frames[0].minY + 2))
                    try require(p[0] > 180 && p[1] < 90, "inline image actual frame color")
                }
            }
            for r in plan.regions where [.strong, .emphasis, .link].contains(r.node.kind) {
                if r.node.kind == .link, let child = r.node.children.first,
                   let leaf = plan.regions.first(where: { $0.node.id == child.id }), let frame = leaf.frames.first {
                    try require(plan.linkTarget(at: CGPoint(x: frame.midX, y: frame.midY)) == r.node.link, "native semantic link target")
                }
                let textIDs = Set(r.node.orderedNodes.filter { $0.kind == .text }.map(\.id))
                for item in plan.items where textIDs.contains(item.nodeID) {
                    if case .text(let line) = item.paint {
                        for run in CTLineGetGlyphRuns(line) as! [CTRun] {
                            let attrs = CTRunGetAttributes(run) as! [String: Any], font = attrs[kCTFontAttributeName as String] as! CTFont
                            if r.node.kind == .strong { try require(CTFontGetSymbolicTraits(font).contains(.boldTrait), "table/caption bold trait") }
                            if r.node.kind == .emphasis { try require(CTFontGetSymbolicTraits(font).contains(.italicTrait), "table/caption italic trait") }
                            if r.node.kind == .link { try require((attrs[kCTUnderlineStyleAttributeName as String] as? NSNumber)?.intValue == 1, "native link style/span") }
                        }
                    }
                }
            }
            try require(counts.ink > 100 && counts.blue >= 1000, "native ink/blue area")
            let name = "\(Int(c.width))-\(Int(c.fontSize))-\(c.theme)-\(c.mode)"
            try savePNG(bitmap, root.appendingPathComponent(name + ".png"))
            matrix.append(["case": name, "contextKey": c.key, "inkPixels": counts.ink, "bluePixels": counts.blue,
                           "layoutMs": layoutTime * 1000, "paintMs": paintTime * 1000, "height": plan.size.height, "pageCount": plan.pageCount, "regions": plan.regions.count,
                           "diagnostics": plan.diagnostics, "scope": "native semantic pagination; not compiler page fidelity"])
        }
        try require(broken > 0, "native inline breaking exercised")
        var richResults = [[String: Any]]()
        let cases = oracle["richAssets"] as! [[String: Any]]
        for region in plans[0].regions where region.node.kind == .image {
            guard let name = region.node.alt, name == "inline-png" || name.hasPrefix("raster-") || cases.contains(where: { $0["name"] as? String == name }) else { continue }
            let id = region.node.assetID!, descriptor = doc.assets.first { $0.id == id }!
            for dark in [false, true] {
                let scene = try NativeReaderObjectRenderer.verifiedAsset(descriptor, bytes: assets[id]!, dark: dark)
                let expected = cases.first { $0["name"] as? String == name } ?? [:]
                richResults.append(try richChecks(scene, name: name, oracle: expected, dark: dark))
                let ctx = try bitmap(scene.intrinsicSize, dark: dark); scene.draw(in: ctx, rect: CGRect(origin: .zero, size: scene.intrinsicSize))
                try savePNG(ctx, root.appendingPathComponent(name + (dark ? "-dark" : "-light") + ".png"))
            }
        }
        try write(richResults, root.appendingPathComponent("rich-asset-results.json"))
        // This glyph oracle uses the compiler's original 74.506 x 30 user
        // coordinates, independently of its CSS em display viewport.
        let labeled = try NativeVectorScene.decode(Data(contentsOf: root.appendingPathComponent("raw-labeled.svg")),
                                                   dark: false, targetSize: CGSize(width: 74.506, height: 30))
        let labeledCtx = try bitmap(labeled.viewBox.size, dark: false)
        labeled.draw(in: labeledCtx, rect: CGRect(origin: .zero, size: labeled.viewBox.size))
        var black = 0
        for y in 4..<(labeledCtx.height - 4) { for x in 4..<(labeledCtx.width - 4) {
            if sample(labeledCtx, x, y).allSatisfy({ $0 < 50 }) { black += 1 }
        } }
        let labeledCounts = pixels(labeledCtx, dark: false), labeledOracle = oracle["labeledCetz"] as! [String: Any]
        try require(black >= labeledOracle["minimumBlackInk"] as! Int && black <= labeledOracle["maximumBlackInk"] as! Int, "actual compiler glyph label ink")
        try require(labeledCounts.blue >= labeledOracle["minimumBlueInk"] as! Int && labeledCounts.blue <= labeledOracle["maximumBlueInk"] as! Int, "actual compiler labeled blue shape")
        try savePNG(labeledCtx, root.appendingPathComponent("actual-compiler-labeled.png"))
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
                    "<svg viewBox=\"0 0 10 10\"><path d=\"M0 0A1 1 0 2 0 2 2\"/></svg>",
                    "<svg viewBox=\"0 0 10 10\"><rect width=\"1\" height=\"1\" fill=\"url(https://example.org)\"/></svg>",
                    "<svg viewBox=\"0 0 10 10\"><text>x</text></svg>",
                    "<svg viewBox=\"0 0 10 10\"><rect width=\"1\" height=\"1\" transform=\"skewX(20)\"/></svg>",
                    "<svg viewBox=\"0 0 10 10\"><g opacity=\"1.5\"><rect width=\"1\" height=\"1\"/></g></svg>",
                    "<svg viewBox=\"0 0 10 10\"><g transform=\"scale(100000000)\"><rect width=\"1\" height=\"1\" transform=\"scale(100000000)\"/></g></svg>",
                    "<svg viewBox=\"0 0 10 10\"><rect width=\"1\" height=\"1\" fill-opacity=\"2\"/></svg>",
                    "<!DOCTYPE svg><svg viewBox=\"0 0 10 10\"/>"] {
            try expectFailure("SVG", { _ = try NativeVectorScene.decode(Data(svg.utf8), dark: false) })
        }
        var invalidNamed: [(String, String)] = [
            ("external-href", "<use href=\"https://example.org/glyph\"/>"),
            ("entity-encoded-external", "<use href=\"&#104;ttps://example.org/glyph\"/>"),
            ("external-gradient", "<defs><linearGradient id=\"g\" href=\"file:///private/a\"/></defs><rect width=\"10\" height=\"10\" fill=\"url(#g)\"/>"),
            ("missing-internal", "<use href=\"#absent\"/>"),
            ("self-cycle", "<defs><g id=\"a\"><use href=\"#a\"/></g></defs><use href=\"#a\"/>"),
            ("indirect-cycle", "<defs><g id=\"a\"><use href=\"#b\"/></g><g id=\"b\"><use href=\"#a\"/></g></defs><use href=\"#a\"/>"),
            ("gradient-cycle", "<defs><linearGradient id=\"a\" href=\"#b\"/><linearGradient id=\"b\" href=\"#a\"/></defs><rect width=\"10\" height=\"10\" fill=\"url(#a)\"/>"),
            ("duplicate-id", "<defs><path id=\"a\" d=\"M0 0L1 1\"/><path id=\"a\" d=\"M0 0L1 1\"/></defs>"),
            ("event", "<rect width=\"10\" height=\"10\" onclick=\"alert(1)\"/>"),
            ("foreign-content", "<foreignObject><body/></foreignObject>"),
            ("font-fetch", "<text style=\"font-family:url(https://example.org/font)\">x</text>"),
            ("style-resource", "<rect width=\"10\" height=\"10\" style=\"fill:url(https://example.org/a)\"/>"),
            ("malformed-arc", "<path d=\"M0 0A1 1 0 0 0 2\"/>"),
            ("duplicate-attribute", "<rect width=\"10\" width=\"20\" height=\"10\"/>"),
            ("malformed-xml", "<g><path d=\"M0 0L1 1\"/></bad>"),
            ("nonfinite", "<g transform=\"scale(1e100)\"><rect width=\"1\" height=\"1\"/></g>")]
        var expansion = "<defs><path id=\"n0\" d=\"M0 0H1V1H0Z\"/>"
        for i in 1...20 { expansion += "<g id=\"n\(i)\"><use href=\"#n\(i-1)\"/><use href=\"#n\(i-1)\"/></g>" }
        expansion += "</defs><use href=\"#n20\"/>"; invalidNamed.append(("expansion-budget", expansion))
        invalidNamed.append(("gradient-stop-budget", "<defs><linearGradient id=\"g\">" + String(repeating: "<stop offset=\"0\" stop-color=\"#000000\"/>", count: 257) + "</linearGradient></defs><rect width=\"1\" height=\"1\" fill=\"url(#g)\"/>"))
        var negativeNames = [String](), negativeDiagnostics = [[String: String]]()
        for (name, body) in invalidNamed {
            let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 80\">" + body + "</svg>"
            let error = try expectFailure(name, { _ = try NativeVectorScene.decode(Data(svg.utf8), dark: false) })
            negativeNames.append(name); negativeDiagnostics.append(["name": name, "error": error, "inputSHA256": sha(svg)])
        }
        try expectFailure("pixel-budget", { _ = try NativeVectorScene.decode(Data("<svg viewBox=\"0 0 100 80\"><g opacity=\"0.5\"><rect width=\"100\" height=\"80\"/></g></svg>".utf8), dark: false, pixelBudget: 10000) })
        negativeNames.append("pixel-budget")
        try expectFailure("oversized-viewport", { _ = try NativeVectorScene.decode(Data("<svg viewBox=\"0 0 1000000 1000000\"><rect width=\"1\" height=\"1\"/></svg>".utf8), dark: false) })
        negativeNames.append("oversized-viewport")
        let png = try Data(contentsOf: root.appendingPathComponent("source/pattern.png")), digest = shaBytes(png)
        let wrongType = NativeReaderAsset(id: digest + ".jpg", sha256: digest, mime: "image/jpeg", byteCount: png.count)
        try expectFailure("raster-content-type", { _ = try NativeReaderObjectRenderer.verifiedAsset(wrongType, bytes: png, dark: false) })
        negativeNames.append("raster-content-type")
        let huge = try Data(contentsOf: root.appendingPathComponent("oversized.png")), hugeHash = shaBytes(huge)
        let hugeAsset = NativeReaderAsset(id: hugeHash + ".png", sha256: hugeHash, mime: "image/png", byteCount: huge.count)
        do { _ = try NativeReaderObjectRenderer.verifiedAsset(hugeAsset, bytes: huge, dark: false); throw NSError(domain: "huge raster accepted", code: 3) }
        catch NativeObjectError.budget { negativeNames.append("raster-decompressed-budget") }
        try expectFailure("raster-malformed", { _ = try NativeVectorScene.raster(Data(png.prefix(20)), mime: "image/png", pixelBudget: 16000000) })
        negativeNames.append("raster-malformed")
        let animatedBytes = try Data(contentsOf: root.appendingPathComponent("source/animated.gif"))
        do { _ = try NativeVectorScene.raster(animatedBytes, mime: "image/gif", pixelBudget: 16000000); throw NSError(domain: "animation silently flattened", code: 3) }
        catch NativeObjectError.unsupported("animated-image") { negativeNames.append("animated-image-no-flatten") }
        try expectFailure("asset-byte-limit", { _ = try NativeVectorScene.raster(Data(repeating: 0, count: 8 * 1024 * 1024 + 1), mime: "image/png", pixelBudget: 16000000) })
        negativeNames.append("asset-byte-limit")
        try write(negativeNames, root.appendingPathComponent("named-invalid-results.json"))
        try write(negativeDiagnostics, root.appendingPathComponent("invalid-svg-diagnostics.json"))
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
        // Native object styling retains the shared semantic spans; NA02 still owns
        // body interaction/AX. No styled text is flattened into plain glyphs.
        var styledJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(doc)) as! [String: Any]
        var styledBlocks = styledJSON["blocks"] as! [[String: Any]]
        styledBlocks[0]["kind"] = "strong"; styledBlocks[0].removeValue(forKey: "headingLevel")
        styledJSON["blocks"] = styledBlocks
        let styledDoc = try NativeReaderDocument.decode(JSONSerialization.data(withJSONObject: styledJSON))
        let styledPlan = try await NativeReaderPagedLayout.layout(document: styledDoc, context: first, assets: assets,
            math: { n, width in try dummy(first, n, width) })
        let headingTextID = styledDoc.blocks[0].children[0].id
        let boldLine = styledPlan.items.first { $0.nodeID == headingTextID }!
        if case .text(let line) = boldLine.paint {
            let runs = CTLineGetGlyphRuns(line) as! [CTRun]
            let attrs = CTRunGetAttributes(runs[0]) as! [String: Any]
            let font = attrs[kCTFontAttributeName as String] as! CTFont
            try require(CTFontGetSymbolicTraits(font).contains(.boldTrait), "strong label native trait")
        } else { throw NativeObjectError.invalidGeometry }
        let preservedStore = NativeObjectPlanStore()
        try preservedStore.adopt(firstPlan, for: preservedStore.begin(first))
        var corruptAssets = assets
        if let key = doc.assets.first?.id { var bytes = assets[key]!; bytes[0] ^= 1; corruptAssets[key] = bytes }
        let failureAssets = corruptAssets
        try await expectAsyncFailure("asset decode preserves accepted plan", {
            _ = try await NativeReaderPagedLayout.layout(document: doc, context: first, assets: failureAssets, math: { n, w in try dummy(first, n, w) })
        })
        try require(preservedStore.accepted?.context == firstPlan.context && preservedStore.accepted?.items.count == firstPlan.items.count, "previous accepted immutable plan retained")
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
        let result: [String: Any] = ["matrix": matrix, "inlineBrokenCases": broken, "vectorBlueArea": vc.blue, "negativeFailures": 0, "richAssetCases": richResults.count / 2, "labeledBlackInk": black, "labeledBlueInk": labeledCounts.blue,
            "verified": ["native vector paths", "whole-formula display selection", "semantic AX handoff", "merged/header table", "native inline flow", "bounded cache/cancel/stale"],
            "unverified": ["GUI/VoiceOver", "macOS13 runtime", "verified Typst source copy", "print-page fidelity", "complete CeTZ/decorations", "offline product runtime delivery"]]
        print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self))
    }
}


extension ObjectsTests {
    @MainActor static func originalPages(root: URL, oracle: [String: Any]) async throws {
        let folder = root.appendingPathComponent("original")
        let inputs = try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("inputs.json"))) as! [String: [String: Any]]
        let expected = oracle["originalPagesV3"] as! [String: Any]
        let base = try Data(contentsOf: folder.appendingPathComponent("base/document.pdf"))
        let three = try Data(contentsOf: folder.appendingPathComponent("three/document.pdf"))
        let viewID = UUID(), preparer = NativeOriginalPagePreparer(), store = NativeOriginalPageStore(viewID: UUID())
        // The test host supplies expectations; none are issued server publication.
        func binding(_ data: Data, name: String = "base", request: Int = 1, viewGeneration: Int = 0, sequence: Int = 1,
                     identity: NativeDocumentIdentity? = nil, fingerprint: String? = nil, rotation: Int = 0, count: Int = 2) -> NativeOriginalPageBinding {
            let metadata = inputs[name]!
            let target = identity ?? NativeDocumentIdentity(documentID: "objects-original", serviceID: "fixture-service",
                revision: metadata["htmlSHA256"] as! String, scope: .fixture)
            return NativeOriginalPageBinding(identity: target, inputFingerprint: fingerprint ?? metadata["capturedFingerprint"] as! String,
                snapshotGeneration: name == "three" ? 2 : 1, requestGeneration: request, viewID: viewID, viewGeneration: viewGeneration,
                publicationSequence: sequence, pdfSHA256: shaBytes(data), pages: (0..<count).map {
                    NativeOriginalPageGeometry(index: $0, mediaBox: CGRect(x: 0, y: 0, width: 320, height: 360), cropBox: CGRect(x: 0, y: 0, width: 320, height: 360), rotation: $0 == 0 ? rotation : 0)
                })
        }
        func modify(_ b: NativeOriginalPageBinding, _ fields: [String: Any]) throws -> NativeOriginalPageBinding {
            var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(b)) as! [String: Any]
            for (key, value) in fields { object[key] = value }
            return try JSONDecoder().decode(NativeOriginalPageBinding.self, from: JSONSerialization.data(withJSONObject: object))
        }
        let baseBinding = binding(base)
        let consumer = NativeOriginalPageStore(viewID: viewID)
        let ticket = try consumer.begin(expected: baseBinding)
        let first = try await preparer.prepare(NativeOriginalPageSupplement(binding: baseBinding, data: base), expected: baseBinding)
        try require(!first.preparationWasMainThread, "original heavy prepare off UI")
        try require(first.pages.count == expected["pageCount"] as! Int, "actual compiler PDF page count")
        let expectedTexts = expected["texts"] as! [String]
        var pageEvidence = [[String: Any]]()
        func metrics(_ image: CGImage) throws -> [String: Any] {
            let ctx = try bitmap(CGSize(width: image.width, height: image.height), dark: false)
            ctx.translateBy(x: 0, y: CGFloat(image.height)); ctx.scaleBy(x: 1, y: -1)
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            let data = ctx.data!.assumingMemoryBound(to: UInt8.self)
            var ink = 0, blueWeight: Double = 0, box = CGRect.null
            for y in 0..<ctx.height { for x in 0..<ctx.width {
                let i = y * ctx.bytesPerRow + x * 4
                let r = Double(data[i]), g = Double(data[i+1]), b = Double(data[i+2])
                if min(r, g, b) < 235 { ink += 1 }
                let a = (255-r)/223, c = (255-g)/159, d = (255-b)/63
                if a > 0.05 && abs(a-c) < 0.015 && abs(a-d) < 0.035 {
                    blueWeight += a; box = box.union(CGRect(x: x, y: y, width: 1, height: 1))
                }
            } }
            return ["ink": ink, "weightedBlueArea": blueWeight, "blueBounds": [box.minX, box.minY, box.width, box.height]]
        }
        for (index, page) in first.pages.enumerated() {
            try require(page.text == expectedTexts[index], "independent per-page display text/order")
            try require(page.offsets == NativeTextOffsets(page.text), "PDF Unicode scalar maps")
            try require(page.pdfCharacterCount == page.text.utf16.count, "fixture PDF index correspondence only")
            try require(page.characterBounds.count == page.pdfCharacterCount, "actual character box calls")
            let nonempty = page.characterBounds.filter { !$0.isNull && !$0.isEmpty }
            try require(nonempty.count > 16, "actual character bounds, not glyph-cluster proof")
            let result = try metrics(page.image)
            try require(result["ink"] as! Int > 100, "native original page ink")
            if index == 0 { try require(abs((result["weightedBlueArea"] as! Double) - (expected["blueRectangleArea"] as! Double)) < 5, "independent blue rectangle area") }
            let destination = CGImageDestinationCreateWithURL(folder.appendingPathComponent("page-\(index).png") as CFURL, UTType.png.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(destination, page.image, nil); try require(CGImageDestinationFinalize(destination), "PDF page PNG")
            pageEvidence.append(["page": index, "text": page.text, "utf16": page.text.utf16.count, "scalars": page.text.unicodeScalars.count,
                "pdfCharacters": page.pdfCharacterCount, "nonemptyBounds": nonempty.count, "bounds": page.characterBounds.map { [$0.minX, $0.minY, $0.width, $0.height] }, "paint": result])
        }
        try consumer.adopt(first, for: ticket)
        try require(consumer.paintAcknowledgment == nil, "adoption is not paint acknowledgment")
        let canvas = try bitmap(CGSize(width: 640, height: 800), dark: false)
        let ack = try consumer.paint(in: canvas)
        try require(ack.snapshotID == first.id && ack.pdfSHA256 == baseBinding.pdfSHA256, "actual native draw acknowledgment")
        try require(pixels(canvas, dark: false).ink > 100, "paint acknowledgment backed by actual ink")
        let office = try await first.access.search("office")[0]
        let officeView = try consumer.viewRect(forPageRect: office.pageBounds)
        var officeInk = 0
        for y in Int(floor(officeView.minY))..<Int(ceil(officeView.maxY)) { for x in Int(floor(officeView.minX))..<Int(ceil(officeView.maxX)) {
            if sample(canvas, x, y).allSatisfy({ $0 < 100 }) { officeInk += 1 }
        } }
        try require(officeInk > 5, "PDF point selection bounds align with actual native paint")
        let rectangleSelection = try await first.access.selection(page: 0, rectangle: office.pageBounds)
        try require(rectangleSelection.displayText == "office", "actual PDFKit rectangle selection")
        let all = try await first.access.search("Page")
        try require(all.map(\.pageIndex) == [0, 1], "PDFKit search page reading order")
        var searchEvidence = [[String: Any]]()
        for query in expected["queries"] as! [String] {
            let found = try await first.access.search(query)
            try require(!found.isEmpty && found.allSatisfy { $0.displayText == query }, "actual PDFKit Unicode search/selection")
            for selected in found {
                try require(!selected.pageBounds.isEmpty, "native selection bounds")
                let again = try await first.access.selection(page: selected.pageIndex, rangeUTF16: selected.rangeUTF16)
                try require(again == selected, "exact PDFKit range selection")
                searchEvidence.append(["query": query, "page": selected.pageIndex, "range": [selected.rangeUTF16.lowerBound, selected.rangeUTF16.upperBound], "text": selected.displayText])
            }
        }
        let unicode = try await first.access.search("👩‍👩‍👧‍👦")[0]
        let privateBoard = NSPasteboard(name: NSPasteboard.Name("NA03-original-pages-" + UUID().uuidString))
        try require(unicode.copyDisplayText(to: privateBoard) && privateBoard.string(forType: .string) == "👩‍👩‍👧‍👦", "private native pasteboard display copy")
        privateBoard.clearContents()
        var negatives = [String]()
        func reject(_ name: String, _ operation: () async throws -> Void) async throws {
            do { try await operation() } catch { negatives.append(name); return }
            throw NSError(domain: "original PDF negative accepted: " + name, code: 1)
        }
        try expectFailure("PDF source authority unavailable", { _ = try unicode.verifiedSourceAnchor() })
        negatives.append("no-verified-source-anchor")
        try await reject("surrogate-boundary", { _ = try await first.access.selection(page: 0, rangeUTF16: unicode.rangeUTF16.lowerBound..<(unicode.rangeUTF16.lowerBound+1)) })
        try await reject("search-budget", { _ = try await first.access.search("Page", maximum: 1) })
        let rawBinding = try JSONSerialization.jsonObject(with: JSONEncoder().encode(baseBinding)) as! [String: Any]
        for key in ["serviceID", "documentID", "revision"] {
            var identity = rawBinding["identity"] as! [String: Any]; identity[key] = "wrong"
            let wrong = try modify(baseBinding, ["identity": identity])
            try await reject("wrong-" + key, { _ = try await preparer.prepare(NativeOriginalPageSupplement(binding: wrong, data: base), expected: baseBinding) })
        }
        for (key, value) in [("inputFingerprint", String(repeating: "f", count: 64)), ("pdfSHA256", String(repeating: "e", count: 64)), ("viewID", UUID().uuidString)] {
            let wrong = try modify(baseBinding, [key: value])
            try await reject("wrong-" + key, { _ = try await preparer.prepare(NativeOriginalPageSupplement(binding: wrong, data: base), expected: baseBinding) })
        }
        for key in ["snapshotGeneration", "requestGeneration", "viewGeneration"] {
            let wrong = try modify(baseBinding, [key: 99])
            try await reject("wrong-" + key, { _ = try await preparer.prepare(NativeOriginalPageSupplement(binding: wrong, data: base), expected: baseBinding) })
        }
        let digestMismatch = try modify(baseBinding, ["pdfSHA256": String(repeating: "a", count: 64)])
        try await reject("actual-byte-hash", { _ = try await preparer.prepare(NativeOriginalPageSupplement(binding: digestMismatch, data: base), expected: digestMismatch) })
        let wrongGeometry = NativeOriginalPageGeometry(index: 0, mediaBox: baseBinding.pages[0].mediaBox, cropBox: CGRect(x: 0, y: 0, width: 319, height: 360), rotation: 0)
        let wrongBoxes = try modify(baseBinding, ["pages": try JSONSerialization.jsonObject(with: JSONEncoder().encode([wrongGeometry, baseBinding.pages[1]]))])
        try await reject("actual-point-geometry", { _ = try await preparer.prepare(NativeOriginalPageSupplement(binding: wrongBoxes, data: base), expected: wrongBoxes) })
        let order = try modify(baseBinding, ["pages": (rawBinding["pages"] as! [Any]).reversed().map { $0 }])
        try await reject("page-order", { _ = try await preparer.prepare(NativeOriginalPageSupplement(binding: order, data: base), expected: order) })
        let countWrong = binding(base, count: 1)
        try await reject("page-count", { _ = try await preparer.prepare(NativeOriginalPageSupplement(binding: countWrong, data: base), expected: countWrong) })
        var limit = NativeOriginalPageLimits(); limit.bytes = 1
        let byteLimit = limit
        try await reject("byte-budget", { _ = try await preparer.prepare(NativeOriginalPageSupplement(binding: baseBinding, data: base), expected: baseBinding, limits: byteLimit) })
        limit = NativeOriginalPageLimits(); limit.pixels = 1; let pixelLimit = limit
        try await reject("pixel-budget", { _ = try await preparer.prepare(NativeOriginalPageSupplement(binding: baseBinding, data: base), expected: baseBinding, limits: pixelLimit) })
        limit = NativeOriginalPageLimits(); limit.characters = 1; let textLimit = limit
        try await reject("text-budget", { _ = try await preparer.prepare(NativeOriginalPageSupplement(binding: baseBinding, data: base), expected: baseBinding, limits: textLimit) })
        limit = NativeOriginalPageLimits(); limit.graphObjects = 1; let graphLimit = limit
        try await reject("graph-budget", { _ = try await preparer.prepare(NativeOriginalPageSupplement(binding: baseBinding, data: base), expected: baseBinding, limits: graphLimit) })
        let truncated = Data(base.dropLast(32)), truncatedBinding = binding(truncated)
        try await reject("truncated-PDF", { _ = try await preparer.prepare(NativeOriginalPageSupplement(binding: truncatedBinding, data: truncated), expected: truncatedBinding) })
        let encryptedDocument = PDFDocument(data: base)!
        let encrypted = encryptedDocument.dataRepresentation(options: [PDFDocumentWriteOption.ownerPasswordOption: "fixture-owner", PDFDocumentWriteOption.userPasswordOption: "fixture-user"])!
        try encrypted.write(to: folder.appendingPathComponent("encrypted-control.pdf"))
        let encryptedBinding = binding(encrypted)
        try await reject("encrypted-PDF", { _ = try await preparer.prepare(NativeOriginalPageSupplement(binding: encryptedBinding, data: encrypted), expected: encryptedBinding) })
        for name in ["js", "launch", "url", "remote", "form", "unit"] {
            let data = try Data(contentsOf: folder.appendingPathComponent(name + ".pdf")), b = binding(data, count: 1)
            try await reject("active-" + name, { _ = try await preparer.prepare(NativeOriginalPageSupplement(binding: b, data: data), expected: b) })
        }
        let annotationDocument = PDFDocument(data: base)!
        let annotation = PDFAnnotation(bounds: CGRect(x: 20, y: 20, width: 30, height: 20), forType: .link, withProperties: nil)
        annotation.action = PDFActionURL(url: URL(string: "https://example.invalid/never")!)
        annotationDocument.page(at: 0)!.addAnnotation(annotation)
        let actionData = annotationDocument.dataRepresentation()!, actionBinding = binding(actionData)
        try actionData.write(to: folder.appendingPathComponent("annotation-url-control.pdf"))
        try await reject("annotation-URL-action", { _ = try await preparer.prepare(NativeOriginalPageSupplement(binding: actionBinding, data: actionData), expected: actionBinding) })
        try require(consumer.accepted?.id == first.id, "all preparation failures preserve accepted PDF")
        let drift = try Data(contentsOf: folder.appendingPathComponent("drift/document.pdf"))
        let driftSupplied = binding(drift, name: "drift", fingerprint: inputs["drift"]!["finalFingerprint"] as? String)
        let driftExpected = binding(drift, name: "drift")
        try await reject("actual-HTML-PDF-input-drift", { _ = try await preparer.prepare(NativeOriginalPageSupplement(binding: driftSupplied, data: drift), expected: driftExpected) })
        let gate = OriginalPreparationGate()
        let pending = Task { try await preparer.prepare(NativeOriginalPageSupplement(binding: baseBinding, data: base), expected: baseBinding, progress: { gate.progress($0) }) }
        let entered = await Task.detached { gate.waitUntilEntered() }.value
        try require(entered, "actual PDF prepare reached second-page barrier")
        pending.cancel(); gate.release.signal()
        try await reject("mid-prepare-cancel", { _ = try await pending.value })
        try require(!gate.timedOut && consumer.accepted?.id == first.id, "cancelled work cannot replace accepted PDF")
        let secondBinding = binding(base, request: 2, sequence: 2)
        let lateTicket = try consumer.begin(expected: secondBinding)
        let second = try await preparer.prepare(NativeOriginalPageSupplement(binding: secondBinding, data: base), expected: secondBinding)
        consumer.cancel()
        try expectFailure("late-cancelled-publication", { try consumer.adopt(second, for: lateTicket) }); negatives.append("late-cancelled-publication")
        let heldBinding = binding(base, request: 3, sequence: 2)
        let heldTicket = try consumer.begin(expected: heldBinding)
        let held = try await preparer.prepare(NativeOriginalPageSupplement(binding: heldBinding, data: base), expected: heldBinding)
        let selected = try await first.access.search("한글")[0], selectionTicket = UUID()
        try consumer.hold(selected, ticket: selectionTicket)
        try expectFailure("held-selection-adoption", { try consumer.adopt(held, for: heldTicket) }); negatives.append("held-selection-adoption")
        consumer.release(ticket: UUID())
        try expectFailure("old-selection-ticket", { try consumer.resize(width: 640) }); negatives.append("old-selection-ticket")
        consumer.release(ticket: selectionTicket); try consumer.adopt(held, for: heldTicket)
        let oldSnapshotBinding = try modify(binding(base, request: 4, sequence: 3), ["snapshotGeneration": 0])
        let oldSnapshotTicket = try consumer.begin(expected: oldSnapshotBinding)
        let oldSnapshot = try await preparer.prepare(NativeOriginalPageSupplement(binding: oldSnapshotBinding, data: base), expected: oldSnapshotBinding)
        try expectFailure("snapshot-generation-regression", { try consumer.adopt(oldSnapshot, for: oldSnapshotTicket) }); negatives.append("snapshot-generation-regression")
        let sameRevisionInput = binding(base, request: 5, sequence: 3, fingerprint: String(repeating: "b", count: 64))
        let wrongInputTicket = try consumer.begin(expected: sameRevisionInput)
        let wrongInputPages = try await preparer.prepare(NativeOriginalPageSupplement(binding: sameRevisionInput, data: base), expected: sameRevisionInput)
        try expectFailure("same-snapshot-different-input", { try consumer.adopt(wrongInputPages, for: wrongInputTicket) }); negatives.append("same-snapshot-different-input")
        try consumer.resize(width: 640); try require(consumer.displayedScale == 2, "native fit-width scale")
        let renderTicket = try consumer.beginRender()
        let highResolution = try await held.access.render(page: renderTicket.pageIndex, scale: renderTicket.rasterScale)
        try require(highResolution.image.width == 640 && highResolution.image.height == 720, "actual PDFKit scale rerender")
        let highMetrics = try metrics(highResolution.image)
        try require(abs(highMetrics["weightedBlueArea"] as! Double - 4 * 1152) < 12, "scale rerender independent ink area")
        try consumer.adoptRender(highResolution, for: renderTicket)
        try require(consumer.paintAcknowledgment == nil, "rerender adoption still not paint ack")
        let highAck = try consumer.paint(in: canvas)
        try require(highAck.scale == 2 && highAck.rasterScale == 2, "paint uses current native high-resolution render")
        try await reject("rerender-pixel-budget", { _ = try await held.access.render(page: 0, scale: 8, maximumPixels: 10) })
        let lateRenderTicket = try consumer.beginRender()
        let lateRender = try await held.access.render(page: 0, scale: lateRenderTicket.rasterScale)
        try consumer.jump(to: 1);
        try expectFailure("late-scale-page-render", { try consumer.adoptRender(lateRender, for: lateRenderTicket) }); negatives.append("late-scale-page-render")
        try require(consumer.pageIndex == 1, "native page jump")
        let needle = try await held.access.search("needle")[0]
        let viewRect = try consumer.viewRect(forPageRect: needle.pageBounds), back = try consumer.pageRect(forViewRect: viewRect)
        try require(abs(back.minX - needle.pageBounds.minX) < 0.0001 && abs(back.minY - needle.pageBounds.minY) < 0.0001, "native PDF point/view coordinate roundtrip")
        try consumer.setScale(1.5); try consumer.resize(width: 960); try require(consumer.displayedScale == 1.5, "fixed scale survives resize")
        try consumer.setScale(nil); try require(consumer.displayedScale == 3, "fit mode restored")
        let beforeResize = binding(base, request: 6, viewGeneration: consumer.viewGeneration, sequence: 3)
        let resizeTicket = try consumer.begin(expected: beforeResize)
        let resizeResult = try await preparer.prepare(NativeOriginalPageSupplement(binding: beforeResize, data: base), expected: beforeResize)
        try consumer.resize(width: 480)
        try expectFailure("late-resize-result", { try consumer.adopt(resizeResult, for: resizeTicket) }); negatives.append("late-resize-result")
        let threeBinding = binding(three, name: "three", request: 7, viewGeneration: consumer.viewGeneration, sequence: 3, count: 3)
        let threeTicket = try consumer.begin(expected: threeBinding)
        let replacement = try await preparer.prepare(NativeOriginalPageSupplement(binding: threeBinding, data: three), expected: threeBinding)
        try require(replacement.pages[2].text == expected["thirdPageText"] as! String, "independent replacement page text")
        try consumer.adopt(replacement, for: threeTicket)
        try require(consumer.accepted?.pages.count == 3 && consumer.paintAcknowledgment == nil, "full replacement page-count change, no false paint ack")
        try consumer.jump(to: 2)
        let thirdAck = try consumer.paint(in: canvas)
        try require(thirdAck.pdfSHA256 == threeBinding.pdfSHA256 && thirdAck.pageIndex == 2, "replacement actual paint acknowledgment")
        try expectFailure("stale-selection-result", { try consumer.hold(selected, ticket: UUID()) }); negatives.append("stale-selection-result")
        try expectFailure("page-jump-bounds", { try consumer.jump(to: 3) }); negatives.append("page-jump-bounds")
        try expectFailure("unimplemented-diff-v1", { try consumer.applyVectorDelta(Data("diff-v1".utf8)) }); negatives.append("unimplemented-diff-v1")
        consumer.reset(); try require(consumer.accepted == nil && consumer.pageIndex == 0, "explicit reset")
        try expectFailure("reset-paint", { _ = try consumer.paint(in: canvas) }); negatives.append("reset-paint")
        let replayBinding = binding(three, name: "three", request: 8, viewGeneration: consumer.viewGeneration, sequence: 3, count: 3)
        let replayTicket = try consumer.begin(expected: replayBinding)
        let replay = try await preparer.prepare(NativeOriginalPageSupplement(binding: replayBinding, data: three), expected: replayBinding)
        try expectFailure("ordered-publication-replay-after-reset", { try consumer.adopt(replay, for: replayTicket) }); negatives.append("ordered-publication-replay-after-reset")
        let rotatedDocument = PDFDocument(data: base)!; rotatedDocument.page(at: 0)!.rotation = 90
        let rotated = rotatedDocument.dataRepresentation()!; try rotated.write(to: folder.appendingPathComponent("rotated-control.pdf"))
        let rotatedBinding = binding(rotated, rotation: 90)
        let rotatedPages = try await preparer.prepare(NativeOriginalPageSupplement(binding: rotatedBinding, data: rotated), expected: rotatedBinding)
        try require(rotatedPages.pages[0].image.width == 360 && rotatedPages.pages[0].image.height == 320, "actual rotated PDF aspect/point geometry")
        let rotatedConsumer = NativeOriginalPageStore(viewID: viewID)
        try rotatedConsumer.adopt(rotatedPages, for: rotatedConsumer.begin(expected: rotatedBinding))
        let rotatedCanvas = try bitmap(CGSize(width: 640, height: 800), dark: false)
        _ = try rotatedConsumer.paint(in: rotatedCanvas)
        let rotatedOffice = try await rotatedPages.access.search("office")[0]
        let rotatedViewBounds = try rotatedConsumer.viewRect(forPageRect: rotatedOffice.pageBounds)
        var rotatedOfficeInk = 0
        for y in Int(floor(rotatedViewBounds.minY))..<Int(ceil(rotatedViewBounds.maxY)) { for x in Int(floor(rotatedViewBounds.minX))..<Int(ceil(rotatedViewBounds.maxX)) {
            if sample(rotatedCanvas, x, y).allSatisfy({ $0 < 150 }) { rotatedOfficeInk += 1 }
        } }
        try require(rotatedOfficeInk > 5, "rotated PDF character geometry aligns with actual paint")
        let rotatedDestination = CGImageDestinationCreateWithURL(folder.appendingPathComponent("rotated-native.png") as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(rotatedDestination, rotatedPages.pages[0].image, nil)
        try require(CGImageDestinationFinalize(rotatedDestination), "rotated PDF PNG")
        let rotatedMetrics = try metrics(rotatedPages.pages[0].image)
        try require(abs(rotatedMetrics["weightedBlueArea"] as! Double - 1152) < 5, "rotated PDF original ink area")
        let restarted = NativeDocumentIdentity(documentID: "objects-original", serviceID: "fixture-new-incarnation", revision: threeBinding.identity.revision, scope: .fixture)
        let restartBinding = binding(three, name: "three", request: 9, viewGeneration: consumer.viewGeneration, sequence: 0, identity: restarted, count: 3)
        let restartTicket = try consumer.begin(expected: restartBinding)
        let restart = try await preparer.prepare(NativeOriginalPageSupplement(binding: restartBinding, data: three), expected: restartBinding)
        try consumer.adopt(restart, for: restartTicket)
        consumer.dispose()
        try expectFailure("disposed-publication", { _ = try consumer.begin(expected: restartBinding) }); negatives.append("disposed-publication")
        try expectFailure("cross-view-binding", { _ = try store.begin(expected: baseBinding) }); negatives.append("cross-view-binding")
        try write(negatives, folder.appendingPathComponent("negative-results.json"))
        try write(searchEvidence, folder.appendingPathComponent("selection-search-results.json"))
        try write(pageEvidence, folder.appendingPathComponent("page-results.json"))
        try JSONEncoder().encode(baseBinding).write(to: folder.appendingPathComponent("expected-binding.json"))
        let result: [String: Any] = ["pageCount": first.pages.count, "replacementPageCount": replacement.pages.count,
            "negativeCases": negatives.count, "preparationWasMainThread": first.preparationWasMainThread, "painted": true,
            "scaledRender": highMetrics, "scaledPixelSize": [highResolution.image.width, highResolution.image.height],
            "paintAcknowledgment": ["viewID": ack.viewID.uuidString, "viewGeneration": ack.viewGeneration, "page": ack.pageIndex, "scale": ack.scale, "rasterScale": ack.rasterScale, "pdfSHA256": ack.pdfSHA256],
            "scope": "fixture-binding; PDFKit character boxes/UTF16 verified here, not glyph clusters, source anchors, backend accepted publication, GUI/VO or diff-v1"]
        print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self))
    }
}

extension ObjectsTests {
    @MainActor static func inputRefresh(root: URL) async throws {
        let folder = root.appendingPathComponent("refresh")
        let inputs = try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("inputs.json"))) as! [String: [String: Any]]
        let before = inputs["before"]!, after = inputs["after"]!
        try require(before["revision"] as! String == after["revision"] as! String, "actual equal HTML revision")
        try require(before["inputFingerprint"] as! String != after["inputFingerprint"] as! String, "actual saved input changed")
        let oldData = try Data(contentsOf: folder.appendingPathComponent("before.pdf"))
        let newData = try Data(contentsOf: folder.appendingPathComponent("after.pdf"))
        let view = UUID(), store = NativeOriginalPageStore(viewID: UUID()), preparer = NativeOriginalPagePreparer()
        let consumer = NativeOriginalPageStore(viewID: view)
        let identity = NativeDocumentIdentity(documentID: "saved-input-refresh", serviceID: "fixture-service",
            revision: before["revision"] as! String, scope: .fixture)
        func binding(_ data: Data, fingerprint: String, snapshot: Int, request: Int, sequence: Int, epoch: Int = 0) -> NativeOriginalPageBinding {
            NativeOriginalPageBinding(identity: identity, inputFingerprint: fingerprint, snapshotGeneration: snapshot,
                requestGeneration: request, viewID: view, viewGeneration: epoch, publicationSequence: sequence,
                pdfSHA256: shaBytes(data), pages: [NativeOriginalPageGeometry(index: 0,
                    mediaBox: CGRect(x: 0, y: 0, width: 320, height: 360), cropBox: CGRect(x: 0, y: 0, width: 320, height: 360), rotation: 0)])
        }
        let oldFingerprint = before["inputFingerprint"] as! String, newFingerprint = after["inputFingerprint"] as! String
        let original = binding(oldData, fingerprint: oldFingerprint, snapshot: 1, request: 1, sequence: 1)
        let originalTicket = try consumer.begin(expected: original)
        let old = try await preparer.prepare(NativeOriginalPageSupplement(binding: original, data: oldData), expected: original)
        try consumer.adopt(old, for: originalTicket)
        let fresh = binding(newData, fingerprint: newFingerprint, snapshot: 2, request: 2, sequence: 2)
        let freshTicket = try consumer.begin(expected: fresh)
        let candidate = try await preparer.prepare(NativeOriginalPageSupplement(binding: fresh, data: newData), expected: fresh)
        try require(old.pages[0].text == candidate.pages[0].text && candidate.pages[0].text.contains("Stable input refresh office 한글."), "same native PDF display text")
        // PAGED-PM-01 positive: equal content revision does not imply equal input.
        try consumer.adopt(candidate, for: freshTicket)
        try require(consumer.accepted?.id == candidate.id && consumer.accepted?.binding == fresh, "fresh saved input must adopt")
        var negatives = [String](), request = 2
        func rejected(_ name: String, _ operation: () async throws -> Void) async throws {
            do { try await operation() } catch let error as NativeOriginalPageError {
                negatives.append(name)
                try require(consumer.accepted?.id == candidate.id, "rejection preserves fresh accepted pages: " + name)
                if name == "same-snapshot-input-contamination" { try require(error == .binding, "same snapshot binds one input") }
                return
            }
            throw NSError(domain: "input refresh negative accepted: " + name, code: 1)
        }
        func rejectBinding(_ name: String, snapshot: Int, sequence: Int) async throws {
            request += 1
            let changed = binding(newData, fingerprint: oldFingerprint, snapshot: snapshot, request: request, sequence: sequence)
            let ticket = try consumer.begin(expected: changed)
            let result = try await preparer.prepare(NativeOriginalPageSupplement(binding: changed, data: newData), expected: changed)
            try await rejected(name, { try consumer.adopt(result, for: ticket) })
        }
        try await rejectBinding("same-snapshot-input-contamination", snapshot: 2, sequence: 3)
        try await rejectBinding("old-snapshot-new-publication", snapshot: 1, sequence: 3)
        try await rejectBinding("new-snapshot-same-publication", snapshot: 3, sequence: 2)
        try await rejectBinding("new-snapshot-old-publication", snapshot: 3, sequence: 1)
        try await rejected("response-differs-from-host-expected", {
            _ = try await preparer.prepare(NativeOriginalPageSupplement(binding: original, data: oldData), expected: fresh)
        })
        try await rejected("different-view", { _ = try store.begin(expected: fresh) })
        try await rejected("old-request-callback", { try consumer.adopt(old, for: originalTicket) })
        let held = try await candidate.access.search("office")[0], heldTicket = UUID()
        try consumer.hold(held, ticket: heldTicket)
        request += 1
        let next = binding(newData, fingerprint: newFingerprint, snapshot: 3, request: request, sequence: 3)
        let nextTicket = try consumer.begin(expected: next)
        let nextPages = try await preparer.prepare(NativeOriginalPageSupplement(binding: next, data: newData), expected: next)
        try await rejected("held-selection", { try consumer.adopt(nextPages, for: nextTicket) })
        consumer.release(ticket: UUID())
        try await rejected("old-release-does-not-release-new-selection", { try consumer.adopt(nextPages, for: nextTicket) })
        consumer.release(ticket: heldTicket)
        try consumer.adopt(nextPages, for: nextTicket)
        // Exercise beyond the bounded32-entry ledger; ordering still rejects old
        // publications after reset even when their snapshot binding is evicted.
        for generation in 4...36 {
            request += 1
            let b = binding(newData, fingerprint: generation % 2 == 0 ? oldFingerprint : newFingerprint,
                snapshot: generation, request: request, sequence: generation)
            let ticket = try consumer.begin(expected: b)
            let pages = try await preparer.prepare(NativeOriginalPageSupplement(binding: b, data: newData), expected: b)
            try consumer.adopt(pages, for: ticket)
        }
        consumer.reset(); request += 1
        let replay = binding(newData, fingerprint: oldFingerprint, snapshot: 1, request: request, sequence: 1, epoch: consumer.viewGeneration)
        let replayTicket = try consumer.begin(expected: replay)
        let replayPages = try await preparer.prepare(NativeOriginalPageSupplement(binding: replay, data: newData), expected: replay)
        try expectFailure("reset-replay-after-ledger-eviction", { try consumer.adopt(replayPages, for: replayTicket) })
        negatives.append("reset-replay-after-ledger-eviction")
        try require(consumer.accepted == nil, "reset replay keeps pages empty")
        let result: [String: Any] = ["freshInputAdopted": true, "sameHTMLRevision": identity.revision,
            "negativeCases": negatives, "adoptedSnapshots": 36, "scope": "fixture expected bindings; no backend accepted-publication or source authority"]
        print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self))
    }
}

extension ObjectsTests {
    @MainActor static func rawImport(root: URL, oracle: [String: Any]) async throws {
        let raw = try Data(contentsOf: root.appendingPathComponent("raw-native.json"))
        let document = try NativeReaderDocument.decode(raw)
        let roundtrip = try NativeReaderDocument.decode(JSONEncoder().encode(document))
        try require(roundtrip == document, "raw Codable exact tree")
        let assets = try Dictionary(uniqueKeysWithValues: document.assets.map { ($0.id, try Data(contentsOf: root.appendingPathComponent("raw-assets/" + $0.id))) })
        let config = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("worker-config.json"))) as! [String: String]
        let executions = ExecutionLog()
        let worker = NativeMathWorker(node: URL(fileURLWithPath: config["node"]!), helper: URL(fileURLWithPath: config["helper"]!), runtime: URL(fileURLWithPath: config["runtime"]!), record: { executions.append($0) })
        let context = NativeObjectContext(identity: document.identity, snapshotGeneration: document.generation, generation: 1,
            width: 640, fontSize: 20, fontName: "system", theme: .light, mode: .reflow, pageHeight: 800)
        let plan = try await NativeReaderPagedLayout.layout(document: document, context: context, assets: assets,
            math: { n, w in try await worker.calculate(n.math!, context: context, width: w) })
        let canvas = try bitmap(plan.size, dark: false)
        NativeReaderObjectRenderer.draw(plan, in: canvas)
        try savePNG(canvas, root.appendingPathComponent("raw-native-paint.png"))
        let descriptors = Dictionary(uniqueKeysWithValues: document.assets.map { ($0.id, $0) })
        let images = plan.regions.filter { $0.node.kind == .image }
        let rasters = images.filter { descriptors[$0.node.assetID!]!.mime != "image/svg+xml" }
        let expected = oracle["rawImageLayouts"] as! [[String: Any]]
        try require(rasters.count == expected.count, "all actual compiler rasters")
        var frames = [[String: Any]]()
        for (region, exp) in zip(rasters, expected) {
            let frame = region.frames[0], layout = region.node.imageLayout!
            try require(frame.width == exp["widthPt"] as! Double && frame.height == exp["heightPt"] as! Double, "independent authored image size")
            try require(layout.placement.rawValue == exp["placement"] as! String && descriptors[region.node.assetID!]!.mime == exp["mime"] as! String, "original display order/type")
            try require(layout.loading == .lazy && layout.decoding == .async, "loading/decoding retained")
            // The original image is 24x12 pixels. Sample four independently
            // authored quadrants at their scaled native frames, including stretch.
            let a = sample(canvas, Int(frame.minX + frame.width / 4), Int(frame.minY + frame.height / 4))
            let b = sample(canvas, Int(frame.minX + frame.width * 3 / 4), Int(frame.minY + frame.height / 4))
            let c = sample(canvas, Int(frame.minX + frame.width / 4), Int(frame.minY + frame.height * 3 / 4))
            try require(a[0] > 180 && a[1] < 90 && b[1] > 180 && b[0] < 90 && c[2] > 180 && c[0] < 90, "actual raw raster painted at authored frame")
            let siblings = plan.items.filter { $0.nodeID != region.node.id && $0.frame.intersects(CGRect(x: 0, y: frame.minY + 0.1, width: 640, height: max(0.1, frame.height - 0.2))) }
            if layout.placement == .inline {
                try require(siblings.contains { $0.frame.maxX <= frame.minX } && siblings.contains { $0.frame.minX >= frame.maxX }, "inline stays between original text")
            } else {
                try require(siblings.isEmpty, "block occupies its own native line")
            }
            frames.append(["node": region.node.id, "widthPt": frame.width, "heightPt": frame.height, "placement": layout.placement.rawValue])
        }
        // Full raw labeled vector is handed through the actual semantic plan.
        let labeledBlock = document.blocks.first { $0.orderedNodes.contains { $0.kind == .caption && $0.canonicalText.contains("Labeled CeTZ") } }!
        let labeledNode = labeledBlock.orderedNodes.first { $0.kind == .image }!
        let frame = images.first { $0.node.id == labeledNode.id }!.frames[0]
        var black = 0
        for y in (Int(frame.minY) + 4)..<(Int(frame.maxY) - 4) { for x in (Int(frame.minX) + 4)..<(Int(frame.maxX) - 4) {
            if sample(canvas, x, y).allSatisfy({ $0 < 50 }) { black += 1 }
        } }
        try require(black > 80, "raw labeled CeTZ glyph paint")
        // No invented label text/range: compiler's glyph paths remain an image.
        try require(labeledNode.canonicalText.isEmpty && labeledNode.children.isEmpty, "no inferred glyph semantics")
        let data = try Data(contentsOf: root.appendingPathComponent("raw-labeled.svg"))
        try require(String(decoding: data, as: UTF8.self).contains("overflow=\"visible\""), "raw symbol overflow retained")
        let originalHidden = Data((oracle["hiddenSymbolSVG"] as! String).utf8)
        let hiddenID = shaBytes(originalHidden) + ".svg"
        try require(assets[hiddenID] == originalHidden, "raw compiler retains exact hidden asset bytes")
        let hidden = images.first { $0.node.assetID == hiddenID }!
        let hiddenFrame = hidden.frames[0]
        try require(hiddenFrame.size == CGSize(width: 100, height: 40), "raw hidden authored viewport")
        // Crop the actual full plan at its authored frame and align its native
        // origin to device pixels, avoiding fractional baseline antialias edges.
        let hiddenCanvas = try bitmap(hiddenFrame.size, dark: false)
        hiddenCanvas.translateBy(x: -hiddenFrame.minX, y: -hiddenFrame.minY)
        NativeReaderObjectRenderer.draw(plan, in: hiddenCanvas)
        let hiddenBlue = pixels(hiddenCanvas, dark: false).blue
        try require(hiddenBlue == oracle["hiddenSymbolBluePixels"] as! Int, "raw full-plan hidden clip exact blue area")
        for y in 0..<40 { for x in 0..<100 {
            let p = sample(hiddenCanvas, x, y)
            let isBlue = p[2] > p[0] + 20 && p[2] > p[1] + 20
            let expectedBlue = (30..<50).contains(x) && (10..<30).contains(y)
            try require(isBlue == expectedBlue, "raw full-plan hidden exact mask")
        } }
        try savePNG(hiddenCanvas, root.appendingPathComponent("raw-hidden-plan-crop.png"))
        try write(try JSONSerialization.jsonObject(with: JSONEncoder().encode(executions.values)), root.appendingPathComponent("raw-worker-executions.json"))
        let result: [String: Any] = ["rasterCases": rasters.count, "paintedAssets": images.count, "frames": frames, "labeledBlackInk": black,
            "rawHiddenBluePixels": hiddenBlue, "hiddenAssetSHA256": shaBytes(originalHidden),
            "unsupported": ["label-level source/AX meaning absent from compiler glyph paths", "general CSS", "GUI/VoiceOver", "delivered runtime"], "skips": 0]
        print(String(decoding: try JSONSerialization.data(withJSONObject: result), as: UTF8.self))
    }
}

extension ObjectsTests {
    @MainActor static func symbolOverflow(root: URL) throws {
        let ink = "<rect x=\"-10\" y=\"0\" width=\"40\" height=\"20\" fill=\"#2060c0\"/>"
        func symbol(_ overflow: String, extra: String = "", content: String? = nil) -> String {
            "<symbol id=\"s\" viewBox=\"0 0 20 20\" overflow=\"" + overflow + "\" " + extra + ">" + (content ?? ink) + "</symbol>"
        }
        func use(_ extra: String = "") -> String { "<use href=\"#s\" x=\"30\" y=\"10\" width=\"20\" height=\"20\" " + extra + "/>" }
        struct Case {
            let name: String, body: String
            let size: CGSize
            let boxes: [CGRect]
            var rgb: [Int]? = nil
        }
        let small = CGSize(width: 100, height: 40), large = CGSize(width: 160, height: 100)
        var cases = [Case]()
        for overflow in ["visible", "hidden"] {
            cases.append(Case(name: overflow, body: "<defs>" + symbol(overflow) + "</defs>" + use(), size: small,
                boxes: [CGRect(x: overflow == "visible" ? 20 : 30, y: 10, width: overflow == "visible" ? 40 : 20, height: 20)]))
        }
        cases.append(Case(name: "transformed", body: "<defs>" + symbol("hidden") + "</defs><g transform=\"translate(10,5)\">" + use("transform=\"scale(2)\"") + "</g>", size: large, boxes: [CGRect(x: 70, y: 25, width: 40, height: 40)]))
        cases.append(Case(name: "multiple-instances", body: "<defs>" + symbol("hidden") + "</defs><use href=\"#s\" x=\"10\" y=\"10\" width=\"20\" height=\"20\"/><use href=\"#s\" x=\"70\" y=\"20\" width=\"40\" height=\"40\"/>", size: large, boxes: [CGRect(x: 10, y: 10, width: 20, height: 20), CGRect(x: 70, y: 20, width: 40, height: 40)]))
        for (aspect, y, height) in [("xMidYMid meet", 20, 20), ("xMinYMin meet", 10, 20), ("xMaxYMax meet", 30, 20), ("none", 10, 40)] {
            let differentViewBox = "<symbol id=\"s\" viewBox=\"10 20 20 10\" preserveAspectRatio=\"" + aspect + "\" overflow=\"hidden\"><rect x=\"0\" y=\"20\" width=\"40\" height=\"10\" fill=\"#2060c0\"/></symbol>"
            cases.append(Case(name: "viewport-" + aspect.replacingOccurrences(of: " ", with: "-"), body: "<defs>" + differentViewBox + "</defs><use href=\"#s\" x=\"30\" y=\"10\" width=\"40\" height=\"40\"/>", size: large, boxes: [CGRect(x: 30, y: y, width: 40, height: height)]))
        }
        cases.append(Case(name: "nested-clips", body: "<defs><clipPath id=\"outer\"><rect x=\"35\" y=\"0\" width=\"10\" height=\"60\"/></clipPath><clipPath id=\"inner\"><rect width=\"10\" height=\"20\"/></clipPath>" + symbol("hidden", extra: "clip-path=\"url(#inner)\"") + "</defs><g clip-path=\"url(#outer)\">" + use() + "</g>", size: large, boxes: [CGRect(x: 35, y: 10, width: 5, height: 20)]))
        cases.append(Case(name: "use-of-use-id-collision", body: "<defs><path id=\"native-symbol-clip-1\" d=\"M0 0L1 1\"/>" + symbol("hidden") + "<use id=\"instance\" href=\"#s\" x=\"0\" y=\"0\" width=\"20\" height=\"20\" transform=\"translate(10,10)\"/></defs><use href=\"#instance\" x=\"20\"/><use href=\"#instance\" x=\"70\"/>", size: large, boxes: [CGRect(x: 30, y: 10, width: 20, height: 20), CGRect(x: 80, y: 10, width: 20, height: 20)]))
        cases.append(Case(name: "nested-symbols", body: "<defs>" + symbol("hidden") + "<symbol id=\"outer\" viewBox=\"0 0 20 20\" overflow=\"hidden\"><use href=\"#s\" width=\"20\" height=\"20\"/></symbol></defs><use href=\"#outer\" x=\"30\" y=\"10\" width=\"40\" height=\"40\"/>", size: large, boxes: [CGRect(x: 30, y: 10, width: 40, height: 40)]))
        cases.append(Case(name: "use-clip", body: "<defs><clipPath id=\"useclip\"><rect x=\"5\" width=\"5\" height=\"20\"/></clipPath>" + symbol("hidden") + "</defs>" + use("clip-path=\"url(#useclip)\""), size: small, boxes: [CGRect(x: 35, y: 10, width: 5, height: 20)]))
        cases.append(Case(name: "viewport-slice", body: "<defs><symbol id=\"s\" viewBox=\"0 0 20 10\" preserveAspectRatio=\"xMidYMid slice\" overflow=\"hidden\"><rect x=\"-10\" width=\"40\" height=\"10\" fill=\"#2060c0\"/></symbol></defs>" + use(), size: small, boxes: [CGRect(x: 30, y: 10, width: 20, height: 20)]))
        cases.append(Case(name: "no-viewbox", body: "<defs><symbol id=\"s\" overflow=\"hidden\">" + ink + "</symbol></defs>" + use(), size: small, boxes: [CGRect(x: 30, y: 10, width: 20, height: 20)]))
        cases.append(Case(name: "symbol-dimensions", body: "<defs>" + symbol("hidden", extra: "width=\"20\" height=\"20\"") + "</defs><use href=\"#s\" x=\"30\" y=\"10\"/>", size: small, boxes: [CGRect(x: 30, y: 10, width: 20, height: 20)]))
        cases.append(Case(name: "point-viewport", body: "<defs>" + symbol("hidden") + "</defs><use href=\"#s\" x=\"30\" y=\"10\" width=\"15pt\" height=\"15pt\"/>", size: small, boxes: [CGRect(x: 30, y: 10, width: 20, height: 20)]))
        cases.append(Case(name: "isolated-opacity", body: "<defs>" + symbol("hidden") + "</defs><g opacity=\"0.5\">" + use() + use() + "</g>", size: small, boxes: [CGRect(x: 30, y: 10, width: 20, height: 20)], rgb: [143, 175, 223]))
        var records = [[String: Any]]()
        for c in cases {
            let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 \(Int(c.size.width)) \(Int(c.size.height))\">" + c.body + "</svg>"
            try Data(svg.utf8).write(to: root.appendingPathComponent("overflow-" + c.name + ".svg"))
            let scene = try NativeVectorScene.decode(Data(svg.utf8), dark: false)
            let ctx = try bitmap(c.size, dark: false)
            scene.draw(in: ctx, rect: CGRect(origin: .zero, size: c.size))
            let blue = pixels(ctx, dark: false).blue
            let expected = Int(c.boxes.reduce(0) { $0 + $1.width * $1.height })
            let record: [String: Any] = ["case": c.name, "bluePixels": blue, "expectedBluePixels": expected, "inputSHA256": sha(svg)]
            try savePNG(ctx, root.appendingPathComponent("overflow-" + c.name + ".png"))
            try write(record, root.appendingPathComponent("overflow-" + c.name + ".json"))
            try require(blue == expected, "symbol viewport blue area: " + c.name + ":" + String(blue) + " expected " + String(expected))
            for y in 0..<Int(c.size.height) { for x in 0..<Int(c.size.width) {
                let p = sample(ctx, x, y), isBlue = p[2] > p[0] + 20 && p[2] > p[1] + 20
                let expectedBlue = c.boxes.contains { $0.contains(CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5)) }
                try require(isBlue == expectedBlue, "symbol viewport exact pixel mask: " + c.name)
            } }
            if let rgb = c.rgb {
                try require(zip(sample(ctx, 40, 20), rgb).allSatisfy { abs($0 - $1) <= 1 }, "isolated opacity after clip")
            }
            records.append(record)
        }
        var rejected = [String]()
        var negatives: [(String, String)] = [
            ("implicit-viewport", "<defs>" + symbol("hidden") + "</defs><use href=\"#s\"/>"),
            ("font-relative-viewport", "<defs>" + symbol("hidden") + "</defs><use href=\"#s\" width=\"2em\" height=\"2em\"/>"),
            ("zero-viewport", "<defs>" + symbol("hidden") + "</defs><use href=\"#s\" width=\"0\" height=\"20\"/>"),
            ("external-hidden", "<defs>" + symbol("hidden") + "</defs><use href=\"https://example.org/s\" width=\"20\" height=\"20\"/>"),
            ("unresolved-hidden", "<use href=\"#missing\" width=\"20\" height=\"20\"/>"),
            ("cyclic-hidden", "<defs>" + symbol("hidden", content: "<use href=\"#s\" width=\"20\" height=\"20\"/>") + "</defs>" + use()),
            ("transform-budget-hidden", "<defs>" + symbol("hidden") + "</defs><g transform=\"scale(100000000)\">" + use("transform=\"scale(100000000)\"") + "</g>")]
        negatives.append(("generated-depth-budget", "<defs>" + symbol("hidden") + "</defs>" + String(repeating: "<g>", count: 123) + use() + String(repeating: "</g>", count: 123)))
        negatives.append(("generated-node-budget", "<defs>" + symbol("hidden") + "</defs>" + String(repeating: "<g/>", count: 19990) + use()))
        negatives.append(("viewport-transform-budget", "<defs><symbol id=\"s\" viewBox=\"0 0 0.00000001 0.00000001\" overflow=\"hidden\">" + ink + "</symbol></defs>" + use()))
        for (name, body) in negatives {
            let svg = "<svg viewBox=\"0 0 100 40\">" + body + "</svg>"
            _ = try expectFailure(name) { _ = try NativeVectorScene.decode(Data(svg.utf8), dark: false) }
            rejected.append(name)
        }
        let pixelInput = "<svg viewBox=\"0 0 100 40\"><defs>" + symbol("hidden") + "</defs>" + use() + "</svg>"
        _ = try expectFailure("hidden-pixel-budget") { _ = try NativeVectorScene.decode(Data(pixelInput.utf8), dark: false, pixelBudget: 1024) }
        rejected.append("hidden-pixel-budget")
        try write(rejected, root.appendingPathComponent("overflow-negative-results.json"))
        print(String(decoding: try JSONSerialization.data(withJSONObject: records), as: UTF8.self))
    }
}
