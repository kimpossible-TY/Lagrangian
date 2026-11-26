import AppKit
import QuartzCore

/// Shared chrome and paper tokens. Typography and PDF ink remain renderer-owned.
enum NativeAppDesign {
    enum Theme: String, CaseIterable { case light, dark }
    struct Preferences {
        var theme: Theme
        var increasedContrast = false
        var reduceTransparency = false
        var reduceMotion = false

        static func current(appearance: NSAppearance) -> Preferences {
            let workspace = NSWorkspace.shared
            return Preferences(
                theme: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light,
                increasedContrast: workspace.accessibilityDisplayShouldIncreaseContrast,
                reduceTransparency: workspace.accessibilityDisplayShouldReduceTransparency,
                reduceMotion: workspace.accessibilityDisplayShouldReduceMotion)
        }
    }
    struct Palette {
        let paper, panel, track, pdfCanvas, codeBg, ink, secondaryInk, disabledInk: NSColor
        let accent, accentHover, onAccent, boundary, glassEdge, glassSpecular, rule: NSColor
        let wash, pressed, selection, highlight, highlightEdge, warning, error, reviewInk, sage: NSColor
        let scrim, glassTintDrawer, glassTintCapsule: NSColor
        var hover: NSColor { wash }
    }
    enum Spacing {
        static let tight: CGFloat = 4, small: CGFloat = 8, control: CGFloat = 12
        static let section: CGFloat = 20, page: CGFloat = 28
    }
    enum Shape {
        static let controlRadius: CGFloat = 6, panelRadius: CGFloat = 10
        static let floatingRadius: CGFloat = 16, minimumControlHeight: CGFloat = 32
        static let stroke: CGFloat = 1, strongStroke: CGFloat = 2, focusStroke: CGFloat = 3
    }
    enum Typography {
        enum Role: CaseIterable { case brandTitle, heading, control, caption }
        static func font(_ role: Role, scale: CGFloat = 1) -> NSFont {
            let scale = scale.isFinite ? max(1, scale) : 1
            switch role {
            case .brandTitle:
                let base = NSFont.systemFont(ofSize: 23 * scale, weight: .light)
                return base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: base.pointSize) } ?? base
            case .heading: return .systemFont(ofSize: 17 * scale, weight: .semibold)
            case .control: return .systemFont(ofSize: 13 * scale, weight: .medium)
            case .caption: return .systemFont(ofSize: 12 * scale)
            }
        }
    }
    static func color(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
    static func palette(_ preferences: Preferences) -> Palette {
        let dark = preferences.theme == .dark, hc = preferences.increasedContrast
        func token(_ light: UInt32, _ night: UInt32, _ highLight: UInt32, _ highNight: UInt32) -> NSColor {
            color(hc ? (dark ? highNight : highLight) : (dark ? night : light))
        }
        let panel = token(0xFFFCF5, 0x302E29, 0xFFFCF5, 0x2E2C27)
        let solid = hc || preferences.reduceTransparency
        return Palette(
            paper: token(0xF7F2E8, 0x24231F, 0xF7F2E8, 0x24231F), panel: panel,
            track: token(0xEAE3D5, 0x1C1B18, 0xE4DCCB, 0x181714),
            pdfCanvas: token(0xEDE7DA, 0x1C1B18, 0xE6DFD0, 0x181714),
            codeBg: token(0xEFE9DC, 0x2E2C27, 0xEAE3D3, 0x34322C),
            ink: token(0x292722, 0xF7F2E8, 0x1A1916, 0xFFFDF8),
            secondaryInk: token(0x625D53, 0xD0C9BC, 0x433F37, 0xE5DFD2),
            disabledInk: token(0x71695E, 0xC0B9AB, 0x575147, 0xCFC8BA),
            accent: token(0x514A83, 0xC6BEFF, 0x3B3469, 0xDCD6FF),
            accentHover: token(0x3E376B, 0xDBD5FF, 0x2B2552, 0xECE8FF),
            onAccent: token(0xFFFCF5, 0x24231F, 0xFFFFFF, 0x181714),
            boundary: token(0x81786A, 0xA59D90, 0x292722, 0xEEE8DC),
            glassEdge: token(0x292722, 0xF7F2E8, 0x292722, 0xEEE8DC).withAlphaComponent(hc ? 1 : 0.14),
            glassSpecular: hc ? .clear : color(dark ? 0xFFFDF8 : 0xFFFFFF).withAlphaComponent(dark ? 0.10 : 0.55),
            rule: token(0xDED8CB, 0x3D3A33, 0x81786A, 0xA59D90),
            wash: token(0xEEE8F5, 0x403C49, 0xE4DBF2, 0x464152),
            pressed: token(0xDED5ED, 0x514A62, 0xD1C4EA, 0x59526B),
            selection: token(0xE6DEF4, 0x49405E, 0xD9CEEE, 0x54496E),
            highlight: token(0xF0DFAA, 0x54472A, 0xEBD48E, 0x61512C),
            highlightEdge: token(0x8F6A1E, 0xDFC070, 0x6E4F12, 0xF0D589),
            warning: token(0x785517, 0xF2CF8C, 0x5E410E, 0xF9DC9E),
            error: token(0x9C302C, 0xFFB5AE, 0x821E1B, 0xFFC7C2),
            reviewInk: token(0xA82828, 0xFF9894, 0x8A1D1D, 0xFFB3AE),
            sage: token(0x56765B, 0xA9C6AA, 0x3B5940, 0xC2DFC3),
            scrim: color(dark ? 0 : 0x292722).withAlphaComponent(hc ? (dark ? 0.52 : 0.28) : (dark ? 0.36 : 0.14)),
            glassTintDrawer: panel.withAlphaComponent(solid ? 1 : (dark ? 0.86 : 0.84)),
            glassTintCapsule: panel.withAlphaComponent(solid ? 1 : (dark ? 0.90 : 0.88)))
    }
    static func sage(_ preferences: Preferences) -> NSColor { palette(preferences).sage }
    enum ButtonRole { case standard, primary, ghost }
    struct ButtonPaint {
        let fill, ink, edge: NSColor
        let lineWidth: CGFloat
    }
    static func buttonPaint(_ preferences: Preferences, role: ButtonRole,
                            enabled: Bool, hovered: Bool, pressed: Bool) -> ButtonPaint {
        let p = palette(preferences)
        let dark = preferences.theme == .dark
        if role == .ghost {
            return ButtonPaint(fill: enabled && pressed ? p.pressed : (enabled && hovered ? p.hover : .clear),
                               ink: enabled ? (hovered ? p.accent : p.ink) : p.disabledInk,
                               edge: preferences.increasedContrast ? p.boundary : .clear,
                               lineWidth: 1)
        }
        let fill: NSColor
        if !enabled { fill = p.paper }
        else if pressed { fill = p.pressed }
        else if hovered { fill = p.hover }
        else { fill = role == .primary ? p.accent : p.panel }
        let disabledEdge = color(dark ? (preferences.increasedContrast ? 0xA59D90 : 0x5C574E)
                                      : (preferences.increasedContrast ? 0x71695E : 0xB8B0A2))
        return ButtonPaint(fill: fill,
                           ink: !enabled ? p.disabledInk : (role == .primary && !pressed && !hovered ? p.onAccent : p.ink),
                           edge: !enabled ? disabledEdge : p.boundary,
                           lineWidth: preferences.increasedContrast ? Shape.strongStroke : Shape.stroke)
    }
}

