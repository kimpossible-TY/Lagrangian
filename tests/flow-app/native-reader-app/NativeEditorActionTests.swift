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
    static func require(_ value: Bool) throws {
        if !value { throw NativeReaderOperationFailure.rejected(code: "test-assertion") }
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
            await trace.attachment(consented: argv.contains("--native-editor-consent"))
            return config
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

    static func main() async throws {
        let args = CommandLine.arguments
        let config = try Data(contentsOf: URL(fileURLWithPath: args[1]))
        let mode = args[2]
        let object = try JSONSerialization.jsonObject(with: config) as! [String: Any]
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
        let gate = Gate(), loss = Loss()
        let trace = Trace()
        let real = NativeReaderNetwork.urlSession()
        let gateOperation = ["new-selection", "invalid-selection", "dispose", "cancel-prepare", "source-change", "wrong-attachment"].contains(mode) ? "prepare" : "jump"
        let network = NativeReaderNetwork(send: { request, limit in
            let payload = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let operation = payload?["operation"] as? String
            if request.url?.path.hasSuffix("/api/native-editor") == true, let operation { await trace.append(operation) }
            let response = try await real.send(request, limit)
            if mode.hasPrefix("lost-receipt"), operation == "jump", await loss.drop() { throw URLError(.networkConnectionLost) }
            if mode == "lost-receipt-unread", operation == "receipt" { throw URLError(.networkConnectionLost) }
            if ["new-selection", "invalid-selection", "dispose", "cancel-prepare", "cancel-after", "late-result", "source-change", "wrong-attachment"].contains(mode),
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
                return config // Injected local inventory; actual registered attachment and HTTP below.
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
        if mode.hasPrefix("lost-receipt") { try require(await trace.operations == ["sync", "prepare", "jump", "receipt"]) }
        print(String(data: try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
