import AppKit

/// Chrome adaptation only. Never visit document/PDF/answer text or object painters.
enum NativeChrome {
    static func color(_ key: KeyPath<NativeAppDesign.Palette, NSColor>) -> NSColor {
        NSColor(name: nil) { appearance in
            NativeAppDesign.palette(.current(appearance: appearance))[keyPath: key]
        }
    }
    static func install(on window: NSWindow) {
        window.contentView = NativeDesignSurface(frame: window.contentView?.bounds ?? .zero)
        (window.contentView as? NativeDesignSurface)?.role = .paper
        window.backgroundColor = color(\.paper)
    }
    static func apply(to view: NSView) {
        if view is NSTextView || view is NativeReaderTextView || view is NativeReaderOriginalPageView { return }
        if let field = view as? NSTextField {
            field.textColor = color(\.ink)
            if field.isEditable { field.backgroundColor = color(\.panel) }
        }
        if let control = view as? NSPopUpButton { control.font = NativeAppDesign.Typography.font(.control) }
        for child in view.subviews { apply(to: child) }
    }
}

/// Presentation binding only. Session/TextView/actions remain the authorities.
@MainActor final class NativeFloatingCapsule: NSView {
    struct Binding: Equatable {
        let context: NativeReaderRequestContext
        let ticket: UUID
        let originalPDF: Bool
        let offlineOriginalPDF: Bool
        init(context: NativeReaderRequestContext, ticket: UUID, originalPDF: Bool, offlineOriginalPDF: Bool = false) {
            self.context = context
            self.ticket = ticket
            self.originalPDF = originalPDF
            self.offlineOriginalPDF = offlineOriginalPDF
        }
    }
    enum Action: String, CaseIterable { case copy, highlight, ask, strike, source, editor }
    private(set) var binding: Binding?
    var onAction: ((Binding, Action) -> Void)?
    var onDismiss: ((Binding) -> Void)?
    var onReleaseSelection: ((Binding) -> Void)?
    let surface = NativeFloatingGlassView(style: .capsule)
    let footnoteSurface = NativeFloatingGlassView(style: .capsule)
    let reason = NSTextField(wrappingLabelWithString: "")
    let footnote = NSTextField(labelWithString: "")
    let releaseSelectionButton = NSButton(title: "선택 해제", target: nil, action: nil)
    let closeButton = NativeCapsuleButton()
    let overflowButton = NativeCapsuleButton()
    private let divider = NSView()
    private(set) var buttons = [Action: NativeCapsuleButton]()
    var compact = false { didSet { updateOverflow(); needsLayout = true } }
    override var isOpaque: Bool { false }
    override init(frame: NSRect) {
        super.init(frame: frame)
        surface.cornerRadius = 28; addSubview(surface)
        footnoteSurface.cornerRadius = 13; addSubview(footnoteSurface)
        for (action, title, symbol) in [(Action.copy,"복사","doc.on.clipboard"), (.highlight,"하이라이트","highlighter"),
            (.ask,"Ask","bubble.left"), (.strike,"빨간 취소선","strikethrough"),
            (.source,"원문","doc.text.magnifyingglass"), (.editor,"편집기","arrow.up.forward.app")] {
            let button = NativeCapsuleButton()
            button.title = title; button.symbol = symbol; button.target = self; button.action = #selector(activate(_:))
            button.identifier = NSUserInterfaceItemIdentifier("capsule." + action.rawValue)
            button.setAccessibilityLabel(title); button.owner = self
            button.ink = action == .strike ? \.reviewInk : \.ink
            button.iconInk = action == .strike ? \.reviewInk : ([.copy, .highlight].contains(action) ? \.accent : \.ink)
            buttons[action] = button; surface.contentView.addSubview(button)
        }
        closeButton.symbol = "xmark"; closeButton.circular = true; closeButton.owner = self
        closeButton.target = self; closeButton.action = #selector(dismissExplicitly)
        closeButton.identifier = NSUserInterfaceItemIdentifier("capsule.dismiss")
        closeButton.setAccessibilityLabel("선택 작업 닫기")
        overflowButton.symbol = "ellipsis"; overflowButton.title = "더보기"; overflowButton.owner = self
        overflowButton.target = self; overflowButton.action = #selector(showOverflow)
        overflowButton.identifier = NSUserInterfaceItemIdentifier("capsule.more")
        surface.contentView.addSubview(overflowButton); surface.contentView.addSubview(divider)
        surface.contentView.addSubview(closeButton)
        divider.wantsLayer = true
        releaseSelectionButton.isHidden = true
        reason.isHidden = true
        footnote.font = .systemFont(ofSize: 11, weight: .medium); footnote.textColor = NativeChrome.color(\.secondaryInk)
        footnote.alignment = .center; footnote.lineBreakMode = .byTruncatingTail
        footnote.identifier = NSUserInterfaceItemIdentifier("capsule.footnote")
        footnoteSurface.contentView.addSubview(footnote); footnoteSurface.isHidden = true; footnote.isHidden = true
        setAccessibilityElement(false); setAccessibilityLabel("선택한 내용의 작업")
        isHidden = true
    }
    required init?(coder: NSCoder) { nil }
    func present(_ binding: Binding, unavailable: [Action: String], summary: String) {
        self.binding = binding; reason.stringValue = summary
        for action in Action.allCases {
            let button = buttons[action]!
            let blocked = unavailable[action] ?? (binding.originalPDF && action != .copy ? "원본 PDF는 복사·검색만 지원합니다." : nil)
            button.isEnabled = blocked == nil; button.isHidden = blocked != nil
            button.toolTip = blocked; button.setAccessibilityHelp(blocked ?? "현재 선택에 적용합니다")
        }
        footnote.stringValue = binding.originalPDF
            ? (binding.offlineOriginalPDF ? "오프라인 PDF · 복사·검색만 지원" : "원본 PDF · 복사·검색만 지원")
            : (summary.contains("32") ? summary : "")
        footnote.isHidden = footnote.stringValue.isEmpty; footnoteSurface.isHidden = footnote.isHidden
        updateOverflow(); isHidden = false; needsLayout = true
    }
    private func updateOverflow() {
        for action in [Action.source, .editor] { buttons[action]?.isHidden = compact || buttons[action]?.isEnabled != true }
        overflowButton.isHidden = !compact || ![Action.source, .editor].contains { buttons[$0]?.isEnabled == true }
    }
    private var visibleButtons: [NativeCapsuleButton] {
        Action.allCases.compactMap { buttons[$0] }.filter { !$0.isHidden } + (overflowButton.isHidden ? [] : [overflowButton]) + [closeButton]
    }
    func hide() { binding = nil; isHidden = true }
    func preferredSize(width maxWidth: CGFloat) -> NSSize {
        let tiles = visibleButtons.filter { $0 !== closeButton }.count
        let footnoteWidth = footnote.isHidden ? 0 : footnote.intrinsicContentSize.width + 24
        return NSSize(width: min(maxWidth, max(CGFloat(tiles) * 74 + 68, footnoteWidth)), height: 64 + (footnote.isHidden ? 0 : 32))
    }
    override func layout() {
        super.layout()
        surface.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 64)
        let tiles = visibleButtons.filter { $0 !== closeButton }
        let tileWidth = min(74, max(62, (bounds.width - 68) / CGFloat(max(1, tiles.count))))
        var x: CGFloat = 8
        for button in tiles { button.frame = NSRect(x: x, y: 5, width: tileWidth, height: 54); x += tileWidth }
        divider.frame = NSRect(x: bounds.width - 54, y: 20, width: 1, height: 24)
        divider.layer?.backgroundColor = NativeChrome.color(\.rule).cgColor
        closeButton.frame = NSRect(x: bounds.width - 46, y: 14, width: 36, height: 36)
        let fw = min(bounds.width, footnote.intrinsicContentSize.width + 24)
        footnoteSurface.frame = NSRect(x: (bounds.width - fw) / 2, y: 70, width: fw, height: 26)
        footnote.frame = footnoteSurface.bounds.insetBy(dx: 12, dy: 5)
        let loop = visibleButtons
        for (index, button) in loop.enumerated() { button.nextKeyView = loop[(index + 1) % loop.count] }
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let result = super.hitTest(point), result !== self else { return nil }
        for glass in [surface, footnoteSurface] where !glass.isHidden {
            if result === glass || result.isDescendant(of: glass) {
                let local = glass.convert(point, from: superview)
                let radius = min(glass.cornerRadius, glass.bounds.height / 2)
                return NSBezierPath(roundedRect: glass.bounds, xRadius: radius, yRadius: radius).contains(local) ? result : nil
            }
        }
        return result
    }
    func focusFirstAction() { window?.makeFirstResponder(visibleButtons.first { $0.isEnabled } ?? closeButton) }
    func moveFocus(from button: NSButton, backward: Bool) {
        let loop = visibleButtons.filter { $0.isEnabled }
        guard let index = loop.firstIndex(where: { $0 === button }), !loop.isEmpty else { return }
        window?.makeFirstResponder(loop[(index + (backward ? loop.count - 1 : 1)) % loop.count])
    }
    @objc private func activate(_ sender: NSButton) {
        guard let binding, !isHidden, sender.isEnabled,
              let action = buttons.first(where: { $0.value === sender })?.key else { return }
        onAction?(binding, action)
    }
    @objc private func showOverflow() {
        guard let binding, !isHidden else { return }
        let menu = NSMenu()
        for action in [Action.source, .editor] where buttons[action]?.isEnabled == true {
            let item = NSMenuItem(title: buttons[action]!.title, action: #selector(overflowAction(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = binding; item.identifier = NSUserInterfaceItemIdentifier(action.rawValue)
            menu.addItem(item)
        }
        if NSApp.activationPolicy() != .prohibited { menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 54), in: overflowButton) }
    }
    @objc private func overflowAction(_ item: NSMenuItem) {
        guard let captured = item.representedObject as? Binding, binding == captured, !isHidden,
              let action = Action(rawValue: item.identifier?.rawValue ?? ""), buttons[action]?.isEnabled == true else { return }
        onAction?(captured, action)
    }
    @objc func releaseSelectionExplicitly() {
        guard let binding, !isHidden, binding.originalPDF else { return }; onReleaseSelection?(binding)
    }
    @objc func dismissExplicitly() { guard let binding, !isHidden else { return }; onDismiss?(binding) }
    override func cancelOperation(_ sender: Any?) { dismissExplicitly() }
    static func placement(size: NSSize, viewport: NSRect, avoiding rects: [NSRect], occupied: [NSRect] = []) -> NSRect? {
        guard size.width <= viewport.width - 32, size.height <= viewport.height - 32 else { return nil }
        return NSRect(x: viewport.midX - size.width / 2, y: viewport.minY + 16, width: size.width, height: size.height)
    }
}

