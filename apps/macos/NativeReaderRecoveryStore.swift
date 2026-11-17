import Foundation
import CryptoKit
import Darwin

struct NativeReaderRestoration: Codable, Equatable {
    struct Fragment: Codable, Equatable {
        let blockID: String
        let start: Int
        let end: Int
        let exact: String
    }
    let blockID: String?
    let offset: Double
    let zoom: Double
    let selectionTicket: UUID?
    let fragments: [Fragment]

    static let initial = Self(blockID: nil, offset: 0, zoom: 1, selectionTicket: nil, fragments: [])
    func validate(in document: NativeReaderDocument) throws {
        guard offset.isFinite, offset >= 0, offset <= 1, zoom.isFinite, (0.5...4).contains(zoom),
              blockID == nil || document.blocks.contains(where: { $0.id == blockID }), fragments.count <= 32, fragments.allSatisfy({ $0.start >= 0 && $0.end > $0.start }) else {
            throw NativeReaderContractError.invalidDocument
        }
        if let ticket = selectionTicket {
            try NativeReaderSelection(ticket: ticket, fragments: fragments.map {
                NativeReaderSelection.Fragment(blockID: $0.blockID, rangeUTF16: $0.start..<$0.end, exact: $0.exact)
            }).validate(in: document)
        } else if !fragments.isEmpty { throw NativeReaderContractError.invalidSelection }
    }
}

struct NativeReaderRecoveredDraft: Codable {
    let conversationID: UUID
    let version: Int
    let text: String
    let pendingMessageID: UUID?
    var model: String? = nil
    // Original uncertain Send, independently of an edited local composer draft.
    // Optional fields preserve decoding of schema-1 snapshots written before this addition.
    var pendingQuestion: String? = nil
    var pendingModel: String? = nil
}

struct NativeReaderRecoverySnapshot: Codable {
    let document: NativeReaderDocument
    let assets: [String: Data]
    let restoration: NativeReaderRestoration
    let drafts: [NativeReaderRecoveredDraft]
    var reviewMarks: [NativeReaderReviewMark] = []

    func validate() throws {
        try document.validate()
        try restoration.validate(in: document)
        guard reviewMarks.count <= 256 else { throw NativeReaderContractError.invalidDocument }
        for mark in reviewMarks { try mark.validate(in: document) }
        guard assets.count == document.assets.count, drafts.count <= 128,
              Set(drafts.map(\.conversationID)).count == drafts.count,
              drafts.allSatisfy({ $0.version >= 0 && $0.text.count <= 8000 && ($0.model?.count ?? 0) <= 120 &&
                  ($0.pendingQuestion?.count ?? 0) <= 8000 && ($0.pendingModel?.count ?? 0) <= 120 &&
                  ($0.pendingMessageID != nil || ($0.pendingQuestion == nil && $0.pendingModel == nil)) }),
              assets.values.reduce(0, { $0 + $1.count }) <= 64 * 1024 * 1024 else { throw NativeReaderContractError.invalidDocument }
        for asset in document.assets {
            guard let data = assets[asset.id], data.count == asset.byteCount, data.count <= 16 * 1024 * 1024,
                  Self.digest(data) == asset.sha256 else { throw NativeReaderContractError.invalidDocument }
        }
    }
    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}

