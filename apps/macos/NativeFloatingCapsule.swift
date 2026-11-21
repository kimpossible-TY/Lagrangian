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
    enum Action: String, CaseIterable { case copy, source, highlight, ask, editor }
    private(set) var binding: Binding?
    var onAction: ((Binding, Action) -> Void)?
    var onDismiss: ((Binding) -> Void)?
    var onReleaseSelection: ((Binding) -> Void)?
    private let surface = NativeDesignSurface()
    private let scroll = NSScrollView()
    private let content = CapsuleContent()
    let reason = NSTextField(wrappingLabelWithString: "")
    let footnote = NSTextField(labelWithString: "")
    let releaseSelectionButton = NativeDesignButton(title: "선택 해제", target: nil, action: nil)
    let closeButton = NativeDesignButton(title: "닫기", target: nil, action: nil)
    private(set) var buttons = [Action: NativeDesignButton]()
    private var row: NativeChromeControlRow!
    override init(frame: NSRect) {
        super.init(frame: frame)
        surface.role = .floating; addSubview(surface)
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.documentView = content; addSubview(scroll)
        for (action, title) in [(Action.copy,"복사"), (.source,"원문 보기"), (.highlight,"원문 강조"), (.ask,"질문하기"), (.editor,"편집기 위치로")] {
            let button = NativeDesignButton(title: title, target: self, action: #selector(activate(_:)))
            button.identifier = NSUserInterfaceItemIdentifier("capsule." + action.rawValue)
            button.setAccessibilityLabel(title); buttons[action] = button
        }
        releaseSelectionButton.target = self; releaseSelectionButton.action = #selector(releaseSelectionExplicitly)
        releaseSelectionButton.identifier = NSUserInterfaceItemIdentifier("capsule.releaseSelection")
        releaseSelectionButton.setAccessibilityLabel("선택 해제")
        releaseSelectionButton.isHidden = true
        closeButton.target = self; closeButton.action = #selector(dismissExplicitly)
        closeButton.identifier = NSUserInterfaceItemIdentifier("capsule.dismiss")
        closeButton.setAccessibilityLabel("닫기")
        closeButton.keyEquivalent = "\u{1b}"; closeButton.keyEquivalentModifierMask = []
        row = NativeChromeControlRow(Action.allCases.compactMap { buttons[$0] } + [releaseSelectionButton, closeButton])
        content.addSubview(reason); content.addSubview(row); content.addSubview(footnote)
        reason.font = NativeAppDesign.Typography.font(.caption); reason.textColor = NativeChrome.color(\.secondaryInk)
        footnote.font = NativeAppDesign.Typography.font(.caption); footnote.textColor = NativeChrome.color(\.secondaryInk)
        footnote.lineBreakMode = .byTruncatingTail
        footnote.identifier = NSUserInterfaceItemIdentifier("capsule.footnote")
        footnote.isHidden = true
        setAccessibilityElement(false); setAccessibilityLabel("선택한 내용의 작업")
        isHidden = true
    }
    required init?(coder: NSCoder) { nil }
    func present(_ binding: Binding, unavailable: [Action: String], summary: String) {
        self.binding = binding; reason.stringValue = summary
        reason.isHidden = summary.isEmpty
        for action in Action.allCases {
            let button = buttons[action]!
            let blocked = unavailable[action]
            button.isEnabled = blocked == nil
            button.isHidden = blocked != nil
            button.toolTip = blocked
            button.setAccessibilityHelp(blocked ?? "현재 선택에 적용합니다")
        }
        releaseSelectionButton.isHidden = true
        releaseSelectionButton.isEnabled = false
        if binding.originalPDF {
            footnote.stringValue = binding.offlineOriginalPDF ? "오프라인 PDF · 복사·검색만 지원" : "원본 PDF · 복사·검색만 지원"
            footnote.isHidden = false
        } else {
            footnote.stringValue = ""
            footnote.isHidden = true
        }
        row.invalidateIntrinsicContentSize(); row.needsLayout = true
        isHidden = false; needsLayout = true
    }
    func hide() { binding = nil; isHidden = true }
    func preferredSize(width maxWidth: CGFloat) -> NSSize {
        let maxWidth = max(120, maxWidth), probeWidth = max(64, maxWidth - 24)
        let rowWidth = row.preferredSingleRowWidth
        let reasonWidth = reason.isHidden || reason.stringValue.isEmpty ? 0 : ceil(reason.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: probeWidth, height: 10000)).width ?? 0)
        let footWidth = footnote.isHidden || footnote.stringValue.isEmpty ? 0 : ceil(footnote.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: probeWidth, height: 10000)).width ?? 0)
        let width = min(maxWidth, max(120, max(rowWidth, max(reasonWidth, footWidth)) + 24))
        let inner = max(64, width - 24)
        row.frame.size.width = inner
        let explanation = reason.isHidden || reason.stringValue.isEmpty ? 0 : (reason.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: inner, height: 10000)).height ?? 20)
        let footer = footnote.isHidden || footnote.stringValue.isEmpty ? 0 : (footnote.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: inner, height: 10000)).height ?? 16)
        let contentHeight = (explanation > 0 ? explanation + 8 : 0) + row.intrinsicContentSize.height + (footer > 0 ? footer + 6 : 0) + 20
        return NSSize(width: width, height: min(180, contentHeight))
    }
    override func layout() {
        super.layout(); surface.frame = bounds; scroll.frame = bounds.insetBy(dx: 10, dy: 8)
        let width = max(64, scroll.contentSize.width)
        var y: CGFloat = 0
        if !reason.isHidden && !reason.stringValue.isEmpty {
            let height = reason.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: 10000)).height ?? 20
            reason.frame = NSRect(x: 0, y: 0, width: width, height: height)
            y = height + 8
        } else {
            reason.frame = .zero
        }
        row.frame = NSRect(x: 0, y: y, width: width, height: row.intrinsicContentSize.height)
        row.layoutSubtreeIfNeeded()
        y = row.frame.maxY
        if !footnote.isHidden && !footnote.stringValue.isEmpty {
            let fh = footnote.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: 10000)).height ?? 16
            footnote.frame = NSRect(x: 0, y: y + 6, width: width, height: fh)
            y = footnote.frame.maxY
        } else {
            footnote.frame = .zero
        }
        content.frame = NSRect(x: 0, y: 0, width: width, height: y + 4)
    }
    func focusFirstAction() { window?.makeFirstResponder(Action.allCases.compactMap { buttons[$0] }.first { $0.isEnabled } ?? closeButton) }
    @objc private func activate(_ sender: NSButton) {
        guard let binding, !isHidden, sender.isEnabled,
              let action = buttons.first(where: { $0.value === sender })?.key else { return }
        onAction?(binding, action)
    }
    @objc func releaseSelectionExplicitly() {
        guard let binding, !isHidden, binding.originalPDF else { return }
        onReleaseSelection?(binding)
    }
    @objc func dismissExplicitly() { guard let binding else { return }; onDismiss?(binding) }
    override func cancelOperation(_ sender: Any?) { dismissExplicitly() }

    /// Return an unobscured overlay within the document viewport; otherwise the host
    /// allocates a separate dock row. Selection rectangles are never inferred here.
    static func placement(size: NSSize, viewport: NSRect, avoiding rects: [NSRect], occupied: [NSRect] = []) -> NSRect? {
        guard size.width <= viewport.width, size.height <= viewport.height, !rects.isEmpty else { return nil }
        let selected = rects.reduce(NSRect.null) { $0.union($1) }
        let x = min(max(viewport.minX, selected.midX - size.width / 2), viewport.maxX - size.width)
        for y in [selected.maxY + 8, selected.minY - size.height - 8] {
            let candidate = NSRect(x: x, y: y, width: size.width, height: size.height)
            if viewport.contains(candidate) && !(rects + occupied).contains(where: { $0.insetBy(dx: -4, dy: -4).intersects(candidate) }) { return candidate }
        }
        return nil
    }
}
private final class CapsuleContent: NSView { override var isFlipped: Bool { true } }

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
