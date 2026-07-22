import Foundation

/// Shared rules for deciding whether a raw CSV token should be treated as a
/// number during *automatic type inference*. Some strings parse through
/// `Double` but are really identifiers, and treating them as numbers corrupts
/// the data:
///   - a leading `0` followed by more digits — zip codes, `"00123"`, `"007"`
///   - an all-digit integer longer than 15 digits, beyond `Double`'s exact
///     integer range (2^53 ≈ 9.0e15), where distinct IDs silently collapse
///
/// Manual, user-requested conversions bypass these rules — the user is opting
/// in — so this is used only by inference (ColumnStatistics / CsvDataQuality),
/// never by `ColumnTypeConversion`.
public enum NumericInference {
    /// Returns the numeric value of `value`, or `nil` when it parses as a number
    /// but should be kept as text (an identifier-like token).
    public static func number(from value: String) -> Double? {
        guard let parsed = Double(value) else { return nil }
        return isIdentifierLike(value) ? nil : parsed
    }

    static func isIdentifierLike(_ value: String) -> Bool {
        var digits = value[...]
        if let first = digits.first, first == "+" || first == "-" {
            digits = digits.dropFirst()
        }
        // Only pure-digit tokens qualify; anything with a decimal point or
        // exponent is a genuine number.
        guard !digits.isEmpty, digits.allSatisfy({ $0 >= "0" && $0 <= "9" }) else {
            return false
        }
        if digits.count > 1, digits.first == "0" {
            return true
        }
        return digits.count > 15
    }
}
