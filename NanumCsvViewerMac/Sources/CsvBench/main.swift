import CsvCore
import Darwin
import Foundation

@main
struct CsvBench {
    static let defaultSize: Int64 = 1_073_741_824
    static let defaultPath = "BenchmarkData/one_gib.csv"

    static func main() throws {
        let options = Options(arguments: CommandLine.arguments)
        let path = options.path
        if options.generate || !FileManager.default.fileExists(atPath: path) {
            try generateCsv(path: path, targetBytes: options.size)
        }

        let fileSize = try FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber
        print("CSV benchmark")
        print("file: \(path)")
        print("size: \(formatBytes(fileSize?.int64Value ?? 0))")

        var results: [(String, Double, String)] = []

        let openResult = try measure("open") {
            try VirtualCsvDocument.open(path: path)
        }
        let document = openResult.value
        results.append(("open", openResult.seconds, "header=\(document.columnCount) columns"))

        let indexResult = try measure("index") {
            try document.runIndexing(progress: { _ in }, cancellation: CancellationFlag())
        }
        let mbps = Double(document.fileLength) / 1_048_576.0 / indexResult.seconds
        results.append(("index", indexResult.seconds, "\(document.dataRowsAvailable.formatted()) rows, \(String(format: "%.1f", mbps)) MiB/s"))

        let rowReadResult = try measure("sample rows") {
            try sampleRows(document: document, samples: options.rowSamples)
        }
        results.append(("sample rows", rowReadResult.seconds, "\(options.rowSamples.formatted()) rows"))

        let filterResult = try measure("filter") {
            try document.filterColumnEquals(column: 1, value: "2024-01-01", withinCurrentView: false, progress: nil as ((Int) -> Void)?, cancellation: CancellationFlag())
        }
        results.append(("filter", filterResult.seconds, "\(document.displayRowCount.formatted()) matches"))

        document.clearView()

        let containsResult = try measure("contains") {
            try document.filterColumnContains(column: 1, term: "2024-01", withinCurrentView: false, progress: nil as ((Int) -> Void)?, cancellation: CancellationFlag())
        }
        results.append(("contains", containsResult.seconds, "\(document.displayRowCount.formatted()) matches"))

        document.clearView()

        if !options.skipSort {
            let sortResult = try measure("sort") {
                try document.sort(column: 1, ascending: true, progress: nil as ((Int) -> Void)?, cancellation: CancellationFlag())
            }
            results.append(("sort", sortResult.seconds, "\(document.displayRowCount.formatted()) rows"))
        }

        print("")
        for result in results {
            print("\(result.0.padding(toLength: 12, withPad: " ", startingAt: 0)) \(formatSeconds(result.1))  \(result.2)")
        }
    }

    private static func sampleRows(document: VirtualCsvDocument, samples: Int) throws {
        let total = max(1, document.dataRowsAvailable)
        let count = min(samples, total)
        let stride = max(1, total / count)
        var row = 0
        for _ in 0..<count {
            _ = try document.getDataRow(row)
            row = min(total - 1, row + stride)
        }
    }

    private static func generateCsv(path: String, targetBytes: Int64) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        let fd = Darwin.open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        guard fd >= 0 else { throw CsvBenchError.fileCreateFailed(path) }
        defer { Darwin.close(fd) }

        let header = "id,date,item,result,patient_id,specimen_id,note\n"
        try writeAll(fd: fd, data: Data(header.utf8))
        var written = Int64(header.utf8.count)

        let filler = String(repeating: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789", count: 24)
        var rowNumber = 0
        let blockLimit = 8 * 1_024 * 1_024
        var block = Data()
        block.reserveCapacity(blockLimit + 2048)

        let start = DispatchTime.now().uptimeNanoseconds
        while written < targetBytes {
            block.removeAll(keepingCapacity: true)
            while block.count < blockLimit, written + Int64(block.count) < targetBytes {
                rowNumber += 1
                let month = (rowNumber % 12) + 1
                let day = (rowNumber % 28) + 1
                let line = String(
                    format: "A%09d,2024-%02d-%02d,TestItem%04d,Result%04d,%010d,%012d,%@\n",
                    rowNumber,
                    month,
                    day,
                    rowNumber % 300,
                    rowNumber % 500,
                    1_000_000_000 + rowNumber,
                    2_200_000_000_000 + rowNumber,
                    filler
                )
                block.append(contentsOf: line.utf8)
            }
            try writeAll(fd: fd, data: block)
            written += Int64(block.count)
            if rowNumber % 100_000 == 0 {
                let elapsed = secondsSince(start)
                let mbps = Double(written) / 1_048_576.0 / max(elapsed, 0.001)
                print("generated \(formatBytes(written))  \(String(format: "%.1f", mbps)) MiB/s")
            }
        }

        print("generated \(rowNumber.formatted()) rows, \(formatBytes(written))")
    }

    private static func writeAll(fd: Int32, data: Data) throws {
        try data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var written = 0
            while written < raw.count {
                let result = Darwin.write(fd, base.advanced(by: written), raw.count - written)
                if result < 0 { throw CsvBenchError.shortWrite }
                written += result
            }
        }
    }

    private static func measure<T>(_ name: String, _ block: () throws -> T) rethrows -> (value: T, seconds: Double) {
        let start = DispatchTime.now().uptimeNanoseconds
        let value = try block()
        let seconds = secondsSince(start)
        print("\(name) completed in \(formatSeconds(seconds))")
        return (value, seconds)
    }

    private static func secondsSince(_ start: UInt64) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000.0
    }

    private static func formatSeconds(_ seconds: Double) -> String {
        String(format: "%.3f s", seconds)
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var unit = 0
        while value >= 1024, unit < units.count - 1 {
            value /= 1024
            unit += 1
        }
        return String(format: "%.2f %@", value, units[unit])
    }
}

private struct Options {
    var path = CsvBench.defaultPath
    var size = CsvBench.defaultSize
    var generate = false
    var skipSort = false
    var rowSamples = 50_000

    init(arguments: [String]) {
        var i = 1
        while i < arguments.count {
            switch arguments[i] {
            case "--path" where i + 1 < arguments.count:
                path = arguments[i + 1]
                i += 2
            case "--size" where i + 1 < arguments.count:
                size = Int64(arguments[i + 1]) ?? size
                i += 2
            case "--generate":
                generate = true
                i += 1
            case "--skip-sort":
                skipSort = true
                i += 1
            case "--row-samples" where i + 1 < arguments.count:
                rowSamples = Int(arguments[i + 1]) ?? rowSamples
                i += 2
            default:
                i += 1
            }
        }
    }
}

private enum CsvBenchError: Error {
    case fileCreateFailed(String)
    case shortWrite
}
