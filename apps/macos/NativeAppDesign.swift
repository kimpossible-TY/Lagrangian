import AppKit

/// Chrome only. Document, answer, math and PDF typography remain with their renderers.
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
        let paper, panel, ink, secondaryInk, accent, boundary, selection, onAccent: NSColor
        let hover, pressed, disabledInk, warning, error: NSColor
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
        let dark = preferences.theme == .dark
        // Opaque sRGB in every mode; preferences never require an optical material.
        return Palette(paper: color(dark ? 0x24231F : 0xF7F2E8),
                       panel: color(dark ? 0x302E29 : 0xFFFCF5),
                       ink: color(dark ? 0xF7F2E8 : 0x292722),
                       secondaryInk: color(dark ? 0xD0C9BC : 0x625D53),
                       accent: color(dark ? 0xC6BEFF : 0x514A83),
                       boundary: color(dark ? (preferences.increasedContrast ? 0xEEE8DC : 0xA59D90)
                                            : (preferences.increasedContrast ? 0x292722 : 0x81786A)),
                       selection: color(dark ? 0x49405E : 0xE6DEF4),
                       onAccent: color(dark ? 0x24231F : 0xFFFCF5),
                       hover: color(dark ? 0x403C49 : 0xEEE8F5),
                       pressed: color(dark ? 0x514A62 : 0xDED5ED),
                       disabledInk: color(dark ? 0xC0B9AB : 0x71695E),
                       warning: color(dark ? 0xF2CF8C : 0x785517),
                       error: color(dark ? 0xFFB5AE : 0x9C302C))
    }
    static func sage(_ preferences: Preferences) -> NSColor {
        color(preferences.theme == .dark ? 0xA9C6AA : 0x56765B)
    }
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
    init(view: NSView) {
        token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak view] _ in view?.needsDisplay = true }
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
