import Foundation
import CryptoKit
import PDFKit
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

/// Optional full-PDF display recovery supplements the existing typed/atomic store.
/// No source anchors, credentials, service control or alternate disk owner.
struct NativeOriginalPageRecovery: Codable {
    let publication: NativeOriginalPagePublication
    let data: Data
    let viewport: NativeReaderOriginalPageView.Recovery
    func validate(document: NativeReaderDocument) throws {
        guard let view = UUID(uuidString: publication.viewID), let request = UUID(uuidString: publication.requestID) else { throw NativeOriginalPageError.binding }
        let context = NativeReaderRequestContext(requestID: request, viewID: view, generation: publication.generation, target: document.identity)
        try publication.validate(context: context)
        guard data.count == publication.byteCount,
              NativeReaderRecoverySnapshot.digest(data) == publication.pdfSHA256,
              viewport.identity == document.identity, viewport.fingerprint == publication.inputFingerprint,
              viewport.digest == publication.pdfSHA256, (0..<2048).contains(viewport.page),
              viewport.scale == nil || (viewport.scale!.isFinite && (0.1...8).contains(viewport.scale!)),
              [viewport.offsetX, viewport.offsetY].allSatisfy({ $0 == nil || ($0!.isFinite && (0...4096).contains($0!)) }) else { throw NativeOriginalPageError.binding }
    }
}

struct NativeReaderRecoverySnapshot: Codable {
    let document: NativeReaderDocument
    let assets: [String: Data]
    let restoration: NativeReaderRestoration
    let drafts: [NativeReaderRecoveredDraft]
    var reviewMarks: [NativeReaderReviewMark] = []
    var originalPages: NativeOriginalPageRecovery? = nil // Optional schema-1 default.

