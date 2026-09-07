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
            let elapsed = result.milliseconds.formatted(.number.precision(.fractionLength(1)).locale(L.locale))
            out.append(L.t("\(result.name): \(elapsed) ms · \(result.rowsProcessed) rows · \(result.rowsPerSecond) rows/s", "\(result.name): \(elapsed) ms · \(result.rowsProcessed)행 · 초당 \(result.rowsPerSecond)행"))
        }
        let total = results.reduce(0) { $0 + $1.milliseconds }
        let elapsed = total.formatted(.number.precision(.fractionLength(1)).locale(L.locale))
        out.append(L.t("Total: \(elapsed) ms", "합계: \(elapsed) ms"))
        return out
    }
}

extension Duration {
    /// Elapsed milliseconds as a Double (seconds + attoseconds fraction).
    /// 1 s = 1e18 attoseconds = 1e3 ms, so attoseconds → ms is ÷1e15.
    var milliseconds: Double {
        Double(components.seconds) * 1000 + Double(components.attoseconds) / 1_000_000_000_000_000
    }
}
