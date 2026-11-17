import AppKit
import CoreText
import CryptoKit
import Darwin

// NA03 adapter; schema 1 remains owned by NA01. All coordinates are top-left pt.
// SVG is decoded into immutable CoreGraphics paths, never executed or sent to a
// WebView. Unsupported resources/paint fail the candidate atomically.
enum NativeObjectError: Error, Equatable {
    case unsupported(String), invalidGeometry, stale, cancelled, budget
}

struct NativeVectorShape {
    let path: CGPath
    let fill: CGColor?
    let stroke: CGColor?
    let strokeWidth: CGFloat
    let evenOdd: Bool
    let alpha: CGFloat
    let transform: CGAffineTransform
    let lineCap: CGLineCap
    let lineJoin: CGLineJoin
    let miterLimit: CGFloat
    let dash: [CGFloat]
    let dashPhase: CGFloat
}

struct NativeVectorScene {
    let viewBox: CGRect
    let shapes: [NativeVectorShape]

    static func decode(_ data: Data, dark: Bool) throws -> Self {
        guard data.count <= 8 * 1024 * 1024,
              let xml = String(data: data, encoding: .utf8),
              !xml.contains("<!"), !xml.contains("<?"),
              !xml.lowercased().contains("url("), !xml.contains("&") else {
            throw NativeObjectError.unsupported("svg-resource-or-limit")
        }
        let delegate = NativeSVGParser(dark: dark)
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), delegate.failure == nil, delegate.depth == 0,
              let box = delegate.box, !delegate.shapes.isEmpty else {
            throw delegate.failure ?? NativeObjectError.unsupported("svg-xml")
        }
        return Self(viewBox: box, shapes: delegate.shapes)
    }

    func draw(in context: CGContext, rect: CGRect) {
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.minY)
        context.scaleBy(x: rect.width / viewBox.width, y: rect.height / viewBox.height)
        context.translateBy(x: -viewBox.minX, y: -viewBox.minY)
        for shape in shapes {
            context.saveGState()
            context.concatenate(shape.transform)
            context.setAlpha(shape.alpha)
            context.setLineCap(shape.lineCap); context.setLineJoin(shape.lineJoin); context.setMiterLimit(shape.miterLimit)
            context.setLineDash(phase: shape.dashPhase, lengths: shape.dash)
            context.addPath(shape.path)
            if let fill = shape.fill { context.setFillColor(fill) }
            if let stroke = shape.stroke { context.setStrokeColor(stroke); context.setLineWidth(shape.strokeWidth) }
            if shape.fill != nil && shape.stroke != nil && shape.strokeWidth > 0 {
                context.drawPath(using: shape.evenOdd ? .eoFillStroke : .fillStroke)
            } else if shape.fill != nil { context.drawPath(using: shape.evenOdd ? .eoFill : .fill) }
            else if shape.stroke != nil && shape.strokeWidth > 0 { context.strokePath() }
            context.restoreGState()
        }
        context.restoreGState()
    }
}

private func numbers(_ text: String) throws -> [CGFloat] {
    let regex = try NSRegularExpression(pattern: "[-+]?(?:[0-9]*\\.[0-9]+|[0-9]+\\.?[0-9]*)(?:[eE][-+]?[0-9]+)?")
    let range = NSRange(text.startIndex..., in: text)
    let matches = regex.matches(in: text, range: range)
    var end = text.startIndex, values = [CGFloat]()
    for match in matches {
        let r = Range(match.range, in: text)!
        guard text[end..<r.lowerBound].allSatisfy({ $0.isWhitespace || $0 == "," }),
              let value = Double(text[r]), value.isFinite, abs(value) <= 1e8 else { throw NativeObjectError.invalidGeometry }
        values.append(CGFloat(value)); end = r.upperBound
    }
    guard text[end...].allSatisfy({ $0.isWhitespace || $0 == "," }) else { throw NativeObjectError.invalidGeometry }
    return values
}

