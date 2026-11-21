import Foundation
import CoreText
import CoreGraphics

func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw NSError(domain: "NA01", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
func reject(_ expected: NativeReaderContractError, _ body: () throws -> Void) throws {
    do { try body() } catch let error as NativeReaderContractError {
        try require(error == expected, "wrong rejection: \(error)")
        return
    }
    throw NSError(domain: "NA01", code: 2, userInfo: [NSLocalizedDescriptionKey: "missing rejection \(expected)"])
}

@main struct ContractTests {
    @MainActor static func main() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let document = try NativeReaderDocument.decode(data)
        let oracle = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))) as! [String: Any]
        let expectedTexts = oracle["texts"] as! [String]
        try require(document.blocks.map(\.kind.rawValue) == oracle["kinds"] as! [String], "ordered kinds")
        try require(document.blocks.map { Array($0.canonicalText.unicodeScalars.map(\.value)) } == expectedTexts.map { $0.unicodeScalars.map(\.value) }, "exact scalar reading order")
        let nodes = document.blocks.flatMap(\.orderedNodes)
        try require(Set(nodes.map(\.id)).count == nodes.count, "duplicate identity")
        try require(document.blocks[3].id != document.blocks[4].id, "repeated paragraph identity")
        try require(document.blocks[3].passageKey != document.blocks[4].passageKey, "repeated passage key")
        try require(nodes.filter { $0.kind == .math }.map { $0.math!.normalizedText } == oracle["mathTexts"] as! [String], "math meaning")
        for item in oracle["unicodeCases"] as! [[String: Any]] {
            let text = item["text"] as! String, units = NativeTextOffsets(text)
            try require(units.scalars == (item["scalars"] as! [UInt32]), "unicode scalars")
            try require(units.cpToUTF8 == item["utf8"] as! [Int], "UTF8")
            try require(units.cpToUTF16 == item["utf16"] as! [Int], "UTF16")
            var boundaries = [0]
            for character in text { boundaries.append(boundaries.last! + String(character).utf16.count) }
            try require(boundaries == item["graphemes"] as! [Int], "graphemes")
            try require(document.blocks[1].canonicalText.unicodeScalars.map(\.value).containsSubsequence(units.scalars), "fixture Unicode missing")
        }
        let crossBlock = NativeReaderSelection(ticket: UUID(), fragments: [
            .init(blockID: document.blocks[3].id, rangeUTF16: 0..<19, exact: "Repeated paragraph."),
            .init(blockID: document.blocks[4].id, rangeUTF16: 0..<19, exact: "Repeated paragraph.")])
        try crossBlock.validate(in: document)
        let store = NativeReaderDocumentStore()
        let generation = try store.beginRequest()
        let context = NativeReaderRequestContext(requestID: UUID(), viewID: store.viewID, generation: generation, target: document.identity)
        try store.adopt(document, for: context)
        let selection = NativeReaderSelection(ticket: UUID(), blockID: document.blocks[1].id, rangeUTF16: 0..<2, exact: "한글")
        try store.holdSelection(selection)
        store.releaseSelection(ticket: UUID())
        try reject(.selectionHeld) { try store.adopt(document, for: context) }
        store.releaseSelection(ticket: selection.ticket)
        try require(store.selection == nil, "ack selection ticket")
        try reject(.invalidSelection) {
            try NativeReaderSelection(ticket: UUID(), blockID: document.blocks[1].id, rangeUTF16: 3..<4, exact: "ᄒ").validate(in: document)
        }
        let wrong = NativeDocumentIdentity(documentID: "other", serviceID: document.identity.serviceID, revision: document.identity.revision, scope: document.identity.scope)
        try reject(.wrongTarget) { try store.adopt(document, for: NativeReaderRequestContext(requestID: UUID(), viewID: store.viewID, generation: generation, target: wrong)) }
        try reject(.wrongTarget) {
            try store.adopt(document, for: NativeReaderRequestContext(requestID: UUID(), viewID: UUID(), generation: generation, target: document.identity))
        }
        try reject(.invalidSelection) {
            try NativeReaderSelection(ticket: UUID(), fragments: crossBlock.fragments.reversed()).validate(in: document)
        }
        store.cancel()
        try reject(.staleGeneration) { try store.adopt(document, for: context) }
        try require(store.document?.identity == document.identity, "retain accepted on rejection")
        store.dispose()
        try reject(.disposed) { _ = try store.beginRequest() }
        func mutated(_ mutation: (inout [String: Any]) -> Void) throws -> Data {
            var value = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            mutation(&value)
            return try JSONSerialization.data(withJSONObject: value)
        }
        try reject(.unsupportedRequiredCapability) { _ = try NativeReaderDocument.decode(mutated { $0["requiredCapabilities"] = ["unknown-paint"] }) }
        try reject(.unsupportedSchema) { _ = try NativeReaderDocument.decode(mutated { $0["schemaVersion"] = 9 }) }
        try reject(.invalidDocument) { _ = try NativeReaderDocument.decode(mutated {
            var blocks = $0["blocks"] as! [[String: Any]]; blocks[1]["id"] = blocks[0]["id"]; $0["blocks"] = blocks
        }) }
        try reject(.invalidDocument) { _ = try NativeReaderDocument.decode(mutated {
            var blocks = $0["blocks"] as! [[String: Any]]; blocks[1]["rangeUTF16"] = [0, 1]; $0["blocks"] = blocks
        }) }
        try require(document.requiredCapabilities == oracle["requiredCapabilities"] as! [String], "dynamic image capability")
        let supplemented = nodes.filter { $0.imageLayout != nil }
        try require(!supplemented.isEmpty, "raw compiler SVG layout")
        let roundtrip = try NativeReaderDocument.decode(JSONEncoder().encode(document))
        try require(roundtrip == document, "metadata Codable roundtrip")
        try reject(.unsupportedRequiredCapability) { _ = try NativeReaderDocument.decode(data, capabilities: ["semantic-tree-v1"]) }
        let rebound = document.rebinding(generation: 42)
        try require(rebound.blocks == document.blocks && rebound.requiredCapabilities == document.requiredCapabilities && rebound.generation == 42, "generation metadata copy")
        let widthOnly = NativeImageLayout(naturalUnit: .px, placement: .inline, fit: .fill,
            width: NativeImageLength(value: 32, unit: .pt), height: nil, loading: nil, decoding: nil)
        let ratioSize = try widthOnly.size(naturalWidth: 24, naturalHeight: 12, fontSize: 20)
        try require(ratioSize.width == 32 && ratioSize.height == 16, "single dimension intrinsic aspect")
        let heightOnly = NativeImageLayout(naturalUnit: .px, placement: .block, fit: .fill,
            width: nil, height: NativeImageLength(value: 2, unit: .em), loading: .lazy, decoding: .async)
        let emSize = try heightOnly.size(naturalWidth: 24, naturalHeight: 12, fontSize: 15)
        try require(emSize.width == 60 && emSize.height == 30, "em uses current logical font")
        var legacy = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        func removeLayout(_ value: [String: Any]) -> [String: Any] {
            var node = value; node.removeValue(forKey: "imageLayout")
            node["children"] = (node["children"] as! [[String: Any]]).map(removeLayout)
            return node
        }
        legacy["blocks"] = (legacy["blocks"] as! [[String: Any]]).map(removeLayout)
        legacy["requiredCapabilities"] = ["semantic-tree-v1"]
        let legacyData = try JSONSerialization.data(withJSONObject: legacy)
        let legacyDocument = try NativeReaderDocument.decode(legacyData, capabilities: ["semantic-tree-v1"])
        try require(legacyDocument.blocks.flatMap(\.orderedNodes).allSatisfy { $0.imageLayout == nil }, "old semantic tree still supported")
        var supplementNegatives = [String]()
        for name in ["missing-cap", "lost-layout", "unknown-layout", "unknown-node", "null-layout", "missing-placement", "unknown-unit", "zero", "huge", "unknown-fit"] {
            var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            if name == "missing-cap" { object["requiredCapabilities"] = ["semantic-tree-v1"] }
            func change(_ node: [String: Any]) -> [String: Any] {
                var n = node
                if var layout = n["imageLayout"] as? [String: Any] {
                    switch name {
                    case "lost-layout": n.removeValue(forKey: "imageLayout")
                    case "unknown-node": n["futureLayout"] = layout
                    case "null-layout": n["imageLayout"] = NSNull()
                    default:
                        if name == "unknown-layout" { layout["rotation"] = 90 }
                        if name == "missing-placement" { layout.removeValue(forKey: "placement") }
                        if name == "unknown-unit" { layout["width"] = ["value": 10, "unit": "%"] }
                        if name == "zero" { layout["width"] = ["value": 0, "unit": "pt"] }
                        if name == "huge" { layout["height"] = ["value": 4097, "unit": "px"] }
                        if name == "unknown-fit" { layout["fit"] = "cover" }
                        n["imageLayout"] = layout
                    }
                }
                n["children"] = (n["children"] as! [[String: Any]]).map(change)
                return n
            }
            object["blocks"] = (object["blocks"] as! [[String: Any]]).map(change)
            let bytes = try JSONSerialization.data(withJSONObject: object)
            var rejected = false
            do { _ = try NativeReaderDocument.decode(bytes) } catch { rejected = true }
            try require(rejected, "reject supplement " + name)
            // Recovery uses generic JSONDecoder, which must reject identically.
            rejected = false
            do { _ = try JSONDecoder().decode(NativeReaderDocument.self, from: bytes) } catch { rejected = true }
            try require(rejected, "generic decoder rejects " + name)
            supplementNegatives.append(name)
        }
        var matrix = [[String: Any]]()
        // CoreText text-layout contract only. This is neither GUI nor object fidelity.
        for width in [320.0, 640.0, 960.0] {
            for size in [14.0, 18.0, 24.0] {
                var lineCount = 0
                var paintedFontNames = Set<String>()
                for block in document.blocks where block.kind == .paragraph || block.kind == .heading {
                    let font = CTFontCreateWithName("Helvetica" as CFString, size, nil)
                    let string = NSAttributedString(string: block.displayText, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
                    let setter = CTFramesetterCreateWithAttributedString(string)
                    let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: string.length), CGPath(rect: CGRect(x: 0, y: 0, width: width, height: 8192), transform: nil), nil)
                    let visible = CTFrameGetVisibleStringRange(frame)
                    try require(visible.location == 0 && visible.length == string.length, "layout truncation")
                    let lines = CTFrameGetLines(frame) as! [CTLine]
                    var position = 0
                    for line in lines {
                        for run in CTLineGetGlyphRuns(line) as! [CTRun] {
                            let attributes = CTRunGetAttributes(run) as NSDictionary
                            if let font = attributes[kCTFontAttributeName] {
                                paintedFontNames.insert(CTFontCopyPostScriptName(font as! CTFont) as String)
                            }
                        }
                        let range = CTLineGetStringRange(line)
                        try require(range.location == position && range.length > 0, "line order")
                        position += range.length
                    }
                    try require(position == block.displayText.utf16.count, "layout UTF16 coverage")
                    lineCount += lines.count
                }
                try selection.validate(in: document)
                matrix.append(["widthPt": width, "fontPt": size, "lines": lineCount, "resolvedFonts": paintedFontNames.sorted(), "status": "pass"])
            }
        }
        let output: [String: Any] = ["status": "pass", "matrix": matrix, "scope": "headless contract/CoreText; objects and GUI remain separate", "negativeCases": 11, "supplementNegatives": supplementNegatives]
        print(String(decoding: try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}

extension Array where Element: Equatable {
    func containsSubsequence(_ value: [Element]) -> Bool {
        guard value.count <= count else { return false }
        return (0...(count - value.count)).contains { Array(self[$0..<($0 + value.count)]) == value }
    }
}