/// Shared preference invalidation only; no global settings, state store or event interception.
final class NativeDesignObservation {
    private var token: NSObjectProtocol?
    init(view: NSView, onChange: (() -> Void)? = nil) {
        token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak view] _ in
            view?.needsLayout = true; view?.needsDisplay = true
            onChange?()
        }
    }
    deinit { if let token { NSWorkspace.shared.notificationCenter.removeObserver(token) } }
}

/// Usable opaque container for home/settings/reader/chat/floating chrome.
final class NativeDesignSurface: NSView {
    enum Role { case paper, panel, floating }
    var role: Role = .panel { didSet { needsDisplay = true } }
    var preferencesOverride: NativeAppDesign.Preferences? { didSet { needsDisplay = true } }
    private var observation: NativeDesignObservation?
    var preferences: NativeAppDesign.Preferences { preferencesOverride ?? .current(appearance: effectiveAppearance) }
    override init(frame: NSRect) { super.init(frame: frame); observation = NativeDesignObservation(view: self) }
    required init?(coder: NSCoder) { super.init(coder: coder); observation = NativeDesignObservation(view: self) }
    override var isOpaque: Bool { true }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        let p = NativeAppDesign.palette(preferences)
        p.paper.setFill(); bounds.fill()
        guard role != .paper else { return }
        let width = preferences.increasedContrast ? NativeAppDesign.Shape.strongStroke : NativeAppDesign.Shape.stroke
        let radius = role == .floating ? NativeAppDesign.Shape.floatingRadius : NativeAppDesign.Shape.panelRadius
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: width / 2, dy: width / 2), xRadius: radius, yRadius: radius)
        p.panel.setFill(); path.fill(); p.boundary.setStroke(); path.lineWidth = width; path.stroke()
    }
}

