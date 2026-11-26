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

// Typed CSS image semantics, separate from renderer geometry. Old schema-1
// memberwise callers can omit imageLayout; wire decoding never invents it.
struct NativeImageLength: Codable, Equatable {
    enum Unit: String, Codable { case px, pt, em; case percent = "%" }
    let value: Double
    let unit: Unit
    func points(fontSize: Double, reference: Double = 100) -> Double {
        unit == .percent ? reference * value / 100 : unit == .px ? value * 72 / 96 : unit == .em ? value * fontSize : value
    }
    func validate() throws {
        guard value.isFinite, value > 0, value <= (unit == .percent ? 100 : 4096) else { throw NativeReaderContractError.invalidDocument }
    }
}

struct NativeImageLayout: Codable, Equatable {
    enum Placement: String, Codable { case inline, block }
    enum Fit: String, Codable { case fill }
    enum Loading: String, Codable { case lazy, eager }
    enum Decoding: String, Codable { case async, sync, auto }
    let naturalUnit: NativeImageLength.Unit
    let placement: Placement
    let fit: Fit
    let width: NativeImageLength?
    let height: NativeImageLength?
    let loading: Loading?
    let decoding: Decoding?

    func validate() throws {
        guard naturalUnit == .pt || naturalUnit == .px else { throw NativeReaderContractError.invalidDocument }
        try width?.validate(); try height?.validate()
    }
    func size(naturalWidth: Double, naturalHeight: Double, fontSize: Double) throws -> (width: Double, height: Double) {
        try validate()
        guard fontSize.isFinite, fontSize > 0, naturalWidth.isFinite, naturalHeight.isFinite, naturalWidth > 0, naturalHeight > 0 else {
            throw NativeReaderContractError.invalidDocument
        }
        let scale = naturalUnit == .px ? 72.0 / 96 : 1
        let explicitWidth = width?.points(fontSize: fontSize, reference: naturalWidth * scale)
        let explicitHeight = height?.points(fontSize: fontSize, reference: naturalHeight * scale)
        let w = explicitWidth ?? explicitHeight.map { $0 * naturalWidth / naturalHeight } ?? naturalWidth * scale
        let h = explicitHeight ?? explicitWidth.map { $0 * naturalHeight / naturalWidth } ?? naturalHeight * scale
        guard w.isFinite, h.isFinite, w > 0, h > 0, w <= 4096, h <= 4096 else {
            throw NativeReaderContractError.invalidDocument
        }
        return (w, h)
    }
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
    var imageLayout: NativeImageLayout? = nil
    var listItemNumber: Int? = nil

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

    func rebinding(generation: Int) -> Self {
        Self(schemaVersion: schemaVersion, identity: identity, generation: generation,
             requiredCapabilities: requiredCapabilities, blocks: blocks, assets: assets, diagnostics: diagnostics)
    }

    static let supportedCapabilities: Set<String> = ["semantic-tree-v1", "image-layout-v1"]
    static let maximumJSONBytes = 64 * 1024 * 1024

    static func decode(_ data: Data, capabilities: Set<String> = supportedCapabilities) throws -> Self {
        guard data.count <= maximumJSONBytes else { throw NativeReaderContractError.invalidDocument }
        let document = try JSONDecoder().decode(Self.self, from: data)
        try document.validate(capabilities: capabilities)
        return document
    }

