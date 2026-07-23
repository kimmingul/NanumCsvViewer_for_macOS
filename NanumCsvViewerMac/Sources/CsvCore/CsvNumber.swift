import Foundation

public enum CsvNumberFormat: String, Sendable, CaseIterable {
    case auto
    case us
    case european
    case plain

    /// Resolves `.auto` against the current locale; other cases pass through.
    /// Callers resolve once (e.g. at app launch) and store the concrete result,
    /// so hot parsing paths never touch `Locale.current`.
    public var resolved: CsvNumberFormat {
        guard self == .auto else { return self }
        return Locale.current.decimalSeparator == "," ? .european : .us
    }
}

/// Locale-aware numeric parsing for user CSV data. `Double()` only understands
/// `"1234.56"`, but real data uses grouping and locale decimals (`"1,234.56"`,
/// `"1.234,56"`). All numeric extraction for stats / analytics / pivots /
/// filters / type inference routes through here so inference, aggregation, and
/// sorting agree on which cells are numbers and what they mean. The format
/// defaults to the current locale and can be overridden by the user.
public enum CsvNumber {
    private static let lock = NSLock()
    // Defaults to `.plain` (pure Double, no `Locale.current`) so library/test
    // use never touches locale state. The app resolves the user's locale choice
    // once at launch and stores a concrete format here.
    nonisolated(unsafe) private static var formatStorage: CsvNumberFormat = .plain

    public static var format: CsvNumberFormat {
        get { lock.withLock { formatStorage } }
        set { lock.withLock { formatStorage = newValue.resolved } }
    }

    public static func parse(_ value: String) -> Double? {
        parse(value, format: format)
    }

    static func parse(_ value: String, format: CsvNumberFormat) -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        switch format {
        case .plain:
            return Double(trimmed)
        case .us:
            // '.' is the decimal in both US convention and Swift's Double, so
            // Double() already handles un-grouped values; strip ',' otherwise.
            if let direct = Double(trimmed) { return direct }
            return normalized(trimmed, grouping: ",", decimal: ".")
        case .european:
            // '.' groups and ',' is the decimal, so Double() would misread it.
            return normalized(trimmed, grouping: ".", decimal: ",")
        case .auto:
            return Double(trimmed) // unreachable once resolved; kept total
        }
    }

    private static func normalized(_ value: String, grouping: Character, decimal: Character) -> Double? {
        var out = ""
        out.reserveCapacity(value.count)
        for ch in value {
            if ch == grouping { continue }
            out.append(ch == decimal ? "." : ch)
        }
        // Double() rejects anything that isn't a clean number after normalization.
        return out.isEmpty ? nil : Double(out)
    }
}
