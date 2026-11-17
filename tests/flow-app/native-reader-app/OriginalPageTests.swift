import AppKit
import CryptoKit
import Darwin

private actor PageSwitch {
    let transport: NativeReaderOriginalPageTransport
    var failing = false
    init(_ transport: NativeReaderOriginalPageTransport) { self.transport = transport }
    func fail(_ value: Bool) { failing = value }
    func pages(_ context: NativeReaderRequestContext) async throws -> NativeOriginalPageDelivery {
        if failing { throw NativeOriginalPageError.invalidPDF }
        return try await transport.pages(for: context)
    }
}

/// Explicitly injected malformed/delayed peer, separate from actual HTTP proof.
private actor PagePeer {
    var manifest: [String: Any]
    let data: Data
    var corrupt = false, delayed = false, disconnected = false
    init(_ delivery: NativeOriginalPageDelivery) throws {
        manifest = try JSONSerialization.jsonObject(with: JSONEncoder().encode(delivery.publication)) as! [String: Any]
        data = delivery.data
    }
    func edit(_ key: String, _ value: Any) { manifest[key] = value }
    func delay(_ value: Bool) { delayed = value }
    func corruptBytes(_ value: Bool) { corrupt = value }
    func disconnect(_ value: Bool) { disconnected = value }
    func send(_ request: URLRequest, limit: Int) async throws -> NativeReaderHTTPResponse {
        if delayed { try? await Task.sleep(nanoseconds: 200_000_000) }
        if disconnected { throw NativeReaderOperationFailure.unavailable }
        if request.url!.path.hasSuffix(".pdf") {
            return .init(status: 200, headers: ["content-type":"application/pdf"], data: corrupt ? Data("tampered".utf8) : data)
        }
        var value = manifest
        let fields = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
        for field in fields where ["generation", "requestID", "viewID"].contains(field.name) {
            value[field.name] = field.name == "generation" ? Int(field.value!)! : field.value!
        }
        value["resource"] = "api/native-pages/\(value["publicationID"]!)/\(value["sequence"]!).pdf"
        return .init(status: 200, headers: ["content-type":"application/json"], data: try JSONSerialization.data(withJSONObject: value))
    }
}

