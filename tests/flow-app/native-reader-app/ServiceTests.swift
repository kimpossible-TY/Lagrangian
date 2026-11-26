import AppKit
import Foundation

private enum TestFailure: Error { case assertion(String) }
@MainActor private var assertions = 0
@MainActor private var layoutCacheReport = [String: Any]()
@MainActor private func serviceCheck(_ condition: Bool, _ label: String) throws {
    assertions += 1
    if !condition { throw TestFailure.assertion(label) }
}
@MainActor private func rejects(_ label: String, _ operation: () async throws -> Void) async throws {
    do { try await operation() } catch { assertions += 1; return }
    throw TestFailure.assertion(label)
}
@MainActor private func refreshConversation(_ view: NativeReaderChatView) async throws {
    func buttons(_ root: NSView) -> [NSButton] {
        (root as? NSButton).map { [$0] } ?? root.subviews.flatMap(buttons)
    }
    view.frame = NSRect(x: 0, y: 0, width: 840, height: 480)
    view.layoutSubtreeIfNeeded()
    let candidates = buttons(view).filter { $0.title == "Refresh conversation" }
    try serviceCheck(candidates.count == 1, "F5-UI production Refresh conversation control is reachable")
    let button = candidates[0]
    try serviceCheck(button.target === view && button.action != nil && button.isEnabled && !button.isHidden && button.bounds.width > 0 && button.bounds.height > 0,
        "F5-UI actual native button layout and target-action")
    button.performClick(nil)
    for _ in 0..<400 {
        if button.isEnabled { return }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    throw TestFailure.assertion("F5-UI history control never completed")
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

private actor HistoryGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var entered = false
    func hold() async { entered = true; await withCheckedContinuation { continuation = $0 } }
    func waiting() -> Bool { entered }
    func release() { continuation?.resume(); continuation = nil }
}

private actor AttachTrace {
    var calls = [[String]]()
    func record(_ args: [String]) -> Int { calls.append(args); return calls.count }
    func snapshot() -> [[String]] { calls }
}

/// Deterministic cache/body fixture, not NA02/NA03 UI. All mutable document and
/// selection authority is the production common store supplied to Session.
@MainActor private final class AdoptionFixture {
    let store = NativeReaderDocumentStore()
    var body: NativeReaderDocument?
    var layout = 0
    var blocked = false
    var failPreparation = false
    var failAdopter = false
    var noOpAdopter = false
    var preparationCount = 0
    var adopterCalls = 0
    var publications = 0
    var events = [String]()
    private var gates: [Int: CheckedContinuation<Void, Never>] = [:]

    func prepare(_ document: NativeReaderDocument, _ context: NativeReaderRequestContext) async throws -> NativeReaderSession.PreparedAdoption {
        preparationCount += 1
        let serial = preparationCount, key = layout
        events.append("prepare:\(serial):\(key)")
        if blocked { await withCheckedContinuation { gates[serial] = $0 } }
        // Intentionally ignore cancellation here to exercise late completion.
        if failPreparation { throw TestFailure.assertion("injected prepare failure") }
        events.append("prepared:\(serial):\(key)")
        return .init(isCurrent: { self.layout == key }, adopt: {
            self.adopterCalls += 1
            guard self.body == self.store.document else { throw TestFailure.assertion("model published before body preparation") }
            if self.failAdopter { throw TestFailure.assertion("injected compose failure before publication") }
            if self.noOpAdopter { return }
            guard self.layout == key else { throw TestFailure.assertion("obsolete prepared key") }
            self.events.append("adopt:\(serial):\(key)")
            try self.store.adopt(document, for: context)
            self.body = document
            self.publications += 1
            self.events.append("install:\(serial):\(key)")
        })
    }
    func resume(_ serial: Int) { gates.removeValue(forKey: serial)?.resume() }
}

@MainActor private var adoptionAssertions = 0

@main struct ServiceTests {
    @MainActor static func main() async {
        do {
            if CommandLine.arguments.count > 1 && CommandLine.arguments[1] == "raw-contract" {
                try await rawPipeline(CommandLine.arguments); return
            }
            try await run()
            let report: [String: Any] = ["stage3": layoutCacheReport, "assertions": assertions, "scope": "real owned HTTP + compiler/source mapping; injected/fake provider, lifecycle/network/storage; headless AppKit activation prohibited", "skips": 0, "adoptionAssertions": adoptionAssertions, "adoptionScope": "real Session/common-store with deterministic preparation/adopter fixture; no integrated text/object UI"]
            print(String(data: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]), encoding: .utf8)!)
        } catch { fputs("ServiceTests failed: \(error)\n", stderr); exit(1) }
    }

    @MainActor private static func waitFor(file: StaticString = #fileID, line: UInt = #line, _ condition: () -> Bool) async throws {
        for _ in 0..<2000 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        throw TestFailure.assertion("bounded wait at \(file):\(line)")
    }

    @MainActor private static func adoptionRegressions(_ document: NativeReaderDocument, _ identity: NativeDocumentIdentity,
                                                           _ snapshot: NativeReaderRecoverySnapshot) async throws {
        let before = assertions
        let provider = Provider(load: { rebased(document, context: $0) })
        func make(_ fixture: AdoptionFixture) -> NativeReaderSession {
            NativeReaderSession(store: fixture.store, provider: provider, target: { identity },
                prepare: { try await fixture.prepare($0, $1) })
        }
        func settled() async {
            for _ in 0..<12 { await Task.yield() }
        }
        let view = AdoptionFixture(), session: NativeReaderSession
        session = make(view)
        session.refresh(); try await waitFor { session.state == .reading }
        try serviceCheck(session.store === view.store, "one shared common store")
        let old = session.store.document!, oldContext = session.context!
        let selected = NativeReaderSelection(ticket: UUID(), blockID: old.blocks[0].id,
            rangeUTF16: 0..<old.blocks[0].displayText.utf16.count, exact: old.blocks[0].displayText)
        let originalEvents = view.events
        view.blocked = true
        session.refresh(); try await waitFor { view.preparationCount == 2 }
        try serviceCheck(session.store.document == old && view.body == old && session.context == oldContext, "slow preparation retains model body and context")
        try serviceCheck(view.events == originalEvents + ["prepare:2:0"] && view.publications == 1, "no premature adoption")
        try session.hold(selected)
        try serviceCheck(session.store.selection == selected, "old content remains selectable during preparation")
        try await rejects("pending preparation cannot authorize mutation") { try session.authorize(oldContext, selection: selected.ticket) }
        view.resume(2); try await waitFor { session.state == .reading }
        try serviceCheck(session.store.document == old && view.body == old && session.store.selection == selected, "selection holds completed preparation")
        view.layout = 1
        session.preparationChanged()
        await settled()
        try serviceCheck(view.preparationCount == 2, "held resize does not start premature preparation")
        // New accepted candidate supersedes the older held candidate, without a
        // second store or a publication until the explicit matching release.
        session.refresh(); try await waitFor { session.state == .reading }
        let newestGeneration = session.store.generation
        try serviceCheck(newestGeneration > old.generation && view.preparationCount == 2, "newest held candidate retained")
        let newerSelection = NativeReaderSelection(ticket: UUID(), fragments: selected.fragments)
        try session.hold(newerSelection)
        session.acknowledge(ticket: selected.ticket)
        try serviceCheck(session.store.selection == newerSelection && view.publications == 1, "late old ticket cannot clear newer user selection")
        // Simulate NA02's actual callback order: shared store releases first,
        // selectionReleased(ticket:) then informs Session. No source result does this.
        session.store.releaseSelection(ticket: newerSelection.ticket)
        session.acknowledge(ticket: newerSelection.ticket)
        try await waitFor { view.preparationCount == 3 }
        try serviceCheck(session.store.document == old && view.body == old && session.context == oldContext, "explicit release still awaits latest object preparation")
        try serviceCheck(view.events.last == "prepare:3:1", "release prepares latest resized key")
        view.resume(3); try await waitFor { session.context?.generation == newestGeneration }
        try serviceCheck(session.store.document == view.body && session.store.document?.generation == newestGeneration, "newest candidate publishes with body once")
        try serviceCheck(view.publications == 2 && view.adopterCalls == 2, "Session never repeats view publication")
        try serviceCheck(Array(view.events.suffix(3)) == ["prepared:3:1", "adopt:3:1", "install:3:1"], "atomic adapter transaction order")
        session.acknowledge(ticket: newerSelection.ticket); await settled()
        try serviceCheck(view.publications == 2 && view.preparationCount == 3, "duplicate release never republishes")

        // Both explicit resize notifications and key drift detected after await
        // must reprepare the retained candidate, without another network request.
        let resize = AdoptionFixture(), resizedSession: NativeReaderSession
        resizedSession = make(resize)
        resizedSession.refresh(); try await waitFor { resizedSession.state == .reading }
        let resizedOld = resize.body, resizedContext = resizedSession.context
        resize.blocked = true
        resizedSession.refresh(); try await waitFor { resize.preparationCount == 2 }
        resize.layout += 1; resizedSession.preparationChanged()
        try await waitFor { resize.preparationCount == 3 }
        resize.resume(2); await settled()
        try serviceCheck(resize.publications == 1 && resizedSession.context == resizedContext && resize.body == resizedOld, "resize rejects obsolete late preparation")
        resize.resume(3); try await waitFor { resize.publications == 2 }
        try serviceCheck(resizedSession.store.document == resize.body && resize.events.last == "install:3:1", "resize adopts latest key")
        resizedSession.refresh(); try await waitFor { resize.preparationCount == 4 }
        resize.layout += 1 // Deliberately omit notification; isCurrent detects this.
        resize.resume(4); try await waitFor { resize.preparationCount == 5 }
        try serviceCheck(resize.publications == 2 && resize.events.last == "prepare:5:2", "key drift reparses newest layout rather than dropping candidate")
        resize.resume(5); try await waitFor { resize.publications == 3 }

        let newer = AdoptionFixture(), newerSession: NativeReaderSession
        newerSession = make(newer)
        newerSession.refresh(); try await waitFor { newerSession.state == .reading }
        newer.blocked = true
        newerSession.refresh(); try await waitFor { newer.preparationCount == 2 }
        newerSession.refresh(); try await waitFor { newer.preparationCount == 3 }
        newer.resume(2); await settled()
        try serviceCheck(newer.publications == 1 && newer.body == newerSession.store.document, "newer refresh revokes older preparation")
        newer.resume(3); try await waitFor { newer.publications == 2 }
        try serviceCheck(newerSession.context?.generation == 3, "newer refresh alone publishes")

        for mode in ["prepare", "adopter", "noop"] {
            let failingView = AdoptionFixture(), failingSession: NativeReaderSession
            failingSession = make(failingView)
            failingSession.refresh(); try await waitFor { failingSession.state == .reading }
            let baseline = failingView.body, baselineContext = failingSession.context
            failingView.failPreparation = mode == "prepare"
            failingView.failAdopter = mode == "adopter"
            failingView.noOpAdopter = mode == "noop"
            failingSession.refresh(); try await waitFor { failingSession.state == .offline }
            try serviceCheck(failingView.body == baseline && failingSession.store.document == baseline && failingSession.context == baselineContext,
                        "\(mode) failure preserves previous published model/body/context")
            try serviceCheck(failingSession.isReadOnly && failingView.publications == 1, "\(mode) cannot fabricate readiness")
            try await rejects("\(mode) disables mutations") { try failingSession.authorize(baselineContext!) }
            failingView.failPreparation = false; failingView.failAdopter = false; failingView.noOpAdopter = false
            failingSession.preparationChanged(); try await waitFor { failingSession.state == .reading }
            try serviceCheck(failingView.preparationCount == 3 && failingView.publications == 2, "\(mode) retry retains valid newest candidate")
            failingSession.event(.dispose)
        }

        for event in ["cancel", "sleep", "offline", "dispose"] {
            let interrupted = AdoptionFixture(), interruptedSession: NativeReaderSession
            interruptedSession = make(interrupted)
            interruptedSession.refresh(); try await waitFor { interruptedSession.state == .reading }
            let baseline = interrupted.body, baselineContext = interruptedSession.context
            interrupted.blocked = true
            interruptedSession.refresh(); try await waitFor { interrupted.preparationCount == 2 }
            switch event {
            case "cancel": interruptedSession.cancel()
            case "sleep": interruptedSession.event(.sleep)
            case "offline": interruptedSession.event(.network(false))
            default: interruptedSession.event(.dispose)
            }
            interrupted.resume(2); await settled()
            try serviceCheck(interrupted.body == baseline && interruptedSession.store.document == baseline && interruptedSession.context == baselineContext,
                        "\(event) rejects noncooperative late prepare without replacing old body")
            try serviceCheck(interrupted.publications == 1 && interruptedSession.isReadOnly, "\(event) cannot authorize stale mutation")
            interruptedSession.event(.dispose)
        }

        let viewCancelled = AdoptionFixture(), viewCancelledSession: NativeReaderSession
        viewCancelledSession = make(viewCancelled)
        viewCancelledSession.refresh(); try await waitFor { viewCancelledSession.state == .reading }
        let cancelledBody = viewCancelled.body, cancelledContext = viewCancelledSession.context
        viewCancelled.blocked = true
        viewCancelledSession.refresh(); try await waitFor { viewCancelled.preparationCount == 2 }
        viewCancelled.store.cancel() // NA02 cancel revokes this same shared generation.
        viewCancelled.resume(2); try await waitFor { viewCancelledSession.state == .offline }
        try serviceCheck(viewCancelled.body == cancelledBody && viewCancelledSession.context == cancelledContext && viewCancelled.publications == 1,
                    "common-store cancellation alone invalidates obsolete preparation")
        try await rejects("common-store cancellation cannot authorize old operations") { try viewCancelledSession.authorize(cancelledContext!) }
        viewCancelledSession.event(.dispose)

        // Recovery shares exactly the same preparation/atomic adopter and can
        // never turn a prepared offline document into source mutation authority.
        let recovered = AdoptionFixture(), recoveredSession: NativeReaderSession
        recoveredSession = make(recovered); recovered.blocked = true
        let recovering = Task { try await recoveredSession.restore(snapshot, matching: identity) }
        try await waitFor { recovered.preparationCount == 1 }
        try serviceCheck(recovered.body == nil && recoveredSession.store.document == nil && recoveredSession.context == nil, "offline restore cannot publish unprepared objects")
        try serviceCheck(recoveredSession.isReadOnly, "recovery preparation is read-only")
        recovered.resume(1); try await recovering.value
        try serviceCheck(recovered.publications == 1 && recoveredSession.store.document == recovered.body && recoveredSession.state == .offline, "prepared offline restore publishes atomically")
        try await rejects("prepared recovery still cannot mutate") { try recoveredSession.authorize(recoveredSession.context!) }
        let recoveredOld = recovered.body, recoveredContext = recoveredSession.context
        try await recoveredSession.restore(snapshot, matching: identity) // Held by recovered selection.
        try serviceCheck(recovered.preparationCount == 1 && recovered.body == recoveredOld && recoveredSession.context == recoveredContext, "held recovery retains old body")
        let recoveredTicket = recoveredSession.store.selection!.ticket
        recoveredSession.acknowledge(ticket: recoveredTicket)
        try await waitFor { recovered.preparationCount == 2 }
        recovered.resume(2); try await waitFor { recovered.publications == 2 }
        try serviceCheck(recoveredSession.isReadOnly && recoveredSession.state == .offline, "released recovery stays read-only")
        recoveredSession.event(.dispose)

        let cancelledRecovery = AdoptionFixture(), cancelledRecoverySession: NativeReaderSession
        cancelledRecoverySession = make(cancelledRecovery); cancelledRecovery.blocked = true
        let recoveryTask = Task { try await cancelledRecoverySession.restore(snapshot, matching: identity) }
        try await waitFor { cancelledRecovery.preparationCount == 1 }
        cancelledRecoverySession.event(.sleep); cancelledRecovery.resume(1)
        try await rejects("sleep revokes pending recovery preparation") { try await recoveryTask.value }
        try serviceCheck(cancelledRecoverySession.state == .sleeping && cancelledRecovery.body == nil && cancelledRecoverySession.context == nil, "late recovery cannot wake or publish")

        let externallyCancelled = AdoptionFixture(), externallyCancelledSession: NativeReaderSession
        externallyCancelledSession = make(externallyCancelled); externallyCancelled.blocked = true
        let externalTask = Task { try await externallyCancelledSession.restore(snapshot, matching: identity) }
        try await waitFor { externallyCancelled.preparationCount == 1 }
        externalTask.cancel(); externallyCancelled.resume(1)
        try await rejects("caller cancellation after awaited recovery prepare") { try await externalTask.value }
        try serviceCheck(externallyCancelledSession.store.document == nil && externallyCancelledSession.context == nil &&
                    externallyCancelled.publications == 0 && externallyCancelledSession.isReadOnly, "cancelled recovery cannot publish or enable mutation")
        externallyCancelledSession.event(.dispose)

        let wrongStore = NativeReaderDocumentStore()
        let mismatched = NativeReaderSession(store: NativeReaderDocumentStore(), provider: provider, target: { identity },
            prepare: { candidate, request in
                _ = try wrongStore.beginRequest()
                return .init(isCurrent: { true }, adopt: { try wrongStore.adopt(candidate, for: request) })
            })
        mismatched.refresh(); try await waitFor { mismatched.state == .offline }
        try serviceCheck(mismatched.store.document == nil && wrongStore.document == nil && mismatched.context == nil,
                    "different viewID/store cannot publish through an adopter")
        mismatched.event(.dispose)

        // Verify the post-await check at the target boundary too; cancelling a
        // resolver must not subsequently invoke the provider or preparation.
        let targetGate = AdoptionFixture(), targetCalls = Counter()
        targetGate.blocked = true
        let targetSession = NativeReaderSession(store: targetGate.store,
            provider: Provider(load: { context in _ = await targetCalls.increment(); return rebased(document, context: context) }),
            target: { _ = try await targetGate.prepare(document, NativeReaderRequestContext(requestID: UUID(), viewID: targetGate.store.viewID,
                        generation: targetGate.store.generation, target: identity)); return identity })
        targetSession.refresh(); try await waitFor { targetGate.preparationCount == 1 }
        targetSession.cancel(); targetGate.resume(1); await settled()
        try serviceCheck(await targetCalls.value() == 0 && targetSession.store.document == nil, "cancel after awaited target cannot invoke provider")

        // Wrong candidates are rejected before any preparation can publish.
        let invalid = AdoptionFixture()
        let invalidSession = NativeReaderSession(store: invalid.store,
            provider: Provider(load: { context in rebased(document, context: NativeReaderRequestContext(requestID: context.requestID,
                viewID: context.viewID, generation: context.generation + 1, target: identity)) }),
            target: { identity }, prepare: { try await invalid.prepare($0, $1) })
        invalidSession.refresh(); try await waitFor { invalidSession.state == .offline }
        try serviceCheck(invalid.preparationCount == 0 && invalidSession.context == nil, "wrong generation never reaches preparer")

        session.event(.dispose); resizedSession.event(.dispose); newerSession.event(.dispose)
        cancelledRecoverySession.event(.dispose); targetSession.event(.dispose); invalidSession.event(.dispose)
        adoptionAssertions = assertions - before
    }

    @MainActor private static func run() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        try serviceCheck(app.activationPolicy() == .prohibited, "headless activation")
        let args = CommandLine.arguments
        let raw = try Data(contentsOf: URL(fileURLWithPath: args[1]))
        let attachment = try NativeReaderAttachment(data: raw)
        let shared = try NativeReaderAttachment(data: Data(contentsOf: URL(fileURLWithPath: args[2])))
        let identity = NativeDocumentIdentity(documentID: attachment.documentID, serviceID: attachment.serviceID, revision: args[3], scope: .service)
        let context = NativeReaderRequestContext(requestID: UUID(), viewID: UUID(), generation: 1, target: identity)
        let network = NativeReaderNetwork.urlSession()
        let transport = NativeReaderTransport(attachment: attachment, network: network)
        let document = try await transport.document(for: context)
        try serviceCheck(document.identity == identity && document.blocks.count == 4, "accepted full real tree")
        try serviceCheck(document.blocks[0].canonicalText == "First paragraph keeps its own question.", "independent literal oracle")
        let prefixed = NativeReaderTransport(attachment: shared, network: network)
        let same = try await prefixed.document(for: context)
        try serviceCheck(document == same, "registered prefix same exact tree")
        let argsCounter = Counter()
        let resolver = NativeReaderManagedResolver(attach: { argv in
            _ = await argsCounter.increment()
            guard argv == ["--attach", "--root", "/isolated/project", "--entry", "main.typ", "--reader-service", "exact"] else { throw TestFailure.assertion("manager argv") }
            return raw
        }, network: network)
        let resolved = try await resolver.resolve(root: "/isolated/project", entry: "main.typ", readerID: "exact")
        try serviceCheck(resolved.1 == identity, "manager observed incarnation/revision")
        try serviceCheck(await argsCounter.value() == 1, "manager attach once")
        let managed = NativeReaderManagedClient(resolver: resolver, root: "/isolated/project", entry: "main.typ", readerID: "exact")
        let managedIdentity = try await managed.target()
        try serviceCheck(managedIdentity == identity, "managed profile identity")
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
        try serviceCheck(initialTarget == sameTarget && restartedTarget.serviceID != initialTarget.serviceID, "injected managed restart binds new incarnation")
        let registrations = await trace.snapshot()
        try serviceCheck(registrations.count == 4 && registrations.filter({ $0.contains("--editor-server") }).count == 2, "one editor registration per incarnation")
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
        try serviceCheck(locate.status == .verified && locate.destinationAnchor != nil, "real guarded locate")
        let math = document.blocks[2]
        let mathSelection = NativeReaderSelection(ticket: UUID(), blockID: math.id, rangeUTF16: 0..<math.displayText.utf16.count, exact: math.displayText)
        try await actions.updateSelection(mathSelection, context: context)
        let excerpt = try await actions.perform(NativeReaderSourceRequest(context: context, selection: mathSelection, action: .excerpt, receiptID: UUID()))
        try serviceCheck(excerpt.status == .verified && excerpt.verifiedText == "$alpha + beta$", "actual source-mapped excerpt")
        let highlight = try await actions.perform(NativeReaderSourceRequest(context: context, selection: mathSelection, action: .highlight, receiptID: UUID()))
        try serviceCheck(highlight.status == .rejected, "missing editor attachment cannot write")
        let receipt = try await actions.receipt(for: NativeReaderSourceRequest(context: context, selection: mathSelection, action: .highlight, receiptID: UUID()))
        try serviceCheck(receipt.status == .uncertain, "missing receipt honest unknown")
        try await actions.updateSelection(selection, context: context)
        let opened = try await actions.perform(.open(selection), context: context)
        try serviceCheck(opened.messages.isEmpty, "open no inference")
        let draft = try await actions.perform(.draft(conversation: opened.conversationID, version: opened.version, text: "Question"), context: context)
        try serviceCheck(draft.version > opened.version && draft.messages.isEmpty, "draft no inference")
        let account = try await actions.account(context: context)
        try serviceCheck(account.models == ["fixture-model"], "existing model catalog")
        let message = UUID()
        let sent = try await actions.perform(.send(conversation: draft.conversationID, version: draft.version, message: message, question: "Question", model: "fixture-model"), context: context)
        try serviceCheck(sent.messages.contains(where: { $0.id == message }), "explicit send stable message")
        let duplicate = try await actions.perform(.send(conversation: draft.conversationID, version: sent.version, message: message, question: "Question", model: "fixture-model"), context: context)
        try serviceCheck(duplicate.messages.filter({ $0.id == message }).count == 1, "server UUID dedup")
        var observed = 0
        for try await state in actions.observe(conversation: opened.conversationID, context: context) {
            observed += 1
            try serviceCheck(state.version >= sent.version && state.sequence >= 0, "bounded real SSE monotonic")
        }
        try serviceCheck(observed > 0, "SSE delivered")
        try await actions.updateSelection(mathSelection, context: context)
        try await rejects("selection changed blocks send") {
            _ = try await actions.perform(.send(conversation: opened.conversationID, version: duplicate.version, message: UUID(), question: "stale", model: "fixture-model"), context: context)
        }

        let oversized = NativeReaderSelection(ticket: UUID(), fragments: Array(repeating: mathSelection.fragments[0], count: 33))
        try await rejects("F4 remote 33-fragment selection still rejects") { try await actions.updateSelection(oversized, context: context) }
        try await rejects("F4 rejected oversized selection cannot leave the old ticket actionable") { _ = try await actions.perform(.open(mathSelection), context: context) }
        try await actions.updateSelection(mathSelection, context: context)

        // Dispatch succeeds at the real owner, then the injected link loses its acknowledgment.
        let dropCount = Counter()
        let lostNetwork = NativeReaderNetwork(send: { request, limit in
            let response = try await network.send(request, limit)
            if request.url?.path.hasSuffix("native-chat") == true,
               let body = request.httpBody,
               (try JSONSerialization.jsonObject(with: body) as? [String: Any])?["operation"] as? String == "send" {
                if await dropCount.increment() == 1 { throw URLError(.networkConnectionLost) }
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
        try serviceCheck(history.contains(where: { $0.state.messages.contains(where: { $0.id == lostID }) }), "lost ack authoritative history")
        try serviceCheck(await dropCount.value() == 1, "uncertain send never replayed")
        let recovered = history.first { $0.state.conversationID == lostOpen.conversationID }!
        let nextMessage = UUID()
        let next = try await lostActions.perform(.send(conversation: recovered.state.conversationID,
            version: recovered.state.version, message: nextMessage, question: "new after confirmed lost Send", model: "fixture-model"), context: context)
        try serviceCheck(next.messages.contains { $0.id == nextMessage && $0.markdown == "new after confirmed lost Send" }, "F5 confirmed history permits a new UUID/question")
        try serviceCheck(await dropCount.value() == 2, "F5 only explicit second Send dispatched")
        // Recovery persists the original pending Send independently of the newer composer.
        var assetBytes: [String: Data] = [:]
        for asset in document.assets { assetBytes[asset.id] = try await transport.asset(asset, context: context) }
        let pendingRecovery = NativeReaderRecoveryStore(root: URL(fileURLWithPath: args[4] + "-pending-ui"))
        let savedPending = NativeReaderRecoveredDraft(conversationID: recovered.state.conversationID,
            version: recovered.state.version, text: "new private draft after lost Send", pendingMessageID: lostID,
            model: "fixture-model", pendingQuestion: "lost", pendingModel: "fixture-model")
        try await pendingRecovery.save(.init(document: document, assets: assetBytes, restoration: .initial, drafts: [savedPending]))
        let restoredPending = try await pendingRecovery.load(identity: identity).drafts[0]
        try serviceCheck(restoredPending.pendingQuestion == "lost" && restoredPending.pendingModel == "fixture-model" && restoredPending.text == savedPending.text,
            "F5-UI atomic disk recovery keeps pending M distinct from newer draft N")
        var oldDraft = try JSONSerialization.jsonObject(with: JSONEncoder().encode(savedPending)) as! [String: Any]
        oldDraft.removeValue(forKey: "pendingQuestion"); oldDraft.removeValue(forKey: "pendingModel")
        let legacy = try JSONDecoder().decode(NativeReaderRecoveredDraft.self, from: JSONSerialization.data(withJSONObject: oldDraft))
        try serviceCheck(legacy.pendingQuestion == nil && legacy.pendingModel == nil && legacy.pendingMessageID == lostID, "F5-UI old schema optional defaults")
        var oversizedPending = savedPending; oversizedPending.pendingQuestion = String(repeating: "x", count: 8001)
        try await rejects("F5-UI pending recovery preserves bounded composer limit") {
            try await pendingRecovery.save(.init(document: document, assets: assetBytes, restoration: .initial, drafts: [oversizedPending]))
        }
        let recoveredView = NativeReaderChatView(actions: lostActions, context: context, authorize: {})
        recoveredView.present(recovered, recovered: restoredPending)
        var persistedPending: NativeReaderRecoveredDraft?
        recoveredView.persistDraft = { persistedPending = $0 }
        recoveredView.presentAccount(.init(signedIn: true, planEnabled: true, homepage: nil, models: ["fixture-model"]))
        recoveredView.textDidChange(Notification(name: NSText.didChangeNotification))
        try serviceCheck(persistedPending?.pendingQuestion == "lost" && persistedPending?.text == savedPending.text,
            "F5-UI edits persist original pending question, not current draft")
        let beforeRefresh = await dropCount.value()
        try await refreshConversation(recoveredView)
        try serviceCheck(recoveredView.composer.string == "new private draft after lost Send" && recoveredView.sendButton.isEnabled,
            "F5 acknowledged old message preserves newer draft and permits new UUID")
        let callsBeforeUI = await dropCount.value()
        try serviceCheck(callsBeforeUI == beforeRefresh && persistedPending?.pendingMessageID == nil, "F5-UI button history is zero inference and clears only confirmed pending")
        recoveredView.sendButton.performClick(nil)
        for _ in 0..<200 {
            if await lostActions.conversation(recovered.state.conversationID)?.state.messages.contains(where: { $0.markdown == "new private draft after lost Send" }) == true { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        try serviceCheck(await dropCount.value() == callsBeforeUI + 1, "F5 UI sends only on explicit action")
        try serviceCheck(await lostActions.conversation(recovered.state.conversationID)?.state.messages.contains(where: { $0.markdown == "new private draft after lost Send" }) == true,
            "F5 UI/actor agree on acknowledged history")
        recoveredView.dispose()

        for mutation in ["missing", "mismatch", "assistant-role", "conversation-missing"] {
            let dispatches = Counter()
            let pendingID = UUID()
            let faultNetwork = NativeReaderNetwork(send: { request, limit in
                let response = try await network.send(request, limit)
                guard request.url?.path.hasSuffix("native-chat") == true, let data = request.httpBody,
                      let body = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return response }
                if body["operation"] as? String == "send", await dispatches.increment() == 1 { throw URLError(.networkConnectionLost) }
                if body["operation"] as? String == "list" {
                    var envelope = try JSONSerialization.jsonObject(with: response.data) as! [String: Any]
                    var conversations = envelope["conversations"] as! [[String: Any]]
                    for index in conversations.indices {
                        var thread = conversations[index]["thread"] as! [[String: Any]]
                        if mutation == "missing" { thread.removeAll { $0["id"] as? String == pendingID.uuidString.lowercased() } }
                        else {
                            for i in thread.indices where thread[i]["id"] as? String == pendingID.uuidString.lowercased() {
                                if mutation == "mismatch" { thread[i]["text"] = "different persisted content" }
                                else { thread[i]["role"] = "assistant" }
                            }
                        }
                        conversations[index]["thread"] = thread
                    }
                    if mutation == "conversation-missing" {
                        // Omit every record to exercise an absent authoritative thread.
                        conversations = []
                    }
                    envelope["conversations"] = conversations
                    return NativeReaderHTTPResponse(status: response.status, headers: response.headers, data: try JSONSerialization.data(withJSONObject: envelope))
                }
                return response
            }, stream: network.stream)
            let faultTransport = NativeReaderTransport(attachment: attachment, network: faultNetwork)
            _ = try await faultTransport.document(for: context)
            let faultActions = NativeReaderActions(transport: faultTransport)
            try await faultActions.updateSelection(mathSelection, context: context)
            let opened = try await faultActions.perform(.open(mathSelection), context: context)
            try await rejects("F5 unconfirmed mutation lost ack") {
                _ = try await faultActions.perform(.send(conversation: opened.conversationID, version: opened.version,
                    message: pendingID, question: "uncertain original", model: "fixture-model"), context: context)
            }
            let records = try await faultActions.history(context: context)
            let cached = await faultActions.conversation(opened.conversationID)
            let current = records.first { $0.state.conversationID == opened.conversationID } ?? cached!
            try await rejects("F5 missing/mismatched history forbids a new UUID") {
                _ = try await faultActions.perform(.send(conversation: current.state.conversationID, version: current.state.version,
                    message: UUID(), question: "new forbidden question", model: "fixture-model"), context: context)
            }
            try serviceCheck(await dispatches.value() == 1, "F5 history and refused new UUID never dispatch Send")
            let faultView = NativeReaderChatView(actions: faultActions, context: context, authorize: {})
            faultView.present(current, recovered: .init(conversationID: current.state.conversationID, version: current.state.version,
                text: "uncertain original", pendingMessageID: pendingID, model: "fixture-model"))
            faultView.presentAccount(.init(signedIn: true, planEnabled: true, homepage: nil, models: ["fixture-model"]))
            try await refreshConversation(faultView)
            if mutation == "conversation-missing" {
                try serviceCheck(!faultView.sendButton.isEnabled && faultView.notice.stringValue.contains("retained") && faultView.composer.string == "uncertain original",
                    "F5-UI missing conversation is not false completion")
                try serviceCheck(await dispatches.value() == 1, "F5-UI missing thread never dispatches inference")
                faultView.dispose(); continue
            }
            try serviceCheck(faultView.sendButton.isEnabled, "F5 exact explicit retry remains available after history")
            faultView.composer.string = "new unrelated draft"
            faultView.textDidChange(Notification(name: NSText.didChangeNotification))
            try serviceCheck(!faultView.sendButton.isEnabled && faultView.composer.string == "new unrelated draft", "F5 unconfirmed UI protects new draft and rejects changed retry")
            faultView.composer.string = "uncertain original"
            faultView.textDidChange(Notification(name: NSText.didChangeNotification))
            try serviceCheck(faultView.sendButton.isEnabled, "F5-UI returning to original draft enables explicit same UUID retry")
            faultView.sendButton.performClick(nil)
            try await waitFor { faultView.historyButton.isEnabled }
            let retried = await faultActions.conversation(current.state.conversationID)!
            let retryDispatches = await dispatches.value()
            try serviceCheck(retried.state.messages.filter { $0.id == pendingID }.count == 1 && retryDispatches == 2, "F5 only same UUID/question explicit retry succeeds")
            faultView.dispose()
        }



        for boundary in ["context", "dispose", "cancel", "stale-version"] {
            let gate = HistoryGate(), calls = Counter()
            let gatedNetwork = NativeReaderNetwork(send: { request, limit in
                let response = try await network.send(request, limit)
                if let data = request.httpBody, let body = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if body["operation"] as? String == "list" { await gate.hold() }
                    if body["operation"] as? String == "send" { _ = await calls.increment() }
                }
                return response
            }, stream: network.stream)
            let gatedTransport = NativeReaderTransport(attachment: attachment, network: gatedNetwork)
            _ = try await gatedTransport.document(for: context)
            let gatedActions = NativeReaderActions(transport: gatedTransport)
            try await gatedActions.updateSelection(mathSelection, context: context)
            _ = try await gatedActions.perform(.open(mathSelection), context: context)
            var currentAuthority = true
            let lateView = NativeReaderChatView(actions: gatedActions, context: context, authorize: {
                guard currentAuthority else { throw NativeReaderContractError.staleGeneration }
            })
            let lateConversation = NativeReaderConversation(state: recovered.state, draft: recovered.draft,
                status: boundary == "cancel" ? "streaming" : recovered.status, attached: recovered.attached)
            lateView.present(lateConversation, recovered: savedPending)
            lateView.presentAccount(.init(signedIn: true, planEnabled: true, homepage: nil, models: ["fixture-model"]))
            var latePersist: NativeReaderRecoveredDraft?
            lateView.persistDraft = { latePersist = $0 }
            lateView.historyButton.performClick(nil)
            for _ in 0..<400 {
                if await gate.waiting() { break }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            try serviceCheck(await gate.waiting() && !lateView.historyButton.isEnabled && !lateView.sendButton.isEnabled, "F5-UI history busy guard")
            if boundary == "context" { currentAuthority = false }
            if boundary == "dispose" { lateView.dispose() }
            if boundary == "cancel" { lateView.cancelExplicitly() }
            if boundary == "stale-version" {
                let newer = NativeReaderChatState(context: context, conversationID: recovered.state.conversationID,
                    version: 10000, sequence: 10000, messages: recovered.state.messages)
                lateView.present(.init(state: newer, draft: "must not overwrite", status: recovered.status, attached: true))
            }
            await gate.release()
            try await Task.sleep(nanoseconds: 100_000_000)
            let pendingPreserved = latePersist == nil || (boundary == "cancel" &&
                latePersist?.pendingMessageID == savedPending.pendingMessageID && latePersist?.pendingQuestion == savedPending.pendingQuestion)
            try serviceCheck(pendingPreserved && lateView.composer.string == savedPending.text && !lateView.sendButton.isEnabled,
                "F5-UI late history cannot clear pending/revive stale presentation: " + boundary)
            try serviceCheck(await calls.value() == 0, "F5-UI history/cancel/late response never sends: " + boundary)
            lateView.dispose()
        }

        // Parser boundaries include split UTF8, malformed UTF8, truncation and stale.
        var parser = NativeReaderSSEParser()
        let event = Data("data: {\"text\":\"한😀\"}\r\n\r\n".utf8)
        var parsed = [Data]()
        for byte in event { parsed += try parser.feed(Data([byte])) }
        try parser.finish()
        try serviceCheck(parsed.count == 1 && String(data: parsed[0], encoding: .utf8) == "{\"text\":\"한😀\"}", "split UTF8 and CRLF SSE")
        try await rejects("malformed SSE") { var p = NativeReaderSSEParser(); _ = try p.feed(Data([0xff,10])) }
        try await rejects("stale SSE") { var p = NativeReaderSSEParser(); _ = try p.feed(Data("event: stale\ndata: {}\n\n".utf8)) }
        try await rejects("truncated SSE") { var p = NativeReaderSSEParser(); _ = try p.feed(Data("data: {}".utf8)); try p.finish() }
        try await rejects("SSE payload bound") { var p = NativeReaderSSEParser(); _ = try p.feed(Data(repeating: 65, count: 2*1024*1024+4097)) }

        try serviceCheck(!assetBytes.isEmpty, "real revision-bound assets verified")
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
        try serviceCheck(session.context == firstContext, "selection holds publication")
        let newer = NativeReaderSelection(ticket: UUID(), fragments: selection.fragments)
        try session.hold(newer)
        session.acknowledge(ticket: selection.ticket)
        try serviceCheck(session.store.selection?.ticket == newer.ticket, "late ack preserves new selection")
        session.acknowledge(ticket: newer.ticket)
        try await waitFor { session.state == .reading && session.context != firstContext }
        try serviceCheck(session.context != firstContext && session.store.selection == nil, "latest pending publication after release")
        let root = URL(fileURLWithPath: args[4])
        let recovery = NativeReaderRecoveryStore(root: root)
        let restoration = NativeReaderRestoration(blockID: document.blocks[0].id, offset: 0.25, zoom: 1.5,
            selectionTicket: selection.ticket, fragments: selection.fragments.map { .init(blockID: $0.blockID, start: $0.rangeUTF16.lowerBound, end: $0.rangeUTF16.upperBound, exact: $0.exact) })
        let snapshot = NativeReaderRecoverySnapshot(document: document, assets: assetBytes, restoration: restoration,
            drafts: [NativeReaderRecoveredDraft(conversationID: opened.conversationID, version: draft.version, text: "Only composer text", pendingMessageID: nil)])
        let review = NativeReaderLocalReview()
        try review.add(NativeReaderReviewMark(id: UUID(), identity: identity, selection: restoration), document: document)
        try serviceCheck(review.marks.count == 1, "native review local paint")
        review.undo(); try serviceCheck(review.marks.isEmpty, "review undo")
        try review.add(NativeReaderReviewMark(id: UUID(), identity: identity, selection: restoration), document: document)
        review.clear(); try serviceCheck(review.marks.isEmpty, "review clear")
        try await recovery.save(snapshot)
        let loaded = try await recovery.load(identity: identity)
        try serviceCheck(loaded.document == document && loaded.restoration == restoration, "atomic digest-checked snapshot")
        let offline = NativeReaderSession(provider: provider, target: { identity })
        try await offline.restore(loaded, matching: identity)
        try serviceCheck(offline.state == .offline && offline.store.selection?.ticket == selection.ticket, "offline read-only selection restoration")
        try await rejects("offline source/chat refusal") { try offline.authorize(offline.context!) }
        let wrong = NativeDocumentIdentity(documentID: identity.documentID, serviceID: "reader:1:1", revision: identity.revision, scope: .service)
        try await rejects("recovery wrong service") { _ = try await recovery.load(identity: wrong) }
        let file = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).first!
        var bytes = try Data(contentsOf: file); bytes[bytes.count/2] ^= 1; try bytes.write(to: file)
        try await rejects("corrupt recovery digest") { _ = try await recovery.load(identity: identity) }
        try await recovery.save(snapshot)
        try serviceCheck(try await recovery.load(identity: identity).document == document, "atomic replacement after corrupt snapshot")
        let canceledSave = Task { () throws -> Void in
            try Task.checkCancellation()
            try await recovery.save(snapshot)
        }
        canceledSave.cancel()
        try await rejects("canceled snapshot preserves old commit") { try await canceledSave.value }
        try serviceCheck(try await recovery.load(identity: identity).document == document, "old snapshot survives canceled save")
        let linkRoot = root.deletingLastPathComponent().appendingPathComponent("recovery-link")
        try FileManager.default.createSymbolicLink(at: linkRoot, withDestinationURL: root)
        let symlinkStore = NativeReaderRecoveryStore(root: linkRoot)
        try await rejects("symlink recovery root") { _ = try await symlinkStore.load(identity: identity) }
        let failedCounter = Counter()
        let failing = NativeReaderSession(provider: Provider(load: { _ in _ = await failedCounter.increment(); throw URLError(.timedOut) }), target: { identity }, wait: { _ in await Task.yield() })
        failing.refresh(); try await waitFor { failing.state == .offline }
        try await Task.sleep(nanoseconds: 30_000_000)
        try serviceCheck(await failedCounter.value() == 4, "bounded reconnect attempts")
        session.event(.power(constrained: true)); session.event(.sleep)
        try serviceCheck(session.state == .sleeping && session.store.document != nil, "sleep retains accepted")
        let sleepGeneration = session.store.generation
        session.event(.network(false)); session.event(.network(true))
        try serviceCheck(session.state == .sleeping && session.store.generation == sleepGeneration,
                         "network changes during sleep cannot start requests before wake")
        session.event(.dispose); session.refresh(); session.event(.wake)
        try serviceCheck(session.state == .disposed && session.store.document != nil, "dispose rejects callbacks retains accepted")
        failing.event(.dispose); offline.event(.dispose)

        layoutCacheReport = try await layoutCacheRegressions(document, assets: assetBytes, root: root.appendingPathComponent("stage3"))
        try await adoptionRegressions(document, identity, loaded)
        let safe = NativeReaderAnswerPart.attributed("# Heading\n**bold** `<script>`\n<script>alert(1)</script>\n$$\nx^2\n$$")
        try serviceCheck(safe.string.contains("<script>alert(1)</script>"), "HTML remains literal native text")
        try serviceCheck(safe.string.contains("native layout unavailable"), "honest math fallback")
        let view = NativeReaderChatView(actions: actions, context: context, authorize: {})
        if let record = await actions.conversation(opened.conversationID) { view.present(record) }
        view.presentAccount(account)
        try serviceCheck(view.composer.isRichText == false && view.answer.isEditable == false, "native composer/answer")
        try serviceCheck(app.windows.allSatisfy({ !$0.isVisible }) && app.activationPolicy() == .prohibited, "no visible GUI windows or foreground activation")
        var persisted: NativeReaderRecoveredDraft?
        view.persistDraft = { persisted = $0 }
        view.composer.string = "Newer local draft"
        view.textDidChange(Notification(name: NSText.didChangeNotification))
        if let record = await actions.conversation(opened.conversationID) { view.present(record) }
        try serviceCheck(view.composer.string == "Newer local draft" && persisted?.text == "Newer local draft", "late history cannot clear newer local draft")
        view.dispose()
        try serviceCheck(!view.sendButton.isEnabled, "disposed UI cannot send")
        await transport.dispose()
        try await rejects("disposed transport") { _ = try await transport.document(for: context) }
    }
}

extension ServiceTests {
    @MainActor static func rawPipeline(_ args: [String]) async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        try serviceCheck(app.activationPolicy() == .prohibited, "raw headless activation")
        let attachment = try NativeReaderAttachment(data: Data(contentsOf: URL(fileURLWithPath: args[2])))
        let identity = NativeDocumentIdentity(documentID: attachment.documentID, serviceID: attachment.serviceID, revision: args[3], scope: .service)
        let context = NativeReaderRequestContext(requestID: UUID(), viewID: UUID(), generation: 17, target: identity)
        let transport = NativeReaderTransport(attachment: attachment, network: .urlSession())
        let document = try await transport.document(for: context)
        let layouts = document.blocks.flatMap(\.orderedNodes).compactMap(\.imageLayout)
        try serviceCheck(document.requiredCapabilities == ["image-layout-v1", "semantic-tree-v1"] && layouts.count >= 8, "full raw HTTP supplement")
        var assets = [String: Data]()
        for descriptor in document.assets { assets[descriptor.id] = try await transport.asset(descriptor, context: context) }
        let root = URL(fileURLWithPath: args[4])
        let recovery = NativeReaderRecoveryStore(root: root.appendingPathComponent("recovery"))
        let snapshot = NativeReaderRecoverySnapshot(document: document, assets: assets, restoration: .initial, drafts: [])
        try await recovery.save(snapshot)
        let loaded = try await recovery.load(identity: identity)
        try serviceCheck(loaded.document == document && loaded.assets == assets, "raw generic Codable disk roundtrip")
        let session = NativeReaderSession(provider: Provider(load: { document.rebinding(generation: $0.generation) }), target: { identity })
        _ = try session.store.beginRequest()
        _ = try session.store.beginRequest()
        try await session.restore(loaded, matching: identity)
        try serviceCheck(session.context!.generation != document.generation, "raw restore actually rebinds generation")
        try serviceCheck(session.store.document!.blocks == document.blocks && session.store.document!.requiredCapabilities == document.requiredCapabilities, "raw session candidate preserves every supplement")
        try await rejects("offline raw source permission") { try session.authorize(session.context!) }
        // Exercise pending candidate/adoption, not just a standalone DTO copy.
        session.refresh()
        try await waitFor { session.state == .reading }
        try serviceCheck(session.store.document!.blocks == document.blocks, "raw live session candidate preserves metadata")
        let fixtureIdentity = NativeDocumentIdentity(documentID: identity.documentID, serviceID: identity.serviceID, revision: identity.revision, scope: .fixture)
        let fixture = NativeReaderDocument(schemaVersion: document.schemaVersion, identity: fixtureIdentity, generation: document.generation,
            requiredCapabilities: document.requiredCapabilities, blocks: document.blocks, assets: document.assets, diagnostics: document.diagnostics)
        let fixtureURL = root.appendingPathComponent("raw-fixture.json")
        try JSONEncoder().encode(fixture).write(to: fixtureURL)
        let provider = NativeReaderFixtureProvider(url: fixtureURL)
        let fixtureContext = NativeReaderRequestContext(requestID: UUID(), viewID: UUID(), generation: 99, target: fixtureIdentity)
        let copied = try await provider.document(for: fixtureContext)
        try serviceCheck(copied.blocks == fixture.blocks && copied.requiredCapabilities == fixture.requiredCapabilities && copied.generation == 99, "production host fixture copy")
        session.event(.dispose)
        let output: [String: Any] = ["assertions": assertions, "layouts": layouts.count, "assets": assets.count, "transport": "actual raw compiler HTTP", "metadata": "generic Codable recovery + session restore/live candidate + host fixture provider", "skips": 0]
        print(String(decoding: try JSONSerialization.data(withJSONObject: output), as: UTF8.self))
    }
}


