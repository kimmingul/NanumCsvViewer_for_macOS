import AppKit

/// User-selectable app appearance, overriding the system light/dark setting.
enum AppearancePreference: String, CaseIterable {
    case system
    case light
    case dark

    /// The `NSAppearance` to force, or `nil` to follow the system.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    var title: String {
        switch self {
        case .system: return L.t("System", "시스템")
        case .light: return L.t("Light", "라이트")
        case .dark: return L.t("Dark", "다크")
        }
    }

    static func from(rawValue: String?) -> AppearancePreference {
        AppearancePreference(rawValue: rawValue ?? "") ?? .system
    }
}

/// Grid text size, applied to data cells and headers independently of row
/// density (the user can combine either freely).
enum GridFontSize: String, CaseIterable {
    case small
    case medium
    case large

    var pointSize: CGFloat {
        switch self {
        case .small: return 11
        case .medium: return 13
        case .large: return 15
        }
    }

    /// Row-number gutter uses a slightly smaller monospaced digit font, kept
    /// proportional to the cell font.
    var gutterPointSize: CGFloat {
        pointSize - 1
    }

    var title: String {
        switch self {
        case .small: return L.t("Small", "작게")
        case .medium: return L.t("Medium", "보통")
        case .large: return L.t("Large", "크게")
        }
    }

    static func from(rawValue: String?) -> GridFontSize {
        GridFontSize(rawValue: rawValue ?? "") ?? .medium
    }
}
