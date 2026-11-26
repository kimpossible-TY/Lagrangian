import Foundation
private struct Failure: Error { let message: String }
@main struct MathBatchTests {
    static func check(_ value: Bool, _ message: String) throws { if !value { throw Failure(message: message) } }
    static func main() async throws {
        let mode = CommandLine.arguments[1]
        var attempts = [Int]()
        if mode == "limits" {
            try check(NativeMathBatchPolicy.chunkItems == 256, "Swift batch chunk size")
            try check(NativeMathBatchPolicy.chunkItems <= NativeMathBatchPolicy.maximumItems, "chunk size within helper ceiling")
            try check(NativeMathBatchPolicy.outputLimit(items: 1) == 8 * 1024 * 1024 + 1, "single stdout cap")
            try check(NativeMathBatchPolicy.outputLimit(items: 4) == 32 * 1024 * 1024 + 1, "scaled stdout cap")
            try check(NativeMathBatchPolicy.outputLimit(items: 512) == 64 * 1024 * 1024 + 1, "bounded stdout cap")
            try check(NativeMathBatchPolicy.timeout(base: 10, items: 4) == 40 && NativeMathBatchPolicy.timeout(base: 10, items: 512) == 60, "scaled bounded deadline")
        } else if mode == "deadline" {
            var elapsed: TimeInterval = 0
            var deadlines = [TimeInterval]()
            do {
                let _: [Int] = try await NativeMathBatchPolicy.run(range: 0..<256, now: { elapsed }) { range, timeout in
                    attempts.append(range.count); deadlines.append(timeout)
                    if range.contains(0) {
                        elapsed += timeout // One formula always consumes the entire subprocess deadline.
                        throw NativeObjectError.unsupported("math-helper-timeout")
                    }
                    return Array(range)
                }
                throw Failure(message: "hanging item accepted")
            } catch NativeObjectError.unsupported("math-helper-timeout") {}
            try check(attempts == [256, 128], "hanging item exceeded attempt bound")
            try check(elapsed == 120 && deadlines.reduce(0, +) == 120, "chunk exceeded cumulative deadline")
        } else if mode == "single" || mode == "stale" || mode == "output-limit" {
            do {
                let _: [Int] = try await NativeMathBatchPolicy.run(range: 0..<8) { range, _ in
                    attempts.append(range.count)
                    if mode == "output-limit" { throw NativeObjectError.unsupported("output-limit") }
                    throw mode == "single" ? NativeObjectError.unsupported("math-helper-timeout") : NativeObjectError.stale
                }
                throw Failure(message: "failure accepted")
            } catch is NativeObjectError {}
            try check(attempts == (mode == "single" ? [8, 4, 2, 1] : [8]), "retry failed to terminate")
        } else {
            let results: [Int] = try await NativeMathBatchPolicy.run(range: 0..<7) { range, _ in
                attempts.append(range.count)
                if range.count > 2 { throw mode == "budget" ? NativeObjectError.budget : NativeObjectError.unsupported("math-helper-timeout") }
                return Array(range)
            }
            try check(results == Array(0..<7), "halving lost item order")
            try check(attempts == [7, 3, 1, 2, 4, 2, 2], "unexpected halving")
        }
        print("passed")
    }
}
