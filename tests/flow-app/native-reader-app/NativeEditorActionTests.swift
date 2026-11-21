import Foundation
import AppKit

private actor Gate {
    var reached = false
    var released = false
    var continuation: CheckedContinuation<Void, Never>?
    func stop() async {
        reached = true
        if released { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func open() { released = true; continuation?.resume(); continuation = nil }
    func wait() async throws {
        for _ in 0..<1000 {
            if reached { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw NativeReaderOperationFailure.unavailable
    }
}
private actor Loss {
    var dropped = false
    func drop() -> Bool { if dropped { return false }; dropped = true; return true }
}
private actor SyncFault {
    var active = false
    func enable() { active = true }
}
private actor Trace {
    var operations = [String]()
    func append(_ value: String) { operations.append(value) }
}

private actor UITrace {
    var events = [[String: String]]()
    var attachments = [Bool]()
    func attachment(consented: Bool) { attachments.append(consented) }
    func record(_ payload: [String: Any]) {
        events.append(["operation": payload["operation"] as? String ?? "", "receiptID": payload["receiptID"] as? String ?? ""])
    }
    var jumpIDs: [String] { events.filter { $0["operation"] == "jump" }.map { $0["receiptID"]! } }
    var jumps: Int { jumpIDs.count }
    var receipts: [String] { events.filter { $0["operation"] == "receipt" }.map { $0["receiptID"]! } }
}

@main struct NativeEditorActionTests {
    static func require(_ value: Bool, line: Int = #line) throws {
        if !value { throw NativeReaderOperationFailure.rejected(code: "test-assertion-line-\(line)") }
    }
    /// Existing tests inject local inventory only; echo its caller correlation,
    /// never use this fake plan in the real-manager R1 lifetime tests.
    private static func fixturePlan(_ data: Data, _ argv: [String]) throws -> Data {
        if argv.first == "--native-editor-scope" {
            return Data(("{\"scope\":\"" + String(repeating: "a", count: 64) + "\",\"requestBinding\":\"" + String(repeating: "b", count: 64) + "\"}").utf8)
        }
        if argv.first == "--release-native-editor-operation" { return Data("{\"released\":false}".utf8) }
        var value = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        if let index = argv.firstIndex(of: "--native-editor-operation") { value["nativeEditorOperation"] = argv[index + 1]; value["nativeEditorScope"] = String(repeating: "a", count: 64) }
        return try JSONSerialization.data(withJSONObject: value)
    }

    @MainActor private static func until(_ predicate: () -> Bool) async throws {
        for _ in 0..<800 {
            if predicate() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw NativeReaderOperationFailure.rejected(code: "offscreen-event-timeout")
    }

    /// Actual AppKit controls -> production host callbacks -> managed client ->
    /// production HTTP. Only local inventory, consent decision and faults inject.
    @MainActor private static func offscreen(_ config: Data, mode: String, marker: String) async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        try require(app.activationPolicy() == .prohibited)
        let value = try JSONSerialization.jsonObject(with: config) as! [String: Any]
        let directory = URL(fileURLWithPath: marker).deletingLastPathComponent()
        let descriptor = directory.appendingPathComponent("editor.json")
        let attachment = try NativeReaderAttachment(data: config)
        let profile = Profile(id: "na15-offscreen", name: "Isolated native events", root: value["root"] as! String,
            entry: value["entry"] as! String, fonts: [], packages: "", port: attachment.baseURL.port!, publicURL: "", label: "na15-offscreen")
        let flow = FlowApp(environment: AppEnvironment(variables: [:], userHome: directory.appendingPathComponent("app-home")),
                           isolated: true, noActivate: true, showNativeWindow: false)
        flow.settings.profiles = [profile]; flow.settings.selectedID = profile.id
        let trace = UITrace(), loss = Loss(), gate = Gate()
        let real = NativeReaderNetwork.urlSession()
        let network = NativeReaderNetwork(send: { request, limit in
            let payload = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            if request.url?.path.hasSuffix("/api/native-editor") == true, let payload { await trace.record(payload) }
            let response = try await real.send(request, limit)
            if let operation = payload?["operation"] as? String {
                if ["ui-lost", "ui-new-selection", "ui-registration-replaced"].contains(mode), operation == "jump", await loss.drop() {
                    throw URLError(.networkConnectionLost)
                }
                if ["ui-close", "ui-stale"].contains(mode), operation == "prepare" { await gate.stop() }
            }
            return response
        }, stream: real.stream)
        flow.managedResolver = NativeReaderManagedResolver(attach: { argv in
            if argv.first == "--attach" { await trace.attachment(consented: argv.contains("--native-editor-consent")) }
            return try fixturePlan(config, argv)
        }, network: network)
        var consentCalls = 0
        if mode != "ui-no-consent" {
            do {
                let adopted = try await flow.connectEditor(descriptor: descriptor, for: profile) {
                    consentCalls += 1; return mode != "ui-declined"
                }
                try require(adopted == (mode != "ui-declined"))
                try require(mode != "ui-invalid-descriptor")
            } catch {
                try require(mode == "ui-invalid-descriptor" && consentCalls == 0)
            }
        }
        _ = flow.readNative(profile, progress: { _ in })
        guard let window = flow.nativeWindow else { throw NativeReaderOperationFailure.unavailable }
        defer { window.dispose() }
        try await until { window.store.document != nil && window.textView.textMap != nil && window.session.state == .reading }
        guard let block = window.store.document?.blocks.first(where: { $0.canonicalText == "Préface 한글 target passage." }) else {
            throw NativeReaderContractError.invalidDocument
        }
        let start = "Préface 한글 ".utf16.count
        func select(_ lower: Int, _ upper: Int) throws {
            try window.textView.select(from: .init(blockID: block.id, utf16: lower, affinity: .downstream),
                                       to: .init(blockID: block.id, utf16: upper, affinity: .upstream))
            window.textView.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification))
        }
        try select(start, start + 6)
        try await until { window.store.selection?.fragments.first?.exact == "target" }
        let originalTicket = window.store.selection!.ticket
        window.hostWindow.locateSelected() // Same selector installed on the native button.
        if ["ui-close", "ui-stale"].contains(mode) {
            try await gate.wait()
            if mode == "ui-close" {
                window.hostWindow.window?.performClose(nil)
                await gate.open()
                try await Task.sleep(nanoseconds: 150_000_000)
                window.hostWindow.locateSelected()
                try require(await trace.jumps == 0)
            } else {
                let file = URL(fileURLWithPath: marker)
                try Data("ready".utf8).write(to: file)
                try await until { FileManager.default.fileExists(atPath: marker + ".done") }
                await gate.open()
                try await until { window.hostWindow.notice.stringValue.contains("changed") }
                try require(window.store.selection?.ticket == originalTicket)
            }
        } else if ["ui-no-consent", "ui-declined", "ui-invalid-descriptor"].contains(mode) {
            try await until { window.hostWindow.notice.stringValue.contains("No explicitly connected editor") }
            try require(await trace.jumps == 0)
            try require(await trace.attachments == [false])
        } else if mode == "ui-jump" {
            try await until { window.hostWindow.notice.stringValue == "Editor moved to the verified saved source." }
            window.hostWindow.editorReceipt()
            try await until { window.hostWindow.notice.stringValue == "Editor moved to the verified saved source." }
            try require(await trace.jumps == 1)
        } else {
            try await until { window.hostWindow.notice.stringValue.contains("effect is unknown") }
            if mode == "ui-registration-replaced" {
                try Data("ready".utf8).write(to: URL(fileURLWithPath: marker))
                try await until { FileManager.default.fileExists(atPath: marker + ".done") }
            }
            if mode == "ui-new-selection" {
                try select(0, 7)
                try await until { window.store.selection?.ticket != originalTicket }
                window.hostWindow.editorReceipt()
                try await until { window.hostWindow.notice.stringValue.contains("unavailable for this selection") }
                try require(await trace.receipts.isEmpty)
            } else {
                window.hostWindow.locateSelected() // Must keep the first uncertain UUID.
                try await until { window.hostWindow.notice.stringValue.contains("before requesting another move") }
                window.hostWindow.editorReceipt()
                try await until {
                    mode == "ui-registration-replaced" ? window.hostWindow.notice.stringValue.contains("effect is unknown")
                        : window.hostWindow.notice.stringValue == "Editor moved to the verified saved source."
                }
                let first = await trace.jumpIDs, reads = await trace.receipts
                try require(first.count == 1 && reads == first)
                if mode == "ui-registration-replaced" {
                    window.hostWindow.locateSelected()
                    try await until { window.hostWindow.notice.stringValue.contains("before requesting another move") }
                }
            }
            try require(await trace.jumps == 1)
        }
        try require(app.activationPolicy() == .prohibited && app.windows.allSatisfy { !$0.isVisible })
        if !["ui-no-consent", "ui-declined", "ui-invalid-descriptor"].contains(mode) { try require(await trace.attachments == [true]) }
        let events = await trace.events
        let result: [String: Any] = ["mode": mode, "nativeGUI": "not-run", "offscreenAppKit": true,
            "activationPolicy": "prohibited", "visibleWindows": 0, "events": events,
            "consentCalls": consentCalls, "notice": window.hostWindow.notice.stringValue,
            "productionFlowAppComposition": true, "productionControlCallbacks": true,
            "assertions": 10, "skips": 0]
        print(String(data: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), encoding: .utf8)!)
    }

    @MainActor static func leases(_ config:[String:Any]) async throws {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.prohibited)
        let editor=try NativeReaderManagedEditor.consentedDescriptor(URL(fileURLWithPath:config["descriptor"] as! String))
        let manager=config["manager"] as! String,root=config["root"] as! String,entry=config["entry"] as! String
        let real=NativeReaderNetwork.urlSession()
        func resolver(_ gate:Gate?=nil,_ failProbe:Bool=false)->NativeReaderManagedResolver {
            NativeReaderManagedResolver(attach:{argv in
                let data=try await CommandRunner.nativeReaderManager(manager,argv)
                if argv.first=="--attach",let gate {await gate.stop()}
                return data
            },network:.init(send:{request,limit in
                if failProbe {throw URLError(.cannotConnectToHost)}
                return try await real.send(request,limit)
            },stream:real.stream))
        }
        for i in 0..<34 {
            let client=NativeReaderManagedClient(resolver:resolver(),root:root,entry:entry,editor:editor)
            _ = try await client.target()
            if i%2==0 {await client.revokeEditorConsent()} else {await client.dispose()}
        }
        // Registration exists before the native state probe. Probe failure must retire it.
        do {_ = try await resolver(nil,true).resolve(root:root,entry:entry,editor:editor);throw FlowError(message:"probe unexpectedly succeeded")}
        catch is URLError {}
        for operation in ["close","cancel","supersede"] {
            let gate=Gate(),client=NativeReaderManagedClient(resolver:resolver(gate),root:root,entry:entry,editor:editor)
            let resolving=Task{try await client.target()};try await gate.wait()
            if operation=="close" {await client.dispose()}
            else if operation=="cancel" {resolving.cancel()}
            else {await client.invalidate()}
            await gate.open()
            do {_ = try await resolving.value;throw FlowError(message:"obsolete resolve adopted")}
            catch NativeReaderContractError.staleGeneration {}
            catch is CancellationError {}
            await client.dispose()
        }
        // The same production generator output is a valid explicit app chooser
        // input; consent is injected, no native panel/GUI is displayed.
        let flow=FlowApp(environment:AppEnvironment(variables:[:],userHome:URL(fileURLWithPath:root).appendingPathComponent("owned-home")),isolated:true,noActivate:true,showNativeWindow:false)
        let profile=Profile(id:"lease",name:"Lease fixture",root:root,entry:entry,fonts:[],packages:"",port:24650,publicURL:"",label:"test.lease")
        flow.settings=Settings(selectedID:profile.id,profiles:[profile])
        try require(try await flow.connectEditor(descriptor:URL(fileURLWithPath:config["descriptor"] as! String),for:profile,consent:{true}))
        flow.disconnectEditor();flow.session.dispose()
        try require(NSApp.windows.allSatisfy{!$0.isVisible})
        print("{\"mode\":\"SF2\",\"reconnects\":34,\"probeFailure\":true,\"lateResolveBoundaries\":3,\"productionDescriptor\":true,\"skips\":0,\"visibleWindows\":0}")
    }

    private static func retirement(_ object: [String: Any], marker: String) async throws {
        let manager = object["manager"] as! String
        let arguments = object["releaseArguments"] as! [String]
        let lease = NativeReaderEditorLease {
            let data = try await Task.detached { Data(try CommandRunner(timeout: 10).run(manager, arguments).utf8) }.value
            guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Bool],
                  Set(result.keys) == ["released"] else { throw NativeReaderOperationFailure.unavailable }
        }
        async let first = lease.release()
        async let concurrent = lease.release()
        let failed = await (first, concurrent)
        try require(!failed.0 && !failed.1)
        try require(await lease.retirement == .pending)
        try Data().write(to: URL(fileURLWithPath: marker))
        for _ in 0..<500 {
            if FileManager.default.fileExists(atPath: marker + ".retry") { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        try require(await lease.release())
        try require(await lease.retirement == .confirmed)
        try require(await lease.release())
        print("{\"mode\":\"lease-retry\",\"pendingAfterLockFailure\":true,\"explicitRetryConfirmed\":true,\"noLoop\":true,\"skips\":0}")
    }

    static func main() async throws {
        let args = CommandLine.arguments
        let config = try Data(contentsOf: URL(fileURLWithPath: args[1]))
        let mode = args[2]
        let object = try JSONSerialization.jsonObject(with: config) as! [String: Any]
        if mode == "scope-v8-r1" || mode == "scope-v8-s1" {
            let manager=object["manager"] as! String, marker=args[3]
            let editor=try NativeReaderManagedEditor.consentedDescriptor(URL(fileURLWithPath:object["descriptor"] as! String))
            let resolver=NativeReaderManagedResolver(attach:{try await CommandRunner.nativeReaderManager(manager,$0)},network:.urlSession())
            let root=object["root"] as! String, entry=object["entry"] as! String
            let requestRoot=object["requestRoot"] as! String, requestEntry=object["requestEntry"] as! String
            let bRoot=object["otherRoot"] as! String, bEntry=object["otherEntry"] as! String
            func connect(_ root:String,_ entry:String) async -> Bool {
                let client=NativeReaderManagedClient(resolver:resolver,root:root,entry:entry,editor:editor)
                var accepted=false
                do{_ = try await client.target();accepted=true}catch{}
                await client.dispose();return accepted
            }
            let first=await connect(requestRoot,requestEntry)
            try require(first == (mode == "scope-v8-s1"))
            try Data().write(to:URL(fileURLWithPath:marker+".first"))
            for _ in 0..<1000 {if FileManager.default.fileExists(atPath:marker+".continue"){break};try await Task.sleep(nanoseconds:10_000_000)}
            let independent=await connect(mode == "scope-v8-r1" ? bRoot:root,mode == "scope-v8-r1" ? bEntry:entry)
            let blocked = !(await connect(bRoot,"./"+bEntry))
            try Data().write(to:URL(fileURLWithPath:marker+".blocked"))
            for _ in 0..<1000 {if FileManager.default.fileExists(atPath:marker+".retry"){break};try await Task.sleep(nanoseconds:10_000_000)}
            let recoveredB=await resolver.retryEditorCleanup(root:bRoot,entry:bEntry)
            let recovered=await resolver.retryEditorCleanup(root:requestRoot,entry:requestEntry)
            let freshB=await connect(bRoot,bEntry), freshA=await connect(root,entry)
            let result=try JSONSerialization.data(withJSONObject:["independentAccepted":independent,"pendingBBlocked":blocked,"recoveredOriginal":recovered,"recoveredB":recoveredB,"freshA":freshA,"freshB":freshB,"externalNonceInput":false,"skips":0])
            try result.write(to:URL(fileURLWithPath:marker+".result"))
            print(String(data:result,encoding:.utf8)!)
            try require(independent && blocked && recovered && recoveredB && freshB && freshA);return
        }
        if mode == "scope-pending" {
            let manager=object["manager"] as! String, marker=args[3]
            let root=object["root"] as! String, entry=object["entry"] as! String
            let editor=try NativeReaderManagedEditor.consentedDescriptor(URL(fileURLWithPath:object["descriptor"] as! String))
            let resolver=NativeReaderManagedResolver(attach:{try await CommandRunner.nativeReaderManager(manager,$0)},network:.urlSession())
            let first=NativeReaderManagedClient(resolver:resolver,root:object["aliasRoot"] as! String,entry:entry,editor:editor)
            _ = try await first.target();await first.dispose() // injected release failure: pending remains
            for (otherRoot, otherEntry) in [(root,"./"+entry),(object["aliasRoot"] as! String,entry)] {
                let next=NativeReaderManagedClient(resolver:resolver,root:otherRoot,entry:otherEntry,editor:editor)
                var rejected=false
                do{_ = try await next.target()}catch{rejected=true}
                await next.dispose();try require(rejected)
            }
            let independent=NativeReaderManagedClient(resolver:resolver,root:object["otherRoot"] as! String,
                entry:object["otherEntry"] as! String,readerID:"other",editor:editor)
            _ = try await independent.target();await independent.dispose()
            try Data().write(to:URL(fileURLWithPath:marker+".blocked"))
            for _ in 0..<1000 {if FileManager.default.fileExists(atPath:marker+".retargeted"){break};try await Task.sleep(nanoseconds:10_000_000)}
            let retarget=NativeReaderManagedClient(resolver:resolver,root:object["aliasRoot"] as! String,entry:entry,editor:editor)
            var rejected=false
            do{_ = try await retarget.target()}catch{rejected=true}
            await retarget.dispose();try require(rejected)
            try Data().write(to:URL(fileURLWithPath:marker+".retarget-blocked"))
            for _ in 0..<1000 {if FileManager.default.fileExists(atPath:marker+".retry"){break};try await Task.sleep(nanoseconds:10_000_000)}
            try require(await resolver.retryEditorCleanup(root:root,entry:"./"+entry))
            let fresh=NativeReaderManagedClient(resolver:resolver,root:root,entry:entry,editor:editor)
            _ = try await fresh.target();await fresh.dispose()
            print("{\"canonicalScopeBlocked\":true,\"explicitRetryRecovered\":true,\"freshConsent\":true,\"independentScopeUsable\":true,\"externalNonceInput\":false,\"skips\":0}");return
        }
        if mode.hasPrefix("alias-") {
            let manager=object["manager"] as! String, marker=args[3]
            let root=object["root"] as! String,entry=object["entry"] as! String
            let editor=try NativeReaderManagedEditor.consentedDescriptor(URL(fileURLWithPath:object["descriptor"] as! String))
            let resolver=NativeReaderManagedResolver(attach:{try await CommandRunner.nativeReaderManager(manager,$0)},network:.urlSession())
            let client=NativeReaderManagedClient(resolver:resolver,root:root,entry:entry,editor:editor)
            if mode=="alias-close" {
                _ = try await client.target()
                try Data().write(to:URL(fileURLWithPath:marker+".adopted"))
            } else {
                let first=Task{try await client.target()}
                for _ in 0..<500 {if FileManager.default.fileExists(atPath:marker+".locked"){break};try await Task.sleep(nanoseconds:10_000_000)}
                first.cancel();var rejected=false
                do{_ = try await first.value}catch{rejected=true};try require(rejected)
                try Data().write(to:URL(fileURLWithPath:marker+".pending"))
            }
            for _ in 0..<500 {if FileManager.default.fileExists(atPath:marker+".changed"){break};try await Task.sleep(nanoseconds:10_000_000)}
            if mode=="alias-close" {await client.dispose()}
            else {try require(await resolver.retryEditorCleanup(root:root,entry:entry))}
            print("{\"sameProductionCaller\":true,\"externalNonceInput\":false,\"skips\":0}");return
        }
        if mode == "lease-retry" { try await retirement(object, marker: args[3]); return }
        if mode == "response-pending-client" || mode == "response-pending-body" {
            await MainActor.run { _ = NSApplication.shared; NSApp.setActivationPolicy(.prohibited) }
            let manager = object["manager"] as! String
            let marker = object["registered"] as! String
            let editor = try NativeReaderManagedEditor.consentedDescriptor(URL(fileURLWithPath: object["descriptor"] as! String))
            let resolver = NativeReaderManagedResolver(attach: { try await CommandRunner.nativeReaderManager(manager, $0) }, network: .urlSession())
            let client = NativeReaderManagedClient(resolver: resolver, root: object["root"] as! String, entry: object["entry"] as! String, editor: editor)
            let first = Task { try await client.target() }
            for _ in 0..<500 {
                if FileManager.default.fileExists(atPath: marker + ".locked") { break }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            first.cancel()
            var rejected = false
            do { _ = try await first.value } catch { rejected = true; try Data(String(describing:error).utf8).write(to:URL(fileURLWithPath:marker+".first-error")) }
            try require(rejected)
            try Data().write(to: URL(fileURLWithPath: marker + ".pending"))
            if mode == "response-pending-body" {
                let body = NativeReaderManagedClient(resolver: resolver, root: object["root"] as! String,
                    entry: object["entry"] as! String, editor: nil)
                let identity = try await body.target()
                let context = NativeReaderRequestContext(requestID: UUID(), viewID: UUID(), generation: 1, target: identity)
                let document = try await body.document(for: context)
                let actions = try await body.currentActions()
                let block = document.blocks.first { $0.canonicalText == "Préface 한글 target passage." }!
                let lower = "Préface 한글 ".utf16.count
                let selection = NativeReaderSelection(ticket: UUID(), blockID: block.id,
                    rangeUTF16: lower..<(lower + 6), exact: "target")
                try await actions.updateSelection(selection, context: context)
                let request = NativeReaderSourceRequest(context: context, selection: selection, action: .locate, receiptID: UUID())
                try require(try await actions.perform(request).status == .verified)
                // Source excerpt is intentionally complete-math-only. Reuse
                // SF1's existing expression owner; do not widen plain-text policy.
                let equation = document.blocks.first { $0.kind == .equation }!
                let expression = NativeReaderSelection(ticket: UUID(), blockID: equation.id,
                    rangeUTF16: 0..<equation.canonicalText.utf16.count, exact: equation.canonicalText)
                try await actions.updateSelection(expression, context: context)
                let excerpt = try await actions.perform(.init(context: context, selection: expression, action: .excerpt, receiptID: UUID()))
                try require(excerpt.status == .verified && excerpt.verifiedText?.contains("frac") == true)
                _ = try await actions.perform(.open(expression), context: context)
                let movement = NativeReaderSourceRequest(context: context, selection: expression, action: .locate, receiptID: UUID())
                do { _ = try await actions.jump(movement); throw FlowError(message: "body acquired editor authority") }
                catch NativeReaderOperationFailure.unavailable {}
                await body.dispose()
                try Data().write(to: URL(fileURLWithPath: marker + ".body"))
            }
            for _ in 0..<500 {
                if FileManager.default.fileExists(atPath: marker + ".retry") { break }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            let start = Date()
            _ = try await client.target() // SAME production caller; no operation supplied by harness.
            let elapsed = Date().timeIntervalSince(start)
            try require(elapsed < 10)
            await client.dispose()
            print("{\"sameManagedClientRecovered\":true,\"bodySourceAskWhilePending\":\(mode == "response-pending-body"),\"externalNonceInput\":false,\"retryElapsed\":\(elapsed),\"skips\":0}")
            return
        }
        if mode.hasPrefix("response-") {
            let start = Date(), gate = Gate()
            let manager = object["manager"] as! String
            let editor = try NativeReaderManagedEditor.consentedDescriptor(URL(fileURLWithPath: object["descriptor"] as! String))
            let resolver = NativeReaderManagedResolver(attach: { argv in
                let data = try await CommandRunner.nativeReaderManager(manager, argv)
                if argv.first == "--attach" {
                    if mode == "response-loss" { throw URLError(.networkConnectionLost) }
                    if mode == "response-late" { await gate.stop() }
                }
                return data
            }, network: .urlSession())
            let task = Task { try await resolver.resolve(root: object["root"] as! String, entry: object["entry"] as! String, editor: editor) }
            if mode == "response-late" {
                try await gate.wait(); task.cancel(); await gate.open()
            } else if mode == "response-cancel" || mode == "response-pending" {
                for _ in 0..<500 {
                    if FileManager.default.fileExists(atPath: object["registered"] as! String) { break }
                    try await Task.sleep(nanoseconds: 10_000_000)
                }
                // Python's lock observer acknowledges its actual flock first.
                if mode == "response-pending" {
                    for _ in 0..<500 {
                        if FileManager.default.fileExists(atPath: (object["registered"] as! String) + ".locked") { break }
                        try await Task.sleep(nanoseconds: 10_000_000)
                    }
                }
                task.cancel()
            }
            var rejected = false
            do { _ = try await task.value } catch { rejected = true }
            try require(rejected)
            let elapsed = Date().timeIntervalSince(start)
            try require(elapsed < 10)
            print("{\"mode\":\"\(mode)\",\"rejected\":true,\"elapsed\":\(elapsed),\"skips\":0}")
            return
        }
        if mode == "SF2" { try await leases(object); return }
        if mode.hasPrefix("ui-") { try await offscreen(config, mode: mode, marker: args[3]); return }
        if mode == "descriptor" {
            let directory = URL(fileURLWithPath: args[1]).deletingLastPathComponent()
            let descriptor = directory.appendingPathComponent("editor.json")
            let editor = try NativeReaderManagedEditor.consentedDescriptor(descriptor)
            try require(editor.consentID != nil && editor.ownerPID > 0)
            let link = directory.appendingPathComponent("editor-link.json")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: descriptor)
            for url in [link, directory.appendingPathComponent("missing.json")] {
                do { _ = try NativeReaderManagedEditor.consentedDescriptor(url); throw NativeReaderOperationFailure.rejected(code: "descriptor-accepted") }
                catch NativeReaderOperationFailure.unavailable { }
                catch let error as CocoaError { try require(error.code == .fileReadNoSuchFile) }
            }
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: descriptor.path)
            do { _ = try NativeReaderManagedEditor.consentedDescriptor(descriptor); throw NativeReaderOperationFailure.rejected(code: "public-descriptor-accepted") }
            catch NativeReaderOperationFailure.unavailable { }
            print("{\"mode\":\"descriptor\",\"assertions\":4,\"skips\":0}")
            return
        }
        let consent = UUID(uuidString: object["consentID"] as! String)!
        let attachment = try NativeReaderAttachment(data: config, editorConsentID: mode == "no-consent" ? nil : consent)
        let target = NativeDocumentIdentity(documentID: attachment.documentID, serviceID: attachment.serviceID,
                                             revision: object["revision"] as! String, scope: .service)
        let context = NativeReaderRequestContext(requestID: UUID(), viewID: UUID(), generation: 1, target: target)
        let gate = Gate(), loss = Loss(), syncFault = SyncFault()
        let trace = Trace()
        let real = NativeReaderNetwork.urlSession()
        let gateOperation = mode.hasPrefix("SF1-") ? "prepare" : ["new-selection", "invalid-selection", "dispose", "cancel-prepare", "source-change", "wrong-attachment"].contains(mode) ? "prepare" : "jump"
        let network = NativeReaderNetwork(send: { request, limit in
            let payload = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let operation = payload?["operation"] as? String
            if request.url?.path.hasSuffix("/api/native-editor") == true, let operation { await trace.append(operation) }
            if mode == "SF1-network", operation == "sync", await syncFault.active { throw URLError(.networkConnectionLost) }
            let response = try await real.send(request, limit)
            if mode=="selection-race", operation=="revoke", await syncFault.active, await loss.drop() { await gate.stop() }
            if mode.hasPrefix("lost-receipt"), operation == "jump", await loss.drop() { throw URLError(.networkConnectionLost) }
            if mode == "lost-receipt-unread", operation == "receipt" { throw URLError(.networkConnectionLost) }
            if (mode.hasPrefix("SF1-") || ["new-selection", "invalid-selection", "dispose", "cancel-prepare", "cancel-after", "late-result", "source-change", "wrong-attachment"].contains(mode)),
               request.url?.path.hasSuffix("/api/native-editor") == true, operation == gateOperation {
                await gate.stop()
            }
            return response
        }, stream: real.stream)
        let transport: NativeReaderTransport
        let owner: NativeReaderActions
        let document: NativeReaderDocument
        var managedClient: NativeReaderManagedClient?
        if mode.hasPrefix("managed") {
            let descriptor = URL(fileURLWithPath: args[1]).deletingLastPathComponent().appendingPathComponent("editor.json")
            let editor = try NativeReaderManagedEditor.consentedDescriptor(descriptor)
            let resolver = NativeReaderManagedResolver(attach: { argv in
                if argv.contains("--editor-server") {
                    try require(argv.contains("--native-editor-consent") && argv.contains(editor.address)
                        && argv.contains(editor.executable) && argv.contains(editor.controlFile))
                    if mode == "managed-pending-close" { await gate.stop() }
                }
                return try fixturePlan(config, argv) // Explicit fake inventory; actual attachment/HTTP below.
            }, network: network)
            let client = NativeReaderManagedClient(resolver: resolver, root: "/fixture", entry: "fixture.typ", editor: editor)
            managedClient = client
            if mode == "managed-pending-close" {
                let resolving = Task { try await client.target() }
                try await gate.wait(); await client.revokeEditorConsent(); await gate.open()
                var rejected = false
                do { _ = try await resolving.value }
                catch NativeReaderContractError.staleGeneration { rejected = true }
                try require(rejected)
            }
            try require(try await client.target() == target)
            document = try await client.document(for: context)
            owner = try await client.currentActions(); transport = owner.transport
        } else {
            transport = NativeReaderTransport(attachment: attachment, network: network)
            owner = NativeReaderActions(transport: transport)
            document = try await transport.document(for: context)
        }
        let block = document.blocks.first { $0.canonicalText == "Préface 한글 target passage." }!
        let start = "Préface 한글 ".utf16.count
        let selection = NativeReaderSelection(ticket: UUID(), blockID: block.id, rangeUTF16: start..<(start+6), exact: "target")
        try await owner.updateSelection(selection, context: context)
        let request = NativeReaderSourceRequest(context: context, selection: selection, action: .locate, receiptID: UUID())
        var statuses = [String]()
        if mode=="selection-race" {
            await syncFault.enable()
            let older=NativeReaderSelection(ticket:UUID(),fragments:selection.fragments)
            let newer=NativeReaderSelection(ticket:UUID(),fragments:selection.fragments)
            let changing=Task{try await owner.updateSelection(older,context:context)}
            try await gate.wait();try await owner.updateSelection(newer,context:context);await gate.open()
            do {try await changing.value;throw FlowError(message:"older selection resurrected")}
            catch NativeReaderContractError.staleGeneration {}
            let located=try await owner.perform(.init(context:context,selection:newer,action:.locate,receiptID:UUID()))
            try require(located.status == .verified)
            do {_ = try await owner.perform(.init(context:context,selection:older,action:.locate,receiptID:UUID()));throw FlowError(message:"older ticket actionable")}
            catch NativeReaderContractError.invalidSelection {}
            print("{\"mode\":\"selection-race\",\"skips\":0,\"assertions\":3}");return
        }
        if mode.hasPrefix("queued-") {
            let marker=URL(fileURLWithPath:args[3])
            try Data().write(to: URL(fileURLWithPath: marker.path + ".ready"))
            for _ in 0..<1000 { if FileManager.default.fileExists(atPath: marker.path + ".held") { break }; try await Task.sleep(nanoseconds: 10_000_000) }
            try require(FileManager.default.fileExists(atPath: marker.path + ".held"))
            let pending=Task{try await owner.jump(request)}
            for _ in 0..<1500 {if FileManager.default.fileExists(atPath:marker.path+".queued"){break};try await Task.sleep(nanoseconds:10_000_000)}
            try require(FileManager.default.fileExists(atPath:marker.path+".queued"))
            if mode=="queued-invalid" {
                let invalid=NativeReaderSelection(ticket:UUID(),blockID:block.id,rangeUTF16:0..<10000,exact:"invalid")
                do {try await owner.updateSelection(invalid,context:context);throw FlowError(message:"queued invalid accepted")}
                catch NativeReaderContractError.invalidSelection {}
            } else {await transport.invalidate()}
            try Data("revoked".utf8).write(to:URL(fileURLWithPath:marker.path+".revoked"))
            do {_ = try await pending.value;throw FlowError(message:"queued obsolete result adopted")}
            catch NativeReaderContractError.staleGeneration {}
            catch NativeReaderContractError.invalidSelection {}
            catch NativeReaderOperationFailure.unknownEffect {}
            let operations=await trace.operations
            try require(operations.filter{$0=="jump"}.count==1)
            print(String(data:try JSONSerialization.data(withJSONObject:["mode":mode,"skips":0,"assertions":5,"jumpTransmitted":true,"effectGate":true,"oldEffect":false]),encoding:.utf8)!)
            return
        }
        if mode.hasPrefix("SF1-") {
            let pending = Task { try await owner.jump(request) }
            try await gate.wait()
            if mode == "SF1-network" { await syncFault.enable() }
            else {
                let marker = URL(fileURLWithPath: args[3]);try Data("fault".utf8).write(to:marker)
                for _ in 0..<1000 { if FileManager.default.fileExists(atPath:marker.path+".done") { break };try await Task.sleep(nanoseconds:10_000_000) }
                try require(FileManager.default.fileExists(atPath:marker.path+".done"))
            }
            let newer = NativeReaderSelection(ticket:UUID(),fragments:selection.fragments)
            try await owner.updateSelection(newer,context:context)
            let locate = NativeReaderSourceRequest(context:context,selection:newer,action:.locate,receiptID:UUID())
            try require(try await owner.perform(locate).status == .verified)
            do { _ = try await owner.jump(locate);throw FlowError(message:"editor failure allowed a new effect") }
            catch NativeReaderOperationFailure.unavailable {}
            catch NativeReaderOperationFailure.unknownEffect {}
            let equation=document.blocks.first{$0.kind == .equation}!
            let math=NativeReaderSelection(ticket:UUID(),blockID:equation.id,rangeUTF16:0..<equation.canonicalText.utf16.count,exact:equation.canonicalText)
            try await owner.updateSelection(math,context:context)
            let excerpt=try await owner.perform(.init(context:context,selection:math,action:.excerpt,receiptID:UUID()))
            try require(excerpt.status == .verified && excerpt.verifiedText?.contains("frac") == true)
            _ = try await owner.perform(.open(math),context:context)
            let invalid=NativeReaderSelection(ticket:UUID(),blockID:block.id,rangeUTF16:0..<10000,exact:"invalid")
            do {try await owner.updateSelection(invalid,context:context);throw FlowError(message:"invalid new selection accepted")}
            catch NativeReaderContractError.invalidSelection {}
            await gate.open()
            do {_ = try await pending.value;throw FlowError(message:"old pending effect survived")}
            catch NativeReaderContractError.invalidSelection {}
            catch NativeReaderContractError.staleGeneration {}
            catch NativeReaderOperationFailure.unavailable {}
            let operations=await trace.operations
            try require(!operations.contains("jump"))
            print(String(data:try JSONSerialization.data(withJSONObject:["mode":mode,"skips":0,"assertions":8,"sourceAndAsk":true,"jumpRequests":0,"oldPendingReused":false]),encoding:.utf8)!)
            return
        }
        if ["managed-close", "managed-pending-close"].contains(mode), let client = managedClient {
            await client.revokeEditorConsent()
            do { _ = try await owner.jump(request); throw NativeReaderOperationFailure.rejected(code: "closed-consent-accepted") }
            catch NativeReaderOperationFailure.unavailable { statuses.append("consent-revoked") }
            try require(try await client.target() == target)
            let reopened = try await client.document(for: context)
            try require(reopened.identity == target)
            try await owner.updateSelection(selection, context: context)
            do { _ = try await owner.jump(request); throw NativeReaderOperationFailure.rejected(code: "reopened-consent-accepted") }
            catch NativeReaderOperationFailure.unavailable { statuses.append("document-reopened-editor-unavailable") }
        } else if mode == "jump" || mode == "managed" || mode == "modified" {
            let result = try await owner.jump(request)
            try require(result.status == (mode == "modified" ? .modified : .jumped))
            statuses.append(result.status.rawValue)
            let receipt = try await owner.jump(request, query: true)
            try require(receipt.status == result.status)
            statuses.append(receipt.status.rawValue)
        } else if mode.hasPrefix("lost-receipt") {
            do { _ = try await owner.jump(request); throw NativeReaderOperationFailure.rejected(code: "lost-ack-accepted") }
            catch NativeReaderOperationFailure.unknownEffect { statuses.append("unknown") }
            try require(await owner.pendingEditorReceiptID() == request.receiptID)
            do { _ = try await owner.jump(request); throw NativeReaderOperationFailure.rejected(code: "automatic-retry") }
            catch NativeReaderOperationFailure.unknownEffect { statuses.append("replay-blocked") }
            // Never replay; the one explicit bounded read recovers the receipt.
            if mode == "lost-receipt-unread" {
                do { _ = try await owner.jump(request, query: true); throw NativeReaderOperationFailure.rejected(code: "unread-accepted") }
                catch is URLError { statuses.append("receipt-unavailable") }
                do { _ = try await owner.jump(request); throw NativeReaderOperationFailure.rejected(code: "replay-after-unread") }
                catch NativeReaderOperationFailure.unknownEffect { statuses.append("replay-blocked") }
                let other = NativeReaderSourceRequest(context: context, selection: selection, action: .locate, receiptID: UUID())
                do { _ = try await owner.jump(other, query: true); throw NativeReaderOperationFailure.rejected(code: "foreign-receipt") }
                catch NativeReaderOperationFailure.unknownEffect { statuses.append("foreign-receipt-blocked") }
            } else {
                let result = try await owner.jump(request, query: true)
                try require(result.status == .jumped); statuses.append(result.status.rawValue)
                try require(await owner.pendingEditorReceiptID() == nil)
            }
        } else if mode == "cancel-before" || mode == "no-consent" {
            let task = Task { () throws -> NativeReaderEditorReceipt in
                if mode == "cancel-before" { withUnsafeCurrentTask { $0?.cancel() } }
                return try await owner.jump(request)
            }
            do { _ = try await task.value; throw NativeReaderOperationFailure.rejected(code: "cancel-accepted") }
            catch is CancellationError { statuses.append("cancelled-before") }
            catch NativeReaderOperationFailure.unavailable { statuses.append("unavailable") }
        } else {
            let task = Task { try await owner.jump(request) }
            try await gate.wait()
            if mode == "invalid-selection" {
                let invalid = NativeReaderSelection(ticket: UUID(), blockID: block.id, rangeUTF16: 0..<10000, exact: "invalid")
                var rejected = false
                do { try await owner.updateSelection(invalid, context: context) } catch { rejected = true }
                try require(rejected)
            } else if mode == "new-selection" || mode == "late-result" {
                let newer = NativeReaderSelection(ticket: UUID(), fragments: selection.fragments)
                try await owner.updateSelection(newer, context: context)
            } else if mode == "dispose" { await transport.dispose() }
            else if mode == "source-change" || mode == "wrong-attachment" {
                // Harness owns the private fixture mutation. It is not an app write.
                let marker = URL(fileURLWithPath: args[3])
                try Data("ready".utf8).write(to: marker)
                for _ in 0..<1000 {
                    if FileManager.default.fileExists(atPath: marker.path + ".done") { break }
                    try await Task.sleep(nanoseconds: 10_000_000)
                }
                try require(FileManager.default.fileExists(atPath: marker.path + ".done"))
            } else { task.cancel() }
            await gate.open()
            var completed: NativeReaderEditorReceipt?
            do { completed = try await task.value } catch { statuses.append("obsolete-rejected") }
            if let result = completed {
                try require(["source-change", "wrong-attachment"].contains(mode) && result.status == .stale)
                statuses.append(result.status.rawValue)
            } else { try require(!["source-change", "wrong-attachment"].contains(mode)) }
            if mode == "cancel-after" {
                let receipt = try await owner.jump(request, query: true)
                try require(receipt.status == .jumped); statuses.append(receipt.status.rawValue)
            }
        }
        // Local mapping alone still has the original contract, separate from jump.
        if mode == "jump" {
            let located = try await owner.perform(request)
            try require(located.status == .verified && located.destinationAnchor != nil)
        }
        if mode == "managed" {
            let write = NativeReaderSourceRequest(context: context, selection: selection, action: .highlight, receiptID: UUID())
            try require(try await owner.perform(write).status == .unsupported)
        }
        let output: [String: Any] = ["mode": mode, "statuses": statuses, "assertions": statuses.count + 1,
            "receiptID": request.receiptID.uuidString.lowercased(), "selectionTicket": selection.ticket.uuidString.lowercased(),
            "documentRequestID": context.requestID.uuidString.lowercased(), "viewID": context.viewID.uuidString.lowercased(),
            "generation": context.generation, "documentID": target.documentID, "serviceID": target.serviceID, "revision": target.revision,
            "operations": await trace.operations,
            "provider": "actual production HTTP and actual Neovim; injected response gate/loss only", "nativeGUI": "not-run", "skips": 0]
        if mode.hasPrefix("lost-receipt") { try require(await trace.operations == ["revoke", "sync", "prepare", "jump", "receipt"]) }
        print(String(data: try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
