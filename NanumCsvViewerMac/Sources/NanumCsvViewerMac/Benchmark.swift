import Foundation

/// One timed operation in a benchmark run.
struct BenchmarkResult: Equatable {
    let name: String
    let milliseconds: Double
    let rowsProcessed: Int

    var rowsPerSecond: Int {
        guard milliseconds > 0 else { return 0 }
        return Int((Double(rowsProcessed) / (milliseconds / 1000)).rounded())
    }
}

/// Formats benchmark results for the performance inspector. Kept separate from
/// the timing so it can be unit-tested deterministically.
enum BenchmarkReport {
    static func lines(results: [BenchmarkResult], iteration: Int) -> [String] {
        var out = [L.t("Benchmark run #\(iteration)", "벤치마크 실행 #\(iteration)")]
        for result in results {
            out.append(String(
                format: "%@: %.1f ms · %@ rows · %@ rows/s",
                result.name,
                result.milliseconds,
                result.rowsProcessed.formatted(),
                result.rowsPerSecond.formatted()
            ))
        }
        let total = results.reduce(0) { $0 + $1.milliseconds }
        out.append(String(format: L.t("Total: %.1f ms", "합계: %.1f ms"), total))
        return out
    }
}

/// Carries benchmark results from the background operation to the main-thread
/// completion. Writes and the later read are sequenced (completion runs after
/// the operation), so the unchecked conformance is safe.
final class BenchmarkResultsBox: @unchecked Sendable {
    var results: [BenchmarkResult] = []
}

extension Duration {
    /// Elapsed milliseconds as a Double (seconds + attoseconds fraction).
    /// 1 s = 1e18 attoseconds = 1e3 ms, so attoseconds → ms is ÷1e15.
    var milliseconds: Double {
        Double(components.seconds) * 1000 + Double(components.attoseconds) / 1_000_000_000_000_000
    }
}
