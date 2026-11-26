import AppKit
import QuartzCore

/// Requests are intent only. The thumb follows the mode accepted by the host.
final class NativeModeMorphSwitch: NSControl {
    enum Mode: Int { case nativeReflow, originalPages }
    var onRequestMode: ((Mode) -> Void)?
    var displayMode: Mode = .nativeReflow {
        didSet {
            if requestedMode == displayMode { requestedMode = nil }
            updateThumb(animated: true); updateButtons()
        }
    }
    var requestedMode: Mode? { didSet { needsLayout = true } }
    var heldSelection = false { didSet { needsLayout = true } }
    var compact = false { didSet { invalidateIntrinsicContentSize(); needsLayout = true; updateButtons() } }
    var allowsModeSwitch = true {
        didSet {
            if !allowsModeSwitch { pressOrigin = nil; updateThumb(animated: false) }
            updateButtons(); needsLayout = true
        }
    }
    var preferencesOverride: NativeAppDesign.Preferences? { didSet { needsLayout = true; updateButtons() } }
    var preferences: NativeAppDesign.Preferences { preferencesOverride ?? .current(appearance: effectiveAppearance) }
    let reflowButton = NativeModeSegmentButton()
    let pageButton = NativeModeSegmentButton()
    private let thumb = CALayer(), contact = CALayer(), loading = CAShapeLayer()
    private var pressOrigin: NSPoint?
    private var dragOffset: CGFloat = 0
    private var observation: NativeDesignObservation?
    override var intrinsicContentSize: NSSize { NSSize(width: compact ? 80 : 140, height: 32) }
    override var acceptsFirstResponder: Bool { true }
    override func isAccessibilityElement() -> Bool { false }
    override func accessibilityChildren() -> [Any]? { [reflowButton, pageButton] }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true; layer?.cornerRadius = 16; layer?.cornerCurve = .continuous
        layer?.addSublayer(contact); layer?.addSublayer(thumb); layer?.addSublayer(loading)
        thumb.cornerRadius = 13; thumb.cornerCurve = .continuous
        loading.fillColor = NSColor.clear.cgColor; loading.lineWidth = 1.5
        focusRingType = .exterior
        setAccessibilityRole(.radioGroup); setAccessibilityLabel("보기 모드")
        for (button, symbol, label, selector) in [
            (reflowButton, "doc.richtext", "본문 보기 (⌘1)", #selector(reflowMode)),
            (pageButton, "doc.viewfinder", "원본 PDF 보기 (⌘2)", #selector(pageMode))] {
            button.owner = self; button.isBordered = false; button.setButtonType(.momentaryPushIn)
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
            button.image?.isTemplate = true
            button.imagePosition = .imageLeading
            button.font = .systemFont(ofSize: 11.5, weight: .medium)
            button.setAccessibilityRole(.radioButton); button.setAccessibilityLabel(label); button.toolTip = label
            button.target = self; button.action = selector; addSubview(button)
        }
        observation = NativeDesignObservation(view: self); updateButtons()
    }
    required init?(coder: NSCoder) { nil }
    private var slot: CGFloat { max(1, (bounds.width - 6) / 2) }
    private var acceptedX: CGFloat { 3 + CGFloat(displayMode.rawValue) * slot }
    private func updateButtons() {
        let p = NativeAppDesign.palette(preferences)
        reflowButton.title = compact ? "" : "본문"; pageButton.title = compact ? "" : "PDF"
        for (index, button) in [reflowButton, pageButton].enumerated() {
            button.isEnabled = isEnabled && allowsModeSwitch
            button.state = index == displayMode.rawValue ? .on : .off
            button.setAccessibilityValue(index == displayMode.rawValue ? 1 : 0)
            button.contentTintColor = !button.isEnabled ? p.disabledInk :
                (index == displayMode.rawValue ? (preferences.increasedContrast ? p.onAccent : p.accent) : p.secondaryInk)
        }
    }
    override var isEnabled: Bool { didSet { updateButtons(); pressOrigin = nil; dragOffset = 0; needsLayout = true } }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsLayout = true; updateButtons() }
    override func draw(_ dirtyRect: NSRect) { needsLayout = true; updateButtons() }
    override func layout() {
        super.layout()
        let p = NativeAppDesign.palette(preferences), hc = preferences.increasedContrast
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer?.backgroundColor = p.track.cgColor
        layer?.borderColor = (hc ? p.boundary : p.ink.withAlphaComponent(0.10)).cgColor
        layer?.borderWidth = hc ? 2 : 1
        thumb.backgroundColor = (hc ? p.accent : p.panel).cgColor
        thumb.borderColor = (hc ? p.boundary : p.ink.withAlphaComponent(preferences.theme == .dark ? 0.12 : 0.08)).cgColor
        thumb.borderWidth = hc ? 1.5 : 1
        for (shadow, radius, opacity, offset) in [(thumb, CGFloat(4), Float(0.10), CGFloat(-1.5)),
                                                 (contact, CGFloat(1), Float(0.06), CGFloat(-0.5))] {
            shadow.shadowColor = NativeAppDesign.color(preferences.theme == .dark ? 0 : 0x292722).cgColor
            let base = preferences.theme == .dark ? (shadow === thumb ? Float(0.36) : Float(0.24)) : opacity
            shadow.shadowRadius = radius; shadow.shadowOpacity = base * (hc ? 0.5 : 1)
            shadow.shadowOffset = CGSize(width: 0, height: offset)
        }
        thumb.frame = CGRect(x: acceptedX + dragOffset, y: 3, width: slot, height: 26)
        contact.frame = thumb.frame
        let shadowPath = CGPath(roundedRect: CGRect(origin: .zero, size: thumb.frame.size), cornerWidth: 13, cornerHeight: 13, transform: nil)
        thumb.shadowPath = shadowPath; contact.shadowPath = shadowPath
        reflowButton.frame = CGRect(x: 3, y: 3, width: slot, height: 26)
        pageButton.frame = CGRect(x: 3 + slot, y: 3, width: slot, height: 26)
        loading.removeAllAnimations()
        loading.isHidden = requestedMode == nil && !(heldSelection && preferences.reduceMotion)
        let requested = requestedMode ?? displayMode
        loading.frame = CGRect(x: 3 + CGFloat(requested.rawValue) * slot, y: 3, width: slot, height: 26)
        loading.path = CGPath(roundedRect: CGRect(x: 0.75, y: 0.75, width: slot - 1.5, height: 24.5), cornerWidth: 12, cornerHeight: 12, transform: nil)
        loading.strokeColor = (heldSelection ? p.warning : p.accent).cgColor
        loading.strokeEnd = preferences.reduceMotion ? 1 : 0.28
        loading.lineDashPattern = preferences.reduceMotion ? [3, 2] : nil
        if !loading.isHidden && !preferences.reduceMotion {
            let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
            rotation.fromValue = 0; rotation.toValue = 2 * Double.pi; rotation.duration = 1.1; rotation.repeatCount = .infinity
            loading.add(rotation, forKey: "loading")
        }
        CATransaction.commit(); updateButtons()
    }
    private func updateThumb(animated: Bool) {
        let oldX = thumb.presentation()?.position.x ?? thumb.position.x
        dragOffset = 0; needsLayout = true; layoutSubtreeIfNeeded()
        guard animated, !preferences.reduceMotion else { thumb.removeAllAnimations(); return }
        let spring = CASpringAnimation(keyPath: "position.x")
        spring.stiffness = 380; spring.damping = 28; spring.mass = 0.85
        spring.fromValue = oldX; spring.toValue = thumb.position.x; spring.duration = spring.settlingDuration
        thumb.add(spring, forKey: "mode")
    }
    @objc func reflowMode() { request(.nativeReflow) }
    @objc func pageMode() { request(.originalPages) }
    func request(_ mode: Mode) {
        guard isEnabled, allowsModeSwitch, mode != displayMode else { updateThumb(animated: true); return }
        if heldSelection {
            if !preferences.reduceMotion {
                let bounce = CASpringAnimation(keyPath: "transform.translation.x")
                bounce.stiffness = 380; bounce.damping = 28; bounce.mass = 0.85
                bounce.fromValue = CGFloat(mode.rawValue - displayMode.rawValue) * slot * 0.25; bounce.toValue = 0
                bounce.duration = bounce.settlingDuration; thumb.add(bounce, forKey: "held")
            }
            needsLayout = true; return
        }
        requestedMode = mode; updateThumb(animated: true); onRequestMode?(mode)
    }
    override func mouseDown(with event: NSEvent) {
        guard isEnabled, allowsModeSwitch else { return }
        window?.makeFirstResponder(self); pressOrigin = convert(event.locationInWindow, from: nil)
    }
    override func mouseDragged(with event: NSEvent) {
        guard isEnabled, allowsModeSwitch, let pressOrigin else { return }
        guard !(heldSelection && preferences.reduceMotion) else { return }
        let point = convert(event.locationInWindow, from: nil)
        let dx = point.x - pressOrigin.x, dy = point.y - pressOrigin.y
        if abs(dy) >= 3, abs(dy) >= abs(dx) {
            self.pressOrigin = nil; updateThumb(animated: true); return
        }
        let proposed = acceptedX + dx
        let clamped = min(3 + slot, max(3, proposed))
        let overshoot = min(3, max(-3, (proposed - clamped) * 0.25))
        dragOffset = (clamped - acceptedX + overshoot) * (heldSelection ? 0.25 : 1)
        needsLayout = true
    }
    override func mouseUp(with event: NSEvent) {
        guard let pressOrigin else { return }
        self.pressOrigin = nil
        let point = convert(event.locationInWindow, from: nil), dx = point.x - pressOrigin.x
        let dy = point.y - pressOrigin.y
        guard isEnabled, allowsModeSwitch, bounds.contains(point) else { updateThumb(animated: true); return }
        let mode: Mode
        if abs(dx) >= slot * 0.40, abs(dx) > 2 * abs(dy) {
            mode = dx > 0 ? .originalPages : .nativeReflow
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        } else if hypot(dx, dy) < 3 { mode = point.x < bounds.midX ? .nativeReflow : .originalPages }
        else { updateThumb(animated: true); return }
        let button = mode == .nativeReflow ? reflowButton : pageButton
        button.performClick(nil)
        updateThumb(animated: true)
    }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123: reflowButton.performClick(nil)
        case 124: pageButton.performClick(nil)
        case 49, 36: (displayMode == .nativeReflow ? pageButton : reflowButton).performClick(nil)
        default: super.keyDown(with: event)
        }
    }
    override var focusRingMaskBounds: NSRect { bounds.insetBy(dx: -2, dy: -2) }
    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: focusRingMaskBounds, xRadius: 18, yRadius: 18).fill()
    }
    override func cancelOperation(_ sender: Any?) { pressOrigin = nil; updateThumb(animated: true) }
}

final class NativeModeSegmentButton: NSButton {
    weak var owner: NativeModeMorphSwitch?
    override func mouseDown(with event: NSEvent) { owner?.mouseDown(with: event) }
    override func mouseDragged(with event: NSEvent) { owner?.mouseDragged(with: event) }
    override func mouseUp(with event: NSEvent) { owner?.mouseUp(with: event) }
}
