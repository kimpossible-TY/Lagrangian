import Foundation

// Candidate adapter contract. NA04 supplies transport over existing guarded owners.
struct NativeReaderRequestContext: Equatable {
    let requestID: UUID
    let viewID: UUID
    let generation: Int
    let target: NativeDocumentIdentity
}

struct NativeReaderSelection: Equatable {
    struct Fragment: Equatable {
        let blockID: String
        let rangeUTF16: Range<Int>
        let exact: String
    }
    let ticket: UUID
    let fragments: [Fragment]

    init(ticket: UUID, fragments: [Fragment]) {
        self.ticket = ticket
        self.fragments = fragments
    }

    init(ticket: UUID, blockID: String, rangeUTF16: Range<Int>, exact: String) {
        self.init(ticket: ticket, fragments: [Fragment(blockID: blockID, rangeUTF16: rangeUTF16, exact: exact)])
    }

    func validate(in document: NativeReaderDocument) throws {
        guard (1...32).contains(fragments.count) else { throw NativeReaderContractError.invalidSelection }
        try validateLocal(in: document)
    }

    /// Display selection and hold may cover the entire accepted document. The
    /// remote source/chat limit remains exclusively in validate(in:).
    func validateLocal(in document: NativeReaderDocument) throws {
        guard !fragments.isEmpty, fragments.count <= document.blocks.count else { throw NativeReaderContractError.invalidSelection }
        let indexes = Dictionary(document.blocks.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
        var previous = -1
        for fragment in fragments {
            guard let index = indexes[fragment.blockID], index > previous else {
                throw NativeReaderContractError.invalidSelection
            }
            let block = document.blocks[index], units = fragment.rangeUTF16
            guard !units.isEmpty, block.graphemeBoundariesUTF16.contains(units.lowerBound),
                  block.graphemeBoundariesUTF16.contains(units.upperBound),
                  let range = Range(NSRange(location: units.lowerBound, length: units.count), in: block.displayText),
                  Array(block.displayText[range].unicodeScalars) == Array(fragment.exact.unicodeScalars) else {
                throw NativeReaderContractError.invalidSelection
            }
            previous = index
        }
    }
}

protocol NativeReaderDocumentProviding {
    func document(for context: NativeReaderRequestContext) async throws -> NativeReaderDocument
}

enum NativeReaderSourceAction { case excerpt, locate, highlight }
struct NativeReaderSourceRequest {
    let context: NativeReaderRequestContext
    let selection: NativeReaderSelection
    let action: NativeReaderSourceAction
    // Stable receipt ID for highlight; a cancelled in-flight mutation is unknown.
    let receiptID: UUID
}
struct NativeReaderSourceResult {
    enum Status { case verified, unmapped, ambiguous, stale, unsupported, uncertain, rejected }
    let context: NativeReaderRequestContext
    let selectionTicket: UUID
    let status: Status
    let verifiedText: String? // Only excerpt owner's response; never reconstructed Typst.
    let destinationAnchor: String? // Opaque accepted anchor; never arbitrary paths.
}
protocol NativeReaderSourceOperations {
    func perform(_ request: NativeReaderSourceRequest) async throws -> NativeReaderSourceResult
}

/// A mapping result is never an editor effect receipt. No coordinates or private
/// registration details enter this DTO or its accessible feedback.
struct NativeReaderEditorReceipt {
    enum Status: String { case jumped, modified, stale, unmapped, ambiguous, refused, error, unknown, unavailable }
    let context: NativeReaderRequestContext
    let selectionTicket: UUID
    let receiptID: UUID
    let status: Status
    var feedback: String {
        switch status {
        case .jumped: return "Editor moved to the verified saved source."
        case .modified: return "Editor has unsaved changes. Save explicitly and select again."
        case .stale: return "Source, selection or editor lifetime changed. Select again after reconnecting."
        case .unmapped: return "No verified source mapping is available."
        case .ambiguous: return "Source mapping is ambiguous."
        case .refused: return "Editor request was refused."
        case .error: return "Editor refused the move."
        case .unknown: return "Editor effect is unknown. Check Editor Result; do not repeat the move."
        case .unavailable: return "No explicitly connected editor is available. Use Connect Editor in the app menu."
        }
    }
}

struct NativeReaderChatState {
    let context: NativeReaderRequestContext
    let conversationID: UUID
    let version: Int
    let sequence: Int
    let messages: [Message]
    /// Exact accepted user content plus UUID, shared by adapter and UI recovery.
    func confirmsUserMessage(_ id: UUID, question: String) -> Bool {
        messages.contains { $0.id == id && $0.role == .user &&
            Array($0.markdown.unicodeScalars) == Array(question.unicodeScalars) }
    }
    struct Message {
        enum Role { case user, assistant }
        let id: UUID
        let role: Role
        let markdown: String
        let complete: Bool
    }
}
enum NativeReaderChatCommand {
    case open(NativeReaderSelection)
    case draft(conversation: UUID, version: Int, text: String)
    case send(conversation: UUID, version: Int, message: UUID, question: String, model: String)
    case cancel(conversation: UUID)
}
protocol NativeReaderChatOperations {
    func perform(_ command: NativeReaderChatCommand, context: NativeReaderRequestContext) async throws -> NativeReaderChatState
    func observe(conversation: UUID, context: NativeReaderRequestContext) -> AsyncThrowingStream<NativeReaderChatState, Error>
}

enum NativeReaderOperationFailure: Error {
    // Codes are bounded/sanitized by the adapter, never arbitrary server exceptions.
    case rejected(code: String), unavailable, unsupported, cancelledBeforeDispatch, unknownEffect
}

// This owns only local candidate adoption. It never replaces server freshness checks.
@MainActor final class NativeReaderDocumentStore {
    let viewID: UUID
    init(viewID: UUID = UUID()) { self.viewID = viewID }

    private(set) var document: NativeReaderDocument?
    private(set) var generation = 0
    private(set) var selection: NativeReaderSelection?
    private(set) var isDisposed = false

    @discardableResult func beginRequest() throws -> Int {
        guard !isDisposed else { throw NativeReaderContractError.disposed }
        generation += 1
        return generation
    }

    func adopt(_ candidate: NativeReaderDocument, for context: NativeReaderRequestContext) throws {
        guard !isDisposed else { throw NativeReaderContractError.disposed }
        guard context.generation == generation, candidate.generation == generation else {
            throw NativeReaderContractError.staleGeneration
        }
        guard context.viewID == viewID, candidate.identity == context.target else { throw NativeReaderContractError.wrongTarget }
        try candidate.validate()
        guard selection == nil else { throw NativeReaderContractError.selectionHeld }
        document = candidate
    }

    func holdSelection(_ selection: NativeReaderSelection) throws {
        guard !isDisposed else { throw NativeReaderContractError.disposed }
        guard let document = document else { throw NativeReaderContractError.invalidSelection }
        try selection.validateLocal(in: document)
        self.selection = selection
    }

    // Late acknowledgments must not clear the user's newer selection.
    func releaseSelection(ticket: UUID) {
        if selection?.ticket == ticket { selection = nil }
    }

    func cancel() { generation += 1 }
    func dispose() { cancel(); isDisposed = true; selection = nil }
}
