import Foundation

/// How ambiguous day/month numeric dates ("03/04/2020") are read.
public enum CsvDateOrder: String, Sendable, CaseIterable {
    case auto
    case monthFirst
    case dayFirst

    /// Resolves `.auto` against the current locale's date-field order. Callers
    /// resolve once (app launch) so hot parsing paths never touch the locale.
    public var resolved: CsvDateOrder {
        guard self == .auto else { return self }
        guard let template = DateFormatter.dateFormat(fromTemplate: "yMd", options: 0, locale: .current),
              let day = template.firstIndex(of: "d"),
              let month = template.firstIndex(of: "M") else {
            return .monthFirst
        }
        return day < month ? .dayFirst : .monthFirst
    }
}

public enum CsvDateSettings {
    private static let lock = NSLock()
    // Defaults to `.monthFirst` (no `Locale.current` access); the app resolves
    // the user's locale choice to a concrete order once at launch.
    nonisolated(unsafe) private static var orderStorage: CsvDateOrder = .monthFirst

    public static var order: CsvDateOrder {
        get { lock.withLock { orderStorage } }
        set { lock.withLock { orderStorage = newValue.resolved } }
    }
}

enum CsvDateParser {
    // Unambiguous formats (year-first, ISO-like, time-of-day, Korean).
    private static let baseFormats = [
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

    // Ambiguous day/month formats, tried in the order the setting selects; a
    // value whose leading field exceeds 12 falls through to the other ordering.
    private static let monthFirstFormats = ["MM/dd/yyyy", "M/d/yyyy", "MM-dd-yyyy", "M-d-yyyy"]
    private static let dayFirstFormats = ["dd/MM/yyyy", "d/M/yyyy", "dd-MM-yyyy", "d-M-yyyy"]

    private static func separatedFormats(order: CsvDateOrder) -> [String] {
        order == .dayFirst
            ? baseFormats + dayFirstFormats + monthFirstFormats
            : baseFormats + monthFirstFormats + dayFirstFormats
    }

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

        let order = CsvDateSettings.order
        if let date = parse(trimmed, formats: separatedFormats(order: order), cacheKey: "CsvDateParser.separated.\(order.rawValue)") {
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
