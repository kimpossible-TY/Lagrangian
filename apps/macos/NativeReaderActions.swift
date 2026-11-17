import Foundation

struct NativeReaderConversation {
    let state: NativeReaderChatState
    let draft: String
    let status: String
    let attached: Bool
}

struct NativeReaderAccountState {
    let signedIn: Bool
    let planEnabled: Bool
    let homepage: URL?
    let models: [String]
    // Document auth deliberately grants no native login/logout/cancel authority.
    static let managementBlocker = "Document /api/chat/auth is status/models-only; use the configured Homepage consent/session flow."
}

actor NativeReaderActions: NativeReaderSourceOperations, NativeReaderChatOperations {
    let transport: NativeReaderTransport
    private let wait: (UInt64) async throws -> Void
    private var selection: NativeReaderSelection?
    private var selectionVersion = 0
    private var uncertainJump: UUID?
    private var conversations: [UUID: NativeReaderConversation] = [:]
    private var frozenTickets: [UUID: UUID] = [:]
    private var frozenContexts: [UUID: NativeReaderRequestContext] = [:]
    private struct PendingSend {
        let message: UUID
        let question: String
        let model: String
        var read = false
    }
    private var unknown: [UUID: PendingSend] = [:]

    init(transport: NativeReaderTransport, wait: @escaping (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }) {
        self.transport = transport; self.wait = wait
    }

    /// NA02 calls this whenever selection changes; never release by an old acknowledgment.
    func updateSelection(_ value: NativeReaderSelection?, context: NativeReaderRequestContext) async throws {
        selectionVersion += 1
        let version = selectionVersion
        try await transport.check(context)
        guard selectionVersion == version else { throw NativeReaderContractError.staleGeneration }
        selection = nil // An over-limit/new selection must never leave an old actionable ticket.
        // Revoke the old editor lease even when the incoming selection is invalid.
        // Common source/chat selection authority does not depend on editor health.
        try await transport.revokeEditorSelection(context: context)
        try Task.checkCancellation()
        guard selectionVersion == version else { throw NativeReaderContractError.staleGeneration }
        if let value { _ = try await transport.selectionFields(value, context: context) }
        selection = value
        do { try await transport.syncEditor(value, context: context) }
        catch NativeReaderOperationFailure.unavailable { return }
        // Identity/input/selection errors still propagate; no stale authority is adopted.
    }

    func jump(_ request: NativeReaderSourceRequest, query: Bool = false) async throws -> NativeReaderEditorReceipt {
        guard request.action == .locate, selection == request.selection else { throw NativeReaderContractError.invalidSelection }
        if !query, uncertainJump != nil { throw NativeReaderOperationFailure.unknownEffect }
        if query, let pending = uncertainJump, pending != request.receiptID { throw NativeReaderOperationFailure.unknownEffect }
        // Keep an uncertain effect blocked across actor reentrancy and failures.
        if !query { uncertainJump = request.receiptID }
        do {
            let result = try await transport.editor(request, query: query)
            guard selection == request.selection else { throw NativeReaderContractError.invalidSelection }
            if result.status != .unknown { uncertainJump = nil }
            return result
        } catch {
            // Before-prepare failures prove no dispatch; after-dispatch failures do
            // not. Transport labels lost/invalid effect acknowledgments unknown.
            if !query, case NativeReaderOperationFailure.unavailable = error { uncertainJump = nil }
            throw error
        }
    }

    func pendingEditorReceiptID() -> UUID? { uncertainJump }

    func perform(_ request: NativeReaderSourceRequest) async throws -> NativeReaderSourceResult {
        guard selection?.ticket == request.selection.ticket else { throw NativeReaderContractError.invalidSelection }
        if request.action == .highlight, transport.attachment.editorConsentID != nil {
            // The new Connect consent is movement-only, never a source-write opt-in.
            try await transport.check(request.context)
            return NativeReaderSourceResult(context: request.context, selectionTicket: request.selection.ticket,
                status: .unsupported, verifiedText: nil, destinationAnchor: nil)
        }
        let operation: String
        switch request.action { case .excerpt: operation = "excerpt"; case .locate: operation = "locate"; case .highlight: operation = "highlight" }
        var fields: [String: Any] = ["operation": operation, "receiptID": request.receiptID.uuidString.lowercased(),
            "selection": try await transport.selectionFields(request.selection, context: request.context)]
        if let token = transport.attachment.editorAttachment { fields["editorAttachment"] = token }
        let result = try await transport.call("api/native-action", fields: fields, context: request.context, mutation: operation == "highlight")
        return sourceResult(result, request: request)
    }

    /// Required after unknown highlight effect; this never executes a source writer.
    func receipt(for request: NativeReaderSourceRequest) async throws -> NativeReaderSourceResult {
        let object = try await transport.call("api/native-action", fields: ["operation": "receipt", "receiptID": request.receiptID.uuidString.lowercased()], context: request.context)
        return sourceResult(object, request: request)
    }

    private func sourceResult(_ object: [String: Any], request: NativeReaderSourceRequest) -> NativeReaderSourceResult {
        let status: NativeReaderSourceResult.Status
        switch object["status"] as? String {
        case "located", "highlighted": status = .verified
        case "unmapped": status = .unmapped
        case "ambiguous": status = .ambiguous
        case "stale": status = .stale
        case "unsupported": status = .unsupported
        case "uncertain", "unknown": status = .uncertain
        default: status = .rejected
        }
        return NativeReaderSourceResult(context: request.context, selectionTicket: request.selection.ticket, status: status,
            verifiedText: status == .verified && request.action == .excerpt ? object["text"] as? String : nil,
            destinationAnchor: status == .verified ? object["anchor"] as? String : nil)
    }

    func perform(_ command: NativeReaderChatCommand, context: NativeReaderRequestContext) async throws -> NativeReaderChatState {
        try await transport.check(context)
        var fields: [String: Any]
        var requested: UUID?
        var pending: PendingSend?
        switch command {
        case .open(let selected):
            guard selection == selected else { throw NativeReaderContractError.invalidSelection }
            fields = ["operation": "open", "selection": try await transport.selectionFields(selected, context: context)]
        case .draft(let id, let version, let text):
            guard text.count <= 8000 else { throw NativeReaderOperationFailure.rejected(code: "draft-limit") }
            fields = ["operation": "draft", "conversationID": id.uuidString.lowercased(), "version": version, "draft": text]
            requested = id
        case .send(let id, let version, let message, let question, let model):
            guard let record = conversations[id], record.state.version == version, record.attached,
                  frozenTickets[id] == selection?.ticket, frozenContexts[id] == context,
                  !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, question.count <= 8000,
                  !model.isEmpty, model.count <= 120 else { throw NativeReaderContractError.invalidSelection }
            if let previous = unknown[id] {
                guard previous.read, previous.message == message, Array(previous.question.unicodeScalars) == Array(question.unicodeScalars), previous.model == model else {
                    throw NativeReaderOperationFailure.unknownEffect
                }
            }
            pending = PendingSend(message: message, question: question, model: model)
            fields = ["operation": "send", "conversationID": id.uuidString.lowercased(), "version": version,
                      "messageID": message.uuidString.lowercased(), "question": question, "model": model]
            requested = id
        case .cancel(let id):
            guard let record = conversations[id] else { throw NativeReaderOperationFailure.unavailable }
            fields = ["operation": "cancel", "conversationID": id.uuidString.lowercased(), "version": record.state.version]
            requested = id
        }
        do {
            let object = try await transport.call("api/native-chat", fields: fields, context: context, mutation: pending != nil)
            let records = try adopt(object, context: context)
            guard let record = records.first(where: { requested == nil || $0.state.conversationID == requested }) else { throw NativeReaderOperationFailure.unavailable }
            if case .open(let selected) = command {
                // Freeze only this conversation's current accepted context.
                frozenTickets[record.state.conversationID] = selected.ticket
                frozenContexts[record.state.conversationID] = context
            }
            if pending != nil { unknown.removeValue(forKey: record.state.conversationID) }
            return record.state
        } catch {
            if let id = requested, let pending { unknown[id] = pending }
            throw error
        }
    }

    func history(context: NativeReaderRequestContext) async throws -> [NativeReaderConversation] {
        try Task.checkCancellation()
        let object = try await transport.call("api/native-chat", fields: ["operation": "list"], context: context)
        try Task.checkCancellation()
        let result = try adopt(object, context: context)
        for id in Array(unknown.keys) {
            guard let pending = unknown[id] else { continue }
            if let record = result.first(where: { $0.state.conversationID == id }),
               record.state.confirmsUserMessage(pending.message, question: pending.question) {
                unknown.removeValue(forKey: id)
            } else { unknown[id]?.read = true }
        }
        return result
    }

    func lastChange(context: NativeReaderRequestContext) async throws -> String? {
        let object = try await transport.call("api/native-action", fields: ["operation": "last-change"], context: context)
        return object["status"] as? String == "located" ? object["anchor"] as? String : nil
    }

    func conversation(_ id: UUID) -> NativeReaderConversation? { conversations[id] }

    private func adopt(_ object: [String: Any], context: NativeReaderRequestContext) throws -> [NativeReaderConversation] {
        guard let records = object["conversations"] as? [[String: Any]], records.count <= 128 else { throw NativeReaderOperationFailure.rejected(code: "conversation-limit") }
        var result = [NativeReaderConversation]()
        var seen = Set<UUID>()
        for record in records {
            guard let rawID = record["conversation_id"] as? String, let id = UUID(uuidString: rawID), seen.insert(id).inserted,
                  let version = record["version"] as? Int, let sequence = record["sequence"] as? Int, version >= 0, sequence >= 0,
                  let thread = record["thread"] as? [[String: Any]], thread.count <= 256,
                  let draft = record["draft"] as? String, draft.count <= 8000,
                  let status = record["status"] as? String else { throw NativeReaderOperationFailure.rejected(code: "conversation-schema") }
            if let old = conversations[id] {
                guard version >= old.state.version, sequence >= old.state.sequence else { throw NativeReaderContractError.staleGeneration }
            }
            var messageIDs = Set<UUID>()
            let messages = try thread.map { message -> NativeReaderChatState.Message in
                guard let raw = message["id"] as? String, let mid = UUID(uuidString: raw), messageIDs.insert(mid).inserted,
                      let role = message["role"] as? String, ["user", "assistant"].contains(role),
                      let text = message["text"] as? String, text.count <= 80000,
                      let state = message["status"] as? String else { throw NativeReaderOperationFailure.rejected(code: "message-schema") }
                return NativeReaderChatState.Message(id: mid, role: role == "user" ? .user : .assistant, markdown: text, complete: state != "streaming")
            }
            let state = NativeReaderChatState(context: context, conversationID: id, version: version, sequence: sequence, messages: messages)
            result.append(NativeReaderConversation(state: state, draft: draft, status: status,
                attached: (record["attachment"] as? [String: Any])?["state"] as? String == "attached"))
        }
        // Validate the entire batch before adopting any record.
        for record in result { conversations[record.state.conversationID] = record }
        return result
    }

    nonisolated func observe(conversation: UUID, context: NativeReaderRequestContext) -> AsyncThrowingStream<NativeReaderChatState, Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task {
                do {
                    for attempt in 0..<4 {
                        try Task.checkCancellation()
                        do {
                            let stream = try await transport.subscription(fields: ["operation": "events"], context: context)
                            var parser = NativeReaderSSEParser()
                            for try await chunk in stream {
                                try Task.checkCancellation()
                                for data in try parser.feed(chunk) {
                                    let object = try await transport.verifyEnvelope(data, context: context)
                                    let records = try await self.adopt(object, context: context)
                                    if let state = records.first(where: { $0.state.conversationID == conversation })?.state { continuation.yield(state) }
                                }
                            }
                            try parser.finish()
                        } catch {
                            try Task.checkCancellation()
                            // Contract failures are never reconnectable to another target.
                            if error is NativeReaderContractError { throw error }
                        }
                        // Every reconnect reads authoritative history, never replays Send.
                        let records = try await self.history(context: context)
                        guard let record = records.first(where: { $0.state.conversationID == conversation }) else { throw NativeReaderOperationFailure.unavailable }
                        continuation.yield(record.state)
                        if record.status != "streaming" { continuation.finish(); return }
                        guard attempt < 3 else { throw NativeReaderOperationFailure.unavailable }
                        try await self.wait(UInt64(1 << attempt) * 1_000_000_000)
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func account(context: NativeReaderRequestContext) async throws -> NativeReaderAccountState {
        try await transport.check(context)
        let attachment = transport.attachment
        var status: [String: Any] = [:], models = [String]()
        for operation in ["status", "models"] {
            let fields: [String: Any] = ["operation": operation, "documentID": context.target.documentID,
                "revision": context.target.revision, "service": attachment.service]
            let request = try await transport.request(path: "api/chat/auth", fields: fields)
            let response = try await transport.network.send(request, 262144)
            try await transport.check(context)
            try await transport.validate(response, limit: 262144)
            guard let object = try JSONSerialization.jsonObject(with: response.data) as? [String: Any] else { throw NativeReaderOperationFailure.unavailable }
            if operation == "status" { status = object }
            else {
                // Provider catalog uses {id,label}; no credentials or provider URL enter UI state.
                models = (object["models"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
                guard models.count <= 100, models.allSatisfy({ !$0.isEmpty && $0.count <= 120 }) else { throw NativeReaderOperationFailure.unavailable }
            }
        }
        var home: URL?
        if let raw = status["homepageURL"] as? String, let url = URL(string: raw),
           ["http", "https"].contains(url.scheme ?? ""), url.user == nil, url.password == nil,
           url.query == nil, url.fragment == nil, url.path == "/" { home = url }
        return NativeReaderAccountState(signedIn: status["signedIn"] as? Bool == true,
            planEnabled: status["planEnabled"] as? Bool == true, homepage: home, models: models)
    }
}

struct NativeReaderSSEParser {
    private var pending = Data()
    private var data = Data()
    private var stale = false
    private var total = 0

    mutating func feed(_ chunk: Data) throws -> [Data] {
        total += chunk.count
        guard total <= 16 * 1024 * 1024, pending.count + chunk.count <= 2 * 1024 * 1024 + 4096 else { throw NativeReaderOperationFailure.rejected(code: "sse-limit") }
        pending.append(chunk)
        var events = [Data]()
        while let end = pending.firstIndex(of: 10) {
            var line = pending.subdata(in: 0..<end)
            pending.removeSubrange(0...end)
            if line.last == 13 { line.removeLast() }
            guard let text = String(data: line, encoding: .utf8) else { throw NativeReaderOperationFailure.rejected(code: "sse-utf8") }
            if text.isEmpty {
                if stale { throw NativeReaderContractError.staleGeneration }
                if !data.isEmpty { data.removeLast(); events.append(data); data.removeAll(keepingCapacity: true) }
            } else if text == "event: stale" { stale = true }
            else if text.hasPrefix("data:") {
                var value = text.dropFirst(5)
                if value.first == " " { value = value.dropFirst() }
                data.append(contentsOf: value.utf8); data.append(10)
                guard data.count <= 2 * 1024 * 1024 else { throw NativeReaderOperationFailure.rejected(code: "sse-event-limit") }
            } else if !text.hasPrefix(":") && !text.hasPrefix("event:") && !text.hasPrefix("id:") && !text.hasPrefix("retry:") {
                throw NativeReaderOperationFailure.rejected(code: "sse-field")
            }
        }
        return events
    }
    func finish() throws {
        guard pending.isEmpty, data.isEmpty, !stale else { throw NativeReaderOperationFailure.unavailable }
    }
}
