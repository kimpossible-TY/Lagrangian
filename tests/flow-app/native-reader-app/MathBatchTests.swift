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
        } else if mode == "single" || mode == "stale" {
            do {
                let _: [Int] = try await NativeMathBatchPolicy.run(range: 0..<8) { range in
                    attempts.append(range.count)
                    throw mode == "single" ? NativeObjectError.unsupported("math-helper-timeout") : NativeObjectError.stale
                }
                throw Failure(message: "failure accepted")
            } catch is NativeObjectError {}
            try check(attempts == (mode == "single" ? [8, 4, 2, 1] : [8]), "retry failed to terminate")
        } else {
            let results: [Int] = try await NativeMathBatchPolicy.run(range: 0..<7) { range in
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
