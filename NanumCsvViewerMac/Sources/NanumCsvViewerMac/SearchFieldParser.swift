import Foundation
import CsvCore

enum SearchFieldParser {
    static func parse(_ rawText: String, column: Int?) throws -> CsvSearchQuery {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("regex:") {
            return try CsvSearchQuery(text: String(text.dropFirst("regex:".count)), mode: .regex, column: column)
        }
        if text.hasPrefix("/") && text.hasSuffix("/") && text.count >= 2 {
            return try CsvSearchQuery(text: String(text.dropFirst().dropLast()), mode: .regex, column: column)
        }
        if text.hasPrefix("fuzzy:") {
            return try CsvSearchQuery(text: String(text.dropFirst("fuzzy:".count)), mode: .fuzzy, column: column)
        }
        return try CsvSearchQuery(text: text, mode: .contains, column: column)
    }
}
