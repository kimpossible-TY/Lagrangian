import Foundation

/// Main-thread publication policy. Network/process/storage work remains asynchronous
/// and injected. It never stops an engine or a shared ReaderManager service.
@MainActor final class NativeReaderSession {
    enum State: Equatable { case idle, loading, reading, offline, sleeping, disposed }
    enum Event { case sleep, wake, network(Bool), power(constrained: Bool), dispose }
    let store: NativeReaderDocumentStore
    private(set) var state: State = .idle
    private(set) var context: NativeReaderRequestContext?
    private(set) var restoration = NativeReaderRestoration.initial
    private(set) var failure: String?
    var onChange: (() -> Void)?
    var onSelection: ((NativeReaderSelection?, NativeReaderRequestContext) -> Void)?
    private let provider: NativeReaderDocumentProviding
    private let target: () async throws -> NativeDocumentIdentity
    private let invalidate: () async -> Void
    private let wait: (UInt64) async throws -> Void
    private var task: Task<Void, Never>?
    private var invalidationTask: Task<Void, Never>?
    private var pending: (NativeReaderDocument, NativeReaderRequestContext)?
    private var online = true
    private var constrained = false
    private var attempts = 0
    private var epoch = 0

    init(viewID: UUID = UUID(), provider: NativeReaderDocumentProviding,
         target: @escaping () async throws -> NativeDocumentIdentity,
         invalidate: @escaping () async -> Void = {},
         wait: @escaping (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }) {
        store = NativeReaderDocumentStore(viewID: viewID)
        self.provider = provider; self.target = target; self.invalidate = invalidate; self.wait = wait
    }

    func refresh() {
        guard state != .disposed, state != .sleeping, online else { return }
        task?.cancel()
        epoch += 1
        let currentEpoch = epoch
        let generation: Int
        do { generation = try store.beginRequest() } catch { return }
        state = .loading
        failure = nil
        onChange?()
        task = Task { [weak self] in
            guard let self else { return }
            do {
                await invalidationTask?.value
                if attempts > 0 { try await wait(UInt64(constrained ? 4 : 1) * 1_000_000_000 * UInt64(attempts)) }
                try Task.checkCancellation()
                let identity = try await target()
                let request = NativeReaderRequestContext(requestID: UUID(), viewID: store.viewID, generation: generation, target: identity)
                let document = try await provider.document(for: request)
                try Task.checkCancellation()
                guard epoch == currentEpoch, state != .disposed, state != .sleeping, online else { return }
                do { try store.adopt(document, for: request); context = request }
                catch NativeReaderContractError.selectionHeld { pending = (document, request) }
                attempts = 0; state = .reading; failure = nil
                onChange?()
            } catch {
                guard epoch == currentEpoch, !Task.isCancelled, state != .disposed, state != .sleeping else { return }
                // Accepted content, current selection and drafts survive every failure.
                state = .offline; failure = "Reader unavailable; accepted content is read-only."
                onChange?()
                if online && attempts < 3 { attempts += 1; refresh() }
            }
        }
    }

    func hold(_ selection: NativeReaderSelection) throws {
        try store.holdSelection(selection)
        if let context { onSelection?(selection, context) }
    }

    func acknowledge(ticket: UUID) {
        store.releaseSelection(ticket: ticket)
        guard store.selection == nil else { return }
        if let next = pending {
            do { try store.adopt(next.0, for: next.1); context = next.1; pending = nil }
            catch { pending = nil }
        }
        if let context { onSelection?(nil, context) }
        onChange?()
    }

    func authorize(_ request: NativeReaderRequestContext, selection ticket: UUID? = nil) throws {
        guard state == .reading, pending == nil, context == request, store.generation == request.generation,
              ticket == nil || store.selection?.ticket == ticket else { throw NativeReaderContractError.staleGeneration }
    }

    func saveRestoration(_ value: NativeReaderRestoration) throws {
        guard let document = store.document else { throw NativeReaderOperationFailure.unavailable }
        try value.validate(in: document)
        restoration = value
    }

    func restore(_ snapshot: NativeReaderRecoverySnapshot, matching identity: NativeDocumentIdentity) throws {
        guard state != .disposed, snapshot.document.identity == identity else { throw NativeReaderContractError.wrongTarget }
        try snapshot.validate()
        task?.cancel(); epoch += 1
        let generation = try store.beginRequest()
        let document = snapshot.document
        let candidate = NativeReaderDocument(schemaVersion: document.schemaVersion, identity: document.identity, generation: generation,
            requiredCapabilities: document.requiredCapabilities, blocks: document.blocks, assets: document.assets, diagnostics: document.diagnostics)
        let request = NativeReaderRequestContext(requestID: UUID(), viewID: store.viewID, generation: generation, target: identity)
        try store.adopt(candidate, for: request)
        restoration = snapshot.restoration; context = request; state = .offline
        if let ticket = restoration.selectionTicket {
            try store.holdSelection(NativeReaderSelection(ticket: ticket, fragments: restoration.fragments.map {
                NativeReaderSelection.Fragment(blockID: $0.blockID, rangeUTF16: $0.start..<$0.end, exact: $0.exact)
            }))
        }
        onChange?()
    }

    func event(_ event: Event) {
        guard state != .disposed else { return }
        switch event {
        case .power(let value): constrained = value; return
        case .wake: state = .offline; attempts = 0; refresh(); return
        case .network(true): online = true; attempts = 0; refresh(); return
        case .sleep: state = .sleeping
        case .network(false): online = false; state = .offline
        case .dispose: state = .disposed; store.dispose()
        }
        task?.cancel(); task = nil; epoch += 1; pending = nil
        if state != .disposed { store.cancel() }
        let invalidate = self.invalidate
        invalidationTask = Task { await invalidate() }
        onChange?()
    }

    deinit { task?.cancel() }
}
