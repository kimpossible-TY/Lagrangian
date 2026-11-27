import AppKit

private struct Failure: Error { let message: String }

@main struct ObjectTransientTests {
    static func check(_ value: Bool, _ message: String) throws {
        if !value { throw Failure(message: message) }
    }
    static let transientCodes = ["math-worker-busy", "math-helper-timeout", "math-helper-io",
        "math-helper-input", "math-helper-memory-observation", "math-runtime-missing",
        "math-runtime-not-delivered", "answer-math-runtime-not-delivered"]
    static func document(count: Int = 4) -> NativeReaderDocument {
        let blocks = (0..<count).map { index in
            NativeReaderNode(id: "object-\(index)", sectionID: "section", kind: .math,
                canonicalText: "x", displayText: "x", rangeUTF16: [0, 1], offsets: NativeTextOffsets("x"),
                children: [], anchors: [], annotationTargets: [], visible: true, mapping: .unmapped,
                passageKey: nil, direction: nil, language: nil, headingLevel: nil,
                math: .init(mathML: "<math><mi>x</mi></math>", normalizedText: "x", display: true),
                cell: nil, link: nil, assetID: nil, alt: "formula \(index)")
        }
        return NativeReaderDocument(schemaVersion: 1,
            identity: .init(documentID: "doc", serviceID: "service", revision: "revision", scope: .fixture),
            generation: 1, requiredCapabilities: ["semantic-tree-v1"], blocks: blocks, assets: [], diagnostics: [])
    }
    static func values(_ nodes: [NativeReaderNode], _ key: NativeReaderTextRenderKey) -> [String: NativeReaderPreparedTextObject] {
        Dictionary(uniqueKeysWithValues: nodes.map {
            ($0.id, .init(key: key, size: NSSize(width: 120, height: 24), baseline: 0,
                         accessibilityLabel: $0.alt!, draw: { _ in }, cost: 1024))
        })
    }
    @MainActor static func finish(_ view: NativeReaderTextView) async throws {
        var tasks = 0
        while let task = view.lazyTask {
            tasks += 1
            try check(tasks <= 8, "viewport failed to reach bounded idle state")
            await task.value
        }
    }
    static func classification() throws {
        for code in transientCodes {
            let policy = NativeObjectError.unsupported(code).classification
            try check(policy.scope == .transient, "transient code isolated: \(code)")
            try check(policy.splitsMathBatch == (code == "math-helper-timeout"), "changed batch splitting: \(code)")
        }
        let deterministic: [NativeObjectError] = [.invalidGeometry, .budget, .unsupported("input-limit"),
            .unsupported("unsupported-object"), .unsupported("math-helper-rejected"), .unsupported("svg-xml"),
            .unsupported("native-svg-decode"), .unsupported("raster-decode"), .unsupported("output-limit"),
            .unsupported("indivisible-math-overflow")]
        for error in deterministic {
            let policy = error.classification
            try check(policy.scope == .deterministic, "deterministic failure lost isolation: \(error)")
            try check(policy.splitsMathBatch == (error == .budget || error == .unsupported("input-limit")),
                      "changed deterministic batch splitting: \(error)")
        }
        for error in [NativeObjectError.cancelled, .stale] {
            try check(error.classification.scope == .obsolete && !error.classification.splitsMathBatch,
                      "cancel/stale must abort without retry or isolation")
        }
    }
    @MainActor static func propagation() async throws {
        let doc = document()
        let key = NativeReaderTextRenderKey(identity: doc.identity, documentGeneration: 1,
            viewID: UUID(), layoutGeneration: 1, width: 640, appearance: .init())
        for code in transientCodes {
            var calls = 0
            do {
                _ = try await NativeReaderPreparedTextObject.prepareLazy(doc.blocks) { _ in
                    calls += 1; throw NativeObjectError.unsupported(code)
                }
                throw Failure(message: "transient returned isolated failures: \(code)")
            } catch let error as NativeObjectError {
                try check(error == .unsupported(code) && calls == 1, "transient was split: \(code)")
            }
            // A transient in the right half also discards a successful left half.
            calls = 0
            do {
                _ = try await NativeReaderPreparedTextObject.prepareLazy(doc.blocks) { nodes in
                    calls += 1
                    if calls == 1 { throw NativeObjectError.budget }
                    if calls == 2 { return values(nodes, key) }
                    throw NativeObjectError.unsupported(code)
                }
                throw Failure(message: "nested transient published a partial result")
            } catch let error as NativeObjectError {
                try check(error == .unsupported(code) && calls == 3, "nested transient was isolated")
            }
            if code != "math-helper-timeout" {
                calls = 0
                do {
                    _ = try await NativeReaderPreparedTextObject.prepareLazy(doc.blocks, provider: { _ in
                        calls += 1; throw NativeObjectError.unsupported(code)
                    }, isolatingTimeout: true)
                    throw Failure(message: "node-independent error isolated on last attempt: \(code)")
                } catch let error as NativeObjectError {
                    try check(error == .unsupported(code) && calls == 1, "last attempt split a node-independent error")
                }
            }
        }
        for failure in [NativeObjectError.invalidGeometry, .unsupported("math-helper-rejected")] {
            let badID = doc.blocks[1].id
            let result = try await NativeReaderPreparedTextObject.prepareLazy(doc.blocks) { nodes in
                if nodes.contains(where: { $0.id == badID }) { throw failure }
                return values(nodes, key)
            }
            try check(result.failures == [badID] && Set(result.objects.keys) == Set(doc.blocks.map(\.id)).subtracting([badID]),
                      "deterministic isolation must record only the bad node")
        }
        let badID = "object-1"
        var calls = 0
        let result = try await NativeReaderPreparedTextObject.prepareLazy(doc.blocks, provider: { nodes in
            calls += 1
            if nodes.contains(where: { $0.id == badID }) { throw NativeObjectError.unsupported("math-helper-timeout") }
            return values(nodes, key)
        }, isolatingTimeout: true)
        try check(result.failures == [badID] && Set(result.objects.keys) == Set(doc.blocks.map(\.id)).subtracting([badID]),
                  "last-attempt timeout isolation must record only the timing-out leaf")
        try check(calls == 5, "one timing-out leaf in four objects must still isolate in five calls")
    }
    @MainActor static func timeoutBudget() async throws {
        for (count, budget) in [(4, 5), (8, 7), (128, 15)] {
            let doc = document(count: count)
            var calls = 0
            do {
                _ = try await NativeReaderPreparedTextObject.prepareLazy(doc.blocks, provider: { _ in
                    calls += 1
                    throw NativeObjectError.unsupported("math-helper-timeout")
                }, isolatingTimeout: true)
                throw Failure(message: "all-timeout preparation returned after exhausting its budget")
            } catch let error as NativeObjectError {
                try check(error == .unsupported("math-helper-timeout") && calls == budget,
                          "all-timeout preparation must stop at its logarithmic budget for \(count) objects")
            }
        }
    }
    @MainActor static func viewport(_ mode: String, failure: Error = NativeObjectError.unsupported("math-helper-timeout")) async throws {
        let doc = document(), store = NativeReaderDocumentStore()
        let view = NativeReaderTextView(store: store)
        defer { view.dispose() }
        view.setFrameSize(NSSize(width: 640, height: 600))
        view.preparesViewedWindowsOnly = true
        let context = NativeReaderRequestContext(requestID: UUID(), viewID: store.viewID,
            generation: try store.beginRequest(), target: doc.identity)
        try view.adopt(doc, context: context)
        view.layoutSubtreeIfNeeded()
        let key = view.requestedRenderKey!
        let expected = Set(doc.blocks.map(\.id)), badID = doc.blocks[1].id
        var calls = 0, delays = [Int](), batches = [Set<String>]()
        view.lazyRetryDelay = { delay in
            delays.append(delay)
            try check(view.preparedObjectIDs.isEmpty, "transient published a staged sub-range")
        }
        view.configureLazyObjects(key: key, initial: [:]) { nodes, current in
            calls += 1; batches.append(Set(nodes.map(\.id)))
            if mode == "deterministic" || mode == "timeout-leaf" {
                if nodes.contains(where: { $0.id == badID }) { throw failure }
            } else if mode == "cap" || mode == "obsolete" || calls <= (mode == "twice" ? 2 : 1) {
                throw failure
            }
            return values(nodes, current)
        }
        try await finish(view)
        try check(batches.first == expected && expected.count > 1, "test must prepare the whole multi-object viewport")
        let settledCalls = calls
        for _ in 0..<5 { view.prepareVisibleObjects(); try await finish(view) }
        try check(calls == settledCalls, "settled viewport dispatched more work")
        switch mode {
        case "once", "twice":
            let failures = mode == "once" ? 1 : 2
            try check(calls == failures + 1 && delays == Array(1...failures), "incorrect backoff schedule")
            try check(batches.allSatisfy { $0 == expected } && view.preparedObjectIDs == expected,
                      "timeout must retry and publish ALL siblings without isolated failures")
        case "cap":
            try check(delays == [1, 2] && Array(batches.prefix(3)) == Array(repeating: expected, count: 3),
                      "all-timeout cap must bisect only on the last allowed attempt")
            try check(batches.dropFirst(2).count == 5 && calls == 7,
                      "last all-timeout attempt must stop within its five-call budget")
            try check(view.preparedObjectIDs.isEmpty && view.preparedObjectCost == 0,
                      "timeout budget exhaustion must leave placeholders")
        case "timeout-leaf":
            try check(delays == [1, 2] && calls == 7 && Array(batches.prefix(3)) == Array(repeating: expected, count: 3),
                      "persistent timeout must bisect only on the last allowed attempt")
            try check(Array(batches.dropFirst(3)) == [Set(["object-0", badID]), Set(["object-0"]), Set([badID]), Set(["object-2", "object-3"])],
                      "last attempt must isolate the timing-out leaf and prepare healthy siblings")
            try check(view.preparedObjectIDs == expected.subtracting([badID]) && view.preparedObjectCost == 3 * 1024,
                      "only the timing-out leaf may remain a placeholder")
        case "deterministic":
            try check(delays.isEmpty && view.preparedObjectIDs == expected.subtracting([badID]),
                      "deterministic failure must publish siblings without backoff")
        case "obsolete":
            try check(calls == 1 && delays.isEmpty && view.preparedObjectIDs.isEmpty,
                      "cancel/stale must abort without isolation or backoff")
        default: throw Failure(message: "unknown viewport case")
        }
    }
    @MainActor static func largeInitial() async throws {
        let doc = document(count: NativeReaderPreparedTextObject.largeDocumentThreshold + 1)
        let nodes = NativeReaderPreparedTextObject.initialNodes(in: doc)
        try check(NativeReaderPreparedTextObject.isLarge(doc) && nodes.count == 128, "test must use the large initial path")
        let store = NativeReaderDocumentStore(), view = NativeReaderTextView(store: store)
        defer { view.dispose() }
        view.setFrameSize(NSSize(width: 640, height: 600))
        view.preparesViewedWindowsOnly = true
        let context = NativeReaderRequestContext(requestID: UUID(), viewID: store.viewID,
            generation: try store.beginRequest(), target: doc.identity)
        let key = try view.preparationKey(for: doc, context: context)
        var calls = 0, delays = [Int]()
        let initial = try await NativeReaderWindowController.prepareInitialLazyObjects(nodes) { selected in
            calls += 1
            try check(selected.count == 128, "initial preparation must retain its object bound")
            throw NativeObjectError.unsupported("math-helper-timeout")
        }
        try check(calls == 1 && initial.isEmpty, "initial timeout must permit adoption without objects")
        try view.adopt(doc, context: context)
        view.layoutSubtreeIfNeeded()
        try check(store.document == doc && view.preparedObjectIDs.isEmpty, "large document must adopt placeholders")
        view.lazyRetryDelay = { delay in
            delays.append(delay)
            try check(view.preparedObjectIDs.isEmpty, "viewport timeout must not publish partial paint")
        }
        view.configureLazyObjects(key: key, initial: initial) { selected, current in
            calls += 1
            if calls <= 3 { throw NativeObjectError.unsupported("math-helper-timeout") }
            return values(selected, current)
        }
        try await finish(view)
        try check(delays == [1, 2] && !view.preparedObjectIDs.isEmpty && store.document == doc,
                  "adopted large document must publish objects through viewport backoff")
        for failure in [NativeObjectError.cancelled, .stale, .unsupported("math-helper-rejected")] {
            do {
                _ = try await NativeReaderWindowController.prepareInitialLazyObjects(Array(nodes.prefix(1))) { _ in throw failure }
                throw Failure(message: "initial preparation swallowed \(failure)")
            } catch let error as NativeObjectError {
                try check(error == failure, "initial preparation changed the propagated error")
            }
        }
        do {
            _ = try await NativeReaderWindowController.prepareInitialLazyObjects(nodes) { _ in throw CancellationError() }
            throw Failure(message: "initial preparation swallowed cancellation")
        } catch is CancellationError {}
    }
    @MainActor static func main() async throws {
        _ = NSApplication.shared.setActivationPolicy(.prohibited)
        switch CommandLine.arguments[1] {
        case "classification": try classification()
        case "propagation": try await propagation()
        case "timeout-budget": try await timeoutBudget()
        case "large-initial": try await largeInitial()
        case "deterministic":
            for error in [NativeObjectError.invalidGeometry, .unsupported("math-helper-rejected")] {
                try await viewport("deterministic", failure: error)
            }
        case "obsolete":
            for error in [CancellationError(), NativeObjectError.cancelled, NativeObjectError.stale,
                          NativeReaderTextFailure.staleGeometry] as [Error] {
                try await viewport("obsolete", failure: error)
            }
        case let mode: try await viewport(mode)
        }
        print("passed")
    }
}
