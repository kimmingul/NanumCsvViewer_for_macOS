import Foundation

enum CsvDateParser {
    private static let dateHeaderTokens: Set<String> = [
        "date",
        "datetime",
        "time",
        "timestamp",
        "dt",
        "dob"
    ]

    private static let dateHeaderSubstrings = [
        "날짜",
        "일자",
        "일시",
        "생년",
        "년월",
        "월일"
    ]

    private static let separatedDateFormats = [
        "yyyy-MM-dd",
        "yyyy-M-d",
        "yyyy/MM/dd",
        "yyyy/M/d",
        "yyyy.MM.dd",
        "yyyy.M.d",
        "yyyy. MM. dd",
        "yyyy-MM",
        "yyyy-M",
        "yyyy/MM",
        "yyyy/M",
        "yyyy.MM",
        "yyyy.M",
        "MM/dd/yyyy",
        "M/d/yyyy",
        "dd/MM/yyyy",
        "d/M/yyyy",
        "MM-dd-yyyy",
        "M-d-yyyy",
        "dd-MM-yyyy",
        "d-M-yyyy",
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-M-d H:mm:ss",
        "yyyy-MM-dd HH:mm",
        "yyyy-M-d H:mm",
        "yyyy/MM/dd HH:mm:ss",
        "yyyy/M/d H:mm:ss",
        "yyyy/MM/dd HH:mm",
        "yyyy/M/d H:mm",
        "yyyy.MM.dd HH:mm:ss",
        "yyyy.M.d H:mm:ss",
        "yyyy.MM.dd HH:mm",
        "yyyy.M.d H:mm",
        "yyyy년 M월 d일",
        "yyyy년 M월 d일 H:mm:ss",
        "yyyy년 M월 d일 H:mm"
    ]

    private static let compactDateFormats = [
        "yyyyMMdd",
        "yyyyMMddHHmmss"
    ]

    static func parse(_ value: String, allowCompactNumeric: Bool = false) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let date = ISO8601DateFormatter().date(from: trimmed) {
            return date
        }

        if let date = parse(trimmed, formats: separatedDateFormats) {
            return date
        }

        if allowCompactNumeric, let date = parse(trimmed, formats: compactDateFormats) {
            return date
        }

        return nil
    }

    static func headerSuggestsDate(_ name: String) -> Bool {
        let lower = name.lowercased()
        if dateHeaderSubstrings.contains(where: { lower.contains($0) }) {
            return true
        }
        let tokens = lower.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        return tokens.contains { dateHeaderTokens.contains($0) }
    }

    private static func parse(_ value: String, formats: [String]) -> Date? {
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.isLenient = false
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return nil
    }
}
