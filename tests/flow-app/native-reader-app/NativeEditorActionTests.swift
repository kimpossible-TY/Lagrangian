import Foundation

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

@main struct NativeEditorActionTests {
    static func require(_ value: Bool) throws {
        if !value { throw NativeReaderOperationFailure.rejected(code: "test-assertion") }
    }
    static func main() async throws {
        let args = CommandLine.arguments
        let config = try Data(contentsOf: URL(fileURLWithPath: args[1]))
        let mode = args[2]
        let object = try JSONSerialization.jsonObject(with: config) as! [String: Any]
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
