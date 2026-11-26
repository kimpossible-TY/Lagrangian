import AppKit
import CoreText
import CryptoKit
import Darwin
import ImageIO
import UniformTypeIdentifiers

// NA03 adapter; schema 1 remains owned by NA01. All coordinates are top-left pt.
// SVG is validated before becoming immutable CoreGraphics paths or bounded
// native CGImages. No WebView executes content. Failed candidates stay atomic.
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
    let intrinsicSize: CGSize
    let image: CGImage?
    let decodedCost: Int
    init(viewBox: CGRect, shapes: [NativeVectorShape], image: CGImage? = nil, decodedCost: Int = 0, intrinsicSize: CGSize? = nil) {
        self.viewBox = viewBox; self.shapes = shapes; self.image = image; self.decodedCost = decodedCost
        self.intrinsicSize = intrinsicSize ?? viewBox.size
    }

    static func decode(_ data: Data, dark: Bool, pixelBudget: Int = 16 * 1024 * 1024,
                       targetSize: CGSize? = nil) throws -> Self {
        let pixelBudget = min(max(0, pixelBudget), 16 * 1024 * 1024)
        let embeddedByteLimit = 6 * 1024 * 1024
        guard data.count <= embeddedByteLimit else { throw NativeObjectError.budget }
        let safe = try NativeSafeSVG.inspect(data, dark: dark)
        guard safe.hasEmbeddedPNG || data.count <= pixelBudget / 16 else { throw NativeObjectError.budget }
        let display = targetSize ?? safe.viewport
        guard display.width.isFinite, display.height.isFinite, display.width > 0, display.height > 0, display.width <= 8192, display.height <= 8192 else { throw NativeObjectError.budget }
        // Keep the exact native path consumer for MathJax's glyph/advance oracle.
        // Rich SVG is decoded only after the same security/complexity boundary.
        if !safe.rich {
            let delegate = NativeSVGParser(dark: dark)
            let parser = XMLParser(data: try safe.data)
            parser.shouldResolveExternalEntities = false; parser.delegate = delegate
            guard parser.parse(), delegate.failure == nil, delegate.depth == 0,
                  let box = delegate.box, !delegate.shapes.isEmpty else {
                throw delegate.failure ?? NativeObjectError.unsupported("svg-xml")
            }
            return Self(viewBox: box, shapes: delegate.shapes, intrinsicSize: safe.viewport)
        }
        let size = targetSize ?? safe.viewport
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0, size.width <= 4096, size.height <= 4096 else { throw NativeObjectError.budget }
        let w = Int(ceil(size.width * 2)), h = Int(ceil(size.height * 2))
        guard w > 0, h > 0, w <= 8192, h <= 8192, w <= pixelBudget / 4 / h else { throw NativeObjectError.budget }
        let xml = try safe.serialized(width: w, height: h)
        guard let native = NSImage(data: xml) else { throw NativeObjectError.unsupported("native-svg-decode") }
        native.size = NSSize(width: w, height: h)
        var rect = NSRect(x: 0, y: 0, width: w, height: h)
        guard let image = native.cgImage(forProposedRect: &rect, context: nil, hints: nil),
              image.width == w, image.height == h, image.bytesPerRow <= pixelBudget / h else { throw NativeObjectError.unsupported("native-svg-size") }
        return Self(viewBox: CGRect(origin: .zero, size: size), shapes: [], image: image, decodedCost: image.bytesPerRow * h)
    }

    static func raster(_ data: Data, mime: String, pixelBudget: Int) throws -> Self {
        guard data.count > 0, data.count <= 8 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let type = CGImageSourceGetType(source) as String? else { throw NativeObjectError.unsupported("raster-decode") }
        let expected = ["image/png": UTType.png.identifier, "image/jpeg": UTType.jpeg.identifier,
                        "image/gif": UTType.gif.identifier, "image/webp": "org.webmproject.webp"]
        guard expected[mime] == type else { throw NativeObjectError.unsupported("asset-content-type") }
        guard CGImageSourceGetStatus(source) == .statusComplete else { throw NativeObjectError.unsupported("raster-incomplete") }
        guard CGImageSourceGetCount(source) == 1 else { throw NativeObjectError.unsupported("animated-image") }
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let w = props[kCGImagePropertyPixelWidth as String] as? Int,
              let h = props[kCGImagePropertyPixelHeight as String] as? Int,
              w > 0, h > 0, w <= 8192, h <= 8192, w <= pixelBudget / 4 / h else { throw NativeObjectError.budget }
        // Thumbnail transform applies EXIF orientation; maxPixelSize is the
        // original maximum dimension, so this does not silently downsample.
        let options = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                       kCGImageSourceCreateThumbnailWithTransform: true,
                       kCGImageSourceShouldCacheImmediately: true,
                       kCGImageSourceThumbnailMaxPixelSize: max(w, h)] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options),
              image.bytesPerRow <= pixelBudget / image.height else { throw NativeObjectError.unsupported("raster-pixel-cost") }
        return Self(viewBox: CGRect(x: 0, y: 0, width: image.width, height: image.height), shapes: [], image: image,
                    decodedCost: image.bytesPerRow * image.height)
    }

    func draw(in context: CGContext, rect: CGRect) {
        context.saveGState()
        if let image = image {
            context.translateBy(x: rect.minX, y: rect.maxY); context.scaleBy(x: 1, y: -1)
            context.draw(image, in: CGRect(origin: .zero, size: rect.size)); context.restoreGState(); return
        }
        context.translateBy(x: rect.minX, y: rect.minY)
        context.scaleBy(x: rect.width / viewBox.width, y: rect.height / viewBox.height)
        context.translateBy(x: -viewBox.minX, y: -viewBox.minY)
        for shape in shapes {
            context.saveGState(); context.concatenate(shape.transform); context.setAlpha(shape.alpha)
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
            let local: [String: Set<String>] = ["svg": ["viewBox", "width", "height", "preserveAspectRatio", "overflow"], "g": [], "path": ["d"], "rect": ["x", "y", "width", "height"], "circle": ["cx", "cy", "r"], "ellipse": ["cx", "cy", "rx", "ry"], "line": ["x1", "y1", "x2", "y2"], "polyline": ["points"], "polygon": ["points"]]
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

    static func verifiedAsset(_ asset: NativeReaderAsset, bytes: Data, dark: Bool, pixelBudget: Int = 16 * 1024 * 1024) throws -> NativeVectorScene {
        guard bytes.count <= 8 * 1024 * 1024, bytes.count == asset.byteCount,
              SHA256.hash(data: bytes).map({ String(format: "%02x", $0) }).joined() == asset.sha256 else {
            throw NativeObjectError.unsupported("asset-type-or-digest")
        }
        return asset.mime == "image/svg+xml" ? try NativeVectorScene.decode(bytes, dark: dark, pixelBudget: pixelBudget) : try NativeVectorScene.raster(bytes, mime: asset.mime, pixelBudget: pixelBudget)
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
    let peakResidentBytes: UInt64
}

/// Answer-only computation result. It carries no source range or source authority.
/// Pixels, SVG validation and metrics are prepared on the worker actor, never UI.
struct NativePreparedAnswerMath {
    let tex: String
    let math: NativeMath
    let layout: NativeMathLayout
    let image: CGImage
    var size: CGSize { CGSize(width: layout.whole.width, height: layout.whole.ascent + layout.whole.descent) }
}

/// Helper protocol limits are kept in lockstep with math_layout.mjs by the reader contract tests.
enum NativeMathBatchPolicy {
    static let maximumItems = 512
    static let chunkItems = 256
    static let maximumBytes = 64 * 1024 * 1024
    static let itemOutputBytes = 8 * 1024 * 1024
    static let itemInputBytes = 256 * 1024
    static let sourceBytes = 65536
    static func outputLimit(items: Int) -> Int { min(maximumBytes, itemOutputBytes * max(1, min(items, maximumItems))) + 1 }
    static func timeout(base: TimeInterval, items: Int) -> TimeInterval { base * Double(max(1, min(items, 6))) }
    static func run<T>(range: Range<Int>, perform: (Range<Int>) async throws -> [T]) async throws -> [T] {
        try Task.checkCancellation()
        do { return try await perform(range) }
        catch {
            let retry: Bool
            switch error {
            case NativeObjectError.budget, NativeObjectError.unsupported("math-helper-timeout"),
                 NativeObjectError.unsupported("input-limit"), NativeObjectError.unsupported("output-limit"):
                retry = true
            default: retry = false
            }
            guard retry, range.count > 1 else { throw error }
            let middle = range.lowerBound + range.count / 2
            let left = try await run(range: range.lowerBound..<middle, perform: perform)
            return left + (try await run(range: middle..<range.upperBound, perform: perform))
        }
    }
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
        let bytes = try await compute(["mathML": math.mathML], source: math.mathML, context: context, width: width)
        return try NativeMathLayout.decode(bytes, math: math, context: context, width: width)
    }

    func calculateBatch(_ items: [(id: String, math: NativeMath, width: Double)], context: NativeObjectContext) async throws -> [String: NativeMathLayout] {
        try Task.checkCancellation()
        try context.validate()
        guard Set(items.map(\.id)).count == items.count else { throw NativeObjectError.stale }
        // Validate the complete request before starting any child. A malformed
        // later chunk must not spend subprocess work on an unusable batch.
        for item in items {
            try Task.checkCancellation()
            guard item.width.isFinite, (16...8192).contains(item.width) else { throw NativeObjectError.invalidGeometry }
            guard item.math.mathML.utf8.count <= NativeMathBatchPolicy.sourceBytes else { throw NativeObjectError.budget }
        }
        var layouts = [String: NativeMathLayout]()
        for start in stride(from: 0, to: items.count, by: NativeMathBatchPolicy.chunkItems) {
            let results = try await NativeMathBatchPolicy.run(range: start..<min(start + NativeMathBatchPolicy.chunkItems, items.count)) { range in
                try await self.calculateChunk(items[range], context: context)
            }
            for (id, layout) in results { layouts[id] = layout }
        }
        return layouts
    }

    private func calculateChunk(_ chunk: ArraySlice<(id: String, math: NativeMath, width: Double)>,
                                context: NativeObjectContext) async throws -> [(String, NativeMathLayout)] {
        struct Input: Hashable { let mathML: String; let width: Double }
        // Repeated symbols/formulas share computation only within this
        // bounded invocation. Each semantic item is still decoded below.
        var requests = [[String: Any]](), indices = [Input: Int](), positions = [Int]()
        for item in chunk {
            try Task.checkCancellation()
            let input = Input(mathML: item.math.mathML, width: item.width)
            if let index = indices[input] { positions.append(index); continue }
            positions.append(requests.count); indices[input] = requests.count
            requests.append(["mathML": item.math.mathML, "width": item.width, "fontSize": context.fontSize,
                "font": "MathJaxNewcm", "context": ["revision": context.identity.revision,
                "generation": context.generation, "theme": context.theme.rawValue]])
        }
        guard active < 2 else { throw NativeObjectError.unsupported("math-worker-busy") }
        let input = try JSONSerialization.data(withJSONObject: ["kind": "mathml-batch", "items": requests])
        guard input.count <= NativeMathBatchPolicy.maximumBytes else { throw NativeObjectError.budget }
        active += 1
        defer { active -= 1 }
        let outputLimit = NativeMathBatchPolicy.outputLimit(items: requests.count)
        let cancellation = NativeMathCancellation(), node = self.node, helper = self.helper,
            runtime = self.runtime, timeout = NativeMathBatchPolicy.timeout(base: self.timeout, items: requests.count), record = self.record
        let bytes = try await withTaskCancellationHandler(operation: {
            try await Task.detached(priority: .userInitiated) {
                try Self.execute(node: node, helper: helper, runtime: runtime, input: input,
                    timeout: timeout, outputLimit: outputLimit, cancellation: cancellation, record: record)
            }.value
        }, onCancel: { cancellation.cancel() })
        try Task.checkCancellation()
        guard let response = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              response["kind"] as? String == "mathml-batch", let results = response["items"] as? [[String: Any]],
              results.count == requests.count else { throw NativeObjectError.stale }
        return try zip(chunk, positions).map { item, position in
            try Task.checkCancellation()
            return (item.id, try NativeMathLayout.decode(JSONSerialization.data(withJSONObject: results[position]),
                math: item.math, context: context, width: item.width))
        }
    }

    func prepare(tex: String, display: Bool, context: NativeObjectContext) async throws -> NativePreparedAnswerMath {
        let bytes = try await compute(["kind": "tex", "tex": tex, "display": display], source: tex, context: context, width: context.width)
        struct Meaning: Decodable {
            let kind: String, normalizedTeX: String, normalizedMathML: String, semanticText: String
            let display: Bool
        }
        let meaning = try JSONDecoder().decode(Meaning.self, from: bytes)
        guard meaning.kind == "tex", meaning.display == display,
              meaning.normalizedTeX == tex.trimmingCharacters(in: .whitespacesAndNewlines),
              !meaning.normalizedMathML.isEmpty, meaning.normalizedMathML.utf8.count <= 65536,
              !meaning.semanticText.isEmpty, meaning.semanticText.utf8.count <= 65536 else { throw NativeObjectError.stale }
        // Existing layout validator binds the exact original input hash and metrics.
        let binding = NativeMath(mathML: tex, normalizedText: "", display: display)
        let layout = try NativeMathLayout.decode(bytes, math: binding, context: context, width: context.width)
        let f = layout.whole, size = CGSize(width: f.width, height: f.ascent + f.descent)
        guard size.width <= 4096, size.height <= 4096 else { throw NativeObjectError.budget }
        let scene = try NativeVectorScene.decode(Data(f.svg.utf8), dark: context.theme == .dark, targetSize: size)
        let w = Int(ceil(size.width * 2)), h = Int(ceil(size.height * 2))
        guard w <= 8192, h <= 8192, w <= 4 * 1024 * 1024 / h,
              let bitmap = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw NativeObjectError.budget }
        bitmap.scaleBy(x: 2, y: 2); bitmap.translateBy(x: 0, y: CGFloat(h) / 2); bitmap.scaleBy(x: 1, y: -1)
        scene.draw(in: bitmap, rect: CGRect(origin: .zero, size: size))
        try Task.checkCancellation()
        guard let image = bitmap.makeImage() else { throw NativeObjectError.invalidGeometry }
        return NativePreparedAnswerMath(tex: meaning.normalizedTeX,
            math: NativeMath(mathML: meaning.normalizedMathML, normalizedText: meaning.semanticText, display: display),
            layout: layout, image: image)
    }

    private func compute(_ fields: [String: Any], source: String, context: NativeObjectContext, width: Double) async throws -> Data {
        guard active < 2 else { throw NativeObjectError.unsupported("math-worker-busy") }
        try Task.checkCancellation()
        try context.validate()
        guard width.isFinite, (16...8192).contains(width) else { throw NativeObjectError.invalidGeometry }
        guard source.utf8.count <= 65536 else { throw NativeObjectError.budget }
        var request = fields
        request.merge(["width": width, "fontSize": context.fontSize, "font": "MathJaxNewcm", "context": ["revision": context.identity.revision,
                "generation": context.generation, "theme": context.theme.rawValue]]) { _, new in new }
        let input = try JSONSerialization.data(withJSONObject: request)
        active += 1; defer { active -= 1 }
        let cancellation = NativeMathCancellation(), node = self.node, helper = self.helper, runtime = self.runtime, timeout = self.timeout, record = self.record
        let bytes = try await withTaskCancellationHandler(operation: {
            try await Task.detached(priority: .userInitiated) {
                try Self.execute(node: node, helper: helper, runtime: runtime, input: input, timeout: timeout, cancellation: cancellation, record: record)
            }.value
        }, onCancel: { cancellation.cancel() })
        if Task.isCancelled { throw NativeObjectError.cancelled }
        return bytes
    }
    private nonisolated static func execute(node: URL, helper: URL, runtime: URL, input: Data,
                                            timeout: TimeInterval, outputLimit: Int = NativeMathBatchPolicy.itemOutputBytes + 1, cancellation: NativeMathCancellation, record: @Sendable (NativeMathExecution) -> Void) throws -> Data {
        guard node.isFileURL, helper.isFileURL, runtime.isFileURL,
              FileManager.default.isExecutableFile(atPath: node.path),
              FileManager.default.fileExists(atPath: helper.path) else { throw NativeObjectError.unsupported("math-runtime-missing") }
        if cancellation.isCancelled { throw NativeObjectError.cancelled }
        let process = Process(), stdinPipe = Pipe(), stdoutPipe = Pipe(), stderrPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        process.arguments = ["-p", "(version 1)(allow default)(deny network*)(deny file-write*)", node.path, "--max-old-space-size=128", "--stack-size=1024", helper.path, "--runtime", runtime.path]
        process.environment = ["PATH": "/usr/bin:/bin"]
        process.standardInput = stdinPipe; process.standardOutput = stdoutPipe; process.standardError = stderrPipe
        let start = ProcessInfo.processInfo.systemUptime
        var output = Data(), errors = Data()
        var peakResidentBytes: UInt64 = 0
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
                stdoutBytes: output.count, stderrBytes: errors.count, peakResidentBytes: peakResidentBytes))
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
            // V8 heap flags do not cover Buffers/native memory. Sample resident
            // bytes as well; exceedance kills this child through the same defer.
            var usage = rusage_info_v2()
            let status = withUnsafeMutablePointer(to: &usage) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(process.processIdentifier, RUSAGE_INFO_V2, $0)
                }
            }
            if status == 0 {
                peakResidentBytes = max(peakResidentBytes, usage.ri_resident_size)
                guard peakResidentBytes <= 256 * 1024 * 1024 else { throw NativeObjectError.budget }
            } else if process.isRunning {
                throw NativeObjectError.unsupported("math-helper-memory-observation")
            }
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
            try drain(outputFD, into: &output, limit: outputLimit)
            try drain(errorFD, into: &errors, limit: 65536)
            if !process.isRunning {
                try drain(outputFD, into: &output, limit: outputLimit)
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

// Validate the entire SVG, references and expansion cost BEFORE AppKit sees it.
// The native decoder receives regenerated XML with explicit bounded dimensions;
// no document CSS, URL resolver, text/font fallback or executable content survives.
private final class NativeSafeSVG: NSObject, XMLParserDelegate {
    private final class Element {
        let name: String
        var attrs: [String: String]
        var children = [Element]()
        var refs = [String]()
        var transform = CGAffineTransform.identity
        var coordinate: CGFloat = 0
        var work = 1
        init(_ name: String, _ attrs: [String: String]) { self.name = name; self.attrs = attrs }
    }
    private var stack = [Element](), elements = [Element](), ids = [String: Element]()
    private var root: Element?
    private var failure: NativeObjectError?
    private let dark: Bool
    private(set) var rich = false
    private(set) var hasEmbeddedPNG = false
    private(set) var viewport = CGSize.zero
    private(set) var box = CGRect.zero
    init(dark: Bool) { self.dark = dark }
    var data: Data { get throws { Data(try xml(root!, viewport: box.size).utf8) } }
    func serialized(width: Int, height: Int) throws -> Data {
        var attrs = root!.attrs
        attrs["width"] = "\(width)pt"; attrs["height"] = "\(height)pt"
        attrs["xmlns:xlink"] = "http://www.w3.org/1999/xlink"
        attrs["xmlns"] = "http://www.w3.org/2000/svg"
        return Data(try xml(root!, attributes: attrs, viewport: box.size).utf8)
    }
    // Resolve a value copy for this instance. Definitions can be reached with
    // several different parent viewports during validation and serialization.
    private func viewportAttributes(_ attributes: [String: String], viewport: CGSize) throws -> ([String: String], CGSize) {
        var attrs = attributes
        let w = try side(attrs["width"], viewport.width), h = try side(attrs["height"], viewport.height)
        attrs["width"] = String(Double(w)); attrs["height"] = String(Double(h))
        if attrs["viewBox"] == nil { attrs["viewBox"] = "0 0 \(w) \(h)" }
        let v = try numbers(attrs["viewBox"]!)
        return (attrs, CGSize(width: v[2], height: v[3]))
    }
    private func side(_ raw: String?, _ fallback: CGFloat) throws -> CGFloat {
        guard let raw = raw else { return fallback }
        let suffix = raw.hasSuffix("pt") ? "pt" : raw.hasSuffix("px") ? "px" : ""
        guard let n = Double(suffix.isEmpty ? raw : String(raw.dropLast(2))), n.isFinite, n > 0, n <= 1e8 else { throw NativeObjectError.invalidGeometry }
        return CGFloat(n * (suffix == "pt" ? 4.0 / 3 : 1))
    }
    private func viewportMapping(_ attrs: [String: String]) throws -> CGAffineTransform {
        let w = try side(attrs["width"], 0), h = try side(attrs["height"], 0)
        let v = try numbers(attrs["viewBox"]!)
        return viewBoxMapping(v, width: w, height: h,
                              x: CGFloat(Double(attrs["x"] ?? "0") ?? 0),
                              y: CGFloat(Double(attrs["y"] ?? "0") ?? 0),
                              aspect: attrs["preserveAspectRatio"] ?? "xMidYMid meet")
    }
    private func viewBoxMapping(_ v: [CGFloat], width w: CGFloat, height h: CGFloat,
                                x: CGFloat, y: CGFloat, aspect: String) -> CGAffineTransform {
        var sx = w / v[2], sy = h / v[3], tx = x, ty = y
        if aspect != "none" {
            sx = aspect.hasSuffix("slice") ? max(sx, sy) : min(sx, sy); sy = sx
            let align: CGFloat = aspect.hasPrefix("xMinYMin") ? 0 : aspect.hasPrefix("xMaxYMax") ? 1 : 0.5
            tx += (w - v[2] * sx) * align; ty += (h - v[3] * sy) * align
        }
        return CGAffineTransform(a: sx, b: 0, c: 0, d: sy, tx: tx - v[0] * sx, ty: ty - v[1] * sy)
    }
    private func requiresInstanceExpansion(_ e: Element) -> Bool {
        e.name == "svg" || e.attrs["fill-opacity"] != nil || e.attrs["stroke-opacity"] != nil ||
            e.children.contains(where: requiresInstanceExpansion) ||
            e.refs.compactMap { ids[$0] }.contains(where: requiresInstanceExpansion)
    }
    private func xml(_ n: Element, attributes: [String: String]? = nil, viewport: CGSize,
                     instance: Bool = false, inheritedPaintOpacity: [String: String] = [:],
                     inheritedPaint: [String: String] = [:]) throws -> String {
        func escape(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        }
        func tag(_ name: String, _ attrs: [String: String], _ body: String) -> String {
            "<" + name + attrs.keys.sorted().map { " " + $0 + "=\"" + escape(attrs[$0]!) + "\"" }.joined() + ">" + body + "</" + name + ">"
        }
        var a = attributes ?? n.attrs, childViewport = viewport
        var paintOpacity = inheritedPaintOpacity
        var paint = inheritedPaint
        let container = ["svg", "g", "defs", "symbol", "clipPath"].contains(n.name)
        let paintOpacityKeys = ["fill-opacity", "stroke-opacity"]
        for key in paintOpacityKeys {
            if let value = a[key] { paintOpacity[key] = value }
            // CoreSVG multiplies group paint opacity into child overrides.
            // SVG paint opacity inherits by replacement; resolve it onto the
            // painted elements instead, keeping group `opacity` independent.
            if container {
                a.removeValue(forKey: key)
            } else if let value = paintOpacity[key] { a[key] = value }
        }
        for key in ["fill", "stroke"] {
            if let value = a[key] { paint[key] = value }
            // CoreSVG also drops leaf paint opacity when only the paint is
            // inherited. Resolve both together on this instance's primitives.
            if !container, paintOpacity[key + "-opacity"] != nil, let value = paint[key] { a[key] = value }
        }
        if n.name == "svg", n !== root {
            (a, childViewport) = try viewportAttributes(a, viewport: viewport)
        }
        if instance { a.removeValue(forKey: "id") }
        if n.name == "use", let href = a["xlink:href"], let target = ids[String(href.dropFirst())],
           !paintOpacity.isEmpty || requiresInstanceExpansion(target) {
            // Shared definitions keep authored attributes. Each expanded use
            // resolves viewport dimensions and paint inheritance independently.
            let x = a.removeValue(forKey: "x") ?? "0", y = a.removeValue(forKey: "y") ?? "0"
            let width = a.removeValue(forKey: "width"), height = a.removeValue(forKey: "height")
            a.removeValue(forKey: "xlink:href")
            for key in paintOpacityKeys { a.removeValue(forKey: key) }
            let body: String
            if target.name == "symbol" {
                var attrs = target.attrs
                attrs.removeValue(forKey: "id")
                attrs["width"] = width ?? attrs["width"] ?? String(Double(viewport.width))
                attrs["height"] = height ?? attrs["height"] ?? String(Double(viewport.height))
                let svg = Element("svg", attrs); svg.children = target.children
                body = try xml(svg, viewport: viewport, instance: true, inheritedPaintOpacity: paintOpacity, inheritedPaint: paint)
            } else { body = try xml(target, viewport: viewport, instance: true, inheritedPaintOpacity: paintOpacity, inheritedPaint: paint) }
            return tag("g", a, tag("g", ["transform": "translate(\(x),\(y))"], body))
        }
        let body = try n.children.map { try xml($0, viewport: childViewport, instance: instance, inheritedPaintOpacity: paintOpacity, inheritedPaint: paint) }.joined()
        if n.name == "svg", n !== root, a["overflow"] == "visible" {
            // CoreSVG clips nested SVGs even with visible overflow. Keep its
            // validated viewport mapping while expressing the unclipped body.
            let t = try viewportMapping(a)
            for key in ["x", "y", "width", "height", "viewBox", "preserveAspectRatio"] { a.removeValue(forKey: key) }
            return tag("g", a, tag("g", ["transform": "matrix(\(t.a),\(t.b),\(t.c),\(t.d),\(t.tx),\(t.ty))"], body))
        }
        return tag(n.name, a, body)
    }
    static func inspect(_ data: Data, dark: Bool) throws -> NativeSafeSVG {
        guard !data.isEmpty, data.count <= 8 * 1024 * 1024,
              let raw = String(data: data, encoding: .utf8), !raw.contains("<!"), !raw.contains("<?") else {
            throw NativeObjectError.unsupported("svg-resource-or-limit")
        }
        let result = NativeSafeSVG(dark: dark), parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false; parser.delegate = result
        guard parser.parse(), result.failure == nil, result.stack.isEmpty, let root = result.root else {
            throw result.failure ?? NativeObjectError.unsupported("svg-xml")
        }
        try result.validate(root)
        try result.clipHiddenSymbolInstances(root)
        return result
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            failure = .unsupported("svg-text-or-font"); parser.abortParsing()
        }
    }
    func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? { nil }
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        do {
            guard stack.count < 128, elements.count < 20000, attributes.count <= 64 else { throw NativeObjectError.budget }
            let common: Set<String> = ["xmlns", "xmlns:xlink", "id", "role", "focusable", "aria-label", "aria-hidden", "class", "style", "transform", "fill", "fill-rule", "fill-opacity", "stroke", "stroke-width", "stroke-linecap", "stroke-linejoin", "stroke-miterlimit", "stroke-dasharray", "stroke-dashoffset", "stroke-opacity", "opacity", "clip-path", "clip-rule", "data-mml-node", "data-mjx-texclass", "data-c", "data-latex"]
            let local: [String: Set<String>] = [
                "svg": ["viewBox", "x", "y", "width", "height", "preserveAspectRatio"], "g": [], "defs": [],
                "symbol": ["viewBox", "width", "height", "preserveAspectRatio", "overflow"],
                "use": ["href", "xlink:href", "x", "y", "width", "height"],
                "path": ["d"], "rect": ["x", "y", "width", "height", "rx", "ry"], "circle": ["cx", "cy", "r"],
                "ellipse": ["cx", "cy", "rx", "ry"], "line": ["x1", "y1", "x2", "y2"], "polygon": ["points"], "polyline": ["points"],
                "clipPath": ["clipPathUnits"],
                "linearGradient": ["href", "xlink:href", "x1", "y1", "x2", "y2", "gradientUnits", "gradientTransform", "spreadMethod"],
                "radialGradient": ["href", "xlink:href", "cx", "cy", "r", "fx", "fy", "fr", "gradientUnits", "gradientTransform", "spreadMethod"],
                "stop": ["offset", "stop-color", "stop-opacity"],
                "image": ["href", "xlink:href", "x", "y", "width", "height", "preserveAspectRatio"]]
            guard let allowed = local[name], Set(attributes.keys).isSubset(of: common.union(allowed)),
                  !stack.isEmpty || root == nil && name == "svg" else {
                throw NativeObjectError.unsupported("svg-element-or-attribute")
            }
            if let parent = stack.last {
                if ["linearGradient", "radialGradient"].contains(parent.name), parent.children.count >= 256 { throw NativeObjectError.budget }
                if ["use", "path", "stop", "image"].contains(parent.name) { throw NativeObjectError.unsupported("svg-child") }
                if ["linearGradient", "radialGradient"].contains(parent.name), name != "stop" { throw NativeObjectError.unsupported("svg-gradient-child") }
                if name == "stop", !["linearGradient", "radialGradient"].contains(parent.name) { throw NativeObjectError.unsupported("svg-stop-parent") }
            }
            let e = Element(name, attributes)
            if name == "svg", !stack.isEmpty { rich = true }
            try attributesChecked(e)
            if let id = e.attrs["id"] {
                guard id.range(of: "^[A-Za-z0-9_.:-]{1,128}$", options: .regularExpression) != nil, ids[id] == nil else { throw NativeObjectError.unsupported("svg-id") }
                ids[id] = e
            }
            if let parent = stack.last { parent.children.append(e) } else { root = e }
            stack.append(e); elements.append(e)
        } catch { failure = (error as? NativeObjectError) ?? .invalidGeometry; parser.abortParsing() }
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) { _ = stack.popLast() }

    private func attributesChecked(_ e: Element) throws {
        if let ns = e.attrs["xmlns"], ns != "http://www.w3.org/2000/svg" { throw NativeObjectError.unsupported("svg-namespace") }
        if let ns = e.attrs["xmlns:xlink"], ns != "http://www.w3.org/1999/xlink" { throw NativeObjectError.unsupported("svg-namespace") }
        if let cls = e.attrs["class"], !cls.isEmpty { throw NativeObjectError.unsupported("svg-css-class") }
        if let css = e.attrs.removeValue(forKey: "style") {
            for declaration in css.split(separator: ";") {
                let p = declaration.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                guard p.count == 2 else { throw NativeObjectError.unsupported("svg-style") }
                switch p[0] {
                case "width", "height":
                    guard e.name == "svg", p[1].range(of: "^[0-9]+(?:\\.[0-9]+)?(?:em|pt|px)$", options: .regularExpression) != nil else { throw NativeObjectError.unsupported("svg-style") }
                    let raw = p[1]
                    guard let value = Double(raw.dropLast(2)), value.isFinite else { throw NativeObjectError.invalidGeometry }
                    let scale = raw.hasSuffix("em") ? 16.0 : raw.hasSuffix("pt") ? 4.0 / 3 : 1
                    e.attrs[p[0]] = String(value * scale)
                case "display": guard e.name == "svg", p[1] == "block" else { throw NativeObjectError.unsupported("svg-style") }
                case "overflow":
                    guard e.name == "svg", p[1] == "visible" else { throw NativeObjectError.unsupported("svg-style") }
                    e.attrs["overflow"] = "visible"
                case "fill", "stroke", "stop-color", "stop-opacity", "fill-opacity", "stroke-opacity", "opacity", "stroke-width", "clip-path", "fill-rule", "clip-rule": e.attrs[p[0]] = p[1]
                default: throw NativeObjectError.unsupported("svg-style")
                }
            }
        }
        let numeric: Set<String> = ["x", "y", "x1", "y1", "x2", "y2", "cx", "cy", "r", "rx", "ry", "fx", "fy", "fr", "stroke-width", "stroke-miterlimit", "stroke-dashoffset"]
        let opacity: Set<String> = ["opacity", "fill-opacity", "stroke-opacity", "stop-opacity"]
        for (key, value) in e.attrs {
            if numeric.contains(key) || opacity.contains(key) || key == "offset" {
                let percent = value.hasSuffix("%")
                if percent && !(e.name.hasSuffix("Gradient") || key == "offset") { throw NativeObjectError.unsupported("svg-percent-coordinate") }
                let values = try numbers(percent ? String(value.dropLast()) : value)
                guard values.count == 1 else { throw NativeObjectError.invalidGeometry }
                let v = values[0]
                if opacity.contains(key), !(0...1).contains(v) { throw NativeObjectError.invalidGeometry }
                if key == "offset", !(0...(percent ? 100 : 1)).contains(v) { throw NativeObjectError.invalidGeometry }
                if ["r", "rx", "ry", "fr", "stroke-width"].contains(key), v < 0 { throw NativeObjectError.invalidGeometry }
                if key == "stroke-miterlimit", v < 1 { throw NativeObjectError.invalidGeometry }
                e.coordinate = max(e.coordinate, abs(v))
                if ["svg", "image"].contains(e.name), ["x", "y"].contains(key) { e.attrs[key] = String(Double(v)) }
            }
            if ["width", "height"].contains(key) {
                let regex = try NSRegularExpression(pattern: "^(\\+?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:[eE][-+]?[0-9]+)?)(pt|px|em|ex)?$")
                guard let m = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
                      let range = Range(m.range(at: 1), in: value), let n = Double(value[range]), n.isFinite, n <= 1e8 else { throw NativeObjectError.invalidGeometry }
                e.coordinate = max(e.coordinate, n)
            }
            if ["fill", "stroke", "stop-color"].contains(key) {
                if key == "stop-color" && value == "none" { throw NativeObjectError.unsupported("svg-stop-color") }
                if value == "currentColor" { e.attrs[key] = dark ? "#ffffff" : "#000000" }
                else if value.hasPrefix("url(") { _ = try reference(value, url: true); rich = true }
                else if !["none", "black", "white"].contains(value), value.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) == nil { throw NativeObjectError.unsupported("svg-paint") }
            }
            if key == "clip-path" { if value != "none" { _ = try reference(value, url: true) }; rich = true }
            if ["href", "xlink:href"].contains(key), e.name != "image" { _ = try reference(value, url: false); rich = true }
            if ["transform", "gradientTransform"].contains(key) {
                let t = try affine(value)
                if key == "transform" { e.transform = t }
            }
            let enums: [String: Set<String>] = ["fill-rule": ["evenodd", "nonzero"], "clip-rule": ["evenodd", "nonzero"],
                "stroke-linecap": ["butt", "round", "square"], "stroke-linejoin": ["miter", "round", "bevel"],
                "clipPathUnits": ["userSpaceOnUse", "objectBoundingBox"], "gradientUnits": ["userSpaceOnUse", "objectBoundingBox"],
                "spreadMethod": ["pad", "reflect", "repeat"], "overflow": ["visible", "hidden"],
                "preserveAspectRatio": ["xMidYMid meet", "none", "xMinYMin meet", "xMaxYMax meet", "xMidYMid slice"]]
            if let allowed = enums[key], !allowed.contains(value) { throw NativeObjectError.unsupported("svg-attribute-value") }
            if key == "stroke-dasharray", value != "none" {
                let n = try numbers(value)
                guard !n.isEmpty, n.count <= 128, n.allSatisfy({ $0 >= 0 }), n.contains(where: { $0 > 0 }) else { throw NativeObjectError.invalidGeometry }
            }
            if key == "points" {
                let n = try numbers(value)
                guard n.count >= 4, n.count % 2 == 0, n.count <= 100000 else { throw NativeObjectError.invalidGeometry }
                e.work += n.count; e.coordinate = max(e.coordinate, n.map(abs).max()!)
            }
        }
        if let viewBox = e.attrs["viewBox"] {
            let n = try numbers(viewBox)
            guard n.count == 4, n[2] > 0, n[3] > 0 else { throw NativeObjectError.invalidGeometry }
            e.coordinate = max(e.coordinate, n.map(abs).max()!)
        }
        if e.name == "svg" {
            for key in ["width", "height"] where e.attrs[key] != nil {
                guard try numbers(e.attrs[key]!.replacingOccurrences(of: "(?:pt|px|em|ex)$", with: "", options: .regularExpression)).first! > 0 else {
                    throw NativeObjectError.invalidGeometry
                }
            }
        }
        if e.name == "image" {
            guard (e.attrs["href"] == nil) != (e.attrs["xlink:href"] == nil),
                  let href = e.attrs["href"] ?? e.attrs["xlink:href"] else { throw NativeObjectError.unsupported("svg-image") }
            let prefix = "data:image/png;base64,", limit = 8 * 1024 * 1024
            guard href.hasPrefix(prefix), href.utf8.count <= prefix.utf8.count + 4 * ((limit + 2) / 3) else { throw NativeObjectError.unsupported("svg-image") }
            let encoded = String(href.dropFirst(prefix.count))
            guard let bytes = Data(base64Encoded: encoded), bytes.count <= limit,
                  bytes.base64EncodedString() == encoded,
                  bytes.starts(with: [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]) else { throw NativeObjectError.unsupported("svg-image") }
            for key in ["width", "height"] {
                guard let raw = e.attrs[key], let side = Double(raw), side.isFinite, side > 0, side <= 4096 else { throw NativeObjectError.invalidGeometry }
            }
            rich = true; hasEmbeddedPNG = true
        }
        if e.attrs["clip-rule"] != nil { rich = true }
        if let d = e.attrs["d"] {
            let info = try validatePath(d)
            e.work += info.0; e.coordinate = max(e.coordinate, info.1)
            if info.2 { rich = true }
        }
        if ["defs", "symbol", "use", "clipPath", "linearGradient", "radialGradient", "stop"].contains(e.name) { rich = true }
        if ["g", "svg"].contains(e.name), let alpha = e.attrs["opacity"], Double(alpha) != 1 { rich = true }
        if e.name == "rect", e.attrs["rx"] != nil || e.attrs["ry"] != nil { rich = true }
        if let aspect = e.attrs["preserveAspectRatio"], aspect != "xMidYMid meet" { rich = true }
    }
    private func reference(_ value: String, url: Bool) throws -> String {
        let pattern = url ? "^url\\(#([A-Za-z0-9_.:-]{1,128})\\)$" : "^#([A-Za-z0-9_.:-]{1,128})$"
        let regex = try NSRegularExpression(pattern: pattern)
        guard let m = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)), let r = Range(m.range(at: 1), in: value) else { throw NativeObjectError.unsupported("external-svg-reference") }
        return String(value[r])
    }
    private func validate(_ root: Element) throws {
        let v = try numbers(root.attrs["viewBox"] ?? "")
        guard v.count == 4, v[2] > 0, v[3] > 0 else { throw NativeObjectError.invalidGeometry }
        box = CGRect(x: v[0], y: v[1], width: v[2], height: v[3]); viewport = box.size
        for (i, key) in ["width", "height"].enumerated() {
            if let raw = root.attrs[key], raw.range(of: "^(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(pt|px)?$", options: .regularExpression) != nil {
                let n = Double(raw.replacingOccurrences(of: "pt", with: "").replacingOccurrences(of: "px", with: ""))!
                if i == 0 { viewport.width = n } else { viewport.height = n }
            }
        }
        for e in elements {
            if let a = e.attrs["href"], let b = e.attrs["xlink:href"], a != b { throw NativeObjectError.unsupported("svg-reference-conflict") }
            for key in ["href", "xlink:href", "clip-path", "fill", "stroke", "stop-color"] {
                if e.name == "image" && ["href", "xlink:href"].contains(key) { continue }
                guard let value = e.attrs[key], value.hasPrefix("#") && ["href", "xlink:href"].contains(key) || value.hasPrefix("url(") else { continue }
                let targetID = try reference(value, url: value.hasPrefix("url("))
                guard let target = ids[targetID] else { throw NativeObjectError.unsupported("svg-unresolved-reference") }
                if key == "clip-path", target.name != "clipPath" { throw NativeObjectError.unsupported("svg-reference-type") }
                if ["fill", "stroke"].contains(key), !["linearGradient", "radialGradient"].contains(target.name) { throw NativeObjectError.unsupported("svg-reference-type") }
                if key == "href" || key == "xlink:href" {
                    if e.name == "use", !["g", "symbol", "path", "rect", "circle", "ellipse", "line", "polygon", "polyline", "use"].contains(target.name) { throw NativeObjectError.unsupported("svg-reference-type") }
                    if e.name.hasSuffix("Gradient"), !target.name.hasSuffix("Gradient") { throw NativeObjectError.unsupported("svg-reference-type") }
                }
                if !e.refs.contains(targetID) { e.refs.append(targetID) }
            }
            // CoreSVG's established xlink path also represents SVG2 href. Only
            // validated internal IDs are normalized; external URLs never arrive.
            if let href = e.attrs.removeValue(forKey: "href") { e.attrs["xlink:href"] = href }
        }
        var active = Set<ObjectIdentifier>(), total = 0
        func walk(_ e: Element, _ inherited: CGAffineTransform, _ depth: Int, _ viewport: CGSize) throws {
            let id = ObjectIdentifier(e)
            guard !active.contains(id), depth <= 128 else { throw NativeObjectError.unsupported("svg-reference-cycle-or-depth") }
            active.insert(id); defer { active.remove(id) }
            total += e.work
            guard total <= 300000 else { throw NativeObjectError.budget }
            var transform = e.transform.concatenating(inherited)
            if e.name == "use" {
                transform = CGAffineTransform(translationX: Double(e.attrs["x"] ?? "0") ?? 0, y: Double(e.attrs["y"] ?? "0") ?? 0).concatenating(transform)
            }
            var childViewport = viewport
            if e.name == "svg", e !== root {
                let (attrs, resolvedViewport) = try viewportAttributes(e.attrs, viewport: viewport)
                childViewport = resolvedViewport
                transform = try viewportMapping(attrs).concatenating(transform)
            }
            let linear = max(abs(transform.a) + abs(transform.c), abs(transform.b) + abs(transform.d))
            guard [transform.a, transform.b, transform.c, transform.d, transform.tx, transform.ty].allSatisfy({ $0.isFinite && abs($0) <= 1e9 }),
                  e.coordinate * linear + max(abs(transform.tx), abs(transform.ty)) <= 1e9 else { throw NativeObjectError.invalidGeometry }
            for child in e.children + e.refs.compactMap({ ids[$0] }) { try walk(child, transform, depth + 1, childViewport) }
        }
        try walk(root, .identity, 0, box.size)
    }
    // CoreSVG ignores symbol overflow and parts of its viewBox mapping. Express
    // hidden instances with validated SVG groups/transforms/clips before decode;
    // primitive painting remains with the existing native consumer.
    private func clipHiddenSymbolInstances(_ root: Element) throws {
        let originalElements = elements
        let uses = originalElements.filter { e in
            e.name == "use" && e.refs.contains { ids[$0]?.name == "symbol" && ids[$0]?.attrs["overflow"] == "hidden" }
        }
        guard !uses.isEmpty else { return }
        func side(_ raw: String?) throws -> CGFloat {
            guard let raw = raw else { throw NativeObjectError.unsupported("svg-symbol-viewport-size") }
            let suffix = raw.hasSuffix("pt") ? "pt" : raw.hasSuffix("px") ? "px" : ""
            let value = suffix.isEmpty ? raw : String(raw.dropLast(2))
            guard let n = Double(value), n.isFinite, n > 0, n <= 1e8 else {
                // Do not guess an implicit or font-relative viewport from the
                // root, especially when a symbol is itself instanced elsewhere.
                throw NativeObjectError.unsupported("svg-symbol-viewport-size")
            }
            return CGFloat(n * (suffix == "pt" ? 4.0 / 3 : 1))
        }
        var serial = 0
        func identifier() -> String {
            var value: String
            repeat { serial += 1; value = "native-symbol-clip-\(serial)" } while ids[value] != nil
            return value
        }
        func register(_ element: Element) throws {
            guard elements.count < 20000 else { throw NativeObjectError.budget }
            try attributesChecked(element); elements.append(element)
        }
        let definitions = Element("defs", [:])
        var contents = [ObjectIdentifier: Element](), wrappers = [ObjectIdentifier: Element]()
        for use in uses {
            guard let symbol = use.refs.compactMap({ ids[$0] }).first(where: { $0.name == "symbol" }) else {
                throw NativeObjectError.unsupported("svg-symbol-reference")
            }
            let w = try side(use.attrs["width"] ?? symbol.attrs["width"])
            let h = try side(use.attrs["height"] ?? symbol.attrs["height"])
            let x = CGFloat(Double(use.attrs["x"] ?? "0") ?? 0), y = CGFloat(Double(use.attrs["y"] ?? "0") ?? 0)
            let mapping: CGAffineTransform
            if let raw = symbol.attrs["viewBox"] {
                mapping = viewBoxMapping(try numbers(raw), width: w, height: h, x: x, y: y,
                                         aspect: symbol.attrs["preserveAspectRatio"] ?? "xMidYMid meet")
            } else {
                mapping = CGAffineTransform(translationX: x, y: y)
            }
            let content: Element
            if let existing = contents[ObjectIdentifier(symbol)] { content = existing }
            else {
                var attrs = symbol.attrs
                for key in ["id", "viewBox", "width", "height", "preserveAspectRatio", "overflow"] { attrs.removeValue(forKey: key) }
                let id = identifier(); attrs["id"] = id
                content = Element("g", attrs)
                // Move, do not duplicate IDs or expand a symbol per instance.
                // Original symbol overflow remains in the validated declaration;
                // caller asset/HTML bytes are never changed.
                content.children = symbol.children; symbol.children = []
                try register(content); ids[id] = content
                contents[ObjectIdentifier(symbol)] = content; definitions.children.append(content)
            }
            let id = identifier()
            let rect = Element("rect", ["x": String(Double(x)), "y": String(Double(y)), "width": String(Double(w)), "height": String(Double(h))])
            let clip = Element("clipPath", ["id": id, "clipPathUnits": "userSpaceOnUse"])
            clip.children = [rect]; ids[id] = clip; definitions.children.append(clip)
            let clipped = Element("g", ["clip-path": "url(#\(id))"])
            let mapped = Element("g", ["transform": "matrix(\(mapping.a),0,0,\(mapping.d),\(mapping.tx - x),\(mapping.ty - y))"])
            let transformed = Element("g", [:]), originalClip = Element("g", [:])
            let translated = Element("g", ["transform": "translate(\(x),\(y))"])
            if let transform = use.attrs.removeValue(forKey: "transform") { transformed.attrs["transform"] = transform }
            if let oldClip = use.attrs.removeValue(forKey: "clip-path") { originalClip.attrs["clip-path"] = oldClip }
            var instance = transformed
            if let originalID = use.attrs.removeValue(forKey: "id") {
                // CoreSVG also omits a referenced root group's transform. Keep
                // the reference ID on a neutral parent, with the transform below.
                instance = Element("g", ["id": originalID])
                instance.children = [transformed]; ids[originalID] = instance
                try register(instance)
            }
            for key in ["x", "y", "width", "height"] { use.attrs.removeValue(forKey: key) }
            use.attrs["xlink:href"] = "#" + content.attrs["id"]!
            use.transform = .identity; use.refs.removeAll()
            mapped.children = [use]; originalClip.children = [mapped]
            translated.children = [originalClip]; clipped.children = [translated]; transformed.children = [clipped]
            wrappers[ObjectIdentifier(use)] = instance
            for element in [rect, clip, clipped, mapped, originalClip, translated, transformed] { try register(element) }
        }
        for parent in originalElements + Array(contents.values) {
            parent.children = parent.children.map { wrappers[ObjectIdentifier($0)] ?? $0 }
        }
        try register(definitions); root.children.insert(definitions, at: 0)
        // Recheck generated IDs, references and composed viewport transforms at
        // the same trust boundary, including total work, depth and node budgets.
        try validate(root)
    }
    // Lexical/arity/flag/finite/current-point validation, including SVG arc A/a.
    // AppKit handles the curve; this prevents malformed path parser fallbacks.
    private func validatePath(_ text: String) throws -> (Int, CGFloat, Bool) {
        let regex = try NSRegularExpression(pattern: "[A-Za-z]|[-+]?(?:[0-9]*\\.[0-9]+|[0-9]+\\.?[0-9]*)(?:[eE][-+]?[0-9]+)?")
        var tokens = [String](), end = text.startIndex
        for m in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            let r = Range(m.range, in: text)!
            guard text[end..<r.lowerBound].allSatisfy({ $0.isWhitespace || $0 == "," }) else { throw NativeObjectError.invalidGeometry }
            tokens.append(String(text[r])); end = r.upperBound
        }
        guard tokens.count <= 300000, text[end...].allSatisfy({ $0.isWhitespace || $0 == "," }) else { throw NativeObjectError.budget }
        var i = 0, command = "", point = CGPoint.zero, start = CGPoint.zero, maximum: CGFloat = 0, arc = false
        let counts = ["M": 2, "L": 2, "H": 1, "V": 1, "C": 6, "S": 4, "Q": 4, "T": 2, "A": 7, "Z": 0]
        while i < tokens.count {
            if tokens[i].first!.isLetter { command = tokens[i]; i += 1 }
            let upper = command.uppercased(), relative = command == command.lowercased()
            guard let count = counts[upper], i + count <= tokens.count, i != 1 || upper == "M" else { throw NativeObjectError.invalidGeometry }
            if upper == "Z" { point = start; command = ""; continue }
            var n = [CGFloat]()
            for j in 0..<count {
                guard let value = Double(tokens[i + j]), value.isFinite, abs(value) <= 1e8 else { throw NativeObjectError.invalidGeometry }
                n.append(value)
            }
            if upper == "A" { guard n[0] >= 0, n[1] >= 0, [CGFloat(0), 1].contains(n[3]), [CGFloat(0), 1].contains(n[4]) else { throw NativeObjectError.invalidGeometry }; arc = true }
            if upper == "H" { point.x = n[0] + (relative ? point.x : 0) }
            else if upper == "V" { point.y = n[0] + (relative ? point.y : 0) }
            else { point = CGPoint(x: n[count - 2] + (relative ? point.x : 0), y: n[count - 1] + (relative ? point.y : 0)) }
            maximum = max(maximum, max(abs(point.x), abs(point.y)) + (n.map(abs).max() ?? 0))
            guard maximum <= 1e8 else { throw NativeObjectError.invalidGeometry }
            if upper == "M" { start = point; command = relative ? "l" : "L" }
            i += count
        }
        return (tokens.count, maximum, arc)
    }
}