private func affine(_ text: String) throws -> CGAffineTransform {
    let regex = try NSRegularExpression(pattern: "([a-zA-Z]+)\\s*\\(([^()]*)\\)")
    var value = CGAffineTransform.identity, end = text.startIndex
    for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
        let r = Range(match.range, in: text)!
        guard text[end..<r.lowerBound].allSatisfy({ $0.isWhitespace || $0 == "," }) else { throw NativeObjectError.invalidGeometry }
        let name = String(text[Range(match.range(at: 1), in: text)!])
        let n = try numbers(String(text[Range(match.range(at: 2), in: text)!]))
        let t: CGAffineTransform
        switch (name, n.count) {
        case ("matrix", 6): t = CGAffineTransform(a: n[0], b: n[1], c: n[2], d: n[3], tx: n[4], ty: n[5])
        case ("translate", 1), ("translate", 2): t = CGAffineTransform(translationX: n[0], y: n.count == 2 ? n[1] : 0)
        case ("scale", 1), ("scale", 2): t = CGAffineTransform(scaleX: n[0], y: n.count == 2 ? n[1] : n[0])
        case ("rotate", 1): t = CGAffineTransform(rotationAngle: n[0] * .pi / 180)
        case ("rotate", 3):
            t = CGAffineTransform(translationX: -n[1], y: -n[2])
                .concatenating(CGAffineTransform(rotationAngle: n[0] * .pi / 180))
                .concatenating(CGAffineTransform(translationX: n[1], y: n[2]))
        default: throw NativeObjectError.unsupported("svg-transform")
        }
        // SVG lists apply rightmost transform first to column vectors.
        value = t.concatenating(value)
        guard [value.a, value.b, value.c, value.d, value.tx, value.ty].allSatisfy({ $0.isFinite && abs($0) <= 1e9 }) else { throw NativeObjectError.invalidGeometry }
        end = r.upperBound
    }
    guard text[end...].allSatisfy({ $0.isWhitespace }) else { throw NativeObjectError.invalidGeometry }
    return value
}

private func svgPath(_ data: String) throws -> CGPath {
    let regex = try NSRegularExpression(pattern: "[A-Za-z]|[-+]?(?:[0-9]*\\.[0-9]+|[0-9]+\\.?[0-9]*)(?:[eE][-+]?[0-9]+)?")
    let matches = regex.matches(in: data, range: NSRange(data.startIndex..., in: data))
    guard matches.count <= 300000 else { throw NativeObjectError.budget }
    var tokens = [String](), end = data.startIndex
    for m in matches {
        let r = Range(m.range, in: data)!
        guard data[end..<r.lowerBound].allSatisfy({ $0.isWhitespace || $0 == "," }) else { throw NativeObjectError.invalidGeometry }
        tokens.append(String(data[r])); end = r.upperBound
    }
    guard data[end...].allSatisfy({ $0.isWhitespace || $0 == "," }) else { throw NativeObjectError.invalidGeometry }
    let path = CGMutablePath()
    var i = 0, command = "", current = CGPoint.zero, start = CGPoint.zero
    var control = CGPoint.zero, previous = ""
    func take() throws -> CGFloat {
        guard i < tokens.count, let n = Double(tokens[i]), n.isFinite, abs(n) <= 1e8 else { throw NativeObjectError.invalidGeometry }
        i += 1; return CGFloat(n)
    }
    while i < tokens.count {
        if tokens[i].first!.isLetter { command = tokens[i]; i += 1 }
        guard !command.isEmpty else { throw NativeObjectError.invalidGeometry }
        let relative = command == command.lowercased(), upper = command.uppercased(), origin = current
        func point() throws -> CGPoint {
            let x = try take(), y = try take()
            return CGPoint(x: x + (relative ? origin.x : 0), y: y + (relative ? origin.y : 0))
        }
        switch upper {
        case "M": current = try point(); path.move(to: current); start = current; command = relative ? "l" : "L"
        case "L": current = try point(); path.addLine(to: current)
        case "H": current.x = try take() + (relative ? origin.x : 0); path.addLine(to: current)
        case "V": current.y = try take() + (relative ? origin.y : 0); path.addLine(to: current)
        case "C":
            let a = try point(), b = try point(); current = try point()
            path.addCurve(to: current, control1: a, control2: b); control = b
        case "S":
            let a = ["C", "S"].contains(previous) ? CGPoint(x: 2 * origin.x - control.x, y: 2 * origin.y - control.y) : origin
            let b = try point(); current = try point(); path.addCurve(to: current, control1: a, control2: b); control = b
        case "Q": let a = try point(); current = try point(); path.addQuadCurve(to: current, control: a); control = a
        case "T":
            let a = ["Q", "T"].contains(previous) ? CGPoint(x: 2 * origin.x - control.x, y: 2 * origin.y - control.y) : origin
            current = try point(); path.addQuadCurve(to: current, control: a); control = a
        case "Z": path.closeSubpath(); current = start; command = ""
        default: throw NativeObjectError.unsupported("svg-path-" + upper)
        }
        previous = upper
    }
    return path.copy()!
}