/// NSButton/NSButtonCell retain tracking, semantic activation, key equivalents,
/// target/action, focus and AX. Paint never dispatches commands or schedules motion.
final class NativeDesignButton: NSButton {
    var designRole: NativeAppDesign.ButtonRole = .standard { didSet { needsDisplay = true } }
    var preferencesOverride: NativeAppDesign.Preferences? { didSet { needsDisplay = true } }
    private(set) var isHovered = false
    private var hoverArea: NSTrackingArea?
    private var observation: NativeDesignObservation?
    private(set) var symbolName: String?
    var showsRunningIndicator = false { didSet { needsDisplay = true } }
    func setSymbol(_ name: String, label: String) {
        symbolName = name
        image = NSImage(systemSymbolName: name, accessibilityDescription: label)
        image?.isTemplate = true
        toolTip = label
        setAccessibilityLabel(label)
    }
    var preferences: NativeAppDesign.Preferences { preferencesOverride ?? .current(appearance: effectiveAppearance) }
    var paint: NativeAppDesign.ButtonPaint {
        NativeAppDesign.buttonPaint(preferences, role: designRole, enabled: isEnabled,
                                    hovered: isHovered, pressed: cell?.isHighlighted == true)
    }
    convenience init(title: String, target: AnyObject?, action: Selector?) {
        self.init(frame: .zero); self.title = title; self.target = target; self.action = action
    }
    override init(frame: NSRect) { super.init(frame: frame); configure() }
    required init?(coder: NSCoder) { super.init(coder: coder); configure() }
    private func configure() {
        cell = NativeDesignButtonCell(textCell: title)
        setButtonType(.momentaryPushIn); isBordered = true; bezelStyle = .regularSquare
        font = NativeAppDesign.Typography.font(.control); focusRingType = .exterior
        observation = NativeDesignObservation(view: self)
    }
    override var isEnabled: Bool {
        didSet { if !isEnabled { clearFeedback() }; needsDisplay = true }
    }
    override var intrinsicContentSize: NSSize {
        let size = super.intrinsicContentSize
        return NSSize(width: max(32, size.width + NativeAppDesign.Spacing.control * 2),
                      height: max(NativeAppDesign.Shape.minimumControlHeight, size.height + NativeAppDesign.Spacing.small))
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area); hoverArea = area
    }
    override func mouseEntered(with event: NSEvent) { isHovered = isEnabled; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { isHovered = false; needsDisplay = true }
    override func mouseDown(with event: NSEvent) {
        defer { highlight(false) }
        super.mouseDown(with: event)
    }
    override func cancelOperation(_ sender: Any?) { clearFeedback() }
    private func clearFeedback() { isHovered = false; highlight(false); needsDisplay = true }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); clearFeedback() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        contentTintColor = paint.ink
        super.draw(dirtyRect)
        if showsRunningIndicator {
            NativeAppDesign.sage(preferences).setFill()
            NSBezierPath(ovalIn: NSRect(x: bounds.maxX - 8, y: 2, width: 6, height: 6)).fill()
        }
    }
    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: NativeAppDesign.Shape.controlRadius,
                     yRadius: NativeAppDesign.Shape.controlRadius).fill()
    }
}

private final class NativeDesignButtonCell: NSButtonCell {
    override func drawBezel(withFrame frame: NSRect, in controlView: NSView) {
        guard let button = controlView as? NativeDesignButton else { super.drawBezel(withFrame: frame, in: controlView); return }
        let paint = button.paint
        let path = NSBezierPath(roundedRect: frame.insetBy(dx: paint.lineWidth / 2, dy: paint.lineWidth / 2),
                                xRadius: NativeAppDesign.Shape.controlRadius, yRadius: NativeAppDesign.Shape.controlRadius)
        paint.fill.setFill(); path.fill(); paint.edge.setStroke(); path.lineWidth = paint.lineWidth; path.stroke()
    }
    override func drawTitle(_ title: NSAttributedString, withFrame frame: NSRect, in controlView: NSView) -> NSRect {
        guard let button = controlView as? NativeDesignButton else { return super.drawTitle(title, withFrame: frame, in: controlView) }
        let text = NSMutableAttributedString(attributedString: title)
        text.addAttribute(.foregroundColor, value: button.paint.ink, range: NSRange(location: 0, length: text.length))
        return super.drawTitle(text, withFrame: frame, in: controlView)
    }
}