/// Fixed geometry keeps icon and label metrics independent of document zoom.
final class NativeCapsuleButton: NSButton {
    weak var owner: NativeFloatingCapsule?
    var symbol = ""
    var circular = false
    var ink: KeyPath<NativeAppDesign.Palette, NSColor> = \.ink
    var iconInk: KeyPath<NativeAppDesign.Palette, NSColor> = \.ink
    override init(frame: NSRect) {
        super.init(frame: frame); isBordered = false; setButtonType(.momentaryPushIn); focusRingType = .exterior
    }
    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { isEnabled && !isHiddenOrHasHiddenAncestor }
    var iconBox: NSRect {
        NSRect(x: bounds.midX - 10, y: circular ? bounds.midY - 10 : 8, width: 20, height: 20)
    }
    var labelBox: NSRect { NSRect(x: bounds.minX, y: 32, width: bounds.width, height: 14) }
    override func draw(_ dirtyRect: NSRect) {
        if circular || cell?.isHighlighted == true {
            NativeChrome.color(circular ? \.wash : \.pressed).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: circular ? 18 : 22, yRadius: circular ? 18 : 22).fill()
        }
        let color = NativeChrome.color(circular ? \.secondaryInk : iconInk)
        let config = NSImage.SymbolConfiguration(pointSize: circular ? 12 : 17, weight: .medium)
            .applying(.init(paletteColors: [color]))
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        if let image {
            let scale = min(iconBox.width / image.size.width, iconBox.height / image.size.height)
            let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
            let target = NSRect(x: iconBox.midX - size.width / 2, y: iconBox.midY - size.height / 2, width: size.width, height: size.height)
            image.draw(in: target, from: .zero, operation: .sourceOver, fraction: isEnabled ? 1 : 0.45, respectFlipped: true, hints: nil)
        }
        if !circular {
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: NativeChrome.color(ink)]
            let size = (title as NSString).size(withAttributes: attributes)
            (title as NSString).draw(at: NSPoint(x: labelBox.midX - size.width / 2, y: labelBox.midY - size.height / 2), withAttributes: attributes)
        }
    }
    override func keyDown(with event: NSEvent) {
        if [48, 123, 124].contains(event.keyCode) {
            owner?.moveFocus(from: self, backward: event.keyCode == 123 || (event.keyCode == 48 && event.modifierFlags.contains(.shift)))
        } else if event.keyCode == 53 { owner?.dismissExplicitly() }
        else { super.keyDown(with: event) }
    }
    override func cancelOperation(_ sender: Any?) { owner?.dismissExplicitly() }
}

