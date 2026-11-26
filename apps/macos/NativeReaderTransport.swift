import Foundation
import CryptoKit

struct NativeReaderHTTPResponse {
    let status: Int
    let headers: [String: String]
    let data: Data
}

/// All process/network effects are injected. Tests never touch a managed job.
struct NativeReaderNetwork {
    var send: (URLRequest, Int) async throws -> NativeReaderHTTPResponse
    var stream: (URLRequest) -> AsyncThrowingStream<Data, Error>
    var sendUntil: ((URLRequest, Int, Date) async throws -> NativeReaderHTTPResponse)? = nil

    func send(_ request: URLRequest, _ limit: Int, before deadline: Date) async throws -> NativeReaderHTTPResponse {
        if let sendUntil { return try await sendUntil(request, limit, deadline) }
        // Injected adapters keep their cancellation contract. The actual
        // URLSession adapter below cancels AND awaits didCompleteWithError.
        return try await withThrowingTaskGroup(of: NativeReaderHTTPResponse.self) { group in
            group.addTask { try await send(request, limit) }
            group.addTask {
                let seconds = deadline.timeIntervalSinceNow
                if seconds > 0 { try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
                throw URLError(.timedOut)
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }

    static func urlSession() -> Self {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 35
        let session = URLSession(configuration: config, delegate: NativeReaderNoRedirect(), delegateQueue: nil)
        return Self(send: { request, limit in
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse, http.url == request.url,
                  response.expectedContentLength <= limit else { throw NativeReaderOperationFailure.unavailable }
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < limit else { throw NativeReaderOperationFailure.rejected(code: "payload-limit") }
                data.append(byte)
            }
            return NativeReaderHTTPResponse(status: http.statusCode, headers: http.allHeaderFields.reduce(into: [:]) {
                $0[String(describing: $1.key).lowercased()] = String(describing: $1.value)
            }, data: data)
        }, stream: { request in
            AsyncThrowingStream(bufferingPolicy: .bufferingOldest(8)) { continuation in
                let task = Task {
                    do {
                        let (bytes, response) = try await session.bytes(for: request)
                        guard let http = response as? HTTPURLResponse, http.url == request.url,
                              http.statusCode == 200,
                              http.value(forHTTPHeaderField: "Content-Type") == "text/event-stream" else {
                            throw NativeReaderOperationFailure.unavailable
                        }
                        var chunk = Data(), total = 0
                        // Yield at newline so sparse SSE frames do not wait for 4KiB.
                        for try await byte in bytes {
                            try Task.checkCancellation()
                            total += 1
                            guard total <= 16 * 1024 * 1024 else { throw NativeReaderOperationFailure.unavailable }
                            chunk.append(byte)
                            if byte == 10 || chunk.count == 4096 {
                                if case .dropped = continuation.yield(chunk) { throw NativeReaderOperationFailure.unavailable }
                                chunk.removeAll(keepingCapacity: true)
                            }
                        }
                        if !chunk.isEmpty { continuation.yield(chunk) }
                        continuation.finish()
                    } catch { continuation.finish(throwing: error) }
                }
                // Closing this view cancels only this HTTP subscription, never inference/OAuth.
                continuation.onTermination = { _ in task.cancel() }
            }
        }, sendUntil: { request, limit, deadline in
            try await NativeReaderDeadlineRequest.perform(request, limit: limit, deadline: deadline)
        })
    }
}

/// One bounded request, not a global session timeout or resident retry loop.
/// Deadline/cancel only resume after URLSession confirms the owned task ended.
private final class NativeReaderDeadlineRequest: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let request: URLRequest
    private let limit: Int
    private let deadline: Date
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var timer: DispatchSourceTimer?
    private var continuation: CheckedContinuation<NativeReaderHTTPResponse, Error>?
    private var response: HTTPURLResponse?
    private var data = Data()
    private var failure: Error?
    private var finished = false

    init(_ request: URLRequest, limit: Int, deadline: Date) {
        self.request = request; self.limit = limit; self.deadline = deadline
    }
    static func perform(_ request: URLRequest, limit: Int, deadline: Date) async throws -> NativeReaderHTTPResponse {
        let owner = NativeReaderDeadlineRequest(request, limit: limit, deadline: deadline)
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { owner.start($0) }
        }, onCancel: { owner.cancel(CancellationError()) })
    }
    private func start(_ continuation: CheckedContinuation<NativeReaderHTTPResponse, Error>) {
        lock.lock()
        if let failure { lock.unlock(); continuation.resume(throwing: failure); return }
        if deadline.timeIntervalSinceNow <= 0 { lock.unlock(); continuation.resume(throwing: URLError(.timedOut)); return }
        self.continuation = continuation
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false; config.urlCache = nil
        config.timeoutIntervalForRequest = 30; config.timeoutIntervalForResource = 35
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.session = session
        let task = session.dataTask(with: request); self.task = task
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + max(0, deadline.timeIntervalSinceNow))
        timer.setEventHandler { [weak self] in self?.cancel(URLError(.timedOut)) }
        self.timer = timer; timer.resume()
        lock.unlock(); task.resume()
    }
    private func cancel(_ error: Error) {
        lock.lock()
        if !finished && failure == nil { failure = error }
        let task = self.task
        lock.unlock(); task?.cancel()
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        lock.lock()
        let valid = (response as? HTTPURLResponse).map { $0.url == request.url && response.expectedContentLength <= limit } ?? false
        if valid { self.response = response as? HTTPURLResponse }
        else { failure = NativeReaderOperationFailure.unavailable }
        let accept = valid && failure == nil
        lock.unlock(); completionHandler(accept ? .allow : .cancel)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        if data.count > limit - self.data.count { failure = NativeReaderOperationFailure.rejected(code: "payload-limit") }
        else if failure == nil { self.data.append(data) }
        let cancel = failure != nil
        lock.unlock(); if cancel { dataTask.cancel() }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true; timer?.cancel(); timer = nil
        let completion = continuation; continuation = nil
        let failure = self.failure ?? error
        let response = self.response, data = self.data
        self.task = nil; self.session = nil
        lock.unlock()
        session.finishTasksAndInvalidate()
        if let failure { completion?.resume(throwing: failure) }
        else if let response {
            completion?.resume(returning: .init(status: response.statusCode, headers: response.allHeaderFields.reduce(into: [:]) {
                $0[String(describing: $1.key).lowercased()] = String(describing: $1.value)
            }, data: data))
        } else { completion?.resume(throwing: NativeReaderOperationFailure.unavailable) }
    }
}