/// Only typed accepted content and bounded composer recovery. No source excerpts,
/// browser storage, provider headers, credentials or account state are serializable here.
actor NativeReaderRecoveryStore {
    private struct Envelope: Codable { let schema: Int; let sha256: String; let payload: Data }
    let root: URL
    static let limit = 128 * 1024 * 1024
    init(root: URL) { self.root = root.standardizedFileURL }

    private func directory() throws {
        guard root.isFileURL, root.path != "/" else { throw NativeReaderOperationFailure.unavailable }
        var path = URL(fileURLWithPath: "/")
        for part in root.pathComponents.dropFirst() {
            path.appendPathComponent(part)
            var info = stat()
            if lstat(path.path, &info) == 0 {
                guard info.st_mode & S_IFMT == S_IFDIR else { throw NativeReaderOperationFailure.rejected(code: "recovery-symlink") }
            } else if errno == ENOENT {
                guard mkdir(path.path, 0o700) == 0 else { throw NativeReaderOperationFailure.unavailable }
            } else { throw NativeReaderOperationFailure.unavailable }
        }
        guard chmod(root.path, 0o700) == 0 else { throw NativeReaderOperationFailure.unavailable }
    }

    private func file(_ identity: NativeDocumentIdentity) -> URL {
        root.appendingPathComponent(NativeReaderRecoverySnapshot.digest(Data(identity.documentID.utf8)) + ".json")
    }

    func save(_ snapshot: NativeReaderRecoverySnapshot) throws {
        try Task.checkCancellation()
        try snapshot.validate()
        try directory()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let payload = try encoder.encode(snapshot)
        let data = try encoder.encode(Envelope(schema: 1, sha256: NativeReaderRecoverySnapshot.digest(payload), payload: payload))
        guard data.count <= Self.limit else { throw NativeReaderOperationFailure.rejected(code: "recovery-limit") }
        let destination = file(snapshot.document.identity)
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.fileSizeKey])
            .filter { $0.lastPathComponent.range(of: "^[0-9a-f]{64}\\.json$", options: .regularExpression) != nil && $0 != destination }
        let total = try files.reduce(0) { try $0 + ($1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }
        guard files.count < 8, total + data.count <= 256 * 1024 * 1024 else { throw NativeReaderOperationFailure.rejected(code: "recovery-budget") }
        let temporary = root.appendingPathComponent(".snapshot-" + UUID().uuidString)
        let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw NativeReaderOperationFailure.unavailable }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close(); unlink(temporary.path) }
        try handle.write(contentsOf: data)
        try handle.synchronize()
        try Task.checkCancellation()
        guard rename(temporary.path, destination.path) == 0 else { throw NativeReaderOperationFailure.unavailable }
        let directoryFD = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        if directoryFD >= 0 { _ = fsync(directoryFD); close(directoryFD) }
    }

    func load(identity: NativeDocumentIdentity) throws -> NativeReaderRecoverySnapshot {
        try directory()
        let fd = open(file(identity).path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw NativeReaderOperationFailure.unavailable }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_size > 0,
              info.st_size <= Self.limit else { throw NativeReaderOperationFailure.rejected(code: "recovery-limit") }
        let data = try handle.read(upToCount: Self.limit + 1) ?? Data()
        guard data.count <= Self.limit else { throw NativeReaderOperationFailure.rejected(code: "recovery-limit") }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard envelope.schema == 1, NativeReaderRecoverySnapshot.digest(envelope.payload) == envelope.sha256 else { throw NativeReaderContractError.invalidDocument }
        let snapshot = try JSONDecoder().decode(NativeReaderRecoverySnapshot.self, from: envelope.payload)
        guard snapshot.document.identity == identity else { throw NativeReaderContractError.wrongTarget }
        try snapshot.validate()
        return snapshot
    }
}

struct NativeReaderReviewMark: Codable {
    let id: UUID
    let identity: NativeDocumentIdentity
    let selection: NativeReaderRestoration
    func validate(in document: NativeReaderDocument) throws {
        guard identity == document.identity, selection.selectionTicket != nil else { throw NativeReaderContractError.wrongTarget }
        try selection.validate(in: document)
    }
}

/// Native-local review paint. No browser migration and no source operation.
@MainActor final class NativeReaderLocalReview {
    private(set) var marks: [NativeReaderReviewMark] = []
    var paint: (([NativeReaderReviewMark]) -> Void)?
    func add(_ mark: NativeReaderReviewMark, document: NativeReaderDocument) throws {
        try mark.validate(in: document)
        guard marks.count < 256, !marks.contains(where: { $0.id == mark.id }),
              marks.allSatisfy({ $0.identity == document.identity }) else { throw NativeReaderOperationFailure.rejected(code: "review-limit") }
        marks.append(mark); paint?(marks)
    }
    func undo() { if !marks.isEmpty { marks.removeLast(); paint?(marks) } }
    func clear() { marks.removeAll(); paint?(marks) }
}
