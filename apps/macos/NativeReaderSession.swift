import Foundation

/// Per-view coordination over one injected common store. Preparation does not
/// publish; the synchronous adopter owns store adoption and body installation.
@MainActor final class NativeReaderSession {
    enum State: Equatable { case idle, loading, reading, offline, sleeping, disposed }
    enum Event { case sleep, wake, network(Bool), power(constrained: Bool), dispose }

    struct PreparedAdoption {
        // Check the exact current layout/cache key immediately before adoption.
        let isCurrent: @MainActor () throws -> Bool
        // Must either throw before publication or atomically adopt + install.
        // NA02 TextView.adopt supplies this operation; no await is permitted here.
        let adopt: @MainActor () throws -> Void
    }
    typealias Prepare = @MainActor (NativeReaderDocument, NativeReaderRequestContext) async throws -> PreparedAdoption

    let store: NativeReaderDocumentStore
    private(set) var state: State = .idle
    private(set) var context: NativeReaderRequestContext?
    private(set) var restoration = NativeReaderRestoration.initial
    private(set) var failure: String?
    private(set) var isReadOnly = true
    // Read-only after a transport failure is not an offline snapshot. The
    // session alone owns whether the accepted/pending content came from recovery.
    private(set) var isRecoveredCopy = false
    var hasPendingRecovery: Bool { pending?.restoration != nil }
    var hasRecoveryCopy: Bool { isRecoveredCopy || pending?.restoration != nil }
    var onChange: (() -> Void)?
    var onSelection: ((NativeReaderSelection?, NativeReaderRequestContext) -> Void)?
    private let provider: NativeReaderDocumentProviding
    private let target: () async throws -> NativeDocumentIdentity
    private let invalidate: () async -> Void
    private let wait: (UInt64) async throws -> Void
    private let prepare: Prepare
    private var task: Task<Void, Never>?
    private var invalidationTask: Task<Void, Never>?
    private struct Candidate {
        let document: NativeReaderDocument
        let context: NativeReaderRequestContext
        let restoration: NativeReaderRestoration?
        // Explicit per-candidate operations retain validated recovery inputs
        // across a hold/retry without changing live transport policy.
        var preparation: Prepare? = nil
        var didAdopt: (@MainActor (NativeReaderDocument) -> Void)? = nil
    }
    private var pending: Candidate?
    // Correlates NA02's selectionReleased callback after that same store was
    // cleared by the view. Selected fragments/authority remain only in store.
    private var observedSelectionTicket: UUID?
    private var pageSelectionHeld = false
    var hasSelection: Bool { store.selection != nil || pageSelectionHeld }
    func holdOriginalPageSelection(_ held: Bool) {
        guard state != .disposed else { return }
        pageSelectionHeld = held
        if !held { preparationChanged() }
    }
    private var online = true
    private var constrained = false
    private var attempts = 0
    private var epoch = 0