private final class NativeReaderNoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

struct NativeReaderAttachment {
    let baseURL: URL
    let documentID: String
    let serviceID: String
    let service: [String: Int64]
    let editorAttachment: String?
    let editorConsentID: UUID?
    let editorLease: NativeReaderEditorLease?

    init(data: Data, editorConsentID: UUID? = nil, editorLease: NativeReaderEditorLease? = nil) throws {
        guard data.count <= 1024 * 1024,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let urlString = object["url"] as? String, let url = URL(string: urlString),
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "http", ["127.0.0.1", "localhost"].contains(parts.host ?? ""),
              let port = parts.port, (1...65535).contains(port), parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil,
              parts.path == "/" || parts.path.range(of: "^/d/[A-Za-z0-9_-]+/$", options: .regularExpression) != nil,
              let doc = object["documentID"] as? String,
              doc.range(of: "^[A-Za-z0-9_.:-]{1,128}$", options: .regularExpression) != nil,
              let service = object["service"] as? [String: Any],
              let pid = service["pid"] as? NSNumber, let start = service["startedAt"] as? NSNumber,
              CFGetTypeID(pid) != CFBooleanGetTypeID(), CFGetTypeID(start) != CFBooleanGetTypeID(),
              pid.doubleValue == Double(pid.int64Value), start.doubleValue == Double(start.int64Value),
              pid.int64Value > 0, start.int64Value > 0 else { throw NativeReaderContractError.wrongTarget }
        baseURL = url
        documentID = doc
        self.service = ["pid": pid.int64Value, "startedAt": start.int64Value]
        serviceID = "reader:\(pid.int64Value):\(start.int64Value)"
        editorAttachment = object["editorAttachment"] as? String
        self.editorConsentID = editorConsentID
        self.editorLease = editorLease
    }
}

struct NativeReaderManagedEditor {
    let address: String
    let executable: String
    let ownerPID: Int
    let controlFile: String
    var consentID: UUID? = nil

