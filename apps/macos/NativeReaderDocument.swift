import Foundation

// Schema 1 is owned by NA01. No source bytes, filesystem locations or credentials.
struct NativeDocumentIdentity: Codable, Equatable {
    enum Scope: String, Codable { case service, fixture }
    let documentID: String
    let serviceID: String
    let revision: String
    let scope: Scope
}

struct NativeTextOffsets: Codable, Equatable {
    let scalars: [UInt32]
    let cpToUTF8: [Int]
    let cpToUTF16: [Int]

    init(_ text: String) {
        scalars = text.unicodeScalars.map(\.value)
        var bytes = [0], units = [0]
        for scalar in text.unicodeScalars {
            bytes.append(bytes.last! + scalar.utf8.count)
            units.append(units.last! + scalar.utf16.count)
        }
        cpToUTF8 = bytes
        cpToUTF16 = units
    }
}

struct NativeMath: Codable, Equatable {
    let mathML: String
    let normalizedText: String
    let display: Bool
}

struct NativeTableCell: Codable, Equatable {
    let rowSpan: Int
    let columnSpan: Int
    let header: Bool
    let scope: String?
}

struct NativeReaderNode: Codable, Equatable {
    enum Kind: String, Codable {
        case text, paragraph, heading, strong, emphasis, link, group, math
        case equation, equationNumber, table, tableHead, tableBody, row, cell
        case figure, image, caption, annotation
        case `break`
    }
    enum Mapping: String, Codable { case unmapped, ambiguous }
    let id: String
    let sectionID: String
    let kind: Kind
    // Exact accepted-HTML scalar sequence; no NFC/NFD conversion. Geometry is external.
    let canonicalText: String
    let displayText: String
    let rangeUTF16: [Int] // Half-open, relative to containing top-level block.
    let offsets: NativeTextOffsets
    let children: [NativeReaderNode]
    let anchors: [String]
    let annotationTargets: [String]
    let visible: Bool
    let mapping: Mapping
    let passageKey: String? // Existing source owner resolves this; never a source range.
    let direction: String?
    let language: String?
    let headingLevel: Int?
    let math: NativeMath?
    let cell: NativeTableCell?
    let link: String?
    let assetID: String?
    let alt: String?

    var orderedNodes: [NativeReaderNode] { [self] + children.flatMap(\.orderedNodes) }
    var graphemeBoundariesUTF16: [Int] {
        var offsets = [0]
        for character in displayText {
            offsets.append(offsets.last! + String(character).utf16.count)
        }
        return offsets
    }
}

struct NativeReaderAsset: Codable, Equatable {
    let id: String
    let sha256: String
    let mime: String
    let byteCount: Int
}

struct NativeReaderDiagnostic: Codable, Equatable {
    let code: String
    let nodeID: String
}

enum NativeReaderContractError: Error, Equatable {
    case invalidDocument, unsupportedSchema, unsupportedRequiredCapability
    case wrongTarget, staleGeneration, selectionHeld, disposed, invalidSelection
}

struct NativeReaderDocument: Codable, Equatable {
    let schemaVersion: Int
    let identity: NativeDocumentIdentity
    let generation: Int
    let requiredCapabilities: [String]
    let blocks: [NativeReaderNode]
    let assets: [NativeReaderAsset]
    let diagnostics: [NativeReaderDiagnostic]

    static let supportedCapabilities: Set<String> = ["semantic-tree-v1"]

    static func decode(_ data: Data, capabilities: Set<String> = supportedCapabilities) throws -> Self {
        guard data.count <= 32 * 1024 * 1024 else { throw NativeReaderContractError.invalidDocument }
        let document = try JSONDecoder().decode(Self.self, from: data)
        try document.validate(capabilities: capabilities)
        return document
    }