@main struct OriginalPageTests {
    @MainActor static var assertions = 0
    @MainActor static func check(_ value: @autoclosure () -> Bool, _ message: String) throws {
        assertions += 1
        if !value() { throw NSError(domain: message, code: 1) }
    }
    @MainActor static func until(_ condition: () -> Bool) async throws {
        for _ in 0..<3000 { if condition() { return }; try await Task.sleep(nanoseconds: 10_000_000) }
        throw NSError(domain: "native page wait timeout", code: 1)
    }
    @MainActor static func rejected(_ message: String, _ body: () async throws -> Void) async throws {
        do { try await body() } catch { assertions += 1; return }
        throw NSError(domain: "negative accepted: " + message, code: 1)
    }
    @MainActor static func paint(_ view: NSView, to url: URL) throws -> String {
        let size = view.bounds.size
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0), let graphics = NSGraphicsContext(bitmapImageRep: rep) else { throw NativeOriginalPageError.budget }
        view.displayIgnoringOpacity(view.bounds, in: graphics)
        let data = rep.representation(using: .png, properties: [:])!
        try data.write(to: url)
        return NativeReaderRecoverySnapshot.digest(data)
    }
    @MainActor static func transportNegatives(_ delivery: NativeOriginalPageDelivery, attachment: NativeReaderAttachment, context: NativeReaderRequestContext) async throws {
        let peer = try PagePeer(delivery)
        let network = NativeReaderNetwork(send: { request, limit in try await peer.send(request, limit: limit) }, stream: { _ in AsyncThrowingStream { $0.finish() } })
        let base = NativeReaderTransport(attachment: attachment, network: network)
        let transport = NativeReaderOriginalPageTransport(transport: base)
        _ = try await transport.pages(for: context)
        for (key, bad) in [("capability", "unknown"), ("serviceID", "reader:wrong"), ("revision", "old"), ("publicationID", UUID().uuidString.lowercased()), ("inputFingerprint", String(repeating: "0", count: 64))] {
            let original = try JSONSerialization.jsonObject(with: JSONEncoder().encode(delivery.publication)) as! [String: Any]
            await peer.edit(key, bad)
            try await rejected("transport " + key) { _ = try await transport.pages(for: context) }
            await peer.edit(key, original[key]!)
        }
        await peer.edit("sequence", delivery.publication.sequence + 1)
        _ = try await transport.pages(for: context)
        await peer.edit("sequence", delivery.publication.sequence)
        try await rejected("out-of-order sequence") { _ = try await transport.pages(for: context) }
        await peer.edit("sequence", delivery.publication.sequence + 1)
        await peer.corruptBytes(true)
        try await rejected("resource tamper") { _ = try await transport.pages(for: context) }
        await peer.corruptBytes(false); await peer.delay(true)
        let waiting = Task { try await transport.pages(for: context) }
        try await Task.sleep(nanoseconds: 30_000_000); await transport.invalidate()
        try await rejected("invalidated late network") { _ = try await waiting.value }
        let cancelled = Task { try await transport.pages(for: context) }
        try await Task.sleep(nanoseconds: 30_000_000); cancelled.cancel()
        try await rejected("cancelled late network") { _ = try await cancelled.value }
        await peer.delay(false); await peer.disconnect(true)
        try await rejected("disconnected") { _ = try await transport.pages(for: context) }
        await peer.disconnect(false); await transport.dispose()
        try await rejected("disposed") { _ = try await transport.pages(for: context) }
    }
    @MainActor static func hostilePDFs(_ out: URL) async throws {
        let identity = NativeDocumentIdentity(documentID: "hostile-fixture", serviceID: "fixture", revision: "owned", scope: .fixture)
        let preparer = NativeOriginalPagePreparer()
        var limits = NativeOriginalPageLimits(); limits.lazy = true
        for name in ["js", "launch", "form", "embed", "unsafe", "unknown"] {
            let data = try Data(contentsOf: out.appendingPathComponent(name + ".pdf"))
            let binding = NativeOriginalPageBinding(identity: identity, inputFingerprint: String(repeating: "a", count: 64),
                snapshotGeneration: 1, requestGeneration: 1, viewID: UUID(), viewGeneration: 0, publicationSequence: 1,
                pdfSHA256: NativeReaderRecoverySnapshot.digest(data), pages: [.init(index: 0, mediaBox: CGRect(x: 0, y: 0, width: 320, height: 360), cropBox: CGRect(x: 0, y: 0, width: 320, height: 360), rotation: 0)])
            if name == "unsafe" || name == "unknown" {
                let prepared = try await preparer.prepare(.init(binding: binding, data: data), expected: binding, limits: limits)
                let links = try await prepared.access.links(page: 0)
                try check(links.isEmpty, "unsafe/unknown PDF link became callback")
            } else {
                try await rejected("lazy hostile PDF " + name) { _ = try await preparer.prepare(.init(binding: binding, data: data), expected: binding, limits: limits) }
            }
        }
    }
    @MainActor static func main() async {
        do { try await run() } catch { fputs("ORIGINAL PAGE FAILURE: \(error)\n", stderr); exit(1) }
    }
    @MainActor static func run() async throws {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.prohibited)
        let configURL = URL(fileURLWithPath: CommandLine.arguments[1]), out = URL(fileURLWithPath: CommandLine.arguments[2])
        let config = try JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as! [String: Any]
        let attachmentData = try JSONSerialization.data(withJSONObject: config["attachment"]!)
        let attachment = try NativeReaderAttachment(data: attachmentData)
        let identity = NativeDocumentIdentity(documentID: attachment.documentID, serviceID: attachment.serviceID,
            revision: config["revision"] as! String, scope: .service)
        let network = NativeReaderNetwork.urlSession(), transport = NativeReaderTransport(attachment: attachment, network: network)
        let pageTransport = NativeReaderOriginalPageTransport(transport: transport), pageSwitch = PageSwitch(pageTransport)
        var sourceDispatches = 0
        let host = NativeReaderWindowController(provider: transport, target: { _ in identity },
            actions: { sourceDispatches += 1; throw NativeReaderOperationFailure.unavailable },
            originalPages: { try await pageSwitch.pages($0) }, show: false, avoidActivation: true)
        let profile = Profile(id: "NA12", name: "Owned synthetic PDF", root: out.path, entry: "main.typ", fonts: [], packages: "", port: 24650, publicURL: "", label: "test.page")
        var events = [String]()
        let oldCancel = host.open(profile) { event in
            switch event { case .accepted: events.append("accepted"); case .windowInitialized: events.append("initialized")
            case .painted: events.append("painted"); case .failed: events.append("failed") }
        }
        try await until { host.session.state == .reading || host.session.failure != nil }
        try check(host.session.failure == nil, "initial reflow failed \(host.diagnostic ?? "")")
        try check(host.store === host.session.store && host.store === host.textView.store, "canonical store duplicated")
        try host.setMode(.originalPages)
        try await until { host.visibleMode == .originalPages || host.session.failure != nil }
        try check(host.session.failure == nil, "original adoption failed \(host.diagnostic ?? "")")
        let view = host.originalPageView
        host.hostWindow.sourceSelected(); host.hostWindow.highlightSelected(); host.hostWindow.askSelected()
        try check(sourceDispatches == 0, "page mode dispatched hidden reflow source/chat")
        try await until { view.isPreparedForPaint }
        try check(view.enclosingScrollView?.documentView === view, "original PDF has no native scroll viewport")
        let accepted = view.store.accepted!
        try check(accepted.binding.pages.count == 256, "not actual 256 pages")
        try check(accepted.pages.isEmpty && !accepted.preparationWasMainThread, "eager raster or main-thread prepare")
        try check(view.store.paintAcknowledgment == nil || view.paintCount > 0, "adoption claimed paint without actual draw")
        let beforeHidden = events.count
        _ = try paint(host.textView.bodyTextView, to: out.appendingPathComponent("hidden-reflow.png"))
        try check(events.count == beforeHidden, "hidden reflow acknowledged page Read")
        let firstPaint = try paint(view, to: out.appendingPathComponent("page-0.png"))
        try check(view.store.paintAcknowledgment?.pageIndex == 0 && events.last == "painted", "actual page draw not acknowledged")
        let initialMetrics = await accepted.access.metrics()
        try check(initialMetrics["renderedPages"] == 1, "all pages rasterized at adoption")
        let down = NSEvent.mouseEvent(with: .leftMouseDown, location: CGPoint(x: 40, y: 50), modifierFlags: [], timestamp: 0,
            windowNumber: host.hostWindow.window!.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        let up = NSEvent.mouseEvent(with: .leftMouseUp, location: CGPoint(x: 140, y: 70), modifierFlags: [], timestamp: 1,
            windowNumber: host.hostWindow.window!.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 0)!
        view.mouseDown(with: down)
        try view.jump(to: 128); try await until { view.isPreparedForPaint }; view.mouseUp(with: up)
        try check(view.selected == nil && !host.session.hasSelection, "old pointer geometry selected a new page")
        for index in [128, 255, 1, 64, 200, 0] {
            try view.jump(to: index); try await until { view.isPreparedForPaint }
            _ = try paint(view, to: out.appendingPathComponent("page-\(index).png"))
            try check(view.store.paintAcknowledgment?.pageIndex == index, "far page receipt")
        }
        let hits = try await view.search("FarNeedle255")
        try check(hits.count == 1 && hits[0].pageIndex == 255 && hits[0].pageBounds.width > 0, "far PDF search/text bounds")
        try view.jump(to: 255); try await until { view.isPreparedForPaint }
        try await view.select(page: 255, range: hits[0].rangeUTF16)
        let privateBoard = NSPasteboard(name: .init("dev.lagrangian.NA12." + UUID().uuidString))
        host.copyText = { privateBoard.clearContents(); return privateBoard.writeObjects([$0 as NSString]) }
        try check(view.copyDisplay() && privateBoard.string(forType: .string) == "FarNeedle255", "PDF display copy not exact")
        try await rejected("PDF source authority") { _ = try view.selected!.verifiedSourceAnchor() }
        try await rejected("mode held") { try host.setMode(.nativeReflow) }
        try await rejected("held zoom") { try view.zoom(1.5) }
        let heldSnapshot = view.store.accepted!.id
        host.refresh(); try await until { host.session.state != .loading }
        try check(view.store.accepted?.id == heldSnapshot && view.selected?.displayText == "FarNeedle255", "refresh replaced held PDF")
        host.hostWindow.releasePageSelection(); try await until { host.session.state == .reading && view.store.accepted?.id != heldSnapshot }
        try await until { view.isPreparedForPaint }
        try view.zoom(1.5); try await until { view.isPreparedForPaint }
        _ = try paint(view, to: out.appendingPathComponent("page-255-zoom.png"))
        try check(view.store.paintAcknowledgment?.scale == 1.5, "zoom did not repaint")
        view.setFrameSize(NSSize(width: 700, height: 600)); try await until { view.isPreparedForPaint }
        try check(view.store.scale == 1.5, "resize lost manual zoom")
        try view.zoom(2); try await until { view.isPreparedForPaint }
        let scroll = view.enclosingScrollView!
        try check(view.frame.height > scroll.contentSize.height, "zoomed page bottom not scrollable")
        let scrollY = min(60, max(0, view.frame.height - scroll.contentSize.height))
        scroll.contentView.scroll(to: CGPoint(x: 0, y: scrollY)); scroll.reflectScrolledClipView(scroll.contentView)
        let recovery = try view.recovery()
        try check((recovery.offsetY ?? 0) > 0, "scroll offset not captured")
        let recoveryOwner = NativeReaderRecoveryStore(root: out.appendingPathComponent("recovery"))
        try await host.saveRecovery(to: recoveryOwner)
        let disk = try await recoveryOwner.load(identity: identity)
        try check(disk.originalPages != nil, "typed page recovery missing")
        try view.jump(to: 0); try await until { view.isPreparedForPaint }
        try view.restore(recovery); try await until { view.isPreparedForPaint }
        try check(view.store.pageIndex == 255 && view.store.scale == 2, "far recovery")
        try check(abs(scroll.contentView.bounds.origin.y - scrollY) < 1, "native viewport offset not restored")
        try await rejected("wrong recovery digest") {
            try view.restore(.init(identity: recovery.identity, fingerprint: recovery.fingerprint, digest: String(repeating: "0", count: 64), page: 255, scale: 1))
        }
        let checkedDelivery = try await pageSwitch.pages(host.session.context!)
        try await transportNegatives(checkedDelivery, attachment: attachment, context: host.session.context!)
        let latest = view.store.accepted!, metrics = await accepted.access.metrics()
        try check(metrics["cachedPages"]! <= 3 && metrics["peakRasterBytes"]! <= 16777216 && metrics["textPages"]! <= 8 && metrics["peakTextBytes"]! <= 1048576 && metrics["evictions"]! > 0, "lazy budgets not enforced")
        try await rejected("long-document zoom budget") { _ = try await latest.access.render(page: 255, scale: 8) }
        try await rejected("search budget") { _ = try await view.search("e") }
        let links = try await latest.access.links(page: 0)
        try check(!links.isEmpty, "actual PDF annotations missing")
        try view.jump(to: 0); try await until { view.isPreparedForPaint }
        var urls = 0, destinations = 0
        view.openURI = { _ in urls += 1 }; view.goTo = { _, _ in destinations += 1 }
        for link in links {
            try view.jump(to: 0); try await until { view.isPreparedForPaint }; try view.activate(link)
        }
        let expectedURLs = links.filter { if case .uri = $0.action { return true }; return false }.count
        let expectedDestinations = links.count - expectedURLs
        try check(expectedURLs > 0 && expectedDestinations > 0 && urls == expectedURLs && destinations == expectedDestinations, "safe native link callbacks missing \(urls)/\(destinations)")
        for text in ["javascript:alert(1)", "file:///tmp/secret", "https://user:pass@example.invalid", "data:text/plain,never", "ftp://example.invalid", "https://example.invalid/%0a"] {
            try check(!NativeOriginalPDFAccess.safeURL(URL(string: text)!), "unsafe URL allowed")
        }
        try await rejected("GoTo out of artifact") {
            try view.activate(.init(snapshotID: latest.id, pageIndex: view.store.pageIndex, bounds: .zero, action: .goTo(256, .zero)))
        }
        await pageSwitch.fail(true)
        host.refresh(); try await until { host.session.failure != nil }
        try check(view.store.accepted?.id == latest.id && host.store.document?.identity == identity, "failed candidate replaced accepted A")
        await pageSwitch.fail(false)
        try host.setMode(.nativeReflow); try await until { host.visibleMode == .nativeReflow && host.session.state == .reading }
        try check(view.isHidden && !host.textView.isHidden, "mode geometry not separated")
        let textEvents = events.count
        _ = try paint(view, to: out.appendingPathComponent("hidden-page.png"))
        try check(events.count == textEvents, "hidden original page acknowledged reflow Read")
        let restored = NativeReaderWindowController(provider: transport, target: { _ in identity }, originalPages: { try await pageSwitch.pages($0) }, show: false)
        _ = restored.open(profile) { _ in }
        try await until { restored.session.state != .loading }
        try await restored.restoreRecovery(disk)
        try await until { restored.originalPageView.isPreparedForPaint }
        try check(restored.visibleMode == .originalPages && restored.session.isReadOnly && restored.originalPageView.store.pageIndex == 255, "offline typed recovery not connected")
        try await rejected("offline source authorization") { try restored.session.authorize(restored.session.context!) }
        // Existing disk owner detects byte corruption before page preparation.
        let files = try FileManager.default.contentsOfDirectory(at: recoveryOwner.root, includingPropertiesForKeys: nil)
        try Data("tampered".utf8).write(to: files.first!)
        try await rejected("recovery corruption") { _ = try await recoveryOwner.load(identity: identity) }
        try host.setMode(.originalPages); try await until { host.visibleMode == .originalPages && host.session.state == .reading }
        try await until { view.isPreparedForPaint }
        let selectedAgain = try await view.search("FarNeedle255")[0]
        try view.jump(to: selectedAgain.pageIndex); try await until { view.isPreparedForPaint }
        try await view.select(page: selectedAgain.pageIndex, range: selectedAgain.rangeUTF16)
        let oldClose = host.hostWindow.onClose
        oldClose?()
        try check(view.selected == nil && !host.session.hasSelection, "explicit page close retained hold")
        _ = host.open(profile) { if case .painted = $0 { events.append("reopen-painted") } }
        try await until { host.session.state == .reading || host.session.failure != nil }
        try check(host.session.failure == nil, "same profile page reopen")
        oldClose?(); oldCancel(); await Task.yield()
        try check(host.session.state == .reading, "old page close/cancel cancelled reopen")
        try await hostilePDFs(out)
        try await until { view.isPreparedForPaint }
        let cancelledCount = events.count
        host.cancel(); _ = try paint(view, to: out.appendingPathComponent("cancelled.png"))
        try check(events.count == cancelledCount, "cancelled draw acknowledged")
        host.dispose(); restored.dispose()
        try check(NSApp.windows.filter(\.isVisible).isEmpty, "visible window")
        var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
        let result: [String: Any] = ["assertions": assertions, "pages": 256, "metrics": metrics,
            "initialMetrics": initialMetrics, "peakRSSBytes": usage.ru_maxrss,
            "firstPaintSHA256": firstPaint, "sourceAnchors": "unsupported", "rawDiffV1": "unverified",
            "visibleWindows": 0, "GUI": false, "VoiceOver": false, "events": events, "pdfSHA256": accepted.binding.pdfSHA256]
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: out.appendingPathComponent("native-results.json"))
        print("NA12 native page assertions \(assertions)")
    }
}
