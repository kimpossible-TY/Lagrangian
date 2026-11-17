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
        })
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

    init(data: Data) throws {
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
    }
}

struct NativeReaderManagedEditor {
    let address: String
    let executable: String
    let ownerPID: Int
    let controlFile: String
}

struct NativeReaderManagedResolver {
    /// Supply an asynchronous bounded runner for the installed manage.py. No shell or preview-port probing.
    var attach: ([String]) async throws -> Data
    var network: NativeReaderNetwork

    func resolve(root: String, entry: String, readerID: String? = nil, editor: NativeReaderManagedEditor? = nil) async throws -> (NativeReaderAttachment, NativeDocumentIdentity) {
        var args = ["--attach", "--root", root, "--entry", entry]
        if let id = readerID { args += ["--reader-service", id] }
        if let editor {
            args += ["--editor-server", editor.address, "--nvim", editor.executable,
                     "--owner-pid", String(editor.ownerPID), "--control-file", editor.controlFile]
        }
        let attachment = try NativeReaderAttachment(data: await attach(args))
        var request = URLRequest(url: attachment.baseURL.appendingPathComponent("api/state"))
        request.timeoutInterval = 5
        let response = try await network.send(request, 1024 * 1024)
        guard response.status == 200, response.data.count <= 1024 * 1024,
              let object = try JSONSerialization.jsonObject(with: response.data) as? [String: Any],
              object["documentID"] as? String == attachment.documentID,
              let service = object["service"] as? [String: Int64], service == attachment.service,
              let revision = object["revision"] as? String,
              revision.range(of: "^[A-Za-z0-9_.:-]{1,128}$", options: .regularExpression) != nil else {
            throw NativeReaderContractError.wrongTarget
        }
        return (attachment, NativeDocumentIdentity(documentID: attachment.documentID,
            serviceID: attachment.serviceID, revision: revision, scope: .service))
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

    init(attachment: NativeReaderAttachment, network: NativeReaderNetwork) {
        self.attachment = attachment
        self.network = network
    }

    func invalidate() { active = nil }
    func dispose() { disposed = true; active = nil }

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
                "schemaVersion": 1, "capabilities": ["semantic-tree-v1"]]
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
        let response = try await network.send(request(path: "api/native-document", fields: fields, get: true), 32 * 1024 * 1024)
        try Task.checkCancellation()
        guard active == context, !disposed else { throw NativeReaderContractError.staleGeneration }
        try validate(response, limit: 32 * 1024 * 1024)
        guard let binding = response.headers["x-native-input-id"], binding.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else {
            throw NativeReaderOperationFailure.rejected(code: "input-binding")
        }
        guard let head = try JSONSerialization.jsonObject(with: response.data) as? [String: Any],
              head["schemaVersion"] as? Int == 1,
              head["requiredCapabilities"] as? [String] == ["semantic-tree-v1"],
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
    private let resolver: NativeReaderManagedResolver
    private let root: String
    private let entry: String
    private let readerID: String?
    private let editor: NativeReaderManagedEditor?
    private var transport: NativeReaderTransport?
    private var actions: NativeReaderActions?
    private var epoch = 0
    private var disposed = false

    init(resolver: NativeReaderManagedResolver, root: String, entry: String, readerID: String? = nil, editor: NativeReaderManagedEditor? = nil) {
        self.resolver = resolver; self.root = root; self.entry = entry; self.readerID = readerID; self.editor = editor
    }

    func target() async throws -> NativeDocumentIdentity {
        guard !disposed else { throw NativeReaderContractError.disposed }
        epoch += 1
        let current = epoch
        var (attachment, identity) = try await resolver.resolve(root: root, entry: entry, readerID: readerID, editor: transport == nil ? editor : nil)
        guard !disposed, epoch == current else { throw NativeReaderContractError.staleGeneration }
        let replaced = transport?.attachment.serviceID != attachment.serviceID || transport?.attachment.baseURL != attachment.baseURL || transport?.attachment.documentID != attachment.documentID
        if replaced {
            // Existing attachments are service-bound. Register once per incarnation,
            // rather than leaking a registration on every readiness poll.
            if transport != nil, editor != nil {
                (attachment, identity) = try await resolver.resolve(root: root, entry: entry, readerID: readerID, editor: editor)
                guard !disposed, epoch == current else { throw NativeReaderContractError.staleGeneration }
            }
            await transport?.dispose()
            guard !disposed, epoch == current else { throw NativeReaderContractError.staleGeneration }
            let next = NativeReaderTransport(attachment: attachment, network: resolver.network)
            transport = next; actions = NativeReaderActions(transport: next)
        }
        return identity
    }
    func document(for context: NativeReaderRequestContext) async throws -> NativeReaderDocument {
        guard !disposed, let transport else { throw NativeReaderOperationFailure.unavailable }
        return try await transport.document(for: context)
    }
    func currentActions() throws -> NativeReaderActions {
        guard !disposed, let actions else { throw NativeReaderOperationFailure.unavailable }
        return actions
    }
    func invalidate() async { epoch += 1; await transport?.invalidate() }
    func dispose() async { disposed = true; epoch += 1; await transport?.dispose() }
}