    func validate(capabilities: Set<String> = supportedCapabilities) throws {
        guard schemaVersion == 1 else { throw NativeReaderContractError.unsupportedSchema }
        guard Set(requiredCapabilities).isSubset(of: capabilities) else {
            throw NativeReaderContractError.unsupportedRequiredCapability
        }
        let required = Set(requiredCapabilities)
        let hasLayout = blocks.flatMap(\.orderedNodes).contains { $0.imageLayout != nil }
        guard required.contains("semantic-tree-v1"), required.count == requiredCapabilities.count,
              required.contains("image-layout-v1") == hasLayout else { throw NativeReaderContractError.invalidDocument }
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
            if required.contains("image-layout-v1"), node.kind == .image, node.imageLayout == nil {
                throw NativeReaderContractError.invalidDocument
            }
            if let layout = node.imageLayout {
                guard node.kind == .image else { throw NativeReaderContractError.invalidDocument }
                try layout.validate()
            }
            if let level = node.headingLevel, level < 1 { throw NativeReaderContractError.invalidDocument }
            if let number = node.listItemNumber, node.kind != .group || number < Int32.min || number > Int32.max {
                throw NativeReaderContractError.invalidDocument
            }
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
                let valid = token(anchor) || anchor.hasPrefix("mark:") && token(String(anchor.dropFirst(5)))
                guard valid, anchors.insert(anchor).inserted else { throw NativeReaderContractError.invalidDocument }
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

private struct NativeWireKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
private func nativeWireKeys(_ decoder: Decoder, allowed: Set<String>) throws {
    let keys = try decoder.container(keyedBy: NativeWireKey.self).allKeys.map(\.stringValue)
    guard Set(keys).isSubset(of: allowed) else { throw NativeReaderContractError.invalidDocument }
}

extension NativeImageLength {
    init(from decoder: Decoder) throws {
        try nativeWireKeys(decoder, allowed: ["value", "unit"])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        value = try c.decode(Double.self, forKey: .value)
        unit = try c.decode(Unit.self, forKey: .unit)
        try validate()
    }
}

extension NativeImageLayout {
    init(from decoder: Decoder) throws {
        try nativeWireKeys(decoder, allowed: ["naturalUnit", "placement", "fit", "width", "height", "loading", "decoding"])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        naturalUnit = try c.decode(NativeImageLength.Unit.self, forKey: .naturalUnit)
        placement = try c.decode(Placement.self, forKey: .placement)
        fit = try c.decode(Fit.self, forKey: .fit)
        width = c.contains(.width) ? try c.decode(NativeImageLength.self, forKey: .width) : nil
        height = c.contains(.height) ? try c.decode(NativeImageLength.self, forKey: .height) : nil
        loading = c.contains(.loading) ? try c.decode(Loading.self, forKey: .loading) : nil
        decoding = c.contains(.decoding) ? try c.decode(Decoding.self, forKey: .decoding) : nil
        try validate()
    }
}

extension NativeReaderNode {
    init(from decoder: Decoder) throws {
        try nativeWireKeys(decoder, allowed: ["id", "sectionID", "kind", "canonicalText", "displayText", "rangeUTF16", "offsets", "children", "anchors", "annotationTargets", "visible", "mapping", "passageKey", "direction", "language", "headingLevel", "math", "cell", "link", "assetID", "alt", "imageLayout", "listItemNumber"])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        sectionID = try c.decode(String.self, forKey: .sectionID)
        kind = try c.decode(Kind.self, forKey: .kind)
        canonicalText = try c.decode(String.self, forKey: .canonicalText)
        displayText = try c.decode(String.self, forKey: .displayText)
        rangeUTF16 = try c.decode([Int].self, forKey: .rangeUTF16)
        offsets = try c.decode(NativeTextOffsets.self, forKey: .offsets)
        children = try c.decode([NativeReaderNode].self, forKey: .children)
        anchors = try c.decode([String].self, forKey: .anchors)
        annotationTargets = try c.decode([String].self, forKey: .annotationTargets)
        visible = try c.decode(Bool.self, forKey: .visible)
        mapping = try c.decode(Mapping.self, forKey: .mapping)
        passageKey = try c.decodeIfPresent(String.self, forKey: .passageKey)
        direction = try c.decodeIfPresent(String.self, forKey: .direction)
        language = try c.decodeIfPresent(String.self, forKey: .language)
        headingLevel = try c.decodeIfPresent(Int.self, forKey: .headingLevel)
        math = try c.decodeIfPresent(NativeMath.self, forKey: .math)
        cell = try c.decodeIfPresent(NativeTableCell.self, forKey: .cell)
        link = try c.decodeIfPresent(String.self, forKey: .link)
        assetID = try c.decodeIfPresent(String.self, forKey: .assetID)
        alt = try c.decodeIfPresent(String.self, forKey: .alt)
        imageLayout = c.contains(.imageLayout) ? try c.decode(NativeImageLayout.self, forKey: .imageLayout) : nil
        listItemNumber = try c.decodeIfPresent(Int.self, forKey: .listItemNumber)
    }
}

extension NativeReaderDocument {
    init(from decoder: Decoder) throws {
        try nativeWireKeys(decoder, allowed: ["schemaVersion", "identity", "generation", "requiredCapabilities", "blocks", "assets", "diagnostics"])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        identity = try c.decode(NativeDocumentIdentity.self, forKey: .identity)
        generation = try c.decode(Int.self, forKey: .generation)
        requiredCapabilities = try c.decode([String].self, forKey: .requiredCapabilities)
        blocks = try c.decode([NativeReaderNode].self, forKey: .blocks)
        assets = try c.decode([NativeReaderAsset].self, forKey: .assets)
        diagnostics = try c.decode([NativeReaderDiagnostic].self, forKey: .diagnostics)
        try validate()
    }
}
