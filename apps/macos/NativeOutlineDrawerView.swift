import AppKit
import QuartzCore

/// A content-coordinate overlay; it consumes scrim clicks without forwarding them
/// to the body text view or changing its selection.
final class NativeOutlineDrawerView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    struct Entry: Equatable {
        let id: String
        let title: String
        let depth: Int
    }
    var entries: [Entry] = [] { didSet { tableView.reloadData(); needsLayout = true } }
    var activeID: String? { didSet { tableView.reloadData() } }
    var onNavigate: ((String) -> Void)?
    var onDismiss: (() -> Void)?
    var toolbarBottom: CGFloat = 0 { didSet { needsLayout = true } }
    var preferencesOverride: NativeAppDesign.Preferences? {
        didSet { glass.preferencesOverride = preferencesOverride; needsDisplay = true; tableView.reloadData() }
    }
    var preferences: NativeAppDesign.Preferences { preferencesOverride ?? .current(appearance: effectiveAppearance) }
    let glass = NativeFloatingGlassView(style: .drawer)
    let tableView = NativeOutlineTableView()
    private let scrollView = NSScrollView()
    private let titleLabel = NSTextField(labelWithString: "목차")
    private let closeButton = NSButton()
    private weak var previousFirstResponder: NSResponder?
    private var observation: NativeDesignObservation?
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override init(frame: NSRect) {
        super.init(frame: frame)
        isHidden = true
        wantsLayer = true
        setAccessibilityRole(.group); setAccessibilityLabel("목차"); setAccessibilityModal(true)
        glass.cornerRadius = 24; addSubview(glass)
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        glass.contentView.addSubview(titleLabel)
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "목차 닫기")
        closeButton.title = ""; closeButton.isBordered = false
        closeButton.wantsLayer = true; closeButton.layer?.cornerRadius = 14
        closeButton.setAccessibilityLabel("목차 닫기")
        closeButton.target = self; closeButton.action = #selector(close)
        glass.contentView.addSubview(closeButton)
        scrollView.drawsBackground = false; scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true; scrollView.scrollerStyle = .overlay
        tableView.style = .plain
        tableView.backgroundColor = .clear; tableView.headerView = nil
        tableView.rowHeight = 34; tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.selectionHighlightStyle = .none
        tableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("outline")))
        tableView.dataSource = self; tableView.delegate = self
        tableView.target = self; tableView.action = #selector(activate)
        tableView.onActivate = { [weak self] in self?.activate() }
        tableView.onClose = { [weak self] in self?.dismiss() }
        tableView.nextKeyView = closeButton; closeButton.nextKeyView = tableView
        scrollView.documentView = tableView; glass.contentView.addSubview(scrollView)
        observation = NativeDesignObservation(view: self) { [weak self] in self?.tableView.reloadData() }
    }
    required init?(coder: NSCoder) { nil }
    override func layout() {
        super.layout()
        let width = min(320, max(260, bounds.width - 28))
        let height = max(0, min(bounds.height - toolbarBottom - 28, 540, 48 + CGFloat(entries.count) * 36 + 12))
        glass.frame = NSRect(x: 14, y: toolbarBottom + 10, width: width, height: height)
        // Glass content uses AppKit's bottom-left coordinate space.
        titleLabel.frame = NSRect(x: 20, y: height - 34, width: width - 72, height: 22)
        closeButton.frame = NSRect(x: width - 42, y: height - 38, width: 28, height: 28)
        scrollView.frame = NSRect(x: 8, y: 8, width: width - 16, height: max(0, height - 56))
        tableView.tableColumns.first?.width = width - 16
    }
    override func draw(_ dirtyRect: NSRect) {
        let p = NativeAppDesign.palette(preferences)
        p.scrim.setFill()
        NSRect(x: 0, y: toolbarBottom, width: bounds.width, height: max(0, bounds.height - toolbarBottom)).fill()
        titleLabel.textColor = p.ink; closeButton.contentTintColor = p.secondaryInk
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard !isHidden, bounds.contains(local), local.y >= toolbarBottom else { return nil }
        return super.hitTest(point)
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance(); needsDisplay = true; tableView.reloadData()
    }
    override func mouseDown(with event: NSEvent) {
        // Empty panel/header areas bubble up through the responder chain too.
        // Only the scrim outside the rounded panel is a dismissal target.
        let point = glass.convert(event.locationInWindow, from: nil)
        let panel = NSBezierPath(roundedRect: glass.bounds, xRadius: glass.cornerRadius, yRadius: glass.cornerRadius)
        if !panel.contains(point) { dismiss() }
    }
    override func cancelOperation(_ sender: Any?) { dismiss() }
    func present() {
        guard isHidden else { return }
        previousFirstResponder = window?.firstResponder
        isHidden = false; needsLayout = true; layoutSubtreeIfNeeded()
        let index = entries.firstIndex { $0.id == activeID } ?? 0
        if entries.indices.contains(index) { tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false) }
        window?.makeFirstResponder(tableView)
        if !preferences.reduceMotion {
            let slide = CABasicAnimation(keyPath: "transform.translation.x")
            slide.fromValue = -20; slide.toValue = 0; slide.duration = 0.22
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0; fade.toValue = 1; fade.duration = 0.22
            glass.layer?.add(slide, forKey: "entrance"); glass.layer?.add(fade, forKey: "fade")
        }
        NSAccessibility.post(element: self, notification: .layoutChanged)
    }
    func dismiss() {
        guard !isHidden else { return }
        isHidden = true; glass.layer?.removeAllAnimations()
        if let previousFirstResponder { window?.makeFirstResponder(previousFirstResponder) }
        onDismiss?()
    }
    @objc private func close() { dismiss() }
    @objc private func activate() {
        guard entries.indices.contains(tableView.selectedRow) else { return }
        navigate(to: entries[tableView.selectedRow].id)
    }
    private func navigate(to id: String) {
        dismiss(); onNavigate?(id)
    }
    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = entries[row]
        let view = NativeOutlineRow(entry: entry, active: entry.id == activeID, preferences: preferences)
        view.onPress = { [weak self] in self?.navigate(to: entry.id) }
        view.isKeyboardSelected = row == tableView.selectedRow
        return view
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        // Keyboard navigation has its own outline; the accepted section keeps
        // its wash and accent bar until the host reports a new active section.
        for row in entries.indices {
            (tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? NativeOutlineRow)?
                .isKeyboardSelected = row == tableView.selectedRow
        }
    }
}