/// The shadow host never paints. All material, tint and edges live inside the clip.
final class NativeFloatingGlassView: NSView {
    enum Style { case drawer, capsule }
    let style: Style
    let contentView = NSView()
    let effectView = NSVisualEffectView()
    private let tint = CALayer(), edge = CALayer(), specular = CALayer()
    private let ambient = CALayer(), contact = CALayer()
    var cornerRadius: CGFloat = 24 { didSet { needsLayout = true } }
    var preferencesOverride: NativeAppDesign.Preferences? { didSet { needsDisplay = true; needsLayout = true } }
    var preferences: NativeAppDesign.Preferences { preferencesOverride ?? .current(appearance: effectiveAppearance) }
    private var observation: NativeDesignObservation?
    override var isOpaque: Bool { false }
    init(style: Style) {
        self.style = style
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = false
        layer?.addSublayer(ambient); layer?.addSublayer(contact)
        contentView.wantsLayer = true
        contentView.layer?.masksToBounds = true
        contentView.layer?.cornerCurve = .continuous
        addSubview(contentView)
        effectView.material = .popover; effectView.blendingMode = .withinWindow
        effectView.state = .followsWindowActiveState
        contentView.addSubview(effectView)
        effectView.wantsLayer = true
        effectView.layer?.addSublayer(tint)
        contentView.layer?.addSublayer(edge); contentView.layer?.addSublayer(specular)
        observation = NativeDesignObservation(view: self)
    }
    required init?(coder: NSCoder) { nil }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsLayout = true }
    override func draw(_ dirtyRect: NSRect) { updatePaint() }
    private func updatePaint() {
        let p = NativeAppDesign.palette(preferences)
        let solid = preferences.reduceTransparency || preferences.increasedContrast
        effectView.isHidden = solid
        contentView.layer?.backgroundColor = (solid ? p.panel : .clear).cgColor
        tint.backgroundColor = (style == .drawer ? p.glassTintDrawer : p.glassTintCapsule).cgColor
        edge.borderColor = (solid ? p.boundary : p.glassEdge).cgColor
        edge.borderWidth = solid ? 2 : 1
        specular.backgroundColor = solid ? NSColor.clear.cgColor : p.glassSpecular.cgColor
        for shadow in [ambient, contact] {
            shadow.backgroundColor = NSColor.clear.cgColor
            let dark = preferences.theme == .dark, outer = shadow === ambient
            shadow.shadowColor = NativeAppDesign.color(dark ? 0 : 0x292722).cgColor
            let opacity: Float = style == .drawer ? (outer ? (dark ? 0.50 : 0.14) : (dark ? 0.32 : 0.08))
                : (outer ? (dark ? 0.42 : 0.11) : (dark ? 0.28 : 0.07))
            shadow.shadowOpacity = opacity * (solid ? 0.5 : 1)
        }
    }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        contentView.frame = bounds; effectView.frame = contentView.bounds
        let radius = min(cornerRadius, min(bounds.width, bounds.height) / 2)
        contentView.layer?.cornerRadius = radius
        tint.frame = contentView.bounds; edge.frame = contentView.bounds; edge.cornerRadius = radius
        edge.cornerCurve = .continuous
        specular.frame = CGRect(x: radius, y: bounds.height - 1, width: max(0, bounds.width - 2 * radius), height: 1)
        for shadow in [ambient, contact] {
            shadow.frame = bounds
            shadow.shadowPath = CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
            shadow.shadowRadius = shadow === ambient
                ? (style == .drawer ? (preferences.theme == .dark ? 30 : 28) : (preferences.theme == .dark ? 20 : 18))
                : (style == .drawer ? 4 : 3)
            shadow.shadowOffset = CGSize(width: 0, height: shadow === ambient ? (style == .drawer ? -10 : -6) : -1)
        }
        updatePaint(); CATransaction.commit()
    }
}