private final class NativeSVGParser: NSObject, XMLParserDelegate {
    struct Style {
        var transform = CGAffineTransform.identity
        var fill: CGColor? = CGColor(gray: 0, alpha: 1)
        var stroke: CGColor?
        var width: CGFloat = 1
        var alpha: CGFloat = 1
        var evenOdd = false
        var lineCap: CGLineCap = .butt
        var lineJoin: CGLineJoin = .miter
        var miterLimit: CGFloat = 4
        var dash = [CGFloat]()
        var dashPhase: CGFloat = 0
    }
    let ink: CGColor
    var styles = [Style](), shapes = [NativeVectorShape]()
    var depth = 0, box: CGRect?, failure: NativeObjectError?
    init(dark: Bool) { ink = CGColor(gray: dark ? 1 : 0, alpha: 1) }
    func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? { nil }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { failure = .unsupported("svg-text"); parser.abortParsing() }
    }
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
        do {
            guard depth < 128, shapes.count < 20000 else { throw NativeObjectError.budget }
            let common: Set<String> = ["xmlns", "xmlns:xlink", "id", "role", "focusable", "aria-hidden", "aria-label", "data-mml-node", "data-c", "data-mjx-texclass", "data-latex", "transform", "fill", "stroke", "stroke-width", "fill-rule", "opacity", "fill-opacity", "stroke-opacity", "style", "stroke-linecap", "stroke-linejoin", "stroke-miterlimit", "stroke-dasharray", "stroke-dashoffset"]
            let local: [String: Set<String>] = ["svg": ["viewBox", "width", "height", "preserveAspectRatio"], "g": [], "path": ["d"], "rect": ["x", "y", "width", "height"], "circle": ["cx", "cy", "r"], "ellipse": ["cx", "cy", "rx", "ry"], "line": ["x1", "y1", "x2", "y2"], "polyline": ["points"], "polygon": ["points"]]
            guard let allowed = local[name], Set(a.keys).isSubset(of: common.union(allowed)),
                  depth != 0 || name == "svg", name != "svg" || depth == 0 else { throw NativeObjectError.unsupported("svg-element-or-attribute") }
            if let css = a["style"] {
                // Accepted compiler SVG carries HTML em dimensions; geometry
                // comes from its explicit viewBox, never CSS or system fonts.
                guard name == "svg" else { throw NativeObjectError.unsupported("svg-style") }
                for declaration in css.split(separator: ";") {
                    let pair = declaration.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                    guard pair.count == 2 else { throw NativeObjectError.unsupported("svg-style") }
                    let valid: Bool
                    switch pair[0] {
                    case "overflow": valid = pair[1] == "visible"
                    case "display": valid = pair[1] == "block"
                    case "width", "height": valid = pair[1].range(of: "^[0-9]+(?:\\.[0-9]+)?(?:em|pt|px)$", options: .regularExpression) != nil
                    default: valid = false
                    }
                    guard valid else { throw NativeObjectError.unsupported("svg-style") }
                }
            }
            if let aspect = a["preserveAspectRatio"], aspect != "xMidYMid meet" { throw NativeObjectError.unsupported("svg-aspect") }
            if ["g", "svg"].contains(name), let opacity = a["opacity"], opacity != "1" { throw NativeObjectError.unsupported("svg-group-opacity") }
            var style = styles.last ?? Style()
            if let t = a["transform"] { style.transform = try affine(t).concatenating(style.transform) }
            guard [style.transform.a, style.transform.b, style.transform.c, style.transform.d, style.transform.tx, style.transform.ty].allSatisfy({ $0.isFinite && abs($0) <= 1e9 }) else { throw NativeObjectError.invalidGeometry }
            func number(_ key: String, _ fallback: CGFloat = 0) throws -> CGFloat {
                guard let s = a[key] else { return fallback }
                let n = try numbers(s)
                guard n.count == 1 else { throw NativeObjectError.invalidGeometry }; return n[0]
            }
            func color(_ s: String) throws -> CGColor? {
                if s == "none" { return nil }
                if s == "currentColor" { return ink }
                if s == "black" { return CGColor(gray: 0, alpha: 1) }
                if s == "white" { return CGColor(gray: 1, alpha: 1) }
                guard s.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil,
                      let n = UInt32(s.dropFirst(), radix: 16) else { throw NativeObjectError.unsupported("svg-paint") }
                return CGColor(red: CGFloat((n >> 16) & 255) / 255, green: CGFloat((n >> 8) & 255) / 255, blue: CGFloat(n & 255) / 255, alpha: 1)
            }
            if let fill = a["fill"] { style.fill = try color(fill) }
            if let stroke = a["stroke"] { style.stroke = try color(stroke) }
            style.width = try number("stroke-width", style.width)
            if let cap = a["stroke-linecap"] {
                guard let value: CGLineCap = ["butt": .butt, "round": .round, "square": .square][cap] else { throw NativeObjectError.unsupported("svg-linecap") }; style.lineCap = value
            }
            if let join = a["stroke-linejoin"] {
                guard let value: CGLineJoin = ["miter": .miter, "round": .round, "bevel": .bevel][join] else { throw NativeObjectError.unsupported("svg-linejoin") }; style.lineJoin = value
            }
            style.miterLimit = try number("stroke-miterlimit", style.miterLimit)
            guard style.miterLimit >= 1 else { throw NativeObjectError.invalidGeometry }
            if let dash = a["stroke-dasharray"] {
                style.dash = dash == "none" ? [] : try numbers(dash)
                guard style.dash.count <= 128, style.dash.allSatisfy({ $0 >= 0 }), style.dash.isEmpty || style.dash.contains(where: { $0 > 0 }) else { throw NativeObjectError.invalidGeometry }
            }
            style.dashPhase = try number("stroke-dashoffset", style.dashPhase)
            style.alpha *= try number("opacity", 1)
            // Separate fill/stroke opacity is applied to colors, not group alpha.
            if let fill = style.fill {
                let alpha = try number("fill-opacity", fill.alpha)
                guard (0...1).contains(alpha) else { throw NativeObjectError.invalidGeometry }; style.fill = fill.copy(alpha: alpha)
            }
            if let stroke = style.stroke {
                let alpha = try number("stroke-opacity", stroke.alpha)
                guard (0...1).contains(alpha) else { throw NativeObjectError.invalidGeometry }; style.stroke = stroke.copy(alpha: alpha)
            }
            if let rule = a["fill-rule"] {
                guard ["nonzero", "evenodd"].contains(rule) else { throw NativeObjectError.unsupported("svg-fill-rule") }
                style.evenOdd = rule == "evenodd"
            }
            guard (0...1).contains(style.alpha), style.width >= 0 else { throw NativeObjectError.invalidGeometry }
            if name == "svg" {
                let n = try numbers(a["viewBox"] ?? "")
                guard n.count == 4, n[2] > 0, n[3] > 0 else { throw NativeObjectError.invalidGeometry }
                box = CGRect(x: n[0], y: n[1], width: n[2], height: n[3])
            }
            let path: CGPath?
            switch name {
            case "path": path = try svgPath(a["d"] ?? "")
            case "rect":
                let w = try number("width"), h = try number("height")
                guard w >= 0, h >= 0 else { throw NativeObjectError.invalidGeometry }
                path = CGPath(rect: CGRect(x: try number("x"), y: try number("y"), width: w, height: h), transform: nil)
            case "circle", "ellipse":
                let rx = try number(name == "circle" ? "r" : "rx"), ry = try number(name == "circle" ? "r" : "ry")
                guard rx >= 0, ry >= 0 else { throw NativeObjectError.invalidGeometry }
                path = CGPath(ellipseIn: CGRect(x: try number("cx") - rx, y: try number("cy") - ry, width: 2 * rx, height: 2 * ry), transform: nil)
            case "line":
                let p = CGMutablePath(); p.move(to: CGPoint(x: try number("x1"), y: try number("y1")))
                p.addLine(to: CGPoint(x: try number("x2"), y: try number("y2"))); path = p
            case "polyline", "polygon":
                let n = try numbers(a["points"] ?? "")
                guard n.count >= 4, n.count % 2 == 0 else { throw NativeObjectError.invalidGeometry }
                let p = CGMutablePath(); p.move(to: CGPoint(x: n[0], y: n[1]))
                for i in stride(from: 2, to: n.count, by: 2) { p.addLine(to: CGPoint(x: n[i], y: n[i + 1])) }
                if name == "polygon" { p.closeSubpath() }; path = p
            default: path = nil
            }
            if let p = path { shapes.append(NativeVectorShape(path: p, fill: style.fill, stroke: style.stroke, strokeWidth: style.width, evenOdd: style.evenOdd, alpha: style.alpha, transform: style.transform, lineCap: style.lineCap, lineJoin: style.lineJoin, miterLimit: style.miterLimit, dash: style.dash, dashPhase: style.dashPhase)) }
            styles.append(style); depth += 1
        } catch { failure = (error as? NativeObjectError) ?? .invalidGeometry; parser.abortParsing() }
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) { depth -= 1; _ = styles.popLast() }
}