final class NativeOutlineTableView: NSTableView {
    var onActivate: (() -> Void)?
    var onClose: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: onClose?()
        case 36, 49, 76: onActivate?()
        case 125, 126:
            guard numberOfRows > 0 else { return }
            let row = min(numberOfRows - 1, max(0, selectedRow + (event.keyCode == 125 ? 1 : -1)))
            selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false); scrollRowToVisible(row)
        case 48:
            if event.modifierFlags.contains(.shift) { window?.selectPreviousKeyView(self) }
            else { window?.selectNextKeyView(self) }
        default: super.keyDown(with: event)
        }
    }
}

private final class NativeOutlineRow: NSView {
    var onPress: (() -> Void)?
    var isKeyboardSelected = false { didSet { needsDisplay = true } }
    let label: NSTextField
    let active: Bool
    let preferences: NativeAppDesign.Preferences
    init(entry: NativeOutlineDrawerView.Entry, active: Bool, preferences: NativeAppDesign.Preferences) {
        label = NSTextField(labelWithString: entry.title); self.active = active; self.preferences = preferences
        super.init(frame: .zero)
        setAccessibilityElement(true); setAccessibilityRole(.button)
        setAccessibilityLabel("제목 \(entry.depth)단계, \(entry.title)")
        setAccessibilityValue(active ? "현재 위치" : nil)
        let p = NativeAppDesign.palette(preferences)
        label.font = .systemFont(ofSize: entry.depth <= 1 ? 13.5 : 12.5,
                                 weight: active || entry.depth <= 1 ? .semibold : .regular)
        label.textColor = active ? p.accent : (entry.depth <= 1 || preferences.increasedContrast ? p.ink : p.secondaryInk)
        label.lineBreakMode = .byTruncatingTail
        label.frame.origin.x = 12 + CGFloat(min(max(0, entry.depth), 4)) * 14
        addSubview(label)
    }
    required init?(coder: NSCoder) { nil }
    override func accessibilityPerformPress() -> Bool {
        guard let onPress else { return false }
        onPress(); return true
    }
    override func layout() {
        super.layout()
        label.frame = NSRect(x: label.frame.minX, y: (bounds.height - 20) / 2, width: max(0, bounds.width - label.frame.minX - 12), height: 20)
    }
    override func draw(_ dirtyRect: NSRect) {
        let p = NativeAppDesign.palette(preferences)
        if active {
            p.wash.setFill(); NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12).fill()
            p.accent.setFill(); NSBezierPath(roundedRect: NSRect(x: 3, y: (bounds.height - 16) / 2, width: 3, height: 16), xRadius: 1.5, yRadius: 1.5).fill()
        }
        if isKeyboardSelected {
            let focus = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 11, yRadius: 11)
            p.boundary.setStroke(); focus.lineWidth = preferences.increasedContrast ? 2 : 1; focus.stroke()
        }
    }
}
