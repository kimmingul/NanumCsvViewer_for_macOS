import Foundation

enum L {
    static let supportedLanguages: [(code: String, name: String)] = [
        ("en", "English"), ("ko", "한국어"), ("ja", "日本語"),
        ("zh-Hans", "简体中文"), ("zh-Hant", "繁體中文"),
        ("fr", "Français"), ("es", "Español"), ("de", "Deutsch"),
        ("pt-BR", "Português (Brasil)"), ("it", "Italiano"), ("ru", "Русский"),
        ("vi", "Tiếng Việt"), ("id", "Bahasa Indonesia"), ("th", "ไทย"),
        ("pl", "Polski"), ("nl", "Nederlands")
    ]

    private static let preferenceKey = "NanumCsvViewerLanguage"

    static var selectedLanguageCode: String? {
        guard let value = UserDefaults.standard.string(forKey: preferenceKey),
              supportedLanguages.contains(where: { $0.code == value }) else { return nil }
        return value
    }

    /// A launch snapshot: changing the setting never mixes languages in existing windows.
    static let languageCode = resolveLanguage(
        preferredLanguages: Locale.preferredLanguages,
        selectedLanguageCode: selectedLanguageCode
    )
    static let locale = Locale(identifier: languageCode)

    static func setLanguage(code: String?) {
        // Freeze this launch's language even if Settings is the first localization access.
        _ = languageCode
        if let code {
            guard supportedLanguages.contains(where: { $0.code == code }) else { return }
            UserDefaults.standard.set(code, forKey: preferenceKey)
        } else {
            UserDefaults.standard.removeObject(forKey: preferenceKey)
        }
    }

    static func resolveLanguage(preferredLanguages: [String], selectedLanguageCode: String? = nil) -> String {
        if let selectedLanguageCode,
           supportedLanguages.contains(where: { $0.code == selectedLanguageCode }) {
            return selectedLanguageCode
        }
        for identifier in preferredLanguages {
            let components = identifier.replacingOccurrences(of: "_", with: "-").lowercased().split(separator: "-")
            guard let base = components.first else { continue }
            if base == "zh" {
                // An explicit script wins over a region, including zh-Hans-HK.
                if components.contains("hant") { return "zh-Hant" }
                if components.contains("hans") { return "zh-Hans" }
                return components.contains(where: { ["tw", "hk", "mo"].contains($0) }) ? "zh-Hant" : "zh-Hans"
            }
            if base == "pt" { return "pt-BR" }
            if base == "in" { return "id" } // Legacy Indonesian language identifier.
            if let match = supportedLanguages.first(where: { $0.code == base }) { return match.code }
        }
        return "en"
    }

    /// The second literal is the Korean authoring source for the catalog extractor.
    /// It is deliberately unevaluated: interpolation values are captured once, in English order.
    static func t(_ english: Text, _: @autoclosure () -> String) -> String {
        translate(english, catalog: catalog)
    }

    static func translate(_ text: Text, catalog: [String: String]) -> String {
        if let translated = catalog[text.key], !translated.isEmpty,
           let result = render(translated, arguments: text.arguments) {
            return result
        }
        // Fallback is a resilience boundary, not evidence of translation coverage.
        // Scripts/localization-catalog.swift --check rejects missing or malformed catalogs.
        return render(text.key, arguments: text.arguments) ?? text.key
    }

    private static let catalog: [String: String] = {
        guard languageCode != "en", let url = catalogURL(languageCode: languageCode),
              let data = try? Data(contentsOf: url),
              let values = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return values
    }()

    static func catalogURL(languageCode: String) -> URL? {
        // A signed .app nests SwiftPM's bundle under Contents/Resources. Check it
        // before Bundle.module, whose generated accessor traps if it cannot find its bundle.
        if let resources = Bundle.main.resourceURL {
            let nested = resources.appendingPathComponent("NanumCsvViewerMac_NanumCsvViewerMac.bundle", isDirectory: true)
            if let bundle = Bundle(url: nested),
               let url = bundle.url(forResource: languageCode, withExtension: "json", subdirectory: "Localization") {
                return url
            }
            if let url = Bundle.main.url(forResource: languageCode, withExtension: "json", subdirectory: "Localization") {
                return url
            }
        }
        #if SWIFT_PACKAGE
        // Release apps must not accidentally use a developer's surviving .build directory.
        guard Bundle.main.bundleURL.pathExtension != "app" else { return nil }
        return Bundle.module.url(forResource: languageCode, withExtension: "json", subdirectory: "Localization")
        #else
        return nil
        #endif
    }