    init(store: NativeReaderDocumentStore, provider: NativeReaderDocumentProviding,
         target: @escaping () async throws -> NativeDocumentIdentity,
         invalidate: @escaping () async -> Void = {},
         wait: @escaping (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) },
         prepare: Prepare? = nil) {
        self.store = store
        self.provider = provider; self.target = target; self.invalidate = invalidate; self.wait = wait
        self.prepare = prepare ?? { document, context in
            PreparedAdoption(isCurrent: { true }, adopt: { try store.adopt(document, for: context) })
        }
        observedSelectionTicket = store.selection?.ticket
    }

    convenience init(viewID: UUID = UUID(), provider: NativeReaderDocumentProviding,
                     target: @escaping () async throws -> NativeDocumentIdentity,
                     invalidate: @escaping () async -> Void = {},
                     wait: @escaping (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) },
                     prepare: Prepare? = nil) {
        self.init(store: NativeReaderDocumentStore(viewID: viewID), provider: provider,
                  target: target, invalidate: invalidate, wait: wait, prepare: prepare)
    }

    private func check(_ expected: Int, generation: Int, offline: Bool = false) throws {
        try Task.checkCancellation()
        guard epoch == expected, state != .disposed, !store.isDisposed else { throw NativeReaderContractError.disposed }
        guard state != .sleeping, offline || online, store.generation == generation else {
            throw NativeReaderContractError.staleGeneration
        }
    }

    private func validate(_ candidate: Candidate) throws {
        guard candidate.context.viewID == store.viewID, candidate.context.target == candidate.document.identity else {
            throw NativeReaderContractError.wrongTarget
        }
        guard candidate.document.generation == candidate.context.generation,
              candidate.context.generation == store.generation else { throw NativeReaderContractError.staleGeneration }
        try candidate.document.validate()
    }

    func refresh() {
        guard state != .disposed, state != .sleeping, online else { return }
        task?.cancel(); epoch += 1; pending = nil
        let currentEpoch = epoch
        let generation: Int
        do { generation = try store.beginRequest() } catch { return }
        state = .loading; failure = nil
        onChange?()
        task = Task { [weak self] in
            guard let self else { return }
            var receivedCandidate = false
            do {
                await invalidationTask?.value
                try check(currentEpoch, generation: generation)
                if attempts > 0 {
                    try await wait(UInt64(constrained ? 4 : 1) * 1_000_000_000 * UInt64(attempts))
                    try check(currentEpoch, generation: generation)
                }
                let identity = try await target()
                try check(currentEpoch, generation: generation)
                let request = NativeReaderRequestContext(requestID: UUID(), viewID: store.viewID, generation: generation, target: identity)
                let document = try await provider.document(for: request)
                try check(currentEpoch, generation: generation)
                receivedCandidate = true
                let candidate = Candidate(document: document, context: request, restoration: nil)
                try validate(candidate)
                pending = candidate; attempts = 0
                try await publishPending(epoch: currentEpoch)
                try check(currentEpoch, generation: generation)
            } catch {
                guard epoch == currentEpoch, !Task.isCancelled, state != .disposed, state != .sleeping else { return }
                fail()
                // Only transport recovery retries the request. Preparation/adopter
                // failure retains the newest candidate for an explicit cache retry.
                if !receivedCandidate && online && attempts < 3 { attempts += 1; refresh() }
            }
        }
    }

    private func heldState() {
        state = isReadOnly || pending?.restoration != nil ? .offline : .reading
        onChange?()
    }

    private func publishPending(epoch expected: Int) async throws {
        guard let candidate = pending else { return }
        let offline = candidate.restoration != nil
        try check(expected, generation: candidate.context.generation, offline: offline)
        try validate(candidate)
        guard !hasSelection else { heldState(); return }
        // A resize without a notification can still invalidate a prepared key.
        // Retry with the latest key, retaining the candidate if churn is bounded out.
        for _ in 0..<4 {
            let prepared = try await (candidate.preparation ?? prepare)(candidate.document, candidate.context)
            try check(expected, generation: candidate.context.generation, offline: offline)
            guard pending?.context == candidate.context else { throw NativeReaderContractError.staleGeneration }
            try validate(candidate)
            guard !hasSelection else { heldState(); return }
            guard try prepared.isCurrent() else { continue }
            try check(expected, generation: candidate.context.generation, offline: offline)
            try prepared.adopt()
            // Returning from a hook is not proof of publication or readiness.
            try check(expected, generation: candidate.context.generation, offline: offline)
            guard store.document == candidate.document, store.selection == nil else {
                throw NativeReaderOperationFailure.rejected(code: "adoption-not-published")
            }
            context = candidate.context
            isReadOnly = offline; isRecoveredCopy = offline
            if let value = candidate.restoration {
                restoration = value
                if let ticket = value.selectionTicket {
                    try hold(NativeReaderSelection(ticket: ticket, fragments: value.fragments.map {
                        NativeReaderSelection.Fragment(blockID: $0.blockID, rangeUTF16: $0.start..<$0.end, exact: $0.exact)
                    }))
                }
            }
            pending = nil; state = offline ? .offline : .reading; failure = nil
            candidate.didAdopt?(candidate.document) // Consumed exactly once, after actual publication and selection restoration.
            onChange?()
            return
        }
        throw NativeReaderOperationFailure.rejected(code: "preparation-key-changed")
    }

    /// Layout/font/zoom/theme/cache changes revoke only obsolete preparation,
    /// retaining the latest candidate. Also retries a failed preparation/adopter.
    func preparationChanged() {
        guard state != .disposed, state != .sleeping, let candidate = pending,
              candidate.restoration != nil || online else { return }
        task?.cancel(); epoch += 1
        let current = epoch
        if hasSelection { heldState(); return }
        state = .loading; failure = nil; onChange?()
        task = Task { [weak self] in
            guard let self else { return }
            do {
                try await publishPending(epoch: current)
                try check(current, generation: candidate.context.generation, offline: candidate.restoration != nil)
            } catch {
                guard epoch == current, !Task.isCancelled, state != .disposed, state != .sleeping else { return }
                fail()
            }
        }
    }

    func hold(_ selection: NativeReaderSelection) throws {
        try store.holdSelection(selection)
        observedSelectionTicket = selection.ticket
        if let context { onSelection?(selection, context) }
    }

    /// Explicit user selection-release ONLY, never a source/copy/network ack.
    /// NA02 may have already cleared this same store before selectionReleased.
    func acknowledge(ticket: UUID) {
        guard state != .disposed else { return }
        if let selected = store.selection {
            guard selected.ticket == ticket else { return }
            store.releaseSelection(ticket: ticket)
        } else {
            guard observedSelectionTicket == ticket else { return }
        }
        observedSelectionTicket = nil
        if let context { onSelection?(nil, context) }
        preparationChanged()
        onChange?()
    }

    func authorize(_ request: NativeReaderRequestContext, selection ticket: UUID? = nil) throws {
        guard !isReadOnly, state == .reading, pending == nil, context == request,
              store.document?.identity == request.target, store.document?.generation == request.generation,
              store.generation == request.generation,
              ticket == nil || store.selection?.ticket == ticket else { throw NativeReaderContractError.staleGeneration }
    }

    func saveRestoration(_ value: NativeReaderRestoration) throws {
        guard let document = store.document else { throw NativeReaderOperationFailure.unavailable }
        try value.validate(in: document)
        restoration = value
    }

    /// Recovery uses the identical preparation/adopter path and stays read-only,
    /// even after successful publication. A held replacement awaits explicit release.
    func restore(_ snapshot: NativeReaderRecoverySnapshot, matching identity: NativeDocumentIdentity, prepare restorationPrepare: Prepare? = nil, didAdopt: (@MainActor (NativeReaderDocument) -> Void)? = nil) async throws {
        guard state != .disposed, state != .sleeping, snapshot.document.identity == identity else { throw NativeReaderContractError.wrongTarget }
        try snapshot.validate()
        task?.cancel(); epoch += 1
        let current = epoch
        let generation = try store.beginRequest()
        let document = snapshot.document
        let candidate = document.rebinding(generation: generation)
        let request = NativeReaderRequestContext(requestID: UUID(), viewID: store.viewID, generation: generation, target: identity)
        pending = Candidate(document: candidate, context: request, restoration: snapshot.restoration, preparation: restorationPrepare, didAdopt: didAdopt)
        isReadOnly = true; state = .loading; failure = nil; onChange?()
        do {
            await invalidationTask?.value
            try check(current, generation: generation, offline: true)
            try await publishPending(epoch: current)
            try check(current, generation: generation, offline: true)
        } catch {
            // A layout retry owns this same candidate now. The original await
            // is not its completion; keep the candidate-local completion alive.
            if epoch != current, pending?.context == request { return }
            if context == request, store.document == candidate, isRecoveredCopy { return }
            if epoch == current, state != .disposed, state != .sleeping { fail() }
            throw error
        }
    }

    private func fail() {
        state = .offline; isReadOnly = true
        failure = "Reader unavailable; accepted content is read-only."
        onChange?()
    }

    func cancel() {
        guard state != .disposed else { return }
        task?.cancel(); task = nil; epoch += 1; pending = nil; store.cancel()
        isReadOnly = true; state = .offline
        let previous = invalidationTask, invalidate = self.invalidate
        invalidationTask = Task { await previous?.value; await invalidate() }
        onChange?()
    }

    func event(_ event: Event) {
        guard state != .disposed else { return }
        switch event {
        case .power(let value): constrained = value; return
        case .wake: state = .offline; attempts = 0; refresh(); return
        case .network(true):
            if online && state == .loading { return }
            online = true; attempts = 0; refresh(); return
        case .sleep: state = .sleeping
        case .network(false):
            guard online else { return }
            online = false
            guard state != .sleeping else { return }
            state = .offline
        case .dispose: state = .disposed; store.dispose()
        }
        task?.cancel(); task = nil; epoch += 1; pending = nil
        if state != .disposed { store.cancel() }
        isReadOnly = true
        let previous = invalidationTask, invalidate = self.invalidate
        invalidationTask = Task { await previous?.value; await invalidate() }
        onChange?()
    }

    deinit { task?.cancel() }
}
