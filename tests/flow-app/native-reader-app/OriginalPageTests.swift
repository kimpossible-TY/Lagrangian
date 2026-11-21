import AppKit
import CryptoKit
import Darwin
import PDFKit

private actor PageSwitch {
    let transport: NativeReaderOriginalPageTransport
    var failing = false
    var paused = false, waiting = false
    var continuation: CheckedContinuation<Void, Never>?
    func pause() { paused = true; waiting = false }
    func entered() -> Bool { waiting }
    func release() { paused = false; continuation?.resume(); continuation = nil }
    init(_ transport: NativeReaderOriginalPageTransport) { self.transport = transport }
    func fail(_ value: Bool) { failing = value }
    func pages(_ context: NativeReaderRequestContext) async throws -> NativeOriginalPageDelivery {
        if failing { throw NativeOriginalPageError.invalidPDF }
        let result = try await transport.pages(for: context)
        if paused { waiting = true; await withCheckedContinuation { continuation = $0 } }
        return result
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

/// Hold the real serial PDF worker while the main actor supersedes a search.
/// The finite wait is released by the test; production methods are unchanged.
private final class PageWorkerLatch: @unchecked Sendable {
    private let lock = NSLock(), done = DispatchSemaphore(value: 0)
    private var started = false
    var entered: Bool { lock.lock(); defer { lock.unlock() }; return started }
    func block() { lock.lock(); started = true; lock.unlock(); _ = done.wait(timeout: .now() + 3) }
    func release() { done.signal() }
}
private func occupyPDF(_ access: isolated NativeOriginalPDFAccess, latch: PageWorkerLatch) { latch.block() }

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
    @MainActor static func reviewD2(_ host: NativeReaderWindowController) async throws {
        let root=host.hostWindow.window!.contentView!,window=host.hostWindow.window!
        func views(_ v:NSView)->[NSView]{[v]+v.subviews.flatMap{views($0)}}
        func click(_ title:String)throws{
            let selector=["Reflow":"reflowMode","Original PDF":"pageMode","Aa":"toggleDisplayPopover"][title]!
            let searchRoot = views(root)
            let button=searchRoot.compactMap{$0 as? NSButton}.first{$0.identifier?.rawValue==selector}!
            try check(button.isEnabled && !button.isHiddenOrHasHiddenAncestor,"D2 reachable control "+title)
            button.performClick(nil)
        }
        // The host starts in real Original PDF with a prepared raster. Change
        // only this owned window's effective appearance, never NSApp/the OS.
        try click("Reflow");try await until{host.visibleMode == .nativeReflow && host.textView.renderKey==host.textView.requestedRenderKey}
        try click("Aa")
        let popView = host.hostWindow.displayPopoverContentView
        let autoBtn = views(popView).compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == "themeAutomatic" }!
        try check(autoBtn.isEnabled, "D2 Aa popover Automatic button enabled")
        try check(NSApp.sendAction(autoBtn.action!, to: autoBtn.target, from: autoBtn), "D2 native Automatic action")
        try await until{host.textView.renderKey==host.textView.requestedRenderKey}
        for (appearance,expected) in [(NSAppearance.Name.darkAqua,NativeReaderTextAppearance.Theme.dark),(.aqua,.light)] {
            try click("Original PDF");try await until{host.visibleMode == .originalPages && host.originalPageView.isPreparedForPaint}
            window.appearance=NSAppearance(named:appearance)
            try await Task.sleep(nanoseconds:30_000_000)
            try click("Reflow");try await until{host.visibleMode == .nativeReflow && host.textView.renderKey==host.textView.requestedRenderKey}
            try check(host.hostWindow.selectedThemeIndex==2 && host.textView.textAppearance.theme==expected && host.textView.renderKey?.appearance.theme==expected,"D2 Reflow resolves current window appearance before preparation both directions")
        }
    }
    @MainActor private static func reviewN1(_ host: NativeReaderWindowController, _ source: PageSwitch) async throws {
        let view = host.originalPageView, old = view.store.accepted!.id
        await source.pause(); host.refresh()
        for _ in 0..<400 { if await source.entered() { break }; try await Task.sleep(nanoseconds: 10_000_000) }
        let entered = await source.entered(); try check(entered, "N1 provider latch reached")
        try await view.select(page: 0, range: 0..<4)
        await source.release(); try await until { host.session.state != .loading }
        try check(view.store.accepted!.id == old && host.session.hasSelection, "N1 prepared B must remain held by A")
        view.releaseSelection()
        try await until { host.session.failure != nil || view.store.accepted?.id != old }
        try check(host.session.failure == nil && view.store.accepted?.id != old, "N1 same pending B must adopt after explicit release without refresh")
        try await until { view.isPreparedForPaint }
        let b = view.store.accepted!.binding
        let isolated = NativeOriginalPageStore(viewID: b.viewID)
        func binding(_ generation: Int, _ digest: String = "") -> NativeOriginalPageBinding {
            .init(identity:b.identity,inputFingerprint:b.inputFingerprint,snapshotGeneration:b.snapshotGeneration,
                requestGeneration:generation,viewID:b.viewID,viewGeneration:0,publicationSequence:b.publicationSequence,
                pdfSHA256:digest.isEmpty ? b.pdfSHA256 : digest,pages:b.pages)
        }
        let ticket = try isolated.begin(expected: binding(1))
        let again = try isolated.begin(expected: binding(1)); try check(again == ticket, "N1 exact in-flight ticket is idempotent")
        try await rejected("N1 equal generation different binding") { _ = try isolated.begin(expected: binding(1,String(repeating:"0",count:64))) }
        _ = try isolated.begin(expected: binding(2))
        try await rejected("N1 past generation") { _ = try isolated.begin(expected: binding(1)) }
        isolated.cancel()
        try await rejected("N1 cancelled ticket cannot revive") { _ = try isolated.begin(expected: binding(2)) }
    }
    private actor OfflineInputs {
        var calls = 0
        func reject() throws -> NativeDocumentIdentity { calls += 1; throw NativeReaderOperationFailure.unavailable }
        func assets() throws -> [String:Data] { calls += 1; throw NativeReaderOperationFailure.unavailable }
        func count() -> Int { calls }
    }
    @MainActor static func reviewN2(_ out: URL) async throws {
        let env = ProcessInfo.processInfo.environment
        let devRoot = URL(fileURLWithPath: "/Volumes/devSSD/Developer/lagrangian-native-20261117")
        let repoHelper = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("tools/flow-reader/native/math_layout.mjs").path
        let cwdHelper = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("tools/flow-reader/native/math_layout.mjs").path
        let defaultHelper = FileManager.default.fileExists(atPath: repoHelper) ? repoHelper : cwdHelper
        let fixture = URL(fileURLWithPath: env["FLOW_NATIVE_FIXTURE"] ?? devRoot.appendingPathComponent("test-output/contract/final-contract/native.json").path)
        let doc = try NativeReaderDocument.decode(Data(contentsOf:fixture))
        var assets = [String:Data]()
        for a in doc.assets { assets[a.id] = try Data(contentsOf:fixture.deletingLastPathComponent().appendingPathComponent("assets").appendingPathComponent(a.id)) }
        try check(!assets.isEmpty,"N2 actual compiler snapshot includes assets")
        let snapshot = NativeReaderRecoverySnapshot(document:doc,assets:assets,restoration:.initial,drafts:[])
        let live = OfflineInputs()
        let runtime = NativeReaderRuntime(
            node: URL(fileURLWithPath: env["FLOW_TEST_NODE"] ?? "/opt/homebrew/bin/node"),
            helper: URL(fileURLWithPath: env["FLOW_TEST_NATIVE_HELPER"] ?? defaultHelper),
            runtime: URL(fileURLWithPath: env["FLOW_TEST_NATIVE_RUNTIME"] ?? devRoot.appendingPathComponent("dependencies/mathjax413").path))
        var actionCalls = 0
        let network=NativeReaderNetwork(send:{_,_ in _ = try await live.reject(); throw NativeReaderOperationFailure.unavailable},
            stream:{_ in AsyncThrowingStream{$0.finish(throwing:NativeReaderOperationFailure.unavailable)}})
        let managed=NativeReaderManagedClient(resolver:.init(attach:{_ in _ = try await live.reject(); throw NativeReaderOperationFailure.unavailable},network:network),root:out.path,entry:"main.typ")
        let restored = NativeReaderWindowController(provider:managed,target:{_ in try await managed.target()},
            assets:{_,_ in try await live.assets()},runtime:runtime,
            actions:{ actionCalls += 1; return try await managed.currentActions() },show:false,avoidActivation:true)
        defer { restored.dispose() }
        restored.hostWindow.initialize()
        try await restored.restoreRecovery(snapshot)
        let liveCalls = await live.count(); try check(liveCalls == 0,"N2 validated offline assets cannot invoke target/provider/live assets")
        try check(restored.session.isReadOnly && restored.session.state == .offline && restored.textView.renderKey != nil,"N2 offline reflow accepted")
        _ = try paint(restored.textView.bodyTextView,to:out.appendingPathComponent("N2-restored.png"))
        let key = restored.textView.renderKey
        let first = doc.blocks.first { $0.kind == .paragraph && !$0.displayText.isEmpty }!
        try restored.textView.select(from:.init(blockID:first.id,utf16:0,affinity:.upstream),to:.init(blockID:first.id,utf16:first.displayText.utf16.count,affinity:.downstream))
        restored.hostWindow.sourceSelected(); restored.hostWindow.askSelected()
        await Task.yield()
        try check(actionCalls == 0 && restored.session.hasSelection,"N2 offline source/chat remain read-only without selection release")
        var invalid = assets; invalid[doc.assets[0].id] = Data("corrupt".utf8)
        try await rejected("N2 invalid recovery asset") { try await restored.restoreRecovery(.init(document:doc,assets:invalid,restoration:.initial,drafts:[])) }
        try check(restored.textView.renderKey == key,"N2 failed restore retains A")
    }
    @MainActor static func reviewN3(_ host: NativeReaderWindowController) async throws {
        let view=host.originalPageView
        let children = view.accessibilityChildren() ?? []
        let text = children.compactMap { $0 as? NSAccessibilityElement }.first { $0.accessibilityRole() == .textArea }
        try check(text != nil,"N3 current PDF text AX child missing")
        let ax=text!, value=ax.accessibilityValue() as! String
        try check(value.contains("Native PDF") && ax.accessibilityNumberOfCharacters() == value.utf16.count,"N3 bounded page AX value/count")
        let range=(value as NSString).range(of:"Native PDF")
        try check(ax.accessibilityString(for:range)=="Native PDF","N3 AX range reads")
        ax.setAccessibilitySelectedTextRange(range)
        try await until { view.selected != nil }
        try check(ax.accessibilitySelectedText()=="Native PDF" && ax.accessibilitySelectedTextRange()==range,"N3 AX selection")
        let board=NSPasteboard.withUniqueName();defer{board.releaseGlobally()}
        view.copyText={board.clearContents();return board.setString($0,forType:.string)}
        try check(view.copyDisplay() && board.string(forType:.string)=="Native PDF","N3 AX private display copy")
        try await rejected("N3 AX offsets are not source authority") { _ = try view.selected!.verifiedSourceAnchor() }
        view.releaseSelection()
        let links=(ax.accessibilityChildren() ?? []).compactMap{$0 as? NSAccessibilityElement}
        try check(!links.isEmpty && links.allSatisfy{$0.accessibilityRole() == .link},"N3 current page AX links")
        var callbacks=0;view.openURI={_ in callbacks += 1};view.goTo={_,_ in callbacks += 1}
        try check(!ax.accessibilityFrame().isEmpty,"N3 native page AX frame")
        let uri=links.first{$0.accessibilityURL() != nil}
        try check(uri?.accessibilityPerformPress()==true && callbacks==1,"N3 explicit current AX link action")
        let tab=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:host.hostWindow.window!.windowNumber,context:nil,characters:"\t",charactersIgnoringModifiers:"\t",isARepeat:false,keyCode:48)!
        let enter=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:host.hostWindow.window!.windowNumber,context:nil,characters:"\r",charactersIgnoringModifiers:"\r",isARepeat:false,keyCode:36)!
        view.keyDown(with:tab);view.keyDown(with:enter)
        try check(callbacks==2,"N3 native Tab/Enter link activation")
        let window=host.hostWindow.window!, before=NSTextField(string:"Before PDF"), after=NSTextField(string:"After PDF")
        window.contentView!.addSubview(before);window.contentView!.addSubview(after)
        before.frame=NSRect(x:0,y:0,width:120,height:24);after.frame=NSRect(x:130,y:0,width:120,height:24);window.autorecalculatesKeyViewLoop=false
        before.nextKeyView=view;view.nextKeyView=after;after.nextKeyView=before
        try check(window.makeFirstResponder(view),"C3 native PDF accepts keyboard focus")
        for _ in 0..<links.count {view.keyDown(with:tab)}
        try check(window.firstResponder === after || window.firstResponder === after.currentEditor(),"C3 final PDF link Tab exits to actual next native control")
        let backtab=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[.shift],timestamp:0,windowNumber:window.windowNumber,context:nil,characters:"\t",charactersIgnoringModifiers:"\t",isARepeat:false,keyCode:48)!
        try check(window.makeFirstResponder(view),"C3 focus enters PDF again")
        for _ in 0...links.count {view.keyDown(with:backtab)}
        try check(window.firstResponder === before || window.firstResponder === before.currentEditor(),"C3 first PDF link ShiftTab exits to actual previous native control")

        try view.jump(to:128);try await until{view.isPreparedForPaint}
        try check(!ax.isAccessibilityEnabled() && ax.accessibilityValue()==nil && !links[0].accessibilityPerformPress(),"N3 stale AX children invalidated")
        ax.setAccessibilitySelectedTextRange(range);await Task.yield()
        try check(view.selected==nil,"N3 stale AX cannot select replacement page")
        let currentAX=(view.accessibilityChildren() ?? []).compactMap{$0 as? NSAccessibilityElement}.first!
        let single=(currentAX.accessibilityChildren() ?? []).compactMap{$0 as? NSAccessibilityElement}
        try check(single.count==1,"C3 actual middle page has one link")
        try check(window.makeFirstResponder(view),"C3 single-link focus")
        view.keyDown(with:tab);view.keyDown(with:tab)
        try check(window.firstResponder === after || window.firstResponder === after.currentEditor(),"C3 single final link exits forward")
        try check(window.makeFirstResponder(view),"C3 single-link reverse focus")
        view.keyDown(with:backtab);view.keyDown(with:backtab)
        try check(window.firstResponder === before || window.firstResponder === before.currentEditor(),"C3 single first link exits backward")

        try check((view.accessibilityChildren() ?? []).count==1,"N3 only one lazy page exposed, never 256-page AX tree")
        let metrics=await view.store.accepted!.access.metrics()
        try check(metrics["textPages"]!<=8 && metrics["renderedPages"]!<=3,"N3 lazy page/text budgets")
    }
    @MainActor static func reviewExport(_ host:NativeReaderWindowController,_ out:URL)async throws{
        func views(_ v:NSView)->[NSView]{[v]+v.subviews.flatMap{views($0)}}
        let root=host.hostWindow.window!.contentView!
        func menuAction(_ title:String)throws->NSMenuItem{
            root.layoutSubtreeIfNeeded()
            let selector=["Export PDF":"exportPDFExplicitly","Cancel":"cancelStorageExplicitly"][title]!
            guard let toggle=views(root).compactMap({$0 as? NSButton}).first(where:{$0.action==NSSelectorFromString("toggleTools")}),
                  !toggle.isHiddenOrHasHiddenAncestor else { throw FlowError(message:"Overflow trigger missing") }
            try check(NSApp.sendAction(toggle.action!,to:toggle.target,from:toggle),"export overflow menu open")
            guard let item=host.hostWindow.moreMenu.items.first(where:{$0.action.map(NSStringFromSelector)==selector}),item.target != nil,item.action != nil else {
                throw FlowError(message:"Export native control missing: "+title)
            }
            return item
        }
        func click(_ title:String)throws{
            let item=try menuAction(title)
            try check(item.isEnabled,"Export reachable enabled "+title)
            try check(NSApp.sendAction(item.action!,to:item.target,from:item),"Export native menu action "+title)
        }
        let disk=NativeReaderRecoveryStore(root:out.appendingPathComponent("export-owned-recovery"))
        try await host.saveRecovery(to:disk)
        let saved=try await disk.load(identity:host.store.document!.identity),original=saved.originalPages!,document=saved.document
        let target=out.appendingPathComponent("original-export.pdf"),old=Data("previous owned file".utf8)
        try old.write(to:target)
        host.choosePDFDestination={_ in target}
        let exportItem = try menuAction("Export PDF")
        try check(exportItem.isEnabled,"F16 actual Export PDF enabled for accepted original")
        try click("Export PDF");try await until{host.hostWindow.notice.stringValue=="Original PDF exported."}
        let bytes=try Data(contentsOf:target)
        try check(bytes==original.data && NativeReaderRecoverySnapshot.digest(bytes)==original.publication.pdfSHA256,"F16 exports exact accepted revision/input/digest bytes")
        try check(PDFDocument(url:target)?.pageCount==host.originalPageView.store.accepted!.binding.pages.count,"F16 exported original reopened by actual PDFKit")
        host.choosePDFDestination={_ in nil};try click("Export PDF")
        try await until{(try? menuAction("Cancel").isEnabled)==false}
        let targetBytes1=try Data(contentsOf:target);try check(targetBytes1==bytes,"F16 save panel cancel preserves old file")
        var continuation:CheckedContinuation<URL?,Never>?,entered=false
        host.choosePDFDestination={_ in entered=true;return await withCheckedContinuation{continuation=$0}}
        try click("Export PDF");try await until{entered}
        try click("Cancel");continuation!.resume(returning:target);continuation=nil
        try await Task.sleep(nanoseconds:30_000_000)
        let targetBytes2=try Data(contentsOf:target);try check(targetBytes2==bytes,"F16 Cancel rejects late chooser and preserves previous file")
        entered=false;try click("Export PDF");try await until{entered}
        host.refresh();let generation=host.store.generation
        try await until{host.session.state == .reading && host.store.document?.generation==generation}
        continuation!.resume(returning:target);continuation=nil
        try await until{(try? menuAction("Cancel").isEnabled)==false}
        let targetBytes3=try Data(contentsOf:target);try check(targetBytes3==bytes,"F16 changed accepted snapshot rejects late export chooser")
        let bad=NativeOriginalPageRecovery(publication:original.publication,data:Data("tampered".utf8),viewport:original.viewport)
        try await rejected("F16 tamper before staging"){_ = try NativeReaderRecoveryStore.stageOriginalPDF(bad,document:document,to:target)}
        let link=out.appendingPathComponent("export-link.pdf");try FileManager.default.createSymbolicLink(at:link,withDestinationURL:target)
        let directory=out.appendingPathComponent("directory.pdf");try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false)
        for invalid in [link,directory,out.appendingPathComponent("missing/child.pdf"),out.appendingPathComponent("wrong.txt")] {
            try await rejected("F16 invalid destination"){_ = try NativeReaderRecoveryStore.stageOriginalPDF(original,document:document,to:invalid)}
        }
        let targetBytes4=try Data(contentsOf:target);try check(targetBytes4==bytes,"F16 invalid destination/tamper retain existing bytes")
        let staged=try NativeReaderRecoveryStore.stageOriginalPDF(original,document:document,to:target)
        let newer=Data("newer external owned edit".utf8);try newer.write(to:target)
        try await rejected("F16 destination changed before atomic publication"){try staged.commit()}
        let targetBytes5=try Data(contentsOf:target);try check(targetBytes5==newer,"F16 atomic guard retains newer destination")
        entered=false;host.choosePDFDestination={_ in entered=true;return await withCheckedContinuation{continuation=$0}}
        try click("Export PDF");try await until{entered};host.dispose();continuation!.resume(returning:target)
        try await Task.sleep(nanoseconds:30_000_000)
        let targetBytes6=try Data(contentsOf:target);try check(targetBytes6==newer,"F16 disposal rejects late chooser with zero writes")
        let leftovers=try FileManager.default.contentsOfDirectory(atPath:out.path).filter{$0.hasPrefix(".lagrangian-export-")}
        // This deliberately failed staging object stays alive until this scope
        // ends; its destructor removes that one owned temporary file.
        try check(leftovers.count<=1,"F16 bounded temporary staging")
    }
    @MainActor static func reviewN4(_ out: URL) async throws {
        let bytes=NSMutableData();var media=CGRect(x:0,y:0,width:320,height:900)
        let cg=CGContext(consumer:CGDataConsumer(data:bytes)!,mediaBox:&media,nil)!
        for i in 0..<4 {
            cg.beginPDFPage(nil)
            cg.addDestination("bottom\(i)" as CFString, at:CGPoint(x:50,y:60))
            cg.setDestination("bottom\(i)" as CFString, for:CGRect(x:30,y:40,width:80,height:20))
            for (text,point) in [("BottomNeedle\(i)",CGPoint(x:40,y:60)),("TopNeedle\(i)",CGPoint(x:170,y:800))] {
                cg.textPosition=point
                let a=NSAttributedString(string:text,attributes:[.font:NSFont.systemFont(ofSize:12)])
                CTLineDraw(CTLineCreateWithAttributedString(a),cg)
            }
            cg.endPDFPage()
        }
        cg.closePDF()
        let pdf=PDFDocument(data:bytes as Data)!, crop=CGRect(x:10,y:20,width:300,height:860)
        var geometries=[NativeOriginalPageGeometry]()
        for i in 0..<4 {
            let page=pdf.page(at:i)!;page.setBounds(crop,for:.cropBox);page.rotation=i*90
            geometries.append(.init(index:i,mediaBox:media,cropBox:crop,rotation:i*90))
        }
        let data=pdf.dataRepresentation()!;try data.write(to:out.appendingPathComponent("N4-cropped-rotated.pdf"))
        let view=NativeReaderOriginalPageView(viewID:UUID())
        let window=NSWindow(contentRect:CGRect(x:0,y:0,width:220,height:120),styleMask:[],backing:.buffered,defer:false)
        let scroll=NSScrollView(frame:window.contentView!.bounds);scroll.hasVerticalScroller=true;scroll.hasHorizontalScroller=true
        scroll.documentView=view;window.contentView!.addSubview(scroll)
        defer{view.dispose();window.close()}
        let identity=NativeDocumentIdentity(documentID:"N4",serviceID:"owned",revision:"fixture",scope:.fixture)
        let binding=NativeOriginalPageBinding(identity:identity,inputFingerprint:String(repeating:"a",count:64),snapshotGeneration:1,
            requestGeneration:1,viewID:view.store.viewID,viewGeneration:0,publicationSequence:1,pdfSHA256:NativeReaderRecoverySnapshot.digest(data),pages:geometries)
        var limits=NativeOriginalPageLimits();limits.lazy=true
        let prepared=try await NativeOriginalPagePreparer().prepare(.init(binding:binding,data:data),expected:binding,limits:limits)
        let ticket=try view.store.begin(expected:binding);try view.store.adopt(prepared,for:ticket);view.installed()
        try await until{view.isPreparedForPaint};try view.zoom(1.5);try await until{view.isPreparedForPaint}
        var proofs=[[String:Any]]()
        func hide(_ rect: CGRect) throws {
            let clip=scroll.contentView
            let candidates=[CGPoint.zero,CGPoint(x:max(0,view.frame.width-clip.bounds.width),y:max(0,view.frame.height-clip.bounds.height))]
            guard let origin=candidates.first(where:{!CGRect(origin:$0,size:clip.bounds.size).intersects(rect)}) else {throw NativeOriginalPageError.geometry}
            clip.scroll(to:origin);scroll.reflectScrolledClipView(clip)
            try check(!clip.bounds.intersects(rect),"N4 target starts outside actual clip")
        }
        for i in 0..<4 {
            try view.jump(to:i);try await until{view.isPreparedForPaint}
            let hits=try await view.search("BottomNeedle\(i)")
            let extracted=try await prepared.access.pageText(page:i)
            try check(!hits.isEmpty,"N4 real PDF Find query missing: \(extracted)")
            let hit=hits[0]
            let rect=try view.store.viewRect(forPageRect:hit.pageBounds);try hide(rect)
            // Same production Find sequence; selection may finish before raster installation.
            try view.jump(to:i);try await view.select(page:i,range:hit.rangeUTF16);try await until{view.isPreparedForPaint}
            let visible=try view.store.viewRect(forPageRect:hit.pageBounds)
            try check(scroll.contentView.bounds.intersects(visible),"N4 Find hit must be visible after raster install rotation \(i*90)")
            proofs.append(["rotation":i*90,"findVisible":true,"clip":NSStringFromRect(scroll.contentView.bounds),"target":NSStringFromRect(visible)])
            view.releaseSelection()
            let decodedLinks=try await prepared.access.links(page:i)
            let decodedPDF=PDFDocument(data:data)!, annotations=decodedPDF.page(at:i)!.annotations
            let detail=annotations.map { "\($0.type ?? "nil") action=\(String(describing:$0.action)) destination=\(String(describing:$0.destination))" }.joined(separator:";")
            try check(!decodedLinks.isEmpty,"N4 actual PDF GoTo annotation missing page \(i): \(detail)")
            let link=decodedLinks[0]
            let target=try view.store.viewRect(forPageRect:CGRect(x:50,y:60,width:1,height:1));try hide(target)
            try view.activate(link);try await until{view.isPreparedForPaint}
            try check(scroll.contentView.bounds.intersects(target),"N4 GoTo point must be visible rotation \(i*90)")
            try hide(target);try view.activate(link);view.cancel()
            let origin=scroll.contentView.bounds.origin
            try await Task.sleep(nanoseconds:50_000_000)
            try check(scroll.contentView.bounds.origin==origin,"N4 cancelled raster cannot apply late scroll")
        }
        // Queue real searches behind the same PDF actor, then supersede their
        // page/operation while they are awaiting the worker (no patched search).
        for boundary in ["page", "cancel"] {
            try view.jump(to:0); try await until { view.isPreparedForPaint }
            let latch = PageWorkerLatch()
            let blocker = Task.detached { await occupyPDF(prepared.access, latch:latch) }
            try await until { latch.entered }
            var entered = false
            let searching = Task { entered = true; return try await view.search("BottomNeedle0") }
            try await until { entered }
            if boundary == "page" { try view.jump(to:1) } else { view.cancel() }
            let origin = scroll.contentView.bounds.origin
            latch.release(); await blocker.value
            do { _ = try await searching.value; throw NSError(domain:"N4 obsolete search returned",code:1) }
            catch NativeOriginalPageError.stale { assertions += 1 }
            if boundary == "page" { try await until { view.isPreparedForPaint } }
            try check(view.selected == nil && scroll.contentView.bounds.origin == origin,"N4 late search cannot select/reveal after \(boundary)")
            proofs.append(["lateSearchBoundary":boundary,"staleRejected":true,"scrollUnchanged":true])
        }
        try JSONSerialization.data(withJSONObject:proofs,options:.prettyPrinted).write(to:out.appendingPathComponent("N4-viewport.json"))
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
        if let review = CommandLine.arguments.dropFirst(3).first {
            if review == "N1" { try await reviewN1(host,pageSwitch) }
            else if review == "N2" { try await reviewN2(out) }
            else if review == "N3" { try await reviewN3(host) }
            else if review == "EXPORT" { try await reviewExport(host,out) }
            else if review == "D2" { try await reviewD2(host) }
            else if review == "N4" { try await reviewN4(out) }
            else { throw NativeOriginalPageError.unsupported("review-case") }
            host.dispose()
            try check(NSApp.windows.allSatisfy{!$0.isVisible},"review visible windows")
            print("review pass \(review); assertions=\(assertions)")
            return
        }
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
        do {
            func rViews(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap { rViews($0) } }
            let rWin = restored.hostWindow.window!, rRoot = rWin.contentView!
            try check(rWin.appearance == nil, "offline PDF inherits OS appearance without forced light override")
            rWin.setFrame(NSRect(x: 0, y: 0, width: 980, height: 752), display: false); rRoot.layoutSubtreeIfNeeded()
            let rAll = rViews(rRoot)
            let badge = rAll.first { $0.identifier?.rawValue == "offlinePDFBadge" }
            let badgeText = badge.map { rViews($0).compactMap { ($0 as? NSTextField)?.stringValue }.joined() } ?? ""
            try check(badge != nil && !badge!.isHiddenOrHasHiddenAncestor && badgeText == "오프라인 PDF", "offline PDF toolbar shows exact '오프라인 PDF' badge")
            let nav = rAll.first { $0.identifier?.rawValue == "pageNavigation" }!
            try check(!nav.isHiddenOrHasHiddenAncestor && rAll.first(where: { $0.identifier?.rawValue == "pageCounter" }).flatMap { ($0 as? NSTextField)?.stringValue } == "256 / 256", "offline PDF toolbar shows centered 256 / 256 counter")
            try check(restored.hostWindow.findField.bezelStyle == .roundedBezel && !restored.hostWindow.findField.isHiddenOrHasHiddenAncestor, "offline PDF toolbar shows rounded search field")
            restored.hostWindow.findField.stringValue = "FarNeedle255"
            _ = NSApp.sendAction(restored.hostWindow.findField.action!, to: restored.hostWindow.findField.target, from: restored.hostWindow.findField)
            try await until { restored.session.hasSelection && !restored.hostWindow.capsule.isHidden }
            let rCapsule = restored.hostWindow.capsule
            let rViewport = restored.originalPageView.enclosingScrollView!.contentView.convert(restored.originalPageView.enclosingScrollView!.contentView.bounds, to: rRoot)
            try check(!rCapsule.convert(rCapsule.bounds, to: rRoot).intersects(rViewport), "offline PDF search hit capsule docks without overlapping PDF")
            try check(!rCapsule.buttons[.copy]!.isHidden && !rCapsule.closeButton.isHidden && rCapsule.footnote.stringValue == "오프라인 PDF · 복사·검색만 지원" && !rCapsule.footnote.isHidden, "offline PDF capsule shows copy, close, and compact footer")
            try check(rCapsule.buttons[.source]!.isHidden && rCapsule.buttons[.highlight]!.isHidden && rCapsule.buttons[.ask]!.isHidden && rCapsule.buttons[.editor]!.isHidden && rCapsule.releaseSelectionButton.isHidden, "offline PDF capsule hides unsupported buttons")
            try check(rViews(rRoot).compactMap({ $0 as? NSButton }).filter({ !$0.isHiddenOrHasHiddenAncestor && $0.title.contains("복사") }).count == 1, "no duplicate copy button in offline PDF mode")
            rCapsule.dismissExplicitly()
            try check(rCapsule.isHidden && !restored.session.hasSelection, "dismissing offline PDF search capsule releases search selection")
            restored.hostWindow.clearFindField()
            restored.hostWindow.findField.stringValue = "FarNeedle255"
            _ = NSApp.sendAction(restored.hostWindow.findField.action!, to: restored.hostWindow.findField.target, from: restored.hostWindow.findField)
            try await until { restored.session.hasSelection && !restored.hostWindow.capsule.isHidden }
            try check(restored.hostWindow.notice.isHidden, "re-search after capsule dismiss and clear succeeds without heldSelection error")
            restored.hostWindow.releasePageSelection()
            try check(restored.hostWindow.findField.stringValue == "FarNeedle255", "search query preserved after release")
            rWin.setFrame(NSRect(x: 0, y: 0, width: 640, height: 752), display: false); rRoot.layoutSubtreeIfNeeded()
            try check(rWin.frame.width <= 640.5, "640pt offline PDF settles at width <= 640.5")
            try check(rWin.minSize.width <= 640, "640pt offline PDF window minSize.width <= 640")
            let horizontalAttrs: Set<NSLayoutConstraint.Attribute> = [.leading, .trailing, .left, .right, .centerX]
            let toolbarHorizontal = restored.hostWindow.toolbarView.constraints.filter { c in
                type(of: c) == NSLayoutConstraint.self &&
                horizontalAttrs.contains(c.firstAttribute) &&
                !((c.secondItem as AnyObject?) === restored.hostWindow.toolbarView && (c.firstAttribute == .leading || c.firstAttribute == .trailing))
            }
            try check(!toolbarHorizontal.isEmpty && toolbarHorizontal.allSatisfy { $0.priority < .windowSizeStayPut }, "toolbar horizontal inter-group constraints yield below windowSizeStayPut")
            try check(!nav.isHiddenOrHasHiddenAncestor && abs(nav.convert(NSPoint(x: nav.bounds.midX, y: 0), to: rRoot).x - rRoot.bounds.midX) <= 12, "640pt offline PDF keeps pageNavigation centered")
            try check(restored.hostWindow.contents.isHiddenOrHasHiddenAncestor && restored.hostWindow.findField.isHiddenOrHasHiddenAncestor, "640pt offline PDF collapses secondary items into overflow")
            let moreBtn = rAll.compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == "toggleTools" }!
            var placed = [NSRect]()
            for ctrl in [badge!, nav, moreBtn] where !ctrl.isHiddenOrHasHiddenAncestor {
                let rect = ctrl.convert(ctrl.bounds, to: rRoot)
                try check(rect.minX >= -0.5 && rect.maxX <= rRoot.bounds.width + 0.5, "640pt offline PDF control within horizontal bounds")
                for prev in placed { try check(!prev.insetBy(dx: 0.5, dy: 0.5).intersects(rect), "640pt offline PDF non-overlapping toolbar controls") }
                placed.append(rect)
            }
        }
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