    func validate(capabilities: Set<String> = supportedCapabilities) throws {
        guard schemaVersion == 1 else { throw NativeReaderContractError.unsupportedSchema }
        guard Set(requiredCapabilities).isSubset(of: capabilities) else {
            throw NativeReaderContractError.unsupportedRequiredCapability
        }
        func token(_ value: String) -> Bool {
            value.range(of: "^[A-Za-z0-9_.:-]{1,128}$", options: .regularExpression) != nil
        }
        guard generation >= 0, token(identity.documentID), token(identity.serviceID), token(identity.revision),
              !blocks.isEmpty, blocks.count <= 100000 else { throw NativeReaderContractError.invalidDocument }
        var ids = Set<String>(), anchors = Set<String>(), targets = [String]()
        let assetIDs = Set(assets.map(\.id))
        guard assetIDs.count == assets.count else { throw NativeReaderContractError.invalidDocument }
        for asset in assets {
            guard asset.sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
                  ["image/svg+xml", "image/png", "image/jpeg", "image/webp", "image/gif"].contains(asset.mime),
                  asset.id == asset.sha256 + "." + ["image/svg+xml": "svg", "image/png": "png", "image/jpeg": "jpg", "image/webp": "webp", "image/gif": "gif"][asset.mime]!, asset.byteCount > 0 else {
                throw NativeReaderContractError.invalidDocument
            }
        }
        func check(_ node: NativeReaderNode, base: Int, depth: Int) throws {
            guard depth <= 128, ids.count < 100000, token(node.id), token(node.sectionID), ids.insert(node.id).inserted,
                  Array(node.canonicalText.unicodeScalars) == Array(node.displayText.unicodeScalars),
                  node.offsets == NativeTextOffsets(node.canonicalText),
                  node.rangeUTF16 == [base, base + node.displayText.utf16.count],
                  node.direction == nil || ["auto", "ltr", "rtl"].contains(node.direction!),
                  (node.kind == .math) == (node.math != nil),
                  (node.kind == .cell) == (node.cell != nil),
                  (node.kind == .heading) == (node.headingLevel != nil),
                  (node.kind == .link) == (node.link != nil),
                  (node.kind == .image) == (node.assetID != nil) else {
                throw NativeReaderContractError.invalidDocument
            }
            if let level = node.headingLevel, level < 1 { throw NativeReaderContractError.invalidDocument }
            if let cell = node.cell, !(1...1000).contains(cell.rowSpan) || !(1...1000).contains(cell.columnSpan) {
                throw NativeReaderContractError.invalidDocument
            }
            if let asset = node.assetID, !assetIDs.contains(asset) { throw NativeReaderContractError.invalidDocument }
            if let link = node.link {
                guard let url = URLComponents(string: link),
                      (link.hasPrefix("#") && link.count > 1) ||
                        (["http", "https", "mailto"].contains(url.scheme ?? "") && url.user == nil && url.password == nil) else {
                    throw NativeReaderContractError.invalidDocument
                }
            }
            for anchor in node.anchors {
                guard token(anchor), anchors.insert(anchor).inserted else { throw NativeReaderContractError.invalidDocument }
            }
            targets += node.annotationTargets
            if [.text, .math, .image, .break].contains(node.kind) {
                guard node.children.isEmpty else { throw NativeReaderContractError.invalidDocument }
            } else if !node.canonicalText.isEmpty && node.children.isEmpty {
                throw NativeReaderContractError.invalidDocument
            }
            if !node.children.isEmpty {
                guard Array(node.children.flatMap { $0.canonicalText.unicodeScalars }) == Array(node.canonicalText.unicodeScalars) else {
                    throw NativeReaderContractError.invalidDocument
                }
            }
            var position = base
            for child in node.children {
                guard child.sectionID == node.sectionID else { throw NativeReaderContractError.invalidDocument }
                try check(child, base: position, depth: depth + 1)
                position = child.rangeUTF16[1]
            }
        }
        for block in blocks { try check(block, base: 0, depth: 0) }
        guard targets.allSatisfy({ anchors.contains($0) }), diagnostics.allSatisfy({ ids.contains($0.nodeID) }) else {
            throw NativeReaderContractError.invalidDocument
        }
    }
}
