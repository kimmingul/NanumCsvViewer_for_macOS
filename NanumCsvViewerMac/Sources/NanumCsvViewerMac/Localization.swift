import Foundation

enum L {
    private static var korean: Bool {
        Locale.preferredLanguages.first?.hasPrefix("ko") == true
    }

    static func t(_ english: String, _ koreanText: String) -> String {
        korean ? koreanText : english
    }
}