    /// Explicitly chosen private local descriptor; never discovered from processes,
    /// environment, ports or HTTP. The chooser supplies fresh consent each time.
    static func consentedDescriptor(_ url: URL) throws -> Self {
        func privateFile(_ url: URL) throws {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            guard url.isFileURL, attrs[.type] as? FileAttributeType == .typeRegular,
                  (attrs[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
                  let mode = attrs[.posixPermissions] as? NSNumber, mode.intValue & 0o077 == 0 else {
                throw NativeReaderOperationFailure.unavailable
            }
        }
        try privateFile(url)
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= 16384,
              let value = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(value.keys) == ["address", "executable", "ownerPID", "controlFile"],
              let address = value["address"] as? String, !address.isEmpty, address.utf8.count <= 4096, !address.contains("\0"),
              let executable = value["executable"] as? String, executable.hasPrefix("/"),
              FileManager.default.isExecutableFile(atPath: executable),
              let pid = value["ownerPID"] as? NSNumber, CFGetTypeID(pid) != CFBooleanGetTypeID(),
              pid.doubleValue == Double(pid.int32Value), pid.int32Value > 0, kill(pid.int32Value, 0) == 0,
              let control = value["controlFile"] as? String, control.hasPrefix("/") else {
            throw NativeReaderOperationFailure.unavailable
        }
        try privateFile(URL(fileURLWithPath: control))
        return Self(address: address, executable: executable, ownerPID: pid.intValue, controlFile: control, consentID: UUID())
    }
}

/// Revoking local consent is independent of confirming exact local-file removal.
/// Coalesce concurrent attempts; a failed bounded command remains explicitly
/// retryable by a subsequent release. There is no background retry loop.
actor NativeReaderEditorLease {
    enum Retirement { case active, pending, confirmed }
    private(set) var retirement = Retirement.active
    private var task: Task<Bool, Never>?
    private var attempt = 0
    private let cleanup: (Date) async throws -> Void
    init(cleanup: @escaping () async throws -> Void) { self.cleanup = { _ in try await cleanup() } }
    init(boundedCleanup: @escaping (Date) async throws -> Void) { self.cleanup = boundedCleanup }
    @discardableResult func release(deadline: Date = Date().addingTimeInterval(2.5)) async -> Bool {
        if retirement == .confirmed { return true }
        if task == nil {
            attempt += 1
            retirement = .pending
            let cleanup = self.cleanup
            task = Task { do { try await cleanup(deadline); return true } catch { return false } }
        }
        let current = attempt
        let confirmed = await task!.value
        if attempt == current {
            retirement = confirmed ? .confirmed : .pending
            task = nil
        }
        return confirmed
    }
}

/// Resolver copies and successive FlowApp clients share this owner. It retains
/// only caller-known leases, never discovers operations by scanning the journal.
struct NativeReaderEditorScope {
    let identity: String?
    let requestBinding: String
    init(data: Data) throws {
        func digest(_ value: Any?) -> String? {
            guard let value = value as? String,
                  value.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else { return nil }
            return value
        }
        guard data.count <= 1024,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == ["scope", "requestBinding"],
              let request = digest(object["requestBinding"]),
              object["scope"] is NSNull || digest(object["scope"]) != nil else {
            throw NativeReaderOperationFailure.unavailable
        }
        identity = digest(object["scope"]); requestBinding = request
    }
}

actor NativeReaderEditorRetirements {
    private struct Entry {
        let scope: NativeReaderEditorScope
        let lease: NativeReaderEditorLease
    }
    private var entries: [String: Entry] = [:]
    func retain(_ operation: String, scope: NativeReaderEditorScope, lease: NativeReaderEditorLease) {
        entries[operation] = Entry(scope: scope, lease: lease)
    }
    /// Manager owns document equivalence. Stable caller binding also recovers a
    /// known operation after its alias disappeared/retargeted; it grants nothing.
    func retry(scope: NativeReaderEditorScope, deadline: Date) async -> Bool {
        let matching = entries.filter {
            $0.value.scope.requestBinding == scope.requestBinding ||
                (scope.identity != nil && $0.value.scope.identity == scope.identity)
        }
        var attempted = false
        var remains = false
        for (id, item) in matching.sorted(by: { $0.key < $1.key }) {
            let state = await item.lease.retirement
            if state == .confirmed { entries[id] = nil; continue }
            guard state == .pending else { continue }
            if !attempted && deadline.timeIntervalSinceNow > 0 {
                attempted = true
                let limit = min(deadline, Date().addingTimeInterval(2.5))
                if await item.lease.release(deadline: limit) { entries[id] = nil; continue }
            }
            remains = true
        }
        return !remains
    }
}

struct NativeReaderManagedResolver {
    /// Supply an asynchronous bounded runner for the installed manage.py. No shell or preview-port probing.
    var attach: ([String]) async throws -> Data
    var network: NativeReaderNetwork
    var retirements = NativeReaderEditorRetirements()

    private func editorScope(root: String, entry: String, readerID: String?, deadline: Date) async throws -> NativeReaderEditorScope {
        var args = ["--native-editor-scope", "--root", root, "--entry", entry,
                    "--native-editor-deadline", String(deadline.timeIntervalSince1970)]
        if let id = readerID { args += ["--reader-service", id] }
        return try NativeReaderEditorScope(data: await attach(args))
    }
    func retryEditorCleanup(root: String, entry: String, readerID: String? = nil,
                            deadline: Date = Date().addingTimeInterval(3.5)) async -> Bool {
        do {
            let scope = try await editorScope(root: root, entry: entry, readerID: readerID, deadline: deadline)
            return await retirements.retry(scope: scope, deadline: deadline)
        } catch { return false }
    }

    func resolve(root: String, entry: String, readerID: String? = nil, editor: NativeReaderManagedEditor? = nil) async throws -> (NativeReaderAttachment, NativeDocumentIdentity) {
        let callerDeadline = Date().addingTimeInterval(10)
        // Pending editor retirement gates a NEW movement grant, never body,
        // Source or Ask authority. Plain Read neither retries nor confirms it.
        let scope: NativeReaderEditorScope?
        if editor?.consentID != nil {
            scope = try await editorScope(root: root, entry: entry, readerID: readerID, deadline: callerDeadline)
            guard scope?.identity != nil, await retirements.retry(scope: scope!, deadline: callerDeadline) else {
                throw NativeReaderOperationFailure.unavailable
            }
        } else { scope = nil }
        try Task.checkCancellation()
        var args = ["--attach", "--root", root, "--entry", entry]
        if let id = readerID { args += ["--reader-service", id] }
        if let editor {
            args += ["--editor-server", editor.address, "--nvim", editor.executable,
                     "--owner-pid", String(editor.ownerPID), "--control-file", editor.controlFile]
            if editor.consentID != nil { args += ["--native-editor-consent"] }
        }
        let operation: String?
        let lease: NativeReaderEditorLease?
        if editor?.consentID != nil {
            operation = (UUID().uuidString + UUID().uuidString).replacingOccurrences(of: "-", with: "").lowercased()
            args += ["--native-editor-operation", operation!, "--native-editor-expected-scope", scope!.identity!, "--native-editor-deadline",
                     String(min(Date().timeIntervalSince1970 + 6.5,
                                callerDeadline.timeIntervalSince1970 - 3))]
            var release = ["--release-native-editor-operation", "--root", root, "--entry", entry,
                           "--native-editor-operation", operation!]
            if let id = readerID { release += ["--reader-service", id] }
            let runner = attach, releaseArguments = release
            // The owner exists BEFORE the manager can publish any registration.
            lease = NativeReaderEditorLease(boundedCleanup: { deadline in
                let arguments = releaseArguments + ["--native-editor-deadline", String(deadline.timeIntervalSince1970)]
                let data = try await runner(arguments)
                guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      Set(result.keys) == ["released"], let value = result["released"] as? NSNumber,
                      CFGetTypeID(value) == CFBooleanGetTypeID() else {
                    throw NativeReaderOperationFailure.unavailable
                }
            })
            await retirements.retain(operation!, scope: scope!, lease: lease!)
        } else { operation = nil; lease = nil }
        let data: Data
        do { data = try await attach(args) }
        catch {
            await lease?.release(deadline: callerDeadline)
            if error is CancellationError { throw CancellationError() }
            throw NativeReaderOperationFailure.unavailable
        }
        let plan: [String: Any]?
        do { plan = try JSONSerialization.jsonObject(with: data) as? [String: Any] }
        catch { await lease?.release(deadline: callerDeadline); throw NativeReaderOperationFailure.unavailable }
        do {
        try Task.checkCancellation()
        if editor?.consentID != nil {
            guard plan?["nativeEditorActions"] as? Int == 1,
                  plan?["nativeEditorOperation"] as? String == operation,
                  plan?["nativeEditorScope"] as? String == scope?.identity else { throw NativeReaderOperationFailure.unavailable }
        }
        let attachment = try NativeReaderAttachment(data: data, editorConsentID: editor?.consentID, editorLease: lease)
        var request = URLRequest(url: attachment.baseURL.appendingPathComponent("api/state"))
        if operation != nil {
            let remaining = callerDeadline.timeIntervalSinceNow - 2.75 // cleanup + TERM grace
            guard remaining > 0 else { throw NativeReaderOperationFailure.unavailable }
            request.timeoutInterval = min(5, remaining)
        } else { request.timeoutInterval = 5 }
        let response: NativeReaderHTTPResponse
        if operation != nil { response = try await network.send(request, 1024 * 1024, before: callerDeadline.addingTimeInterval(-2.75)) }
        else { response = try await network.send(request, 1024 * 1024) }
        if operation != nil, callerDeadline.timeIntervalSinceNow <= 2.75 {
            throw NativeReaderOperationFailure.unavailable
        }
        guard response.status == 200, response.data.count <= 1024 * 1024,
              let object = try JSONSerialization.jsonObject(with: response.data) as? [String: Any],
              object["documentID"] as? String == attachment.documentID,
              let service = object["service"] as? [String: Int64], service == attachment.service,
              let revision = object["revision"] as? String,
              revision.range(of: "^[A-Za-z0-9_.:-]{1,128}$", options: .regularExpression) != nil else {
            throw NativeReaderContractError.wrongTarget
        }
        try Task.checkCancellation()
        return (attachment, NativeDocumentIdentity(documentID: attachment.documentID,
            serviceID: attachment.serviceID, revision: revision, scope: .service))
        } catch { await lease?.release(deadline: callerDeadline); throw error }
    }
}

actor NativeReaderTransport: NativeReaderDocumentProviding {
    let attachment: NativeReaderAttachment
    let network: NativeReaderNetwork
    private var active: NativeReaderRequestContext?
    private var accepted: NativeReaderDocument?
    private var acceptedContext: NativeReaderRequestContext?
    private var inputID: String?
    private var disposed = false
    private var editorSequence = 0
    private var editorSelection: NativeReaderSelection?
    private var editorContext: NativeReaderRequestContext?
    private var editorSynced = false
    private var editorEnabled = true

    init(attachment: NativeReaderAttachment, network: NativeReaderNetwork) {
        self.attachment = attachment
        self.network = network
    }

    func invalidate() async {
        guard !disposed else { return }
        active = nil
        if editorEnabled { await closeEditor(permanent: false) }
    }
    func dispose() async { disposed = true; active = nil; await closeEditor(permanent: true) }

    func revokeEditorConsent() async {
        editorEnabled = false
        await closeEditor(permanent: true)
    }

    private func closeEditor(permanent: Bool) async {
        editorSynced = false
        // Local registration cleanup must also run before a document/context
        // exists, and independently of a best-effort HTTP tombstone.
        if permanent { await attachment.editorLease?.release() }
        guard let context = editorContext, let consent = attachment.editorConsentID,
              let token = attachment.editorAttachment else { return }
        editorSequence += 1
        // Local authority is already revoked. This bounded best-effort tombstone
        // never dispatches a move, and cannot claim rollback of an in-flight RPC.
        var values: [String: Any] = ["documentID": context.target.documentID, "serviceID": context.target.serviceID,
            "revision": context.target.revision, "generation": context.generation,
            "viewID": context.viewID.uuidString.lowercased(), "requestID": context.requestID.uuidString.lowercased(),
            "schemaVersion": 1, "capabilities": NativeReaderDocument.supportedCapabilities.sorted(),
            "inputID": inputID ?? "", "operation": permanent ? "close" : "revoke", "consentID": consent.uuidString.lowercased(),
            "editorAttachment": token, "sequence": editorSequence]
        values["selection"] = NSNull()
        if var request = try? request(path: "api/native-editor", fields: values) {
            request.timeoutInterval = 3
            _ = try? await network.send(request, 16384)
        }
    }

    func revokeEditorSelection(context: NativeReaderRequestContext) async throws {
        try check(context)
        editorSelection = nil; editorContext = context
        await closeEditor(permanent: false)
        try check(context)
    }

    func syncEditor(_ selection: NativeReaderSelection?, context: NativeReaderRequestContext) async throws {
        try check(context)
        editorSequence += 1; editorSelection = selection; editorContext = context; editorSynced = false
        guard editorEnabled, attachment.editorConsentID != nil, attachment.editorAttachment != nil else { return }
        let sequence = editorSequence
        let result: [String: Any]
        do { result = try await call("api/native-editor", fields: editorFields(operation: "sync", context: context), context: context) }
        catch is URLError { throw NativeReaderOperationFailure.unavailable }
        guard editorSequence == sequence else { throw NativeReaderContractError.staleGeneration }
        guard result["status"] as? String == "ready" else {
            if result["status"] as? String == "unavailable" { throw NativeReaderOperationFailure.unavailable }
            throw NativeReaderContractError.staleGeneration
        }
        editorSynced = true
    }

    private func editorFields(operation: String, context: NativeReaderRequestContext, receipt: UUID? = nil) throws -> [String: Any] {
        try check(context)
        guard let consent = attachment.editorConsentID, let token = attachment.editorAttachment else {
            throw NativeReaderOperationFailure.unavailable
        }
        var values: [String: Any] = ["operation": operation, "consentID": consent.uuidString.lowercased(),
            "editorAttachment": token, "sequence": editorSequence]
        values["selection"] = try editorSelection.map { try selectionFields($0, context: context) } ?? (NSNull() as Any)
        if let receipt { values["receiptID"] = receipt.uuidString.lowercased() }
        return values
    }

    func editor(_ request: NativeReaderSourceRequest, query: Bool = false) async throws -> NativeReaderEditorReceipt {
        try Task.checkCancellation(); try check(request.context)
        guard editorEnabled, editorSynced, editorSelection == request.selection, editorContext == request.context else {
            throw NativeReaderOperationFailure.unavailable
        }
        let sequence = editorSequence
        func current() throws {
            try Task.checkCancellation(); try check(request.context)
            guard editorSynced, editorSequence == sequence, editorSelection == request.selection else {
                throw NativeReaderContractError.invalidSelection
            }
        }
        var result: [String: Any]
        var dispatched = false
        if query {
            result = try await call("api/native-editor", fields: editorFields(operation: "receipt", context: request.context, receipt: request.receiptID), context: request.context)
        } else {
            result = try await call("api/native-editor", fields: editorFields(operation: "prepare", context: request.context, receipt: request.receiptID), context: request.context)
            try current()
            if result["status"] as? String == "ready" {
                dispatched = true
                result = try await call("api/native-editor", fields: editorFields(operation: "jump", context: request.context, receipt: request.receiptID), context: request.context, mutation: true)
            }
        }
        do { try current() }
        catch { if dispatched { throw NativeReaderOperationFailure.unknownEffect }; throw error }
        guard result["receiptID"] as? String == request.receiptID.uuidString.lowercased(),
              result["inputID"] as? String == inputID,
              result["selectionTicket"] as? String == request.selection.ticket.uuidString.lowercased(),
              result["consentID"] as? String == attachment.editorConsentID?.uuidString.lowercased(),
              result["sequence"] as? Int == sequence,
              let raw = result["status"] as? String, let status = NativeReaderEditorReceipt.Status(rawValue: raw) else {
            throw NativeReaderOperationFailure.unknownEffect
        }
        return NativeReaderEditorReceipt(context: request.context, selectionTicket: request.selection.ticket,
                                         receiptID: request.receiptID, status: status)
    }

    func check(_ context: NativeReaderRequestContext) throws {
        guard !disposed else { throw NativeReaderContractError.disposed }
        guard active == context, acceptedContext == context, accepted?.identity == context.target else { throw NativeReaderContractError.staleGeneration }
    }

    func fields(_ context: NativeReaderRequestContext) throws -> [String: Any] {
        guard !disposed, context.target.scope == .service,
              context.target.documentID == attachment.documentID, context.target.serviceID == attachment.serviceID else {
            throw NativeReaderContractError.wrongTarget
        }
        return ["documentID": context.target.documentID, "serviceID": context.target.serviceID,
                "revision": context.target.revision, "generation": context.generation,
                "viewID": context.viewID.uuidString.lowercased(), "requestID": context.requestID.uuidString.lowercased(),
                "schemaVersion": 1, "capabilities": NativeReaderDocument.supportedCapabilities.sorted()]
    }

    func request(path: String, fields: [String: Any], get: Bool = false) throws -> URLRequest {
        var url = URLComponents(url: attachment.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        var request: URLRequest
        if get {
            url.queryItems = fields.sorted { $0.key < $1.key }.map {
                URLQueryItem(name: $0.key, value: ($0.value as? [String])?.joined(separator: ",") ?? String(describing: $0.value))
            }
            request = URLRequest(url: url.url!)
        } else {
            request = URLRequest(url: url.url!)
            request.httpMethod = "POST"
            request.httpBody = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
            guard request.httpBody!.count <= 262144 else { throw NativeReaderOperationFailure.rejected(code: "payload-limit") }
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.timeoutInterval = 30
        let origin = "http://\(attachment.baseURL.host!):\(attachment.baseURL.port!)"
        request.setValue(origin, forHTTPHeaderField: "Origin")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    func document(for context: NativeReaderRequestContext) async throws -> NativeReaderDocument {
        let fields = try fields(context)
        active = context
        let response = try await network.send(request(path: "api/native-document", fields: fields, get: true), NativeReaderDocument.maximumJSONBytes)
        try Task.checkCancellation()
        guard active == context, !disposed else { throw NativeReaderContractError.staleGeneration }
        try validate(response, limit: NativeReaderDocument.maximumJSONBytes)
        guard let binding = response.headers["x-native-input-id"], binding.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else {
            throw NativeReaderOperationFailure.rejected(code: "input-binding")
        }
        guard let head = try JSONSerialization.jsonObject(with: response.data) as? [String: Any],
              head["schemaVersion"] as? Int == 1,
              let required = head["requiredCapabilities"] as? [String],
              Set(required).isSubset(of: NativeReaderDocument.supportedCapabilities),
              head["generation"] as? Int == context.generation,
              let identity = head["identity"] as? [String: String],
              identity == ["documentID": context.target.documentID, "serviceID": context.target.serviceID,
                           "revision": context.target.revision, "scope": "service"] else { throw NativeReaderContractError.wrongTarget }
        let document = try NativeReaderDocument.decode(response.data)
        guard document.identity == context.target, document.generation == context.generation else { throw NativeReaderContractError.wrongTarget }
        accepted = document
        acceptedContext = context
        inputID = binding
        return document
    }

    func validate(_ response: NativeReaderHTTPResponse, limit: Int) throws {
        guard response.data.count <= limit else { throw NativeReaderOperationFailure.rejected(code: "payload-limit") }
        if response.status == 409 { throw NativeReaderContractError.staleGeneration }
        guard response.status == 200, response.headers["content-type"]?.split(separator: ";").first == "application/json" else {
            throw NativeReaderOperationFailure.rejected(code: "http-\(response.status)")
        }
    }

    func selectionFields(_ selection: NativeReaderSelection, context: NativeReaderRequestContext) throws -> [String: Any] {
        try check(context)
        guard let document = accepted else { throw NativeReaderOperationFailure.unavailable }
        try selection.validate(in: document)
        return ["ticket": selection.ticket.uuidString.lowercased(), "fragments": selection.fragments.map {
            ["blockID": $0.blockID, "rangeUTF16": [$0.rangeUTF16.lowerBound, $0.rangeUTF16.upperBound], "exact": $0.exact] as [String: Any]
        }]
    }

    func payload(_ fields: [String: Any], context: NativeReaderRequestContext) throws -> [String: Any] {
        try check(context)
        return try self.fields(context).merging(["inputID": inputID ?? ""]) { _, new in new }.merging(fields) { _, new in new }
    }

    func verifyEnvelope(_ data: Data, context: NativeReaderRequestContext) throws -> [String: Any] {
        try check(context)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["documentID"] as? String == context.target.documentID,
              object["serviceID"] as? String == context.target.serviceID,
              object["revision"] as? String == context.target.revision,
              object["requestID"] as? String == context.requestID.uuidString.lowercased(),
              object["viewID"] as? String == context.viewID.uuidString.lowercased(),
              object["generation"] as? Int == context.generation else { throw NativeReaderContractError.wrongTarget }
        return object
    }

    func call(_ path: String, fields: [String: Any], context: NativeReaderRequestContext, mutation: Bool = false) async throws -> [String: Any] {
        try Task.checkCancellation()  // Before dispatch: no effect.
        let request = try request(path: path, fields: payload(fields, context: context))
        let response: NativeReaderHTTPResponse
        do { response = try await network.send(request, 2 * 1024 * 1024) }
        catch { if mutation { throw NativeReaderOperationFailure.unknownEffect }; throw error }
        // Once dispatched, a lost/invalid/late acknowledgment cannot prove rollback.
        do {
            try Task.checkCancellation()
            try validate(response, limit: 2 * 1024 * 1024)
            return try verifyEnvelope(response.data, context: context)
        } catch {
            if mutation && (response.status >= 500 || response.status == 200) { throw NativeReaderOperationFailure.unknownEffect }
            throw error
        }
    }

    func subscription(fields: [String: Any], context: NativeReaderRequestContext) throws -> AsyncThrowingStream<Data, Error> {
        network.stream(try request(path: "api/native-chat", fields: payload(fields, context: context)))
    }

    func asset(_ asset: NativeReaderAsset, context: NativeReaderRequestContext) async throws -> Data {
        try check(context)
        guard accepted?.assets.contains(asset) == true, asset.byteCount <= 16 * 1024 * 1024 else { throw NativeReaderContractError.wrongTarget }
        let response = try await network.send(request(path: "api/native-assets/" + asset.id, fields: fields(context), get: true), asset.byteCount)
        try check(context)
        guard response.status == 200, response.headers["content-type"] == asset.mime, response.data.count == asset.byteCount,
              SHA256.hash(data: response.data).map({ String(format: "%02x", $0) }).joined() == asset.sha256 else {
            throw NativeReaderOperationFailure.rejected(code: "asset-digest")
        }
        return response.data
    }
}

/// NA06's profile-scoped composition seam. Re-resolve through ReaderManager on
/// reconnect; a new incarnation replaces only this view's transport/action adapters.
actor NativeReaderManagedClient: NativeReaderDocumentProviding {
    private static let revokeEditorConsentDidFinishLock = NSLock()
    nonisolated(unsafe) private static var revokeEditorConsentDidFinishStorage: (@Sendable () -> Void)?
    internal static var onRevokeEditorConsentDidFinish: (@Sendable () -> Void)? {
        get {
            revokeEditorConsentDidFinishLock.lock()
            defer { revokeEditorConsentDidFinishLock.unlock() }
            return revokeEditorConsentDidFinishStorage
        }
        set {
            revokeEditorConsentDidFinishLock.lock()
            defer { revokeEditorConsentDidFinishLock.unlock() }
            revokeEditorConsentDidFinishStorage = newValue
        }
    }
    private let resolver: NativeReaderManagedResolver
    private let root: String
    private let entry: String
    private let readerID: String?
    private let editor: NativeReaderManagedEditor?
    private var transport: NativeReaderTransport?
    private var actions: NativeReaderActions?
    private var pageTransport: NativeReaderOriginalPageTransport?
    private var epoch = 0
    private var disposed = false
    private var editorConsentRevoked = false

    init(resolver: NativeReaderManagedResolver, root: String, entry: String, readerID: String? = nil, editor: NativeReaderManagedEditor? = nil) {
        self.resolver = resolver; self.root = root; self.entry = entry; self.readerID = readerID; self.editor = editor
    }

    func target() async throws -> NativeDocumentIdentity {
        guard !disposed else { throw NativeReaderContractError.disposed }
        epoch += 1
        let current = epoch
        var (attachment, identity) = try await resolver.resolve(root: root, entry: entry, readerID: readerID,
            editor: transport == nil && !editorConsentRevoked ? editor : nil)
        guard !disposed, epoch == current else { await attachment.editorLease?.release(); throw NativeReaderContractError.staleGeneration }
        let replaced = transport?.attachment.serviceID != attachment.serviceID || transport?.attachment.baseURL != attachment.baseURL || transport?.attachment.documentID != attachment.documentID
        if replaced {
            // Existing attachments are service-bound. Register once per incarnation,
            // rather than leaking a registration on every readiness poll.
            if transport != nil, let editor, editor.consentID == nil {
                (attachment, identity) = try await resolver.resolve(root: root, entry: entry, readerID: readerID, editor: editor)
                guard !disposed, epoch == current else { await attachment.editorLease?.release(); throw NativeReaderContractError.staleGeneration }
            }
            let oldPages = pageTransport, oldTransport = transport
            await oldPages?.dispose()
            await oldTransport?.dispose()
            guard !disposed, epoch == current else { await attachment.editorLease?.release(); throw NativeReaderContractError.staleGeneration }
            let next = NativeReaderTransport(attachment: attachment, network: resolver.network)
            transport = next; actions = NativeReaderActions(transport: next)
            pageTransport = NativeReaderOriginalPageTransport(transport: next)
        }
        return identity
    }
    func document(for context: NativeReaderRequestContext) async throws -> NativeReaderDocument {
        guard !disposed, let transport else { throw NativeReaderOperationFailure.unavailable }
        return try await transport.document(for: context)
    }
    func originalPages(for context: NativeReaderRequestContext) async throws -> NativeOriginalPageDelivery {
        guard !disposed, let pageTransport else { throw NativeReaderOperationFailure.unavailable }
        return try await pageTransport.pages(for: context)
    }
    func currentActions() throws -> NativeReaderActions {
        guard !disposed, let actions else { throw NativeReaderOperationFailure.unavailable }
        return actions
    }
    func revokeEditorConsent() async {
        defer {
            let onFinish = Self.onRevokeEditorConsentDidFinish
            onFinish?()
        }
        guard !editorConsentRevoked, editor?.consentID != nil else { return }
        editorConsentRevoked = true; epoch += 1
        if let transport { await transport.revokeEditorConsent() }
        else { _ = await resolver.retryEditorCleanup(root: root, entry: entry, readerID: readerID) }
    }
    func invalidate() async {
        epoch += 1
        let pages = pageTransport, document = transport
        await pages?.invalidate(); await document?.invalidate()
    }
    func dispose() async {
        disposed = true; epoch += 1
        let pages = pageTransport, document = transport
        await pages?.dispose(); await document?.dispose()
        if document == nil { _ = await resolver.retryEditorCleanup(root: root, entry: entry, readerID: readerID) }
    }
}