    /// One-pass substitution never interprets braces inside user data as placeholders.
    static func render(_ template: String, arguments: [String]) -> String? {
        if arguments.isEmpty, !template.contains("{"), !template.contains("}") { return template }
        var result = String()
        result.reserveCapacity(template.utf8.count)
        var used = Set<Int>()
        var cursor = template.startIndex
        while cursor < template.endIndex {
            let character = template[cursor]
            let next = template.index(after: cursor)
            if character == "{" {
                if next < template.endIndex, template[next] == "{" {
                    result.append("{")
                    cursor = template.index(after: next)
                    continue
                }
                guard let end = template[next...].firstIndex(of: "}"),
                      !template[next..<end].isEmpty,
                      template[next..<end].allSatisfy({ $0.isASCII && $0.isNumber }),
                      let index = Int(template[next..<end]), arguments.indices.contains(index),
                      used.insert(index).inserted else { return nil }
                result.append(arguments[index])
                cursor = template.index(after: end)
            } else if character == "}" {
                guard next < template.endIndex, template[next] == "}" else { return nil }
                result.append("}")
                cursor = template.index(after: next)
            } else {
                result.append(character)
                cursor = next
            }
        }
        return used.count == arguments.count ? result : nil
    }

    static func formatFloatingPoint<T: BinaryFloatingPoint>(_ value: T, locale: Locale) -> String {
        // Match Swift's shortest round-trip precision, not FormatStyle's default
        // fractional rounding or all binary representation digits (Float(0.1)).
        var significantDigits = 0
        var foundNonzero = false
        for byte in String(describing: value).utf8 {
            if byte == 101 || byte == 69 { break } // Exponent digits are not precision.
            guard byte >= 48, byte <= 57 else { continue }
            if byte != 48 { foundNonzero = true }
            if foundNonzero { significantDigits += 1 }
        }
        return FloatingPointFormatStyle<T>(locale: locale)
            .precision(.significantDigits(1...max(1, significantDigits)))
            .format(value)
    }

    struct Text: ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
        let key: String
        let arguments: [String]

        init(stringLiteral value: String) {
            key = Self.escapeBraces(value)
            arguments = []
        }

        init(stringInterpolation: StringInterpolation) {
            key = stringInterpolation.key
            arguments = stringInterpolation.arguments
        }

        fileprivate static func escapeBraces(_ literal: String) -> String {
            guard literal.contains("{") || literal.contains("}") else { return literal }
            return literal.replacingOccurrences(of: "{", with: "{{").replacingOccurrences(of: "}", with: "}}")
        }

        struct StringInterpolation: StringInterpolationProtocol {
            var key: String
            var arguments: [String]

            init(literalCapacity: Int, interpolationCount: Int) {
                key = String()
                key.reserveCapacity(literalCapacity + interpolationCount * 3)
                arguments = []
                arguments.reserveCapacity(interpolationCount)
            }

            mutating func appendLiteral(_ literal: String) {
                key.append(Text.escapeBraces(literal))
            }

            mutating func appendInterpolation<T>(_ value: T) {
                appendArgument(String(describing: value))
            }

            mutating func appendInterpolation<T: BinaryInteger>(_ value: T) {
                appendArgument(IntegerFormatStyle<T>(locale: L.locale).format(value))
            }

            mutating func appendInterpolation<T: BinaryFloatingPoint>(_ value: T) {
                appendArgument(L.formatFloatingPoint(value, locale: L.locale))
            }

            mutating func appendInterpolation(_ value: Decimal) {
                appendArgument(value.formatted(.number.precision(.significantDigits(1...38)).locale(L.locale)))
            }

            private mutating func appendArgument(_ value: String) {
                key.append("{\(arguments.count)}")
                arguments.append(value)
            }
        }
    }
}
