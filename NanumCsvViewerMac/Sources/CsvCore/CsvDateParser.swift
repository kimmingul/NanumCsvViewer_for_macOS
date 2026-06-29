import Foundation

enum CsvDateParser {
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
        guard looksDateLike(trimmed, allowCompactNumeric: allowCompactNumeric) else { return nil }

        if looksISO8601DateTime(trimmed), let date = iso8601Formatter.date(from: trimmed) {
            return date
        }

        if let date = parse(trimmed, formats: separatedDateFormats, cacheKey: "CsvDateParser.separated") {
            return date
        }

        if allowCompactNumeric, let date = parse(trimmed, formats: compactDateFormats, cacheKey: "CsvDateParser.compact") {
            return date
        }

        return nil
    }

    private static func looksDateLike(_ value: String, allowCompactNumeric: Bool) -> Bool {
        var digitCount = 0
        var hasSeparator = false
        var hasKoreanDateMarker = false
        var scalarCount = 0
        var allDigits = true

        for scalar in value.unicodeScalars {
            scalarCount += 1
            if CharacterSet.decimalDigits.contains(scalar) {
                digitCount += 1
            } else {
                allDigits = false
            }
            switch scalar {
            case "-", "/", ".", ":", " ", "T", "Z", "+":
                hasSeparator = true
            case "년", "월", "일":
                hasKoreanDateMarker = true
            default:
                break
            }
        }

        if allowCompactNumeric, allDigits, digitCount == scalarCount, (digitCount == 8 || digitCount == 14) {
            return true
        }
        guard digitCount >= 5 else { return false }
        return hasSeparator || hasKoreanDateMarker
    }

    private static func looksISO8601DateTime(_ value: String) -> Bool {
        value.contains("T") || value.hasSuffix("Z")
    }

    private static var iso8601Formatter: ISO8601DateFormatter {
        let key = "CsvDateParser.iso8601"
        let dictionary = Thread.current.threadDictionary
        if let formatter = dictionary[key] as? ISO8601DateFormatter {
            return formatter
        }
        let formatter = ISO8601DateFormatter()
        dictionary[key] = formatter
        return formatter
    }

    private static func parse(_ value: String, formats: [String], cacheKey: String) -> Date? {
        for formatter in cachedFormatters(formats: formats, key: cacheKey) {
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return nil
    }

    private static func cachedFormatters(formats: [String], key: String) -> [DateFormatter] {
        let dictionary = Thread.current.threadDictionary
        if let formatters = dictionary[key] as? [DateFormatter] {
            return formatters
        }
        let formatters = formats.map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.isLenient = false
            formatter.dateFormat = format
            return formatter
        }
        dictionary[key] = formatters
        return formatters
    }
}
