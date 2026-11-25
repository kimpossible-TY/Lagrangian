import AppKit

/// Exact adapter of svg.reader-logo-mark (240 × 220), never a replacement drawing.
enum NativeBrandMark {
    enum Phase: String, CaseIterable { case idle, busy, reconnecting, offline, error, held, completed }
    struct Stroke {
        let width: CGFloat
        let opacity: CGFloat
        let dash: [CGFloat] // SVG pathLength=100 units.
    }
    struct Layers {
        let base: Stroke
        let halo: Stroke?
        let beam: Stroke?
        let color: NSColor
    }
    static let viewBox = NSSize(width: 240, height: 220)
    static let path: CGPath = {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 31, y: 29))
        path.addCurve(to: CGPoint(x: 75, y: 48), control1: CGPoint(x: 48, y: 45), control2: CGPoint(x: 63, y: 53))
        path.addCurve(to: CGPoint(x: 93, y: 20), control1: CGPoint(x: 85, y: 45), control2: CGPoint(x: 88, y: 30))
        path.addCurve(to: CGPoint(x: 108, y: 17), control1: CGPoint(x: 97, y: 12), control2: CGPoint(x: 105, y: 10))
        path.addCurve(to: CGPoint(x: 91, y: 44), control1: CGPoint(x: 112, y: 26), control2: CGPoint(x: 103, y: 38))
        path.addCurve(to: CGPoint(x: 78, y: 60), control1: CGPoint(x: 83, y: 48), control2: CGPoint(x: 79, y: 49))
        path.addCurve(to: CGPoint(x: 67, y: 160), control1: CGPoint(x: 76, y: 100), control2: CGPoint(x: 78, y: 137))
        path.addCurve(to: CGPoint(x: 34, y: 201), control1: CGPoint(x: 59, y: 180), control2: CGPoint(x: 45, y: 199))
        path.addCurve(to: CGPoint(x: 23, y: 174), control1: CGPoint(x: 19, y: 204), control2: CGPoint(x: 16, y: 187))
        path.addCurve(to: CGPoint(x: 66, y: 169), control1: CGPoint(x: 32, y: 158), control2: CGPoint(x: 51, y: 163))
        path.addCurve(to: CGPoint(x: 145, y: 201), control1: CGPoint(x: 91, y: 181), control2: CGPoint(x: 113, y: 200))
        path.addCurve(to: CGPoint(x: 215, y: 164), control1: CGPoint(x: 183, y: 204), control2: CGPoint(x: 211, y: 189))
        path.addCurve(to: CGPoint(x: 198, y: 141), control1: CGPoint(x: 219, y: 146), control2: CGPoint(x: 208, y: 137))
        path.addCurve(to: CGPoint(x: 196, y: 153), control1: CGPoint(x: 190, y: 144), control2: CGPoint(x: 191, y: 151))
        return path
    }()

    // Numerical arc length only converts SVG pathLength dash units to CG points.
    // Geometry itself always uses the original cubic curves above.
    static let length: CGFloat = {
        var previous = CGPoint.zero, total: CGFloat = 0
        path.applyWithBlock { pointer in
            let element = pointer.pointee
            if element.type == .moveToPoint { previous = element.points[0] }
            else if element.type == .addCurveToPoint {
                let start = previous, a = element.points[0], b = element.points[1], end = element.points[2]
                for step in 1...256 {
                    let t = CGFloat(step) / 256, u = 1 - t
                    let point = CGPoint(x: u*u*u*start.x + 3*u*u*t*a.x + 3*u*t*t*b.x + t*t*t*end.x,
                                        y: u*u*u*start.y + 3*u*u*t*a.y + 3*u*t*t*b.y + t*t*t*end.y)
                    total += hypot(point.x - previous.x, point.y - previous.y); previous = point
                }
            }
        }
        return total
    }()

    static func layers(phase: Phase, preferences: NativeAppDesign.Preferences) -> Layers {
        let p = NativeAppDesign.palette(preferences)
        let busy = phase == .busy
        let strong = preferences.increasedContrast || preferences.reduceTransparency
        let base = Stroke(width: 11, opacity: strong || preferences.reduceMotion ? 1 : (busy ? 0.62 : (phase == .offline ? 0.5 : 0.9)),
                          dash: phase == .offline || phase == .reconnecting ? [5, 3] : [])
        return Layers(base: base,
                      halo: busy && !preferences.reduceMotion && !strong ? Stroke(width: 15, opacity: 0.3, dash: [8, 92]) : nil,
                      beam: busy && !preferences.reduceMotion ? Stroke(width: 8, opacity: 1, dash: [8, 92]) : nil,
                      color: phase == .error ? p.error : (phase == .held ? p.warning : (busy || phase == .completed ? p.accent : p.ink)))
    }
    /// Uniform fit, centered letterboxing, no crop/stretch; callers should give ≥24pt.
    static func transform(in rect: NSRect) -> CGAffineTransform {
        guard rect.width.isFinite, rect.height.isFinite, rect.minX.isFinite, rect.minY.isFinite,
              rect.width > 0, rect.height > 0 else { return CGAffineTransform(scaleX: 0, y: 0) }
        let scale = min(rect.width / viewBox.width, rect.height / viewBox.height)
        return CGAffineTransform(a: scale, b: 0, c: 0, d: scale,
                                 tx: rect.midX - viewBox.width * scale / 2, ty: rect.midY - viewBox.height * scale / 2)
    }
    static func draw(in rect: NSRect, context: CGContext, phase: Phase, preferences: NativeAppDesign.Preferences) {
        let layers = layers(phase: phase, preferences: preferences)
        context.saveGState(); defer { context.restoreGState() }
        context.concatenate(transform(in: rect))
        context.setLineCap(.round); context.setLineJoin(.round)
        // Original order: base, halo, beam. No blur/timers; static native low-motion treatment.
        for stroke in [layers.base, layers.halo, layers.beam].compactMap({ $0 }) {
            context.setStrokeColor(layers.color.withAlphaComponent(stroke.opacity).cgColor)
            context.setLineWidth(stroke.width)
            context.setLineDash(phase: 0, lengths: stroke.dash.map { $0 * length / 100 })
            context.addPath(path); context.strokePath()
        }
    }
    /// Monochrome menu-bar adapter of the canonical path. AppKit supplies its tint.
    static func statusImage(phase: Phase) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.saveGState()
            context.concatenate(transform(in: rect.insetBy(dx: 1, dy: 1)))
            context.setStrokeColor(NSColor.black.cgColor)
            context.setLineWidth(11); context.setLineCap(.round); context.setLineJoin(.round)
            context.setLineDash(phase: 0, lengths: (phase == .offline || phase == .reconnecting ? [5, 3] :
                (phase == .busy ? [18, 6] : [])).map { CGFloat($0) * length / 100 })
            context.addPath(path); context.strokePath()
            context.restoreGState()
            NSColor.black.setFill()
            if phase == .completed {
                NSBezierPath(ovalIn: NSRect(x: 14, y: 14, width: 3, height: 3)).fill()
            } else if phase == .error {
                NSRect(x: 15, y: 10, width: 2, height: 4).fill()
                NSBezierPath(ovalIn: NSRect(x: 15, y: 15, width: 2, height: 2)).fill()
            } else if phase == .held {
                NSRect(x: 13, y: 12, width: 1, height: 5).fill()
                NSRect(x: 16, y: 12, width: 1, height: 5).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Lagrangian"
        return image
    }
}

final class NativeBrandMarkView: NSView {
    var phase: NativeBrandMark.Phase = .idle { didSet { needsDisplay = true } }
    var showsRunningIndicator = false { didSet { needsDisplay = true } }
    var preferencesOverride: NativeAppDesign.Preferences? { didSet { needsDisplay = true } }
    private var observation: NativeDesignObservation?
    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 44, height: 41) }
    override init(frame: NSRect) { super.init(frame: frame); configure() }
    required init?(coder: NSCoder) { super.init(coder: coder); configure() }
    private func configure() {
        setAccessibilityElement(true); setAccessibilityRole(.image); setAccessibilityLabel("Lagrangian")
        observation = NativeDesignObservation(view: self)
    }
    override func accessibilityValue() -> Any? { phase.rawValue }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        NativeBrandMark.draw(in: bounds, context: context, phase: phase,
                             preferences: preferencesOverride ?? .current(appearance: effectiveAppearance))
        if showsRunningIndicator {
            NativeAppDesign.sage(preferencesOverride ?? .current(appearance: effectiveAppearance)).setFill()
            NSBezierPath(ovalIn: NSRect(x: bounds.maxX - 6, y: bounds.maxY - 6, width: 6, height: 6)).fill()
        }
    }
}