// Drawing consumes immutable plans. A view sets the clip/scroll transform and
// supplies a top-left CGContext. CoreText is flipped only for its glyph draw.
enum NativeReaderObjectRenderer {
    static func draw(_ plan: NativeObjectPlan, in context: CGContext) {
        for item in plan.items {
            switch item.paint {
            case .vector(let scene): scene.draw(in: context, rect: item.frame)
            case .text(let line):
                context.saveGState()
                context.translateBy(x: item.frame.minX, y: item.frame.minY + item.ascent)
                context.scaleBy(x: 1, y: -1)
                context.textMatrix = .identity; context.textPosition = .zero
                CTLineDraw(line, context); context.restoreGState()
            case .cell(let header):
                context.saveGState()
                context.setFillColor(CGColor(gray: plan.context.theme == .dark ? (header ? 0.2 : 0.08) : (header ? 0.9 : 1), alpha: 1))
                context.fill(item.frame)
                context.setStrokeColor(CGColor(gray: 0.5, alpha: 1)); context.setLineWidth(0.5); context.stroke(item.frame)
                context.restoreGState()
            }
        }
    }

    static func verifiedAsset(_ asset: NativeReaderAsset, bytes: Data, dark: Bool) throws -> NativeVectorScene {
        guard asset.mime == "image/svg+xml", bytes.count == asset.byteCount,
              SHA256.hash(data: bytes).map({ String(format: "%02x", $0) }).joined() == asset.sha256 else {
            throw NativeObjectError.unsupported("asset-type-or-digest")
        }
        return try NativeVectorScene.decode(bytes, dark: dark)
    }
}