/// Wrapping layout for repeated native command groups. No DOM/CSS policy or
/// hidden duplicate commands; actual controls participate in native key loops.
@MainActor final class NativeChromeControlRow: NSView {
  private var lastHeight: CGFloat = 0
  override var isFlipped: Bool { true }
  init(_ controls: [NSView]) { super.init(frame: .zero); for view in controls { addSubview(view) } }
  required init?(coder: NSCoder) { nil }
  var preferredSingleRowWidth: CGFloat { singleRowWidth() }
  private func singleRowWidth() -> CGFloat {
    let gap: CGFloat = 6
    var total: CGFloat = 0
    var count = 0
    for view in subviews where !view.isHidden {
      let width: CGFloat
      if let nested = view as? NativeChromeControlRow {
        width = nested.singleRowWidth()
      } else {
        var size = view.fittingSize
        if view is NSPopUpButton { size.width = min(280, size.width) }
        width = max(32, size.width)
      }
      total += (count > 0 ? gap : 0) + width
      count += 1
    }
    return max(32, total)
  }
  private func arrange(forWidth availableWidth: CGFloat, apply: Bool) -> CGFloat {
    let width = max(1, availableWidth), gap: CGFloat = 6
    var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
    for view in subviews where !view.isHidden {
      var size: NSSize
      if let nested = view as? NativeChromeControlRow {
        let preferredWidth = nested.singleRowWidth()
        let nestedWidth = min(width, max(32, preferredWidth))
        size = NSSize(width: nestedWidth, height: max(24, nested.arrange(forWidth: nestedWidth, apply: false)))
      } else {
        size = view.fittingSize
        if let popup = view as? NSPopUpButton {
          size.width = min(280, size.width); popup.toolTip = popup.titleOfSelectedItem
        }
        size.width = min(width, max(32, size.width)); size.height = max(24, size.height)
        if let text = view as? NSTextField, text.cell?.wraps == true {
          size.height = max(size.height, text.cell!.cellSize(forBounds: NSRect(x: 0, y: 0, width: size.width, height: 10000)).height)
        }
      }
      if x > 0 && x + size.width > width { x = 0; y += rowHeight + gap; rowHeight = 0 }
      if apply { view.frame = NSRect(origin: NSPoint(x: x, y: y), size: size) }
      x += size.width + gap; rowHeight = max(rowHeight, size.height)
    }
    return y + rowHeight
  }
  override var intrinsicContentSize: NSSize {
    let width = bounds.width > 0 ? bounds.width : singleRowWidth()
    return NSSize(width: NSView.noIntrinsicMetric, height: arrange(forWidth: width, apply: false))
  }
  override func layout() {
    super.layout(); let height = arrange(forWidth: bounds.width, apply: true)
    if abs(lastHeight-height) > 0.5 { lastHeight = height; invalidateIntrinsicContentSize() }
  }
  override func setFrameSize(_ size: NSSize) {
    let changed = frame.width != size.width; super.setFrameSize(size)
    if changed { invalidateIntrinsicContentSize(); needsLayout = true }
  }
}
