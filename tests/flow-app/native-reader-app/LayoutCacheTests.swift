import AppKit
import Darwin

private struct Failure: Error { let message: String }
@main struct LayoutCacheTests {
    static func check(_ value: Bool, _ message: String) throws { if !value { throw Failure(message: message) } }
    static func snapshot(owner: String = "owner", documentID: String = "doc", revision: String = "revision",
                         viewed: Set<String> = ["first"], offset: Double = 0.2) -> NativeReaderLayoutSnapshot {
        let identity = NativeDocumentIdentity(documentID: documentID, serviceID: "service", revision: revision, scope: .fixture)
        let blocks = ["first", "second"].map { id in
            NativeReaderNode(id: id, sectionID: "section", kind: .text, canonicalText: "Text", displayText: "Text",
                rangeUTF16: [0, 4], offsets: NativeTextOffsets("Text"), children: [], anchors: [], annotationTargets: [],
                visible: true, mapping: .unmapped, passageKey: nil, direction: nil, language: nil,
                headingLevel: nil, math: nil, cell: nil, link: nil, assetID: nil, alt: nil)
        }
        let doc = NativeReaderDocument(schemaVersion: 1, identity: identity, generation: 1,
            requiredCapabilities: ["semantic-tree-v1"], blocks: blocks, assets: [], diagnostics: [])
        return .init(ownerID: owner, key: .init(documentID: documentID, revision: revision, width: 640, fontSize: 14, theme: "light"),
            document: doc, restoration: .init(blockID: "first", offset: offset, zoom: 1, selectionTicket: nil, fragments: []),
            viewedBlockIDs: viewed, layouts: [:], assets: [:])
    }
    static func entries(_ root: URL, _ suffix: String) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).filter { $0.pathExtension == suffix }
    }
    static func inode(_ url: URL) throws -> UInt64 {
        (try FileManager.default.attributesOfItem(atPath: url.path)[.systemFileNumber] as! NSNumber).uint64Value
    }
    static func main() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".layout-cache-test-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = NativeReaderLayoutCache(root: root), a = snapshot()
        switch CommandLine.arguments[1] {
        case "envelope":
            for compressed in [false, true] {
                let data = try NativeReaderSnapshotStorage.encode(a, compressed: compressed, payloadLimit: 100000)
                let read = try NativeReaderSnapshotStorage.decode(NativeReaderLayoutSnapshot.self, from: data, compressed: compressed, payloadLimit: 100000)
                try check(read.document == a.document, "shared envelope roundtrip")
                var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
                json["sha256"] = String(repeating: "0", count: 64)
                do {
                    _ = try NativeReaderSnapshotStorage.decode(NativeReaderLayoutSnapshot.self,
                        from: JSONSerialization.data(withJSONObject: json), compressed: compressed, payloadLimit: 100000)
                    throw Failure(message: "corrupt envelope accepted")
                } catch is NativeReaderContractError {}
            }
        case "skip":
            try await cache.save(a)
            let file = try entries(root, "layout")[0], original = try Data(contentsOf: file), number = try inode(file)
            try await cache.save(snapshot(offset: 0.8))
            try check(try Data(contentsOf: file) == original && inode(file) == number, "identical content rewrote file")
            try check(try await cache.load(ownerID: a.ownerID, key: a.key)?.restoration.offset == 0.2, "position-only write")
            try await cache.save(snapshot(offset: 0.8), immediate: true)
            try check(try await cache.load(ownerID: a.ownerID, key: a.key)?.restoration.offset == 0.8, "close flush missing")
        case "document":
            try await cache.save(a)
            let file = try entries(root, "document")[0], number = try inode(file), original = try Data(contentsOf: file)
            try await cache.save(snapshot(viewed: ["first", "second"]))
            try await cache.save(snapshot(offset: 0.8), immediate: true)
            try check(try inode(file) == number && Data(contentsOf: file) == original, "document rewritten within revision")
            try check(try entries(root, "document").count == 1, "duplicate full document")
            try await cache.save(snapshot(revision: "new"))
            try check(try entries(root, "document").count == 1 && entries(root, "document")[0] != file, "revision not replaced")
        case "filter":
            let other = snapshot(owner: "other")
            try await cache.save(other)
            let foreign = try entries(root, "layout")[0]
            try Data("corrupt unrelated owner".utf8).write(to: foreign)
            try await cache.save(a)
            try check(try await cache.latest(ownerID: a.ownerID)?.ownerID == a.ownerID, "matching owner missing")
            try check(try Data(contentsOf: foreign) == Data("corrupt unrelated owner".utf8), "foreign owner decoded/deleted")
            let sameOwner = snapshot(documentID: "another")
            try await cache.save(sameOwner)
            let another = try entries(root, "layout").first { $0.lastPathComponent.contains(NativeReaderRecoverySnapshot.digest(Data("another".utf8))) }!
            try Data("corrupt other document".utf8).write(to: another)
            try await cache.save(a, immediate: true)
            try check(FileManager.default.fileExists(atPath: another.path), "save decoded another document")
            for file in try entries(root, "layout") {
                try check(file.lastPathComponent.range(of: "^[0-9a-f]{64}-[0-9a-f]{64}-[0-9a-f]{64}\\.layout$", options: .regularExpression) != nil, "identity absent in filename")
            }
        case "unsafe":
            try await cache.save(a)
            let legacy = root.appendingPathComponent(String(repeating: "a", count: 64) + ".layout")
            try Data("legacy".utf8).write(to: legacy)
            let bad = root.appendingPathComponent(String(repeating: "b", count: 64) + "-" + String(repeating: "c", count: 64) + "-" + String(repeating: "d", count: 64) + ".layout")
            try FileManager.default.createSymbolicLink(at: bad, withDestinationURL: legacy)
            try check(try await cache.load(ownerID: a.ownerID, key: a.key) != nil, "unsafe entry disabled cache")
            try check(!FileManager.default.fileExists(atPath: legacy.path) && !FileManager.default.fileExists(atPath: bad.path), "legacy/unsafe not discarded")
        case "lru":
            try await cache.save(a)
            let bytes = try await cache.diskBytes()
            let small = NativeReaderLayoutCache(root: root, byteLimit: bytes * 2 - 1)
            let b = snapshot(owner: "b")
            try await small.save(b)
            try check(try await small.diskBytes() <= bytes * 2 - 1, "byte cap exceeded")
            try check(try await small.load(ownerID: a.ownerID, key: a.key) == nil, "LRU not evicted")
            let file = try entries(root, "document")[0]
            try Data("corrupt".utf8).write(to: file)
            try check(try await small.latest(ownerID: b.ownerID) == nil, "corrupt document accepted")
            try check(try await small.diskBytes() == 0, "corrupt group retained")
        default: throw Failure(message: "unknown case")
        }
        print("passed")
    }
}
