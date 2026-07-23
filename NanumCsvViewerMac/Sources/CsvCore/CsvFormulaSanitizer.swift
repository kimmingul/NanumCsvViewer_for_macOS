import Foundation

/// Neutralizes CSV/TSV cells that a spreadsheet app (Excel, Numbers, Sheets)
/// would interpret as a formula when the exported file is reopened there — the
/// classic "CSV injection" vector (`=HYPERLINK(...)`, `=cmd|'/c calc'!A1`).
///
/// Opt-in only: prefixing neutralizes legitimate values too (a leading `-`
/// negative number, an intended formula), so callers gate this on a
/// user-controlled setting that defaults to off.
public enum CsvFormulaSanitizer {
    private static let triggers: Set<Character> = ["=", "+", "-", "@"]

    /// Prefixes an at-risk cell with an apostrophe so the spreadsheet treats it
    /// as text; leaves everything else untouched.
    public static func sanitize(_ value: String) -> String {
        guard let first = value.first else { return value }
        if triggers.contains(first) || first == "\t" || first == "\r" {
            return "'" + value
        }
        return value
    }
}