// Computation subprocess adapter. The app supplies pinned, offline delivery URLs;
// none originate in document JSON. Two jobs maximum, no unbounded queue/cache.
// Process I/O/deadlines run off MainActor; cancellation kills only this child.
private final class NativeMathCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func cancel() { lock.lock(); value = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
}

struct NativeMathExecution: Codable {
    let argv: [String]
    let exit: Int32
    let reason: String
    let elapsed: Double
    let stdoutBytes: Int
    let stderrBytes: Int
}

actor NativeMathWorker {
    private let node: URL, helper: URL, runtime: URL
    private let timeout: TimeInterval
    private var active = 0
    private let record: @Sendable (NativeMathExecution) -> Void
    init(node: URL, helper: URL, runtime: URL, timeout: TimeInterval = 10, record: @escaping @Sendable (NativeMathExecution) -> Void = { _ in }) {
        self.node = node; self.helper = helper; self.runtime = runtime
        self.timeout = timeout.isFinite ? max(0.1, min(timeout, 30)) : 10
        self.record = record
    }
    func calculate(_ math: NativeMath, context: NativeObjectContext, width: Double) async throws -> NativeMathLayout {
        guard active < 2 else { throw NativeObjectError.unsupported("math-worker-busy") }
        try context.validate()
        guard width.isFinite, (16...8192).contains(width) else { throw NativeObjectError.invalidGeometry }
        guard math.mathML.utf8.count <= 65536 else { throw NativeObjectError.budget }
        let input = try JSONSerialization.data(withJSONObject: ["mathML": math.mathML, "width": width,
            "fontSize": context.fontSize, "font": "MathJaxNewcm", "context": ["revision": context.identity.revision,
                "generation": context.generation, "theme": context.theme.rawValue]])
        active += 1; defer { active -= 1 }
        let cancellation = NativeMathCancellation(), node = self.node, helper = self.helper, runtime = self.runtime, timeout = self.timeout, record = self.record
        let bytes = try await withTaskCancellationHandler(operation: {
            try await Task.detached(priority: .userInitiated) {
                try Self.execute(node: node, helper: helper, runtime: runtime, input: input, timeout: timeout, cancellation: cancellation, record: record)
            }.value
        }, onCancel: { cancellation.cancel() })
        if Task.isCancelled { throw NativeObjectError.cancelled }
        return try NativeMathLayout.decode(bytes, math: math, context: context, width: width)
    }
    private nonisolated static func execute(node: URL, helper: URL, runtime: URL, input: Data,
                                            timeout: TimeInterval, cancellation: NativeMathCancellation, record: @Sendable (NativeMathExecution) -> Void) throws -> Data {
        guard node.isFileURL, helper.isFileURL, runtime.isFileURL,
              FileManager.default.isExecutableFile(atPath: node.path),
              FileManager.default.fileExists(atPath: helper.path) else { throw NativeObjectError.unsupported("math-runtime-missing") }
        if cancellation.isCancelled { throw NativeObjectError.cancelled }
        let process = Process(), stdinPipe = Pipe(), stdoutPipe = Pipe(), stderrPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        process.arguments = ["-p", "(version 1)(allow default)(deny network*)(deny file-write*)", node.path, helper.path, "--runtime", runtime.path]
        process.environment = ["PATH": "/usr/bin:/bin"]
        process.standardInput = stdinPipe; process.standardOutput = stdoutPipe; process.standardError = stderrPipe
        let start = ProcessInfo.processInfo.systemUptime
        var output = Data(), errors = Data()
        try process.run()
        try? stdinPipe.fileHandleForReading.close()
        try? stdoutPipe.fileHandleForWriting.close(); try? stderrPipe.fileHandleForWriting.close()
        let inputFD = stdinPipe.fileHandleForWriting.fileDescriptor
        let outputFD = stdoutPipe.fileHandleForReading.fileDescriptor, errorFD = stderrPipe.fileHandleForReading.fileDescriptor
        for fd in [inputFD, outputFD, errorFD] { _ = fcntl(fd, F_SETFL, O_NONBLOCK) }
        _ = fcntl(inputFD, F_SETNOSIGPIPE, 1)
        defer {
            if process.isRunning { process.terminate(); usleep(20000); if process.isRunning { kill(process.processIdentifier, SIGKILL) } }
            process.waitUntilExit()
            record(NativeMathExecution(argv: [process.executableURL!.path] + process.arguments!, exit: process.terminationStatus,
                reason: process.terminationReason == .exit ? "exit" : "signal", elapsed: ProcessInfo.processInfo.systemUptime - start,
                stdoutBytes: output.count, stderrBytes: errors.count))
            try? stdinPipe.fileHandleForWriting.close(); try? stdoutPipe.fileHandleForReading.close(); try? stderrPipe.fileHandleForReading.close()
        }
        var sent = 0, inputClosed = false
        func drain(_ fd: Int32, into data: inout Data, limit: Int) throws {
            var buffer = [UInt8](repeating: 0, count: 16384)
            while true {
                let count = read(fd, &buffer, buffer.count)
                if count > 0 {
                    guard data.count + count <= limit else { throw NativeObjectError.budget }
                    data.append(contentsOf: buffer.prefix(count))
                } else if count == 0 || errno == EAGAIN { return }
                else if errno != EINTR { throw NativeObjectError.unsupported("math-helper-io") }
            }
        }
        while true {
            if cancellation.isCancelled { throw NativeObjectError.cancelled }
            if ProcessInfo.processInfo.systemUptime - start > timeout { throw NativeObjectError.unsupported("math-helper-timeout") }
            if !inputClosed {
                let count = input.withUnsafeBytes { bytes in
                    Darwin.write(inputFD, bytes.baseAddress!.advanced(by: sent), input.count - sent)
                }
                if count > 0 { sent += count }
                else if count < 0 && errno != EAGAIN && errno != EINTR { throw NativeObjectError.unsupported("math-helper-input") }
                if sent == input.count { try stdinPipe.fileHandleForWriting.close(); inputClosed = true }
            }
            try drain(outputFD, into: &output, limit: 8 * 1024 * 1024)
            try drain(errorFD, into: &errors, limit: 65536)
            if !process.isRunning {
                try drain(outputFD, into: &output, limit: 8 * 1024 * 1024)
                try drain(errorFD, into: &errors, limit: 65536)
                break
            }
            usleep(5000)
        }
        guard process.terminationStatus == 0 else {
            if process.terminationReason == .exit, process.terminationStatus == 2,
               let status = try? JSONSerialization.jsonObject(with: errors) as? [String: String],
               status["status"] == "unsupported", let code = status["code"],
               code.range(of: "^[a-z][a-z0-9-]{0,64}$", options: .regularExpression) != nil {
                throw NativeObjectError.unsupported(code)
            }
            throw NativeObjectError.unsupported("math-helper-rejected")
        }
        return output
    }
}
