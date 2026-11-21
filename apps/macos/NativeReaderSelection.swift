import AppKit

// Presentation offsets belong to TextKit; these positions always belong to the
// accepted block. In particular, an attachment is not one logical UTF16 unit.
struct NativeReaderTextPosition: Equatable {
    let blockID: String
    let utf16: Int
    let affinity: NSSelectionAffinity
}

struct NativeReaderPresentationSpan {
    let blockID: String
    let logical: Range<Int>
    let presentation: NSRange
    let isObject: Bool
}

struct NativeReaderTextMap {
    let document: NativeReaderDocument
    let spans: [NativeReaderPresentationSpan]
    let length: Int

    func snapped(_ position: NativeReaderTextPosition) throws -> NativeReaderTextPosition {
        guard let block = document.blocks.first(where: { $0.id == position.blockID }),
              (0...block.displayText.utf16.count).contains(position.utf16) else {
            throw NativeReaderContractError.invalidSelection
        }
        let boundaries = block.graphemeBoundariesUTF16
        let offset = position.affinity == .upstream
            ? boundaries.last(where: { $0 <= position.utf16 })!
            : boundaries.first(where: { $0 >= position.utf16 })!
        return NativeReaderTextPosition(blockID: position.blockID, utf16: offset, affinity: position.affinity)
    }

    func logical(at offset: Int, affinity: NSSelectionAffinity) throws -> NativeReaderTextPosition {
        guard offset >= 0, offset <= length, !spans.isEmpty else {
            throw NativeReaderContractError.invalidSelection
        }
        let matches = spans.filter { offset >= $0.presentation.location && offset <= NSMaxRange($0.presentation) }
        let span = affinity == .upstream ? matches.first : matches.last
        // A block separator has two equivalent caret edges. Affinity determines
        // which block owns that caret; separators never become source ranges.
        let chosen = span ?? (affinity == .upstream
            ? spans.last(where: { NSMaxRange($0.presentation) < offset })
            : spans.first(where: { $0.presentation.location > offset }))
        guard let item = chosen else { throw NativeReaderContractError.invalidSelection }
        let relative = min(max(0, offset - item.presentation.location), item.presentation.length)
        let unit: Int
        if item.isObject {
            unit = relative == 0 ? item.logical.lowerBound : item.logical.upperBound
        } else {
            unit = item.logical.lowerBound + relative
        }
        return try snapped(NativeReaderTextPosition(blockID: item.blockID, utf16: unit, affinity: affinity))
    }

    func presentation(of position: NativeReaderTextPosition) throws -> Int {
        let position = try snapped(position)
        let matches = spans.filter {
            $0.blockID == position.blockID && $0.logical.lowerBound <= position.utf16 && position.utf16 <= $0.logical.upperBound
        }
        guard let span = position.affinity == .upstream ? matches.first : matches.last else {
            throw NativeReaderContractError.invalidSelection
        }
        if span.isObject {
            if position.utf16 == span.logical.lowerBound { return span.presentation.location }
            if position.utf16 == span.logical.upperBound { return NSMaxRange(span.presentation) }
            return position.affinity == .upstream ? span.presentation.location : NSMaxRange(span.presentation)
        }
        return span.presentation.location + position.utf16 - span.logical.lowerBound
    }

    func normalized(_ range: NSRange, affinity: NSSelectionAffinity) throws -> NSRange {
        guard range.location != NSNotFound, range.location >= 0, range.length >= 0,
              range.location <= length, range.length <= length - range.location else {
            throw NativeReaderContractError.invalidSelection
        }
        if range.length == 0 {
            return NSRange(location: try presentation(of: logical(at: range.location, affinity: affinity)), length: 0)
        }
        let start = try presentation(of: logical(at: range.location, affinity: .upstream))
        let end = try presentation(of: logical(at: NSMaxRange(range), affinity: .downstream))
        return NSRange(location: start, length: max(0, end - start))
    }

    func selection(for range: NSRange, ticket: UUID = UUID()) throws -> NativeReaderSelection? {
        let range = try normalized(range, affinity: .downstream)
        if range.length == 0 { return nil }
        var fragments: [NativeReaderSelection.Fragment] = []
        for block in document.blocks {
            let intersections = spans.filter { $0.blockID == block.id }.compactMap { span -> Range<Int>? in
                let overlap = NSIntersectionRange(span.presentation, range)
                guard overlap.length > 0 else { return nil }
                if span.isObject { return span.logical }
                let start = span.logical.lowerBound + overlap.location - span.presentation.location
                return start..<(start + overlap.length)
            }
            guard let start = intersections.first?.lowerBound, let end = intersections.last?.upperBound,
                  start < end, let textRange = Range(NSRange(location: start, length: end - start), in: block.displayText) else { continue }
            fragments.append(.init(blockID: block.id, rangeUTF16: start..<end, exact: String(block.displayText[textRange])))
        }
        if fragments.isEmpty { return nil }
        let selection = NativeReaderSelection(ticket: ticket, fragments: fragments)
        try selection.validateLocal(in: document)
        return selection
    }

    func presentationRange(blockID: String, logical: Range<Int>) throws -> NSRange {
        let start = try presentation(of: .init(blockID: blockID, utf16: logical.lowerBound, affinity: .upstream))
        let end = try presentation(of: .init(blockID: blockID, utf16: logical.upperBound, affinity: .downstream))
        guard end >= start else { throw NativeReaderContractError.invalidSelection }
        return NSRange(location: start, length: end - start)
    }
}

struct NativeReaderInsertionPoint {
    let presentationUTF16: Int
    let x: CGFloat
    let alternate: Bool
}

// TextKit returns primary positions and *only* the additional bidi positions in
// separate calls. Neither array can stand in for the other.
func nativeReaderInsertionPoints(_ manager: NSLayoutManager, character: Int) -> [NativeReaderInsertionPoint] {
    var result: [NativeReaderInsertionPoint] = []
    for alternate in [false, true] {
        let count = manager.getLineFragmentInsertionPoints(forCharacterAt: character,
            alternatePositions: alternate, inDisplayOrder: true, positions: nil, characterIndexes: nil)
        var positions = [CGFloat](repeating: 0, count: count)
        var indexes = [Int](repeating: 0, count: count)
        let actual = manager.getLineFragmentInsertionPoints(forCharacterAt: character,
            alternatePositions: alternate, inDisplayOrder: true, positions: &positions, characterIndexes: &indexes)
        for i in 0..<actual { result.append(.init(presentationUTF16: indexes[i], x: positions[i], alternate: alternate)) }
    }
    return result
}