private final class LayoutTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var tick = 0
    func next() -> Date {
        lock.lock(); defer { lock.unlock() }; tick += 1
        return Date(timeIntervalSince1970: Double(1_000_000 + tick))
    }
}

extension ServiceTests {
    @MainActor static func layoutCacheRegressions(_ document: NativeReaderDocument, assets: [String: Data], root: URL) async throws -> [String: Any] {
        func snapshot(_ number: Int, width: Double = 640, fontSize: Double = 14, font: String = "system",
                      theme: String = "light", revision: String? = nil) -> NativeReaderLayoutSnapshot {
            let identity = NativeDocumentIdentity(documentID: "layout-document-\(number)", serviceID: document.identity.serviceID,
                revision: revision ?? document.identity.revision, scope: document.identity.scope)
            let copy = NativeReaderDocument(schemaVersion: document.schemaVersion, identity: identity, generation: 1,
                requiredCapabilities: document.requiredCapabilities, blocks: document.blocks, assets: document.assets, diagnostics: document.diagnostics)
            return NativeReaderLayoutSnapshot(ownerID: "profile-\(number)",
                key: NativeReaderLayoutCacheKey(documentID: identity.documentID, revision: identity.revision,
                    width: width, fontSize: fontSize, fontName: font, theme: theme), document: copy,
                restoration: .init(blockID: copy.blocks[0].id, offset: 0.45, zoom: 1, selectionTicket: nil, fragments: []),
                viewedBlockIDs: [copy.blocks[0].id], layouts: [:], assets: [:])
        }
        let a = snapshot(1), b = snapshot(2), c = snapshot(3)
        let environment = AppEnvironment(variables: ["FLOW_DATA_DIR": root.appendingPathComponent("support").path], userHome: root)
        func profile(_ id: String) -> Profile {
            Profile(id: id, name: id, root: root.path, entry: "main.typ", fonts: [], packages: root.path,
                port: 12345, publicURL: "", label: "test.\(id)")
        }
        let profileA = profile("shared-a"), profileB = profile("shared-b")
        let recoveryA = NativeReaderRecoveryStore(root: environment.nativeRecoveryRoot(for: profileA))
        let recoveryB = NativeReaderRecoveryStore(root: environment.nativeRecoveryRoot(for: profileB))
        let defaultA = NativeReaderOfflineStorage(owner: recoveryA).layoutCache!
        let defaultB = NativeReaderOfflineStorage(owner: recoveryB).layoutCache!
        try serviceCheck(recoveryA.root != recoveryB.root && defaultA.root == defaultB.root &&
            defaultA.root == environment.support.appendingPathComponent("native-reader/layout-cache", isDirectory: true),
            "distinct AppEnvironment profiles share the default layout namespace")
        try serviceCheck(defaultA.byteLimit == 64 * 1024 * 1024 && defaultB.byteLimit == 64 * 1024 * 1024,
            "default shared disk cap is 64 MiB")
        func owned(_ snapshot: NativeReaderLayoutSnapshot, _ profile: Profile, offset: Double = 0.45) -> NativeReaderLayoutSnapshot {
            .init(ownerID: [profile.id, profile.root, profile.entry].joined(separator: "\n"), key: snapshot.key,
                document: snapshot.document, restoration: .init(blockID: snapshot.restoration.blockID, offset: offset, zoom: 1, selectionTicket: nil, fragments: []), viewedBlockIDs: snapshot.viewedBlockIDs,
                layouts: snapshot.layouts, assets: snapshot.assets)
        }
        var longProfile = profile("long-path")
        longProfile.root = root.path + "/" + String(repeating: "긴경로/", count: 300)
        let longSnapshot = owned(a, longProfile)
        try serviceCheck(longSnapshot.ownerID.count > 256 && longSnapshot.ownerID.utf8.count <= 8192,
            "long profile fixture satisfies the snapshot owner contract")
        let longCache = NativeReaderLayoutCache(root: root.appendingPathComponent("long-owner"))
        try await longCache.save(longSnapshot)
        let longLatest = try await longCache.latest(ownerID: longSnapshot.ownerID)
        let longLoaded = try await longCache.load(ownerID: longSnapshot.ownerID, key: longSnapshot.key)
        try serviceCheck(longLatest?.ownerID == longSnapshot.ownerID && longLatest?.document == longSnapshot.document &&
            longLoaded?.ownerID == longSnapshot.ownerID && longLoaded?.restoration == longSnapshot.restoration,
            "long profile saves and loads through both cache entry points")
        try await longCache.invalidate(ownerID: longSnapshot.ownerID, key: longSnapshot.key)
        let longMissing = try await longCache.load(ownerID: longSnapshot.ownerID, key: longSnapshot.key)
        let longLatestMissing = try await longCache.latest(ownerID: longSnapshot.ownerID)
        let longBytes = try await longCache.diskBytes()
        try serviceCheck(longMissing == nil && longLatestMissing == nil && longBytes == 0,
            "long profile invalidation removes the cached file")
        for ownerID in ["", String(repeating: "é", count: 4097)] {
            try await rejects("lookup rejects empty or over-budget UTF-8 owner") { _ = try await longCache.load(ownerID: ownerID, key: a.key) }
            try await rejects("invalidation rejects empty or over-budget UTF-8 owner") { try await longCache.invalidate(ownerID: ownerID, key: a.key) }
        }

        // Derive both on-disk names independently of the private cache helpers.
        // Keep the real envelope bytes when recreating the historical filename.
        struct LayoutStorageKey: Encodable { let ownerID: String; let key: NativeReaderLayoutCacheKey }
        let cacheEncoder = JSONEncoder(); cacheEncoder.outputFormatting = [.sortedKeys]
        func cacheFile(_ item: NativeReaderLayoutSnapshot, in directory: URL, legacy: Bool = false) throws -> URL {
            let key = try legacy ? cacheEncoder.encode(item.key) : cacheEncoder.encode(LayoutStorageKey(ownerID: item.ownerID, key: item.key))
            return directory.appendingPathComponent(NativeReaderRecoverySnapshot.digest(key) + ".layout")
        }
        for useLatest in [true, false] {
            let directory = root.appendingPathComponent(useLatest ? "legacy-latest" : "legacy-load")
            let legacyClock = LayoutTestClock()
            let cache = NativeReaderLayoutCache(root: directory, now: { legacyClock.next() })
            let original = owned(a, profileA), other = owned(a, profileB, offset: 0.7)
            let scoped = try cacheFile(original, in: directory), legacy = try cacheFile(original, in: directory, legacy: true)
            let otherFile = try cacheFile(other, in: directory)
            try await cache.save(other); try await cache.save(original)
            let originalBytes = try Data(contentsOf: scoped), otherBytes = try Data(contentsOf: otherFile)
            try FileManager.default.moveItem(at: scoped, to: legacy)
            let wrongOwner = "absent-profile"
            let wrongLoad = try await cache.load(ownerID: wrongOwner, key: original.key)
            let wrongLatest = try await cache.latest(ownerID: wrongOwner)
            try await cache.invalidate(ownerID: wrongOwner, key: original.key)
            try serviceCheck(wrongLoad == nil && wrongLatest == nil && (try Data(contentsOf: legacy)) == originalBytes,
                "legacy lookup and invalidation preserve another owner's file")
            let recovered: NativeReaderLayoutSnapshot?
            if useLatest { recovered = try await cache.latest(ownerID: original.ownerID) }
            else { recovered = try await cache.load(ownerID: original.ownerID, key: original.key) }
            try serviceCheck(try recovered.map { try cacheEncoder.encode($0) } == cacheEncoder.encode(original),
                "legacy recovery preserves the entire validated snapshot")
            try serviceCheck(!FileManager.default.fileExists(atPath: legacy.path) &&
                (try Data(contentsOf: scoped)) == originalBytes && (try Data(contentsOf: otherFile)) == otherBytes,
                "both entry points rename legacy bytes to the scoped file and preserve the other profile")

            // Force latest to encounter the valid legacy before the corrupt destination.
            try originalBytes.write(to: legacy)
            var corruptEnvelope = try JSONSerialization.jsonObject(with: originalBytes) as! [String: Any]
            corruptEnvelope["sha256"] = String(repeating: "0", count: 64)
            try JSONSerialization.data(withJSONObject: corruptEnvelope).write(to: scoped)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2_000_000_000)], ofItemAtPath: legacy.path)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000_000_000)], ofItemAtPath: scoped.path)
            let repaired: NativeReaderLayoutSnapshot?
            if useLatest { repaired = try await cache.latest(ownerID: original.ownerID) }
            else { repaired = try await cache.load(ownerID: original.ownerID, key: original.key) }
            try serviceCheck(try repaired.map { try cacheEncoder.encode($0) } == cacheEncoder.encode(original),
                "\(useLatest ? "latest" : "load") recovers the validated legacy snapshot despite a corrupt scoped destination")
            try serviceCheck(!FileManager.default.fileExists(atPath: legacy.path) &&
                (try Data(contentsOf: scoped)) == originalBytes && (try Data(contentsOf: otherFile)) == otherBytes,
                "\(useLatest ? "latest" : "load") replaces corrupt scoped bytes by migrating legacy and preserves the other profile")

            // A duplicate with a later mtime must still defer to the scoped data.
            let newer = owned(a, profileA, offset: 0.85)
            try await cache.save(newer)
            let newerBytes = try Data(contentsOf: scoped)
            try originalBytes.write(to: legacy)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2_000_000_000)], ofItemAtPath: legacy.path)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000_000_000)], ofItemAtPath: scoped.path)
            let scopedLoad = try await cache.load(ownerID: original.ownerID, key: original.key)
            // load touches scoped mtime; explicitly keep the legacy first in latest's order.
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000_000_000)], ofItemAtPath: scoped.path)
            let preferred = try await cache.latest(ownerID: original.ownerID)
            try serviceCheck(scopedLoad?.restoration.offset == 0.85 && preferred?.restoration.offset == 0.85 &&
                !FileManager.default.fileExists(atPath: legacy.path) && (try Data(contentsOf: scoped)) == newerBytes &&
                (try Data(contentsOf: otherFile)) == otherBytes,
                "newer legacy duplicate cannot overwrite scoped data or another owner's file")

            try originalBytes.write(to: legacy)
            try await cache.invalidate(ownerID: original.ownerID, key: original.key)
            try serviceCheck(!FileManager.default.fileExists(atPath: scoped.path) && !FileManager.default.fileExists(atPath: legacy.path) &&
                (try Data(contentsOf: otherFile)) == otherBytes, "invalidation removes matching scoped and legacy files only")
            // Also preserve a different owner's key-only file with the same key.
            try FileManager.default.moveItem(at: otherFile, to: legacy)
            try await cache.invalidate(ownerID: original.ownerID, key: original.key)
            try serviceCheck(try Data(contentsOf: legacy) == otherBytes, "invalidation leaves a different owner's legacy file intact")
            try await cache.invalidate(ownerID: other.ownerID, key: other.key)
            try serviceCheck(try await cache.diskBytes() == 0, "legacy-only invalidation removes the matching owner")
        }
        // Identical layout keys in two profiles must remain independent.
        // Superseding A must not delete B as an old version of A's document.
        let sharedA = owned(a, profileA), sharedB = owned(a, profileB, offset: 0.7), sharedC = owned(c, profileA)
        let sharedProbe = NativeReaderLayoutCache(root: root.appendingPathComponent("shared-probe"))
        var sharedSizes = [Int](), sharedPrevious = 0
        for item in [sharedA, sharedB, sharedC] {
            try await sharedProbe.save(item)
            let total = try await sharedProbe.diskBytes(); sharedSizes.append(total - sharedPrevious); sharedPrevious = total
        }
        let sharedCap = sharedSizes.reduce(0, +) - sharedSizes.min()!
        let sharedClock = LayoutTestClock()
        let cacheA = NativeReaderLayoutCache(root: defaultA.root, byteLimit: sharedCap, now: { sharedClock.next() })
        let cacheB = NativeReaderLayoutCache(root: defaultB.root, byteLimit: sharedCap, now: { sharedClock.next() })
        try await cacheA.save(sharedA); try await cacheB.save(sharedB)
        let loadedA = try await cacheA.load(ownerID: sharedA.ownerID, key: sharedA.key), loadedB = try await cacheB.load(ownerID: sharedB.ownerID, key: sharedB.key)
        try serviceCheck(loadedA?.ownerID == sharedA.ownerID && loadedA?.restoration.offset == sharedA.restoration.offset &&
            loadedB?.ownerID == sharedB.ownerID && loadedB?.restoration.offset == sharedB.restoration.offset, "same document profiles coexist")
        try serviceCheck(sharedA.key == sharedB.key && sharedA.ownerID != sharedB.ownerID, "identical keys have distinct owners")
        let latestA = try await cacheA.latest(ownerID: sharedA.ownerID), latestB = try await cacheB.latest(ownerID: sharedB.ownerID)
        try serviceCheck(latestA?.ownerID == sharedA.ownerID && latestA?.restoration.offset == sharedA.restoration.offset &&
            latestB?.ownerID == sharedB.ownerID && latestB?.restoration.offset == sharedB.restoration.offset, "latest preserves both profiles")
        try await cacheA.invalidate(ownerID: sharedA.ownerID, key: sharedA.key)
        let invalidatedA = try await cacheA.load(ownerID: sharedA.ownerID, key: sharedA.key)
        let preservedB = try await cacheB.load(ownerID: sharedB.ownerID, key: sharedB.key)
        try serviceCheck(invalidatedA == nil && preservedB?.ownerID == sharedB.ownerID, "invalidation preserves other profile")
        try await cacheA.save(sharedA)
        _ = try await cacheA.load(ownerID: sharedA.ownerID, key: sharedA.key) // A is the newest read across both actors.
        try await cacheA.save(sharedC)
        try serviceCheck(try await cacheB.load(ownerID: sharedB.ownerID, key: sharedB.key) == nil, "shared LRU evicts B across profile actors")
        let sharedRetainedA = try await cacheA.load(ownerID: sharedA.ownerID, key: sharedA.key), sharedRetainedC = try await cacheB.load(ownerID: sharedC.ownerID, key: sharedC.key)
        let sharedBytes = try await cacheA.diskBytes()
        try serviceCheck(sharedRetainedA != nil && sharedRetainedC != nil && sharedBytes <= sharedCap,
            "combined profile bytes obey one shared cap")

        // The original cached restore must stay pending while a layout retry
        // owns preparation, and accept a retry that adopted before it resumed.
        for adoptedFirst in [false, true] {
            let fixture = AdoptionFixture(); fixture.blocked = true
            let session = NativeReaderSession(store: fixture.store,
                provider: Provider { _ in throw TestFailure.assertion("cache restore called live provider") },
                target: { throw TestFailure.assertion("cache restore called live target") })
            var completed = false
            let restore = Task { @MainActor in
                defer { completed = true }
                try await session.restoreLayoutWindow(a, prepare: fixture.prepare)
            }
            try await waitFor { fixture.preparationCount == 1 }
            fixture.layout += 1; session.preparationChanged()
            try await waitFor { fixture.preparationCount == 2 }
            if adoptedFirst {
                fixture.resume(2)
                try await waitFor { fixture.publications == 1 }
                try serviceCheck(!completed, "original restore still awaits its own preparation")
                fixture.resume(1)
            } else {
                fixture.resume(1)
                try await waitFor { fixture.events.contains("prepared:1:0") }
                for _ in 0..<10 { await Task.yield() }
                try serviceCheck(!completed && fixture.publications == 0,
                    "cached restore awaits the retry rather than returning or throwing early")
                fixture.resume(2)
            }
            try await restore.value
            try serviceCheck(session.isCachedCopy && session.isReadOnly && session.state == .offline &&
                fixture.publications == 1 && fixture.events.contains("install:2:1"),
                "only current cached preparation adopts before restore completion")
            session.event(.dispose)
        }
        let probe = NativeReaderLayoutCache(root: root.appendingPathComponent("probe"))
        var previous = 0, sizes = [Int]()
        for item in [a, b, c] {
            try await probe.save(item)
            let total = try await probe.diskBytes(); sizes.append(total - previous); previous = total
        }
        let cap = sizes.reduce(0, +) - sizes.min()!
        let clock = LayoutTestClock(), directory = root.appendingPathComponent("bounded/layout-cache")
        let disk = NativeReaderLayoutCache(root: directory, byteLimit: cap, now: { clock.next() })
        try await disk.save(a); try await disk.save(b)
        try serviceCheck(try await disk.load(ownerID: a.ownerID, key: a.key) != nil, "read touches LRU")
        try await disk.save(c)
        try serviceCheck(try await disk.diskBytes() <= cap, "strict total disk byte cap")
        try serviceCheck(try await disk.load(ownerID: b.ownerID, key: b.key) == nil, "least recently read document evicted")
        let retainedA = try await disk.load(ownerID: a.ownerID, key: a.key), retainedC = try await disk.load(ownerID: c.ownerID, key: c.key)
        try serviceCheck(retainedA != nil && retainedC != nil, "recent documents retained")
        let permissions = try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber
        try serviceCheck(permissions?.intValue == 0o700, "layout cache namespace private")
        for changed in [snapshot(1, width: 641), snapshot(1, fontSize: 15), snapshot(1, font: "Helvetica"),
                        snapshot(1, theme: "dark"), snapshot(1, revision: "new-revision")] {
            try serviceCheck(changed.key != a.key, "stable layout input changes key")
            try serviceCheck(try await disk.load(ownerID: changed.ownerID, key: changed.key) == nil, "changed key cannot return stale metrics")
        }
        try serviceCheck(snapshot(1, width: 640.24).key == a.key && snapshot(1, width: 640.26).key.width == 640.5,
            "half point width quantization")
        let changed = snapshot(1, width: 641)
        try await disk.save(changed)
        try serviceCheck(try await disk.load(ownerID: a.ownerID, key: a.key) == nil, "old geometry invalidated on save")
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        for file in files {
            var envelope = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
            envelope["sha256"] = String(repeating: "0", count: 64)
            try JSONSerialization.data(withJSONObject: envelope).write(to: file)
        }
        try serviceCheck(try await disk.latest(ownerID: changed.ownerID) == nil, "corrupt SHA envelope never loaded")
        try serviceCheck(try await disk.diskBytes() == 0, "corrupt SHA envelopes discarded regardless of directory order")
        let tiny = NativeReaderLayoutCache(root: root.appendingPathComponent("tiny"), byteLimit: 1)
        try await rejects("oversize file rejected before writing") { try await tiny.save(a) }
        try serviceCheck(try await tiny.diskBytes() == 0, "oversize write consumes no disk budget")

        let source = document.blocks.flatMap(\.orderedNodes).first { $0.math != nil }!
        let math = source.math!, context = a.key.context(identity: a.document.identity, generation: 99, snapshotGeneration: 1)
        let fragment = NativeMathLayout.Fragment(svg: "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"20\" height=\"14\"><path d=\"M0 0L20 14\"/></svg>", width: 20, ascent: 10, descent: 4)
        let layout = NativeMathLayout(version: 1, inputHash: NativeReaderRecoverySnapshot.digest(Data(math.mathML.utf8)),
            context: .init(revision: a.key.revision, generation: 1, theme: "light"), font: "MathJaxNewcm",
            fontSize: 14, width: 608, whole: fragment, fragments: [fragment], diagnostics: [])
        let roundTrip = try JSONDecoder().decode(NativeMathLayout.self, from: JSONEncoder().encode(layout))
        try serviceCheck(try roundTrip.rebinding(math: math, context: context, width: 608).context.generation == 99,
            "validated Codable layout rebinds only generation")
        let fields: [(String, Any)] = [("version", 2), ("inputHash", "bad"), ("font", "bad"), ("fontSize", 15), ("width", 607)]
        for (field, value) in fields {
            var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(layout)) as! [String: Any]
            json[field] = value
            let invalid = try JSONDecoder().decode(NativeMathLayout.self, from: JSONSerialization.data(withJSONObject: json))
            try await rejects("strict layout field \(field)") { _ = try invalid.rebinding(math: math, context: context, width: 608) }
        }
        for field in ["revision", "theme"] {
            var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(layout)) as! [String: Any]
            var c = json["context"] as! [String: Any]; c[field] = "wrong"; json["context"] = c
            let invalid = try JSONDecoder().decode(NativeMathLayout.self, from: JSONSerialization.data(withJSONObject: json))
            try await rejects("strict layout context \(field)") { _ = try invalid.rebinding(math: math, context: context, width: 608) }
        }
        let viewed = NativeReaderViewedLayouts()
        for i in 0..<300 { await viewed.record(["math-\(i)": layout], key: a.key) }
        let retained = await viewed.cached(for: a.key)
        try serviceCheck(retained.count == 256 && retained["math-0"] == nil && retained["math-299"] != nil, "viewed math LRU bounded to 256")
        try serviceCheck(await viewed.cached(for: changed.key).isEmpty, "geometry change revokes in-memory layouts")
        let assetBlock = document.blocks.first { $0.orderedNodes.contains { $0.assetID != nil } }!
        let referenced = Set(assetBlock.orderedNodes.compactMap(\.assetID))
        let assetSnapshot = NativeReaderLayoutSnapshot(ownerID: "asset-profile",
            key: .init(documentID: document.identity.documentID, revision: document.identity.revision, width: 640, fontSize: 14, theme: "light"),
            document: document, restoration: .init(blockID: assetBlock.id, offset: 0.5, zoom: 1, selectionTicket: nil, fragments: []),
            viewedBlockIDs: [assetBlock.id], layouts: [:], assets: assets.filter { referenced.contains($0.key) })
        let recovery = NativeReaderRecoveryStore(root: root.appendingPathComponent("coexisting"))
        try await recovery.save(.init(document: document, assets: assets, restoration: .initial, drafts: []))
        let assetCache = NativeReaderLayoutCache(root: recovery.root.appendingPathComponent("layout-cache"))
        try await assetCache.save(assetSnapshot)
        let assetLoaded = try await assetCache.load(ownerID: assetSnapshot.ownerID, key: assetSnapshot.key)!
        try serviceCheck(Set(assetLoaded.assets.keys) == referenced && !referenced.isEmpty, "only viewed-block asset bytes round trip")
        try serviceCheck(try await recovery.list().count == 1, "layout namespace does not collide with recovery files")
        let unreadAssets = NativeReaderLayoutSnapshot(ownerID: a.ownerID, key: a.key, document: a.document,
            restoration: a.restoration, viewedBlockIDs: a.viewedBlockIDs, layouts: [:], assets: assets)
        try await rejects("unviewed asset bytes rejected") { try await probe.save(unreadAssets) }
        let privateLink = root.appendingPathComponent("cache-link")
        try FileManager.default.createSymbolicLink(at: privateLink, withDestinationURL: directory)
        let unsafe = NativeReaderLayoutCache(root: privateLink)
        try await rejects("cache never follows directory symlink") { try await unsafe.save(a) }
        return ["byteCap": cap, "lru": true, "privateDirectory": true, "keyInvalidation": true,
                "sha256": true, "strictRebinding": true, "mathEntryCap": retained.count,
                "viewedAssets": true, "recoveryCoexistence": true, "noFollow": true,
                "sharedProfiles": true, "sharedLRU": true, "longOwnerID": true, "legacyMigration": true,
                "restoreRetryWait": true, "restoreRetryAdopted": true]
    }
}
