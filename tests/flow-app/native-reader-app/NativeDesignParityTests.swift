import AppKit
import CoreText
import CryptoKit

private struct ParityInput: NativeReaderDocumentProviding {
    let value: NativeReaderDocument
    func document(for context: NativeReaderRequestContext) async throws -> NativeReaderDocument { value.rebinding(generation: context.generation) }
}

@main struct NativeDesignParityTests {
    @MainActor static var assertions = 0
    @MainActor static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        assertions += 1
        if !condition() { throw FlowError(message: message) }
    }
    @MainActor static func until(_ condition: () -> Bool) async throws {
        for _ in 0..<1000 { if condition() { return }; try await Task.sleep(nanoseconds: 10_000_000) }
        throw FlowError(message: "Parity condition timed out")
    }
    @MainActor static func views(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { views($0) } }
    @MainActor static func event(_ window: NSWindow, _ key: String, _ flags: NSEvent.ModifierFlags = [], code: UInt16 = 0) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: window.windowNumber,
            context: nil, characters: key, charactersIgnoringModifiers: key, isARepeat: false, keyCode: code)!
    }
    static func node(_ id: String, text: String, kind: NativeReaderNode.Kind, level: Int? = nil, children: [NativeReaderNode] = []) -> NativeReaderNode {
        .init(id: id, sectionID: "section", kind: kind, canonicalText: text, displayText: text,
            rangeUTF16: [0, text.utf16.count], offsets: NativeTextOffsets(text), children: children, anchors: [], annotationTargets: [],
            visible: true, mapping: .unmapped, passageKey: nil, direction: nil, language: nil, headingLevel: level,
            math: nil, cell: nil, link: nil, assetID: nil, alt: nil)
    }
    static func document(shortEnd: Bool = false, endHeading: Bool = false) -> NativeReaderDocument {
        let blocks = (0..<40).map { index -> NativeReaderNode in
            let heading = index % 10 == 0 || (endHeading && index == 39)
            let text = heading ? "목차 제목 \(index) · 연구 노트" : "Search needle \(index). " + String(repeating: "선택 영역과 본문을 보존합니다. ", count: shortEnd && index == 39 ? 0 : 8)
            return node("b\(index)", text: text, kind: heading ? .heading : .paragraph, level: heading ? 1 : nil,
                        children: [node("t\(index)", text: text, kind: .text)])
        }
        return .init(schemaVersion: 1, identity: .init(documentID: "parity", serviceID: "reader:1:1", revision: "r1", scope: .service),
                     generation: 1, requiredCapabilities: ["semantic-tree-v1"], blocks: blocks, assets: [], diagnostics: [])
    }
    static func pdf() -> Data {
        let data = NSMutableData(); var box = CGRect(x: 0, y: 0, width: 420, height: 600)
        let consumer = CGDataConsumer(data: data as CFMutableData)!, context = CGContext(consumer: consumer, mediaBox: &box, nil)!
        for _ in 0..<2 {
            context.beginPDFPage(nil); context.setFillColor(NSColor.black.cgColor)
            for y in stride(from: 40, through: 560, by: 40) {
                context.textPosition = CGPoint(x: 32, y: y)
                CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: "Search needle original PDF", attributes: [.font: NSFont.systemFont(ofSize: 14)])), context)
            }
            context.endPDFPage()
        }
        context.closePDF(); return data as Data
    }
    static func publication(_ context: NativeReaderRequestContext, _ data: Data) -> NativeOriginalPagePublication {
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let id = "00000000-0000-0000-0000-000000000001"
        return .init(schemaVersion: 1, capability: "original-pdf-full-v1", documentID: context.target.documentID,
            serviceID: context.target.serviceID, revision: context.target.revision, requestID: context.requestID.uuidString.lowercased(),
            viewID: context.viewID.uuidString.lowercased(), generation: context.generation, publicationID: id, sequence: 1,
            inputFingerprint: hash, htmlInputFingerprint: hash, pdfInputFingerprint: hash, pdfSHA256: hash, byteCount: data.count,
            resource: "api/native-pages/\(id)/1.pdf", sourceAnchors: "unsupported", delivery: "immutable-pdf-full-reset")
    }
    @MainActor static func main() async {
        do { try await run() } catch { fputs("PARITY FAILURE: \(error)\n", stderr); exit(1) }
    }
    @MainActor static func run() async throws {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.prohibited)
        let output = URL(fileURLWithPath: CommandLine.arguments[1]), scenario = CommandLine.arguments[2]
        let doc = document(shortEnd: scenario == "review-offset", endHeading: scenario == "drawer"), bytes = pdf(); try doc.validate()
        let host = NativeReaderWindowController(provider: ParityInput(value: doc), target: { _ in doc.identity },
            originalPages: { context in .init(publication: publication(context, bytes), data: bytes) }, show: false, avoidActivation: true, fixtureMode: true)
        defer { host.dispose() }
        let profile = Profile(id: "parity", name: "Parity", root: output.path, entry: "main.typ", fonts: [], packages: "", port: 23620, publicURL: "", label: "owned.parity")
        _ = host.open(profile) { _ in }
        try await until { host.session.state == .reading && host.textView.renderKey != nil && host.textView.renderKey == host.textView.requestedRenderKey }
        let chrome = host.hostWindow, window = chrome.window!, root = window.contentView!
        window.setFrame(NSRect(x: 0, y: 0, width: 980, height: 752), display: false); root.layoutSubtreeIfNeeded()
        let originalFrame = window.frame
        let context = host.session.context!
        // Also supply isolated fixtures for the existing source harnesses.
        try JSONEncoder().encode(doc).write(to: output.appendingPathComponent("document.json"))
        try JSONEncoder().encode(doc).write(to: output.appendingPathComponent("long-document.json"))
        try bytes.write(to: output.appendingPathComponent("publication.pdf"))
        try JSONEncoder().encode(publication(context, bytes)).write(to: output.appendingPathComponent("publication.json"))
        if scenario == "drawer" {
            try check(chrome.outlineToggleButton.identifier?.rawValue == "contentsDrawerToggle" && chrome.outlineToggleButton.isEnabled, "Ghost outline toggle wired")
            try check(chrome.outlineToggleButton.designRole == .ghost, "Outline uses shared ghost paint")
            try check(abs(chrome.outlineToggleButton.bounds.height - 30) < 0.5, "Outline ghost has 30pt hit height")
            try check(chrome.outlineDrawer.entries.count == 5, "Flat semantic outline")
            window.makeFirstResponder(host.textView.bodyTextView)
            try check(root.performKeyEquivalent(with: event(window, "\\", .command)), "Cmd backslash opens drawer")
            try check(!chrome.outlineDrawer.isHidden && chrome.currentMode == .nativeReflow, "Drawer opens without changing mode")
            try check(root.performKeyEquivalent(with: event(window, "\\", .command)), "Cmd backslash closes drawer")
            try check(chrome.outlineDrawer.isHidden && chrome.currentMode == .nativeReflow, "Drawer closes without changing mode")
            try check(root.performKeyEquivalent(with: event(window, "o", [.command, .shift])), "Cmd Shift O routed")
            try check(!chrome.outlineDrawer.isHidden && window.firstResponder === chrome.outlineDrawer.tableView, "Drawer takes keyboard focus")
            window.makeFirstResponder(host.textView.bodyTextView)
            try check(root.performKeyEquivalent(with: event(window, "o", [.command, .shift])), "Cmd Shift O refocuses")
            try check(!chrome.outlineDrawer.isHidden && window.firstResponder === chrome.outlineDrawer.tableView, "Open drawer remains open and focused")
            try check(chrome.handleReaderEscape() && chrome.outlineDrawer.isHidden && window.firstResponder === host.textView.bodyTextView, "Escape returns focus")
            chrome.toggleOutlineDrawer()
            let table = chrome.outlineDrawer.tableView
            table.keyDown(with: event(window, "", [], code: 125))
            try check(table.selectedRow == 1, "Down moves the outline keyboard row")
            table.keyDown(with: event(window, "\r", [], code: 36))
            try check(chrome.outlineDrawer.isHidden && window.firstResponder === host.textView.bodyTextView,
                      "Return navigates and focuses body")
            chrome.toggleDisplayPopover(); chrome.toggleOutlineDrawer()
            try check(!chrome.isDisplayPopoverOpen && !chrome.outlineDrawer.isHidden, "Drawer excludes Aa")
            chrome.toggleDisplayPopover()
            try check(chrome.outlineDrawer.isHidden && chrome.isDisplayPopoverOpen && (chrome.displayPopoverContentView as? NativeDesignSurface)?.isOpaque == true, "Aa excludes drawer and remains opaque")
            chrome.toggleDisplayPopover()
            let drawer = NativeOutlineDrawerView(frame: root.bounds)
            let longTitle = String(repeating: "긴 한국어 제목과 English heading ", count: 8)
            drawer.entries = [.init(id: "long", title: longTitle, depth: 3)]
            drawer.activeID = "long"
            var navigated: String?, dismissals = 0
            drawer.onNavigate = { navigated = $0 }; drawer.onDismiss = { dismissals += 1 }
            root.addSubview(drawer); drawer.present(); drawer.layoutSubtreeIfNeeded()
            let outlineTable = drawer.tableView
            outlineTable.layoutSubtreeIfNeeded()
            let row = outlineTable.view(atColumn: 0, row: 0, makeIfNecessary: true)!
            row.layoutSubtreeIfNeeded()
            let label = views(row).compactMap { $0 as? NSTextField }.first!
            let rowRect = row.convert(row.bounds, to: outlineTable)
            let columnRect = outlineTable.frameOfCell(atColumn: 0, row: 0)
            try check(outlineTable.style == .plain && rowRect.minX >= columnRect.minX - 0.5 && rowRect.maxX <= columnRect.maxX + 0.5,
                      "Plain table keeps the active row inside its column")
            try check(label.lineBreakMode == .byTruncatingTail && label.frame.maxX <= row.bounds.maxX - 11.5 && label.intrinsicContentSize.width > label.frame.width,
                      "Long Korean and English heading truncates with a trailing inset")
            try check(row.isAccessibilityElement() && row.accessibilityRole() == .button &&
                      row.accessibilityLabel()?.contains(longTitle) == true && row.accessibilityLabel()?.contains("3") == true &&
                      row.accessibilityValue() as? String == "현재 위치", "Active outline row exposes its heading and state as a button")
            try check(row.accessibilityPerformPress() && navigated == "long" && drawer.isHidden && dismissals == 1,
                      "Accessibility press navigates and dismisses")
            drawer.removeFromSuperview()
            chrome.triggerFind(); chrome.toggleOutlineDrawer()
            window.sendEvent(event(window, "\u{1b}", [], code: 53))
            try check(!chrome.outlineDrawer.isHidden, "Actual Escape closes Find before the focused drawer")
            window.sendEvent(event(window, "\u{1b}", [], code: 53))
            try check(chrome.outlineDrawer.isHidden, "Next actual Escape closes drawer")
            let second = host.textView.outline[1]
            let headings = host.textView.outline
            let scroll = host.textView.scrollView, clip = scroll.contentView
            let maxScroll = host.textView.bodyTextView.bounds.height - clip.bounds.height
            var previous = -1, observed = Set<Int>()
            for offset in stride(from: CGFloat(0), through: maxScroll, by: 40) {
                clip.scroll(to: NSPoint(x: 0, y: offset)); scroll.reflectScrolledClipView(clip); chrome.updateScrollChrome()
                let index = headings.firstIndex { $0.id == chrome.outlineDrawer.activeID }!
                try check(index >= previous, "Active heading advances monotonically")
                previous = index; observed.insert(index)
            }
            try check(observed.count >= 4, "Scrolling reaches multiple headings")
            chrome.outlineDrawer.onNavigate?(second.id)
            let targetRect = host.textView.nodeRectInDocument(forNodeID: second.id)!
            try check(abs(clip.bounds.minY - targetRect.minY) < 1, "TOC heading aligns with viewport top")
            try check(chrome.outlineDrawer.activeID == second.id && chrome.outlineToggleButton.title == second.displayText, "TOC updates active heading and toolbar title")
            let last = headings.last!
            let item = NSMenuItem(); item.representedObject = last.id; chrome.outlineMenuSelected(item)
            try check(abs(clip.bounds.minY - maxScroll) < 1 && host.textView.nodeRectInDocument(forNodeID: last.id)!.minY > maxScroll + 96, "Last heading clamps at document bottom")
            chrome.updateScrollChrome()
            try check(chrome.outlineDrawer.activeID == last.id && chrome.outlineToggleButton.title == last.displayText, "Clamped heading remains active")
            clip.scroll(to: NSPoint(x: 0, y: maxScroll - 4)); scroll.reflectScrolledClipView(clip); chrome.updateScrollChrome()
            try check(chrome.outlineDrawer.activeID != last.id, "Scrolling four points clears pinned heading")
            try await Task.sleep(nanoseconds: 100_000_000)
            chrome.outlineDrawer.onNavigate?(last.id)
            try await Task.sleep(nanoseconds: 100_000_000)
            // Re-pin at the already clamped position, with no earlier scroll tasks pending.
            chrome.outlineDrawer.onNavigate?(last.id)
            let pinnedY = clip.bounds.minY
            try check(chrome.outlineDrawer.activeID == last.id, "Bottom heading is pinned before bounce")
            var notificationOffsets: [CGFloat] = []
            let observer = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: nil) { _ in
                notificationOffsets.append(clip.bounds.minY)
            }
            clip.scroll(to: NSPoint(x: 0, y: pinnedY - 4)); scroll.reflectScrolledClipView(clip)
            clip.scroll(to: NSPoint(x: 0, y: pinnedY)); scroll.reflectScrolledClipView(clip)
            NotificationCenter.default.removeObserver(observer)
            try check(notificationOffsets.contains { abs($0 - pinnedY) >= 4 } && notificationOffsets.last == pinnedY,
                      "Both bounce offsets are delivered synchronously")
            try await Task.sleep(nanoseconds: 100_000_000)
            let expected = headings.last { host.textView.nodeRectInDocument(forNodeID: $0.id)!.minY <= pinnedY + 96 } ?? headings.first!
            try check(expected.id != last.id && chrome.outlineDrawer.activeID == expected.id,
                      "Bounce clears the pin and restores the heading at the actual scroll position")
            chrome.outlineDrawer.onNavigate?(last.id); chrome.refreshOutline()
            try check(chrome.outlineDrawer.activeID != last.id, "Reload clears pinned heading")
            let secondRect = host.textView.nodeRectInView(forNodeID: second.id)!
            let documentRect = host.textView.bodyTextView.convert(secondRect, from: host.textView)
            clip.scroll(to: NSPoint(x: 0, y: documentRect.minY - 24)); host.textView.scrollView.reflectScrolledClipView(clip)
            chrome.updateScrollChrome()
            try check(chrome.outlineDrawer.activeID == second.id, "Scroll baseline tracks active section")
            try check(chrome.toolbarView.scrollOffset > 4, "Scrolled reader enables toolbar hairline")
            window.setFrame(NSRect(x: 0, y: 0, width: 640, height: 752), display: false); root.layoutSubtreeIfNeeded()
            try check(!chrome.outlineToggleButton.isHidden && chrome.outlineToggleButton.title.isEmpty, "Compact Reflow retains outline icon")
            try check(chrome.outlineToggleButton.bounds.size == NSSize(width: 30, height: 30), "Compact outline has a 30pt square target")
        } else if scenario == "notifications" {
            window.makeFirstResponder(host.textView.bodyTextView); let responder = window.firstResponder
            chrome.setNotice("오프라인 저장 완료", tone: .success); root.layoutSubtreeIfNeeded()
            try check(!chrome.noticeBanner.isHidden && chrome.noticeBanner.frame.width >= 160 && chrome.noticeBanner.frame.width <= 520, "Notification is content sized")
            let frame = chrome.noticeBanner.convert(chrome.noticeBanner.bounds, to: root)
            try check(abs(frame.midX - root.bounds.midX) < 1 && abs(chrome.toolbarView.frame.minY - frame.maxY - 10) < 1, "Centered below toolbar")
            try check(chrome.overlayStack.hitTest(NSPoint(x: 2, y: chrome.overlayStack.frame.midY)) == nil, "Empty centering margin passes through")
            let corner = chrome.noticeBanner.convert(NSPoint(x: 0.1, y: 0.1), to: root)
            try check(chrome.overlayStack.hitTest(corner) == nil, "Transparent capsule corner passes clicks through")
            try check(!chrome.noticeBanner.isOpaque && chrome.noticeBanner.layer?.backgroundColor?.alpha == 0, "Transparent glass exterior")
            chrome.requestMode(.originalPages)
            chrome.updateStatus(state: .reading, failed: true)
            try check(!chrome.statusBanner.isHidden && chrome.noticeBanner.isHidden, "Persistent failure suppresses transient notice")
            try check(chrome.brandMark.statusText.contains("불러오지 못했습니다") || chrome.brandMark.statusText.contains("이전 읽기 결과"), "Brand status describes the current failure")
            try check(window.firstResponder === responder, "Notification never steals focus")
            for preference in [NativeAppDesign.Preferences(theme: .light, increasedContrast: false, reduceTransparency: true, reduceMotion: true),
                               NativeAppDesign.Preferences(theme: .dark, increasedContrast: true, reduceTransparency: false, reduceMotion: true)] {
                chrome.noticeBanner.preferencesOverride = preference; chrome.noticeBanner.layoutSubtreeIfNeeded()
                try check(chrome.noticeBanner.effectView.isHidden && chrome.noticeBanner.contentView.layer?.masksToBounds == true && chrome.noticeBanner.layer?.masksToBounds == false, "Accessibility fallback remains inside rounded clip")
            }
        } else if scenario == "toolbar" {
            let mode = chrome.modeSegmentSurface
            let children = mode.accessibilityChildren() ?? []
            try check(chrome.brandMark.isAccessibilityElement() && chrome.brandMark.accessibilityRole() == .button, "Brand mark is an accessible button")
            try check(!mode.isAccessibilityElement() && children.count == 2 && (children[0] as AnyObject) === mode.reflowButton && (children[1] as AnyObject) === mode.pageButton && mode.reflowButton.accessibilityRole() == .radioButton && mode.pageButton.accessibilityRole() == .radioButton, "Mode switch exposes both radio buttons")
            var homes = 0; chrome.onOpenHome = { homes += 1 }
            chrome.brandMark.beginPress(at: .zero, timestamp: 0); chrome.brandMark.completeHold()
            try check(homes == 1, "Brand hold invokes reader Home callback")
            try check(chrome.modeSegmentSurface.bounds.size == NSSize(width: 140, height: 32), "Wide centered sliding switch")
            try check(abs(chrome.modeSegmentSurface.convert(chrome.modeSegmentSurface.bounds, to: root).midX - root.bounds.midX) < 1, "Reflow switch centered")
            for (selector, symbol) in [("triggerFind", "magnifyingglass"), ("toggleTools", "ellipsis")] {
                guard let button = views(root).compactMap({ $0 as? NativeDesignButton }).first(where: { $0.action.map(NSStringFromSelector) == selector }) else {
                    throw FlowError(message: "Toolbar cell must preserve target/action: \(selector)")
                }
                try check(button.symbolName == symbol && button.designRole == .ghost && button.bounds.size == NSSize(width: 32, height: 30),
                          "SF Symbol ghost toolbar: \(selector), symbol=\(button.symbolName ?? "nil"), role=\(button.designRole), bounds=\(button.bounds)")
                try check(button.target === chrome && button.keyEquivalent == (selector == "triggerFind" ? "f" : "t"), "Ghost cell retains action owner and key equivalent")
            }
            try check(host.textView.frame.width == root.bounds.width, "Document extends to window edges")
            let aa = views(root).compactMap { $0 as? NativeDesignButton }.first { $0.action == #selector(NativeReaderHostWindow.toggleDisplayPopover) }!
            aa.performClick(nil)
            try check(chrome.isDisplayPopoverOpen, "Aa ghost target/action opens display popover")
            aa.performClick(nil)
            try check(!chrome.isDisplayPopoverOpen && aa.designRole == .ghost, "Aa returns to ghost on close")
            chrome.pageMode(); try await until { host.visibleMode == .originalPages && host.session.state == .reading && host.originalPageView.isPreparedForPaint }
            root.layoutSubtreeIfNeeded()
            try check(chrome.modeSegmentSurface.bounds.size == NSSize(width: 80, height: 32) && !chrome.outlineToggleButton.isEnabled,
                      "Wide PDF uses compact mode switch and disabled outline")
            chrome.reflowMode(); try await until { host.visibleMode == .nativeReflow }
            window.setFrame(NSRect(x: 0, y: 0, width: 640, height: 752), display: false); root.layoutSubtreeIfNeeded()
            try check(chrome.modeSegmentSurface.bounds.size == NSSize(width: 80, height: 32), "Compact icon-only switch")
            chrome.pageMode(); try await until { host.visibleMode == .originalPages && host.session.state == .reading && host.originalPageView.isPreparedForPaint }
            try check(chrome.modeSegmentSurface.isHidden && chrome.outlineToggleButton.isHidden, "Narrow online PDF collapses switch and outline")
            chrome.updateStatus(state: .offline, failed: false, allowsRefresh: false, allowsModeSwitch: false)
            try check(views(root).compactMap { $0 as? NSTextField }.contains { $0.stringValue == "오프라인 PDF" && !$0.isHiddenOrHasHiddenAncestor }, "Exact offline badge")
            try check(!chrome.handleReaderShortcut(event(window, "0", .command)), "Cmd 0 remains owned by FlowApp")
        } else if scenario == "capsule" {
            let block = doc.blocks[1]
            try host.textView.select(from: .init(blockID: block.id, utf16: 0, affinity: .downstream), to: .init(blockID: block.id, utf16: 13, affinity: .upstream))
            chrome.showSelectionActions(); try await until { !chrome.capsule.isHidden }
            let capsule = chrome.capsule, ticket = host.store.selection!.ticket
            let binding = NativeFloatingCapsule.Binding(context: context, ticket: ticket, originalPDF: false)
            capsule.present(binding, unavailable: [:], summary: "")
            let clip = host.textView.scrollView.contentView, viewport = clip.convert(clip.bounds, to: root)
            chrome.placeCapsule(viewport: viewport, avoiding: host.textView.visibleSelectionRects(in: root))
            let body = host.textView.bodyTextView
            let manager = body.layoutManager!, container = body.textContainer!
            let glyphs = manager.glyphRange(forCharacterRange: body.selectedRange(), actualCharacterRange: nil)
            let selectedBounds = manager.boundingRect(forGlyphRange: glyphs, in: container)
                .offsetBy(dx: body.textContainerOrigin.x, dy: body.textContainerOrigin.y)
            let initial = body.convert(selectedBounds, to: root)
            let offset = capsule.frame.maxY + 10 - initial.minY
            clip.scroll(to: NSPoint(x: clip.bounds.minX, y: clip.bounds.minY + offset))
            host.textView.scrollView.reflectScrolledClipView(clip)
            let beforeClearance = body.convert(selectedBounds, to: root)
            try check(abs(beforeClearance.minY - capsule.frame.maxY - 10) < 0.5, "Short selection starts in the 8–11pt band")
            chrome.placeCapsule(viewport: viewport, avoiding: host.textView.visibleSelectionRects(in: root))
            let afterClearance = body.convert(selectedBounds, to: root)
            try check(afterClearance.minY >= capsule.frame.maxY + 11.5 && afterClearance.minY > beforeClearance.minY + 1,
                      "Short selection scrolls to 12pt clearance")
            try check(window.frame == originalFrame && capsule.surface.frame.height == 64 && capsule.surface.cornerRadius == 28, "Selection never resizes window and primary capsule is 64pt")
            try check(abs(capsule.frame.midX - viewport.midX) < 1 && abs(capsule.frame.minY - viewport.minY - 16) < 1, "Bottom center anchor")
            for action in NativeFloatingCapsule.Action.allCases {
                let tile = capsule.buttons[action]!
                try check(tile.identifier?.rawValue == "capsule." + action.rawValue && tile.frame.height == 54 && tile.frame.width >= 62, "Vertical action tile")
            }
            try check(capsule.closeButton.frame.size == NSSize(width: 36, height: 36), "Circular close target")
            capsule.focusFirstAction(); let first = window.firstResponder
            capsule.buttons[.copy]!.keyDown(with: event(window, "", [], code: 124))
            try check(window.firstResponder === capsule.buttons[.highlight], "Right advances focus")
            capsule.buttons[.highlight]!.keyDown(with: event(window, "", [.shift], code: 48))
            try check(window.firstResponder === first, "Shift Tab reverses focus")
            capsule.buttons[.copy]!.keyDown(with: event(window, "", [], code: 123))
            try check(window.firstResponder === capsule.closeButton, "Left wraps to close")
            capsule.closeButton.keyDown(with: event(window, "\t", [], code: 48))
            try check(window.firstResponder === first, "Tab wraps to first action")
            capsule.dismissExplicitly()
            try check(host.store.selection?.ticket == ticket && capsule.isHidden && window.frame == originalFrame, "Dismiss preserves selection, frame and focus")
            try check(root.performKeyEquivalent(with: event(window, "a", [.command, .option])), "Opt Cmd A reopens")
            try check(!capsule.isHidden && capsule.binding?.ticket == ticket, "Reopen uses same ticket")
            let old = capsule.binding!
            try host.textView.select(from: .init(blockID: block.id, utf16: 1, affinity: .downstream), to: .init(blockID: block.id, utf16: 14, affinity: .upstream))
            try await until { capsule.binding?.ticket != old.ticket && !capsule.isHidden }
            capsule.onDismiss?(old)
            try check(!capsule.isHidden && capsule.binding?.ticket == host.store.selection?.ticket, "Stale binding cannot dismiss newer selection")
            chrome.updateReaderControls(readOnly: false); chrome.reviewCount = 1
            try check(!chrome.reviewActionsCapsule.isHidden && chrome.reviewActionsCapsule.frame.height == 40 && abs(chrome.reviewActionsCapsule.frame.minY - capsule.frame.maxY - 8) < 1, "Review capsule sits above tools")
            var undos = 0, clears = 0
            chrome.onUndoReview = { undos += 1 }; chrome.onClearReview = { clears += 1 }
            for button in views(chrome.reviewActionsCapsule).compactMap({ $0 as? NSButton }) {
                try check(NSApp.sendAction(button.action!, to: button.target, from: button), "Review target/action is connected")
            }
            try check(undos == 1 && clears == 1, "Upper review buttons dispatch once to their existing owners")
            chrome.updateReaderControls(readOnly: true)
            try check(chrome.reviewActionsCapsule.isHidden, "Read only state hides review actions")
            capsule.compact = true; capsule.present(binding, unavailable: [:], summary: "최대 32개 블록")
            try check(capsule.buttons[.source]!.isHidden && capsule.buttons[.editor]!.isHidden && !capsule.overflowButton.isHidden && !capsule.footnote.isHidden, "Compact tools overflow with limit mini pill")
            chrome.placeCapsule(viewport: viewport, avoiding: host.textView.visibleSelectionRects(in: root))
            try check(host.textView.scrollView.contentInsets.bottom >= 132, "Footnote reserves space above the primary capsule")
            chrome.showSelectionActions(); capsule.focusFirstAction(); chrome.toggleDisplayPopover()
            window.sendEvent(event(window, "\u{1b}", [], code: 53))
            try check(!chrome.isDisplayPopoverOpen && !capsule.isHidden && host.store.selection != nil,
                      "Actual Escape closes Aa before tools even with capsule focus")
            chrome.releasePageSelection()
            let last = doc.blocks.last!
            let scroll = host.textView.scrollView
            scroll.contentView.scroll(to: NSPoint(x: 0, y: body.bounds.height - scroll.contentView.bounds.height))
            scroll.reflectScrolledClipView(scroll.contentView)
            try host.textView.select(from: .init(blockID: last.id, utf16: last.displayText.utf16.count - 12, affinity: .downstream),
                                     to: .init(blockID: last.id, utf16: last.displayText.utf16.count, affinity: .upstream))
            chrome.showSelectionActions(); try await until { !capsule.isHidden }
            try check(scroll.contentInsets.bottom >= 104 && !host.textView.visibleSelectionRects(in: root).isEmpty &&
                      !host.textView.visibleSelectionRects(in: root).contains { $0.intersects(capsule.frame) },
                      "Final Reflow selection scrolls above tools using the reserved bottom inset")
            try check(window.frame == originalFrame, "Selection release and final-paragraph reveal keep window frame unchanged")
        } else if scenario == "review-existing" || scenario == "review-added" || scenario == "review-offset" {
            if scenario == "review-existing" {
                let first = doc.blocks[1]
                try host.textView.select(from: .init(blockID: first.id, utf16: 0, affinity: .downstream),
                    to: .init(blockID: first.id, utf16: 13, affinity: .upstream))
                chrome.markSelected(); chrome.releasePageSelection()
                try check(chrome.reviewCount == 1, "Existing review retained")
            }
            let scroll = host.textView.scrollView, body = host.textView.bodyTextView, last = doc.blocks.last!
            scroll.contentView.scroll(to: NSPoint(x: 0, y: body.bounds.height - scroll.contentView.bounds.height))
            scroll.reflectScrolledClipView(scroll.contentView)
            let start = scenario == "review-offset" ? 0 : last.displayText.utf16.count - 12
            let end = scenario == "review-offset" ? 6 : last.displayText.utf16.count
            if scenario == "review-offset" { chrome.reviewCount = 1 }
            try host.textView.select(from: .init(blockID: last.id, utf16: start, affinity: .downstream),
                to: .init(blockID: last.id, utf16: end, affinity: .upstream))
            chrome.showSelectionActions(); try await until { !chrome.capsule.isHidden }
            if scenario == "review-added" { chrome.markSelected() }
            try await Task.sleep(nanoseconds: 200_000_000)
            root.layoutSubtreeIfNeeded()
            let manager = body.layoutManager!, container = body.textContainer!
            let glyphs = manager.glyphRange(forCharacterRange: body.selectedRange(), actualCharacterRange: nil)
            let fullBounds = manager.boundingRect(forGlyphRange: glyphs, in: container)
                .offsetBy(dx: body.textContainerOrigin.x, dy: body.textContainerOrigin.y)
            let selectionRect = body.convert(fullBounds, to: root)
            let viewport = scroll.contentView.convert(scroll.contentView.bounds, to: root)
            let primary = chrome.capsule.convert(chrome.capsule.surface.frame, to: root)
            let review = chrome.reviewActionsCapsule.convert(chrome.reviewActionsCapsule.bounds, to: root)
            try check(chrome.reviewCount == 1 && !chrome.reviewActionsCapsule.isHidden, "Review tools visible")
            let obstruction = primary.union(review)
            try check(scroll.contentInsets.bottom >= 148 && selectionRect.minY >= obstruction.maxY + 11.5 && selectionRect.maxY <= viewport.maxY + 0.5,
                "Full selection clears both capsules and remains visible: selection=\(selectionRect), obstruction=\(obstruction), viewport=\(viewport)")
            if scenario == "review-offset" {
                try check(selectionRect.maxX < obstruction.minX, "Narrow selection is horizontally offset from tools")
            }
            try check(window.frame == originalFrame, "Review never resizes window")
            chrome.reviewCount = 0
            try check(scroll.contentInsets.bottom == 104, "Removing review restores base inset")
        } else if scenario == "tall-selection" {
            let scroll = host.textView.scrollView, body = host.textView.bodyTextView
            let first = doc.blocks[30], last = doc.blocks[39]
            try host.textView.select(from: .init(blockID: first.id, utf16: 0, affinity: .downstream),
                to: .init(blockID: last.id, utf16: last.displayText.utf16.count, affinity: .upstream))
            let manager = body.layoutManager!, container = body.textContainer!
            let glyphs = manager.glyphRange(forCharacterRange: body.selectedRange(), actualCharacterRange: nil)
            let bounds = manager.boundingRect(forGlyphRange: glyphs, in: container)
                .offsetBy(dx: body.textContainerOrigin.x, dy: body.textContainerOrigin.y)
            let clip = scroll.contentView
            clip.scroll(to: NSPoint(x: 0, y: bounds.maxY - clip.bounds.height + 100))
            scroll.reflectScrolledClipView(clip)
            chrome.showSelectionActions(); try await until { !chrome.capsule.isHidden }
            let viewport = clip.convert(clip.bounds, to: root)
            let obstruction = chrome.capsule.frame
            // Leave positive headroom while the selection end intersects the tools.
            clip.scroll(to: NSPoint(x: 0, y: bounds.minY - 20))
            scroll.reflectScrolledClipView(clip)
            let before = body.convert(bounds, to: root)
            let headroom = viewport.maxY - before.maxY
            try check(headroom > 10 && before.height > viewport.maxY - (obstruction.maxY + 12) &&
                      before.minY < obstruction.maxY + 8 && before.maxY <= viewport.maxY + 0.5,
                      "Tall selection intersects the obstruction with its start in view: \(before)")
            chrome.placeCapsule(viewport: viewport, avoiding: host.textView.visibleSelectionRects(in: root))
            let selectionRect = body.convert(bounds, to: root)
            try check(abs(selectionRect.maxY - before.maxY - headroom) < 0.5, "Tall selection uses available headroom")
            try check(selectionRect.maxY <= viewport.maxY + 0.5, "Tall selection start stays within viewport: \(selectionRect), viewport=\(viewport)")
            try check(window.frame == originalFrame, "Tall selection never resizes window")
        } else if scenario == "pending-strike" {
            let block = doc.blocks[1]
            try host.textView.select(from: .init(blockID: block.id, utf16: 0, affinity: .downstream),
                to: .init(blockID: block.id, utf16: 13, affinity: .upstream))
            chrome.showSelectionActions()
            let ticket = host.store.selection!.ticket
            host.session.refresh()
            try check((try? host.session.authorize(context, selection: ticket)) == nil, "Pending refresh gates services")
            var serviceCalls = 0
            host.textView.callbacks.sourceRequested = { _ in serviceCalls += 1 }
            chrome.capsule.onAction?(chrome.capsule.binding!, .highlight)
            try check(serviceCalls == 0, "Service action remains gated")
            chrome.capsule.buttons[.strike]!.performClick(nil)
            try check(chrome.reviewCount == 1 && host.store.selection?.ticket == ticket, "Strike tile applies during held refresh")
            _ = root.performKeyEquivalent(with: event(window, "s", [.command, .shift]))
            try check(chrome.reviewCount == 2, "Shortcut applies the same local review")
        } else if scenario == "keyboard-pdf" {
            var strikes = 0, highlights = 0, asks = 0, refreshes = 0
            chrome.onMarkReview = { strikes += 1 }; chrome.onRefresh = { refreshes += 1 }
            host.textView.callbacks.sourceRequested = { if $0.action == .highlight { highlights += 1 } }
            host.textView.callbacks.chatRequested = { _, _ in asks += 1 }
            chrome.updateReaderControls(readOnly: false)
            let block = doc.blocks[1]
            try host.textView.select(from: .init(blockID: block.id, utf16: 0, affinity: .downstream), to: .init(blockID: block.id, utf16: 13, affinity: .upstream))
            for key in ["s", "h", "k"] { try check(root.performKeyEquivalent(with: event(window, key, [.command, .shift])), "Review/highlight/Ask shortcut handled") }
            try check(strikes == 1 && highlights == 1 && asks == 1, "Shortcuts call existing action owners once")
            try check(root.performKeyEquivalent(with: event(window, "r", .command)), "Held refresh shortcut handled")
            let release = views(root).compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == "releasePageSelection" }!
            try check(refreshes == 0 && !chrome.statusBanner.isHidden && !release.isHiddenOrHasHiddenAncestor && window.firstResponder === release,
                      "Held refresh keeps selection and focuses visible release action")
            chrome.releasePageSelection()
            try check(root.performKeyEquivalent(with: event(window, "r", .command)), "Cmd R routed")
            try check(root.performKeyEquivalent(with: event(window, "\r", .shift, code: 36)), "Shift Return routed")
            try check(refreshes == 2, "Refresh shortcuts call existing owner")
            window.makeFirstResponder(host.textView.bodyTextView)
            NSApp.sendEvent(event(window, "\r", .shift, code: 36))
            try check(refreshes == 3, "Ordinary Shift Return keyDown refreshes before the body consumes it")
            try check(root.performKeyEquivalent(with: event(window, "2", .command)), "Cmd 2 PDF")
            try await until { host.visibleMode == .originalPages && host.session.state == .reading && host.originalPageView.isPreparedForPaint }
            try check(root.performKeyEquivalent(with: event(window, "\\", .command)), "Cmd backslash handled in PDF")
            try check(chrome.currentMode == .originalPages, "Outline shortcut preserves PDF mode")
            let frame = window.frame
            let acceptedPDF = host.originalPageView.store.accepted!.binding.pdfSHA256
            let hit = try await host.originalPageView.search("Search needle").last!
            try host.originalPageView.jump(to: hit.pageIndex)
            try await until { host.originalPageView.isPreparedForPaint }
            try await host.originalPageView.select(page: hit.pageIndex, range: hit.rangeUTF16)
            try await until { !chrome.capsule.isHidden }
            try check(chrome.capsule.footnote.stringValue == "원본 PDF · 복사·검색만 지원" && chrome.capsule.buttons[.strike]!.isHidden, "PDF only Copy and exact mini pill")
            try check(chrome.capsule.footnote.frame.width >= chrome.capsule.footnote.intrinsicContentSize.width,
                      "PDF capability footnote is fully visible in the Copy-only capsule")
            try check(window.frame == frame && host.originalPageView.enclosingScrollView!.contentInsets.bottom >= 88, "PDF avoids tools through inset without resize")
            let pdfSelection = host.originalPageView.selected!
            let selectedRect = try host.originalPageView.store.viewRect(forPageRect: pdfSelection.pageBounds)
            let inkRect = host.originalPageView.convert(selectedRect, to: root)
            try check(!inkRect.intersects(chrome.capsule.frame), "PDF selection ink is scrolled above tools")
            try check(host.originalPageView.store.accepted!.binding.pdfSHA256 == acceptedPDF && SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() == acceptedPDF, "Chrome preserves exact accepted PDF bytes")
            try check(chrome.handleReaderEscape() && host.originalPageView.selected != nil && chrome.capsule.isHidden, "First Esc hides tools preserving PDF selection")
            try check(chrome.handleReaderEscape() && host.originalPageView.selected == nil, "Next Esc releases PDF selection")
            chrome.findField.stringValue = "Search needle"; chrome.findPage()
            try await until { chrome.currentSearchSelectionTicket != nil && !chrome.capsule.isHidden }
            let searchTicket = host.originalPageView.store.selection!.0
            chrome.capsule.dismissExplicitly()
            try check(host.originalPageView.store.selection?.0 == searchTicket && chrome.currentSearchSelectionTicket == searchTicket, "Search-hit capsule close preserves its PDF ticket")
            chrome.showSelectionActions()
            try check(!chrome.capsule.isHidden, "Search-hit tools reopen for same ticket")
            chrome.triggerFind()
            window.sendEvent(event(window, "\u{1b}", [], code: 53))
            try check(chrome.findField.stringValue.isEmpty && host.originalPageView.store.selection?.0 == searchTicket && !chrome.capsule.isHidden,
                      "Actual Find-field Escape closes search before tools, preserving selection")
            window.sendEvent(event(window, "\u{1b}", [], code: 53))
            try check(chrome.capsule.isHidden && host.originalPageView.store.selection?.0 == searchTicket, "Second Escape hides search-hit tools, preserving selection")
            window.sendEvent(event(window, "\u{1b}", [], code: 53))
            try check(host.originalPageView.selected == nil, "Third Escape releases search-hit selection")
            try check(root.performKeyEquivalent(with: event(window, "1", .command)), "Cmd 1 Reflow")
            try await until { host.visibleMode == .nativeReflow }
            var appearance = host.textView.textAppearance; appearance.zoom = 1.25; try host.textView.setAppearance(appearance)
            try check(root.performKeyEquivalent(with: event(window, "0", [.command, .option])), "Opt Cmd 0 reset")
            try check(host.textView.textAppearance.zoom == 1, "Zoom reset distinct from Home")
        } else { throw FlowError(message: "Unknown parity scenario") }
        try check(NSApp.activationPolicy() == .prohibited && NSApp.windows.allSatisfy { !$0.isVisible && !$0.isKeyWindow && !$0.isMainWindow }, "Headless only; no visible/key/main windows")
        print("\(scenario): \(assertions) assertions; offscreen AppKit only")
    }
}