    func validate() throws {
        try document.validate()
        try restoration.validate(in: document)
        try originalPages?.validate(document: document)
        try NativeReaderReviewMark.validateCollection(reviewMarks, in: document)
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

    final class StagedPDF: @unchecked Sendable {
        private let directory: Int32
        private let temporary: String
        private let name: String
        private let previous: String?
        private let destination: URL
        private var committed = false
        private static func fingerprint(_ directory: Int32, _ name: String) throws -> String? {
            var info = stat()
            if fstatat(directory, name, &info, AT_SYMLINK_NOFOLLOW) != 0 {
                if errno == ENOENT { return nil }; throw NativeReaderOperationFailure.unavailable
            }
            guard info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1 else { throw NativeReaderOperationFailure.rejected(code: "export-destination") }
            return "\(info.st_dev):\(info.st_ino):\(info.st_size):\(info.st_mtimespec.tv_sec):\(info.st_mtimespec.tv_nsec)"
        }
        init(data: Data, destination: URL) throws {
            guard destination.isFileURL, destination.path.hasPrefix("/"), destination.pathExtension.lowercased() == "pdf",
                  destination.standardizedFileURL.path == destination.path else { throw NativeReaderOperationFailure.rejected(code: "export-destination") }
            var parent = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            guard parent >= 0 else { throw NativeReaderOperationFailure.unavailable }
            do {
                for part in destination.deletingLastPathComponent().pathComponents.dropFirst() {
                    let next = openat(parent, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
                    guard next >= 0 else { throw NativeReaderOperationFailure.rejected(code: "export-destination") }
                    close(parent); parent = next
                }
                let name = destination.lastPathComponent
                let previous = try Self.fingerprint(parent, name)
                let temporary = ".lagrangian-export-" + UUID().uuidString
                let fd = openat(parent, temporary, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
                guard fd >= 0 else { throw NativeReaderOperationFailure.unavailable }
                let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
                do {
                    defer { try? handle.close() }
                    try Task.checkCancellation(); try handle.write(contentsOf: data); try handle.synchronize()
                    try handle.seek(toOffset: 0)
                    let read = try handle.readToEnd() ?? Data()
                    guard read == data, let pdf = PDFDocument(data: read), !pdf.isEncrypted, !pdf.isLocked, (1...2048).contains(pdf.pageCount) else { throw NativeOriginalPageError.invalidPDF }
                    try Task.checkCancellation()
                } catch { unlinkat(parent, temporary, 0); throw error }
                self.destination = destination; self.directory = parent; self.temporary = temporary; self.name = name; self.previous = previous
            } catch { close(parent); throw error }
        }
        // Caller rechecks the accepted snapshot and operation immediately before
        // this synchronous atomic publication. No async window remains here.
        func commit() throws {
            try Task.checkCancellation()
            var checkDirectory = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            guard checkDirectory >= 0 else { throw NativeReaderOperationFailure.unavailable }
            defer { close(checkDirectory) }
            for part in destination.deletingLastPathComponent().pathComponents.dropFirst() {
                let next = openat(checkDirectory, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
                guard next >= 0 else { throw NativeReaderOperationFailure.rejected(code: "export-destination") }
                close(checkDirectory); checkDirectory = next
            }
            var oldDirectory = stat(), currentDirectory = stat()
            guard fstat(directory, &oldDirectory) == 0, fstat(checkDirectory, &currentDirectory) == 0,
                  oldDirectory.st_dev == currentDirectory.st_dev, oldDirectory.st_ino == currentDirectory.st_ino,
                  !committed, try Self.fingerprint(directory, name) == previous,
                  renameat(directory, temporary, directory, name) == 0 else { throw NativeReaderOperationFailure.rejected(code: "export-destination-changed") }
            committed = true; _ = fsync(directory)
        }
        deinit { if !committed { unlinkat(directory, temporary, 0) }; close(directory) }
    }
    nonisolated static func stageOriginalPDF(_ original: NativeOriginalPageRecovery, document: NativeReaderDocument, to destination: URL) throws -> StagedPDF {
        try Task.checkCancellation(); try original.validate(document: document)
        return try StagedPDF(data: original.data, destination: destination)
    }

    struct Entry: Equatable {
        let identity: NativeDocumentIdentity
        let title: String
    }

    /// Enumerate only this explicitly composed profile namespace. The identical
    /// typed envelope/hash/document validator serves both list and open.
    func list() throws -> [Entry] {
        try Task.checkCancellation()
        try directory()
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.fileSizeKey])
            .filter { $0.lastPathComponent.range(of: "^[0-9a-f]{64}\\.json$", options: .regularExpression) != nil }
        guard files.count <= 8 else { throw NativeReaderOperationFailure.rejected(code: "recovery-budget") }
        var bytes = 0, result = [Entry]()
        for url in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            try Task.checkCancellation()
            bytes += try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard bytes <= 256 * 1024 * 1024 else { throw NativeReaderOperationFailure.rejected(code: "recovery-budget") }
            let snapshot = try read(url)
            let heading = snapshot.document.blocks.flatMap(\.orderedNodes).first { $0.kind == .heading && !$0.displayText.isEmpty }?.displayText
            result.append(Entry(identity: snapshot.document.identity, title: heading.map { String($0.prefix(120)) } ?? "Saved document"))
        }
        return result
    }

    func load(identity: NativeDocumentIdentity) throws -> NativeReaderRecoverySnapshot {
        try directory()
        let snapshot = try read(file(identity))
        guard snapshot.document.identity == identity else { throw NativeReaderContractError.wrongTarget }
        return snapshot
    }

    private func read(_ url: URL) throws -> NativeReaderRecoverySnapshot {
        try Task.checkCancellation()
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
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
        guard file(snapshot.document.identity) == url else { throw NativeReaderContractError.wrongTarget }
        try snapshot.validate()
        return snapshot
    }
}

struct NativeReaderReviewMark: Codable {
    let id: UUID
    let identity: NativeDocumentIdentity
    let selection: NativeReaderRestoration
    static func validateCollection(_ values: [NativeReaderReviewMark], in document: NativeReaderDocument) throws {
        guard values.count <= 256, Set(values.map(\.id)).count == values.count else { throw NativeReaderContractError.invalidDocument }
        for value in values { try value.validate(in: document) }
    }
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
    func restore(_ values: [NativeReaderReviewMark], document: NativeReaderDocument) throws {
        try NativeReaderReviewMark.validateCollection(values, in: document)
        marks = values; paint?(marks)
    }
    func undo() { if !marks.isEmpty { marks.removeLast(); paint?(marks) } }
    func clear() { marks.removeAll(); paint?(marks) }
}
