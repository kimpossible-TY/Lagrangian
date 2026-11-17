import AppKit
import Foundation

private enum TestFailure: Error { case assertion(String) }
@MainActor private var assertions = 0
@MainActor private func require(_ condition: Bool, _ label: String) throws {
    assertions += 1
    if !condition { throw TestFailure.assertion(label) }
}
@MainActor private func rejects(_ label: String, _ operation: () async throws -> Void) async throws {
    do { try await operation() } catch { assertions += 1; return }
    throw TestFailure.assertion(label)
}
private func rebased(_ document: NativeReaderDocument, context: NativeReaderRequestContext) -> NativeReaderDocument {
    NativeReaderDocument(schemaVersion: document.schemaVersion, identity: context.target, generation: context.generation,
        requiredCapabilities: document.requiredCapabilities, blocks: document.blocks, assets: document.assets, diagnostics: document.diagnostics)
}
private struct Provider: NativeReaderDocumentProviding {
    var load: (NativeReaderRequestContext) async throws -> NativeReaderDocument
    func document(for context: NativeReaderRequestContext) async throws -> NativeReaderDocument { try await load(context) }
}
private actor Counter {
    var count = 0
    func increment() -> Int { count += 1; return count }
    func value() -> Int { count }
}

private actor AttachTrace {
    var calls = [[String]]()
    func record(_ args: [String]) -> Int { calls.append(args); return calls.count }
    func snapshot() -> [[String]] { calls }
}

