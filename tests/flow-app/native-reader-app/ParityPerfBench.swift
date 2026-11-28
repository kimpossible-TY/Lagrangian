import AppKit
import Foundation

private struct BenchInput: NativeReaderDocumentProviding {
    let value: NativeReaderDocument
    func document(for context: NativeReaderRequestContext) async throws -> NativeReaderDocument {
        value.rebinding(generation: context.generation)
    }
}

@main struct ParityPerfBench {
    static func node(_ id: String, _ text: String, _ kind: NativeReaderNode.Kind,
                     children: [NativeReaderNode] = [], link: String? = nil) -> NativeReaderNode {
        .init(id: id, sectionID: "section", kind: kind, canonicalText: text, displayText: text,
              rangeUTF16: [0, text.utf16.count], offsets: NativeTextOffsets(text), children: children,
              anchors: [], annotationTargets: [], visible: true, mapping: .unmapped, passageKey: nil,
              direction: nil, language: nil, headingLevel: nil, math: nil, cell: nil, link: link, assetID: nil, alt: nil)
    }
    static func document() -> NativeReaderDocument {
        let blocks = (0..<600).map { index in
            let label = "Link number \(index)"
            let leaf = node("text\(index)", label, .text)
            let link = node("link\(index)", label, .link, children: [leaf], link: "https://example.com/\(index)")
            return node("block\(index)", label, .paragraph, children: [link])
        }
        return .init(schemaVersion: 1, identity: .init(documentID: "bench", serviceID: "reader:1:1", revision: "r1", scope: .service),
                     generation: 1, requiredCapabilities: ["semantic-tree-v1"], blocks: blocks, assets: [], diagnostics: [])
    }
    @MainActor static func main() async {
        do { try await run() } catch { fputs("Benchmark failed: \(error)\n", stderr); exit(1) }
    }
    @MainActor static func run() async throws {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.prohibited)
        let doc = document(); try doc.validate()
        let host = NativeReaderWindowController(provider: BenchInput(value: doc), target: { _ in doc.identity },
                                                show: false, avoidActivation: true, fixtureMode: true)
        defer { host.dispose() }
        let profile = Profile(id: "bench", name: "Bench", root: NSTemporaryDirectory(), entry: "main.typ", fonts: [], packages: "", port: 23620, publicURL: "", label: "owned.bench")
        _ = host.open(profile) { _ in }
        for _ in 0..<2000 {
            if host.session.state == .reading && host.textView.renderKey != nil && host.textView.renderKey == host.textView.requestedRenderKey { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        guard host.session.state == .reading, host.textView.renderKey != nil,
              host.textView.renderKey == host.textView.requestedRenderKey,
              let window = host.hostWindow.window, let root = window.contentView,
              let storage = host.textView.bodyTextView.textStorage,
              let manager = host.textView.bodyTextView.layoutManager,
              let container = host.textView.bodyTextView.textContainer else { throw FlowError(message: "Reader did not load") }
        window.setFrame(NSRect(x: 0, y: 0, width: 980, height: 752), display: false)
        root.layoutSubtreeIfNeeded(); window.displayIfNeeded()
        let body = host.textView.bodyTextView, clip = host.textView.scrollView.contentView
        manager.ensureLayout(for: container)
        var points: [NSPoint] = []
        storage.enumerateAttribute(NSAttributedString.Key("NativeReaderLink"), in: NSRange(location: 0, length: storage.length)) { value, range, stop in
            guard value != nil else { return }
            let glyphs = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let rect = manager.boundingRect(forGlyphRange: glyphs, in: container)
            if !rect.isEmpty {
                points.append(NSPoint(x: rect.midX + body.textContainerOrigin.x, y: rect.midY + body.textContainerOrigin.y))
                if points.count == 2 { stop.pointee = true }
            }
        }
        guard points.count == 2 else { throw FlowError(message: "Two rendered links required") }
        let n = 500, runs = 5
        var scroll = [Double](), hover = [Double](), cursor = [Double]()
        func ms(_ start: UInt64) -> Double { Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000 }
        for _ in 0..<runs {
            let start = DispatchTime.now().uptimeNanoseconds
            for step in 0..<n {
                clip.scroll(to: NSPoint(x: 0, y: CGFloat(step % 200) * 3))
                host.textView.scrollView.reflectScrolledClipView(clip)
                root.layoutSubtreeIfNeeded(); window.displayIfNeeded()
            }
            scroll.append(ms(start))
            clip.scroll(to: .zero); host.textView.scrollView.reflectScrolledClipView(clip)
            root.layoutSubtreeIfNeeded(); window.displayIfNeeded()
            let hoverStart = DispatchTime.now().uptimeNanoseconds
            for step in 0..<n {
                let point = points[(step / 2) % 2]
                let moved = NSPoint(x: point.x + CGFloat(step % 2), y: point.y)
                let event = NSEvent.mouseEvent(with: .mouseMoved, location: body.convert(moved, to: nil), modifierFlags: [], timestamp: 0,
                                               windowNumber: window.windowNumber, context: nil, eventNumber: step, clickCount: 0, pressure: 0)!
                body.mouseMoved(with: event)
            }
            hover.append(ms(hoverStart))
            let cursorStart = DispatchTime.now().uptimeNanoseconds
            body.resetCursorRects()
            cursor.append(ms(cursorStart))
        }
        var scrollHandler = [Double](), foreignBounds = [Double](), sameValueLayout = [Double]()
        // Repeat the legacy scroll positions without forcing a window redraw.
        for _ in 0..<runs {
            clip.scroll(to: .zero); host.textView.scrollView.reflectScrolledClipView(clip)
            root.layoutSubtreeIfNeeded()
            let start = DispatchTime.now().uptimeNanoseconds
            for step in 0..<n {
                clip.scroll(to: NSPoint(x: 0, y: CGFloat(step % 200) * 3))
                host.textView.scrollView.reflectScrolledClipView(clip)
                root.layoutSubtreeIfNeeded()
            }
            scrollHandler.append(ms(start))
        }
        clip.scroll(to: .zero); host.textView.scrollView.reflectScrolledClipView(clip)
        root.layoutSubtreeIfNeeded()

        // An attached, unrelated clip view exercises global bounds observers.
        let foreignScroll = NSScrollView(frame: NSRect(x: -200, y: 0, width: 100, height: 100))
        foreignScroll.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 1200))
        let foreignClip = foreignScroll.contentView
        foreignClip.postsBoundsChangedNotifications = true
        root.addSubview(foreignScroll)
        root.layoutSubtreeIfNeeded()
        for _ in 0..<runs {
            foreignClip.scroll(to: .zero)
            root.layoutSubtreeIfNeeded()
            let start = DispatchTime.now().uptimeNanoseconds
            for step in 0..<n {
                foreignClip.scroll(to: NSPoint(x: 0, y: CGFloat(step % 200) * 3))
                root.layoutSubtreeIfNeeded()
            }
            foreignBounds.append(ms(start))
        }
        foreignScroll.removeFromSuperview()
        // Settle fixture changes before timing unchanged root layout passes.
        root.needsLayout = true
        root.layoutSubtreeIfNeeded()
        for _ in 0..<runs {
            let start = DispatchTime.now().uptimeNanoseconds
            for _ in 0..<n {
                root.needsLayout = true
                root.layoutSubtreeIfNeeded()
            }
            sameValueLayout.append(ms(start))
        }
        func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }
        let scrollTotal = median(scroll), hoverTotal = median(hover)
        let scrollHandlerTotal = median(scrollHandler), foreignBoundsTotal = median(foreignBounds)
        let result: [String: Any] = ["n": n, "runs": runs, "document_links": 600,
            "scroll_ms_total": scrollTotal, "scroll_ms_per_step": scrollTotal / Double(n),
            "scroll_handler_ms_total": scrollHandlerTotal, "scroll_handler_ms_per_step": scrollHandlerTotal / Double(n),
            "foreign_bounds_ms_total": foreignBoundsTotal, "foreign_bounds_ms_per_step": foreignBoundsTotal / Double(n),
            "same_value_layout_ms": median(sameValueLayout),
            "hover_ms_total": hoverTotal, "hover_ms_per_call": hoverTotal / Double(n), "cursor_rects_ms": median(cursor)]
        let json = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: json, as: UTF8.self))
    }
}