@main struct ServiceTests {
    @MainActor static func main() async {
        do {
            try await run()
            let report: [String: Any] = ["assertions": assertions, "scope": "real owned HTTP + compiler/source mapping; injected/fake provider, lifecycle/network/storage; headless AppKit activation prohibited", "skips": 0]
            print(String(data: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]), encoding: .utf8)!)
        } catch { fputs("ServiceTests failed: \(error)\n", stderr); exit(1) }
    }

    @MainActor private static func waitFor(_ condition: () -> Bool) async throws {
        for _ in 0..<2000 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        throw TestFailure.assertion("bounded wait")
    }

    @MainActor private static func run() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        try require(app.activationPolicy() == .prohibited, "headless activation")
        let args = CommandLine.arguments
        let raw = try Data(contentsOf: URL(fileURLWithPath: args[1]))
        let attachment = try NativeReaderAttachment(data: raw)
        let shared = try NativeReaderAttachment(data: Data(contentsOf: URL(fileURLWithPath: args[2])))
        let identity = NativeDocumentIdentity(documentID: attachment.documentID, serviceID: attachment.serviceID, revision: args[3], scope: .service)
        let context = NativeReaderRequestContext(requestID: UUID(), viewID: UUID(), generation: 1, target: identity)
        let network = NativeReaderNetwork.urlSession()
        let transport = NativeReaderTransport(attachment: attachment, network: network)
        let document = try await transport.document(for: context)
        try require(document.identity == identity && document.blocks.count == 4, "accepted full real tree")
        try require(document.blocks[0].canonicalText == "First paragraph keeps its own question.", "independent literal oracle")
        let prefixed = NativeReaderTransport(attachment: shared, network: network)
        let same = try await prefixed.document(for: context)
        try require(document == same, "registered prefix same exact tree")
        let argsCounter = Counter()
        let resolver = NativeReaderManagedResolver(attach: { argv in
            _ = await argsCounter.increment()
            guard argv == ["--attach", "--root", "/isolated/project", "--entry", "main.typ", "--reader-service", "exact"] else { throw TestFailure.assertion("manager argv") }
            return raw
        }, network: network)
        let resolved = try await resolver.resolve(root: "/isolated/project", entry: "main.typ", readerID: "exact")
        try require(resolved.1 == identity, "manager observed incarnation/revision")
        try require(await argsCounter.value() == 1, "manager attach once")
        let managed = NativeReaderManagedClient(resolver: resolver, root: "/isolated/project", entry: "main.typ", readerID: "exact")
        let managedIdentity = try await managed.target()
        try require(managedIdentity == identity, "managed profile identity")
        _ = try await managed.document(for: context)
        _ = try await managed.currentActions()
        await managed.invalidate()
        try await rejects("managed invalidation blocks stale actions") { try await managed.currentActions().updateSelection(nil, context: context) }
        _ = try await managed.target()
        _ = try await managed.document(for: context)
        await managed.dispose()
        try await rejects("managed dispose blocks new attachment") { _ = try await managed.target() }
        let trace = AttachTrace()
        let simulatedAttach = NativeReaderManagedResolver(attach: { argv in
            let count = await trace.record(argv)
            let service = ["pid": attachment.service["pid"]!, "startedAt": attachment.service["startedAt"]! + (count >= 3 ? 1 : 0)]
            var plan: [String: Any] = ["url": attachment.baseURL.absoluteString, "documentID": attachment.documentID, "service": service]
            if argv.contains("--editor-server") { plan["editorAttachment"] = "fixture-registration" }
            return try JSONSerialization.data(withJSONObject: plan)
        }, network: NativeReaderNetwork(send: { _, _ in
            let count = await trace.snapshot().count
            let service = ["pid": attachment.service["pid"]!, "startedAt": attachment.service["startedAt"]! + (count >= 3 ? 1 : 0)]
            let data = try JSONSerialization.data(withJSONObject: ["documentID": attachment.documentID, "service": service, "revision": identity.revision])
            return NativeReaderHTTPResponse(status: 200, headers: ["content-type": "application/json"], data: data)
        }, stream: network.stream))
        let reconnect = NativeReaderManagedClient(resolver: simulatedAttach, root: "/fixture", entry: "main.typ",
            editor: NativeReaderManagedEditor(address: "fixture-editor", executable: "fixture-nvim", ownerPID: 123, controlFile: "/fixture/control"))
        let initialTarget = try await reconnect.target()
        let sameTarget = try await reconnect.target()
        let restartedTarget = try await reconnect.target()
        try require(initialTarget == sameTarget && restartedTarget.serviceID != initialTarget.serviceID, "injected managed restart binds new incarnation")
        let registrations = await trace.snapshot()
        try require(registrations.count == 4 && registrations.filter({ $0.contains("--editor-server") }).count == 2, "one editor registration per incarnation")
        await reconnect.dispose()
        var invalidAttachment = try JSONSerialization.jsonObject(with: raw) as! [String: Any]
        for url in ["http://127.0.0.1:1234/p/preview/", "https://evil.invalid/", "http://127.0.0.1:1234/d/../", "http://127.0.0.1:1234/?token=x"] {
            invalidAttachment["url"] = url
            let bytes = try JSONSerialization.data(withJSONObject: invalidAttachment)
            try await rejects("reject non-reader attachment") { _ = try NativeReaderAttachment(data: bytes) }
        }
        let selection = NativeReaderSelection(ticket: UUID(), blockID: document.blocks[0].id, rangeUTF16: 0..<document.blocks[0].displayText.utf16.count, exact: document.blocks[0].displayText)
        let actions = NativeReaderActions(transport: transport)
        try await actions.updateSelection(selection, context: context)
        let locate = try await actions.perform(NativeReaderSourceRequest(context: context, selection: selection, action: .locate, receiptID: UUID()))
        try require(locate.status == .verified && locate.destinationAnchor != nil, "real guarded locate")
        let math = document.blocks[2]
        let mathSelection = NativeReaderSelection(ticket: UUID(), blockID: math.id, rangeUTF16: 0..<math.displayText.utf16.count, exact: math.displayText)
        try await actions.updateSelection(mathSelection, context: context)
        let excerpt = try await actions.perform(NativeReaderSourceRequest(context: context, selection: mathSelection, action: .excerpt, receiptID: UUID()))
        try require(excerpt.status == .verified && excerpt.verifiedText == "$alpha + beta$", "actual source-mapped excerpt")
        let highlight = try await actions.perform(NativeReaderSourceRequest(context: context, selection: mathSelection, action: .highlight, receiptID: UUID()))
        try require(highlight.status == .rejected, "missing editor attachment cannot write")
        let receipt = try await actions.receipt(for: NativeReaderSourceRequest(context: context, selection: mathSelection, action: .highlight, receiptID: UUID()))
        try require(receipt.status == .uncertain, "missing receipt honest unknown")
        try await actions.updateSelection(selection, context: context)
        let opened = try await actions.perform(.open(selection), context: context)
        try require(opened.messages.isEmpty, "open no inference")
        let draft = try await actions.perform(.draft(conversation: opened.conversationID, version: opened.version, text: "Question"), context: context)
        try require(draft.version > opened.version && draft.messages.isEmpty, "draft no inference")
        let account = try await actions.account(context: context)
        try require(account.models == ["fixture-model"], "existing model catalog")
        let message = UUID()
        let sent = try await actions.perform(.send(conversation: draft.conversationID, version: draft.version, message: message, question: "Question", model: "fixture-model"), context: context)
        try require(sent.messages.contains(where: { $0.id == message }), "explicit send stable message")
        let duplicate = try await actions.perform(.send(conversation: draft.conversationID, version: sent.version, message: message, question: "Question", model: "fixture-model"), context: context)
        try require(duplicate.messages.filter({ $0.id == message }).count == 1, "server UUID dedup")
        var observed = 0
        for try await state in actions.observe(conversation: opened.conversationID, context: context) {
            observed += 1
            try require(state.version >= sent.version && state.sequence >= 0, "bounded real SSE monotonic")
        }
        try require(observed > 0, "SSE delivered")
        try await actions.updateSelection(mathSelection, context: context)
        try await rejects("selection changed blocks send") {
            _ = try await actions.perform(.send(conversation: opened.conversationID, version: duplicate.version, message: UUID(), question: "stale", model: "fixture-model"), context: context)
        }

        // Dispatch succeeds at the real owner, then the injected link loses its acknowledgment.
        let dropCount = Counter()
        let lostNetwork = NativeReaderNetwork(send: { request, limit in
            let response = try await network.send(request, limit)
            if request.url?.path.hasSuffix("native-chat") == true,
               let body = request.httpBody,
               (try JSONSerialization.jsonObject(with: body) as? [String: Any])?["operation"] as? String == "send" {
                _ = await dropCount.increment()
                throw URLError(.networkConnectionLost)
            }
            return response
        }, stream: network.stream)
        let lostTransport = NativeReaderTransport(attachment: attachment, network: lostNetwork)
        _ = try await lostTransport.document(for: context)
        let lostActions = NativeReaderActions(transport: lostTransport)
        try await lostActions.updateSelection(mathSelection, context: context)
        let lostOpen = try await lostActions.perform(.open(mathSelection), context: context)
        let lostID = UUID()
        try await rejects("lost send ack unknown") {
            _ = try await lostActions.perform(.send(conversation: lostOpen.conversationID, version: lostOpen.version, message: lostID, question: "lost", model: "fixture-model"), context: context)
        }
        try await rejects("no retry before authoritative read") {
            _ = try await lostActions.perform(.send(conversation: lostOpen.conversationID, version: lostOpen.version, message: lostID, question: "lost", model: "fixture-model"), context: context)
        }
        let history = try await lostActions.history(context: context)
        try require(history.contains(where: { $0.state.messages.contains(where: { $0.id == lostID }) }), "lost ack authoritative history")
        try require(await dropCount.value() == 1, "uncertain send never replayed")

        // Parser boundaries include split UTF8, malformed UTF8, truncation and stale.
        var parser = NativeReaderSSEParser()
        let event = Data("data: {\"text\":\"한😀\"}\r\n\r\n".utf8)
        var parsed = [Data]()
        for byte in event { parsed += try parser.feed(Data([byte])) }
        try parser.finish()
        try require(parsed.count == 1 && String(data: parsed[0], encoding: .utf8) == "{\"text\":\"한😀\"}", "split UTF8 and CRLF SSE")
        try await rejects("malformed SSE") { var p = NativeReaderSSEParser(); _ = try p.feed(Data([0xff,10])) }
        try await rejects("stale SSE") { var p = NativeReaderSSEParser(); _ = try p.feed(Data("event: stale\ndata: {}\n\n".utf8)) }
        try await rejects("truncated SSE") { var p = NativeReaderSSEParser(); _ = try p.feed(Data("data: {}".utf8)); try p.finish() }
        try await rejects("SSE payload bound") { var p = NativeReaderSSEParser(); _ = try p.feed(Data(repeating: 65, count: 2*1024*1024+4097)) }

        var assetBytes: [String: Data] = [:]
        for asset in document.assets { assetBytes[asset.id] = try await transport.asset(asset, context: context) }
        try require(!assetBytes.isEmpty, "real revision-bound assets verified")
        let responseData = try JSONEncoder().encode(document)
        let responseHeaders = ["content-type": "application/json", "x-native-input-id": String(repeating: "a", count: 64)]
        for change in ["schema", "capability", "revision"] {
            var object = try JSONSerialization.jsonObject(with: responseData) as! [String: Any]
            if change == "schema" { object["schemaVersion"] = 2 }
            else if change == "capability" { object["requiredCapabilities"] = ["unknown"] }
            else { var target = object["identity"] as! [String: Any]; target["revision"] = "wrong"; object["identity"] = target }
            let data = try JSONSerialization.data(withJSONObject: object)
            let fake = NativeReaderNetwork(send: { _, _ in NativeReaderHTTPResponse(status: 200, headers: responseHeaders, data: data) }, stream: { _ in AsyncThrowingStream { $0.finish() } })
            let guarded = NativeReaderTransport(attachment: attachment, network: fake)
            try await rejects("reject response contract before typed decode") { _ = try await guarded.document(for: context) }
        }
        let delayed = NativeReaderNetwork(send: { _, _ in
            try await Task.sleep(nanoseconds: 50_000_000)
            return NativeReaderHTTPResponse(status: 200, headers: responseHeaders, data: responseData)
        }, stream: network.stream)
        let late = NativeReaderTransport(attachment: attachment, network: delayed)
        let lateTask = Task { try await late.document(for: context) }
        try await Task.sleep(nanoseconds: 5_000_000)
        await late.invalidate()
        try await rejects("late network response") { _ = try await lateTask.value }

        // Publication hold/late ticket/readonly recovery/laptop lifecycle.
        let provider = Provider(load: { rebased(document, context: $0) })
        let session = NativeReaderSession(provider: provider, target: { identity }, wait: { _ in await Task.yield() })
        session.refresh(); try await waitFor { session.state == .reading }
        let firstContext = session.context!
        try session.hold(selection)
        session.refresh(); try await waitFor { session.state == .reading }
        try require(session.context == firstContext, "selection holds publication")
        let newer = NativeReaderSelection(ticket: UUID(), fragments: selection.fragments)
        try session.hold(newer)
        session.acknowledge(ticket: selection.ticket)
        try require(session.store.selection?.ticket == newer.ticket, "late ack preserves new selection")
        session.acknowledge(ticket: newer.ticket)
        try require(session.context != firstContext && session.store.selection == nil, "latest pending publication after release")
        let root = URL(fileURLWithPath: args[4])
        let recovery = NativeReaderRecoveryStore(root: root)
        let restoration = NativeReaderRestoration(blockID: document.blocks[0].id, offset: 0.25, zoom: 1.5,
            selectionTicket: selection.ticket, fragments: selection.fragments.map { .init(blockID: $0.blockID, start: $0.rangeUTF16.lowerBound, end: $0.rangeUTF16.upperBound, exact: $0.exact) })
        let snapshot = NativeReaderRecoverySnapshot(document: document, assets: assetBytes, restoration: restoration,
            drafts: [NativeReaderRecoveredDraft(conversationID: opened.conversationID, version: draft.version, text: "Only composer text", pendingMessageID: nil)])
        let review = NativeReaderLocalReview()
        try review.add(NativeReaderReviewMark(id: UUID(), identity: identity, selection: restoration), document: document)
        try require(review.marks.count == 1, "native review local paint")
        review.undo(); try require(review.marks.isEmpty, "review undo")
        try review.add(NativeReaderReviewMark(id: UUID(), identity: identity, selection: restoration), document: document)
        review.clear(); try require(review.marks.isEmpty, "review clear")
        try await recovery.save(snapshot)
        let loaded = try await recovery.load(identity: identity)
        try require(loaded.document == document && loaded.restoration == restoration, "atomic digest-checked snapshot")
        let offline = NativeReaderSession(provider: provider, target: { identity })
        try offline.restore(loaded, matching: identity)
        try require(offline.state == .offline && offline.store.selection?.ticket == selection.ticket, "offline read-only selection restoration")
        try await rejects("offline source/chat refusal") { try offline.authorize(offline.context!) }
        let wrong = NativeDocumentIdentity(documentID: identity.documentID, serviceID: "reader:1:1", revision: identity.revision, scope: .service)
        try await rejects("recovery wrong service") { _ = try await recovery.load(identity: wrong) }
        let file = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).first!
        var bytes = try Data(contentsOf: file); bytes[bytes.count/2] ^= 1; try bytes.write(to: file)
        try await rejects("corrupt recovery digest") { _ = try await recovery.load(identity: identity) }
        try await recovery.save(snapshot)
        try require(try await recovery.load(identity: identity).document == document, "atomic replacement after corrupt snapshot")
        let canceledSave = Task { () throws -> Void in
            try Task.checkCancellation()
            try await recovery.save(snapshot)
        }
        canceledSave.cancel()
        try await rejects("canceled snapshot preserves old commit") { try await canceledSave.value }
        try require(try await recovery.load(identity: identity).document == document, "old snapshot survives canceled save")
        let linkRoot = root.deletingLastPathComponent().appendingPathComponent("recovery-link")
        try FileManager.default.createSymbolicLink(at: linkRoot, withDestinationURL: root)
        let symlinkStore = NativeReaderRecoveryStore(root: linkRoot)
        try await rejects("symlink recovery root") { _ = try await symlinkStore.load(identity: identity) }
        let failedCounter = Counter()
        let failing = NativeReaderSession(provider: Provider(load: { _ in _ = await failedCounter.increment(); throw URLError(.timedOut) }), target: { identity }, wait: { _ in await Task.yield() })
        failing.refresh(); try await waitFor { failing.state == .offline }
        try await Task.sleep(nanoseconds: 30_000_000)
        try require(await failedCounter.value() == 4, "bounded reconnect attempts")
        session.event(.power(constrained: true)); session.event(.sleep)
        try require(session.state == .sleeping && session.store.document != nil, "sleep retains accepted")
        session.event(.network(false)); try require(session.state == .offline, "network offline")
        session.event(.dispose); session.refresh(); session.event(.wake)
        try require(session.state == .disposed && session.store.document != nil, "dispose rejects callbacks retains accepted")
        failing.event(.dispose); offline.event(.dispose)

        let safe = NativeReaderAnswerPart.attributed("# Heading\n**bold** `<script>`\n<script>alert(1)</script>\n$$\nx^2\n$$")
        try require(safe.string.contains("<script>alert(1)</script>"), "HTML remains literal native text")
        try require(safe.string.contains("native layout unavailable"), "honest math fallback")
        let view = NativeReaderChatView(actions: actions, context: context, authorize: {})
        if let record = await actions.conversation(opened.conversationID) { view.present(record) }
        view.presentAccount(account)
        try require(view.composer.isRichText == false && view.answer.isEditable == false, "native composer/answer")
        try require(app.windows.allSatisfy({ !$0.isVisible }) && app.activationPolicy() == .prohibited, "no visible GUI windows or foreground activation")
        var persisted: NativeReaderRecoveredDraft?
        view.persistDraft = { persisted = $0 }
        view.composer.string = "Newer local draft"
        view.textDidChange(Notification(name: NSText.didChangeNotification))
        if let record = await actions.conversation(opened.conversationID) { view.present(record) }
        try require(view.composer.string == "Newer local draft" && persisted?.text == "Newer local draft", "late history cannot clear newer local draft")
        view.dispose()
        try require(!view.sendButton.isEnabled, "disposed UI cannot send")
        await transport.dispose()
        try await rejects("disposed transport") { _ = try await transport.document(for: context) }
    }
}
