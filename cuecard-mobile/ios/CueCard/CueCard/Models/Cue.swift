import SwiftUI

/// A color a delivery cue can be tagged with.
///
/// The raw value is written into the script as `[note:green pause]`, so it has to
/// stay stable once shipped — renaming a case orphans every script that uses it.
enum CueColor: String, Codable, CaseIterable, Identifiable {
    case pink
    case yellow
    case green
    case blue
    case purple
    case red

    var id: String { rawValue }

    /// Used when a cue carries no explicit color, i.e. the original `[note text]` form.
    static let fallback: CueColor = .pink

    var displayName: String {
        rawValue.capitalized
    }

    func color(for colorScheme: ColorScheme) -> Color {
        switch self {
        case .pink: return AppColors.pink(for: colorScheme)
        case .yellow: return AppColors.yellow(for: colorScheme)
        case .green: return AppColors.green(for: colorScheme)
        case .blue: return AppColors.blue(for: colorScheme)
        case .purple: return AppColors.purple(for: colorScheme)
        case .red: return AppColors.red(for: colorScheme)
        }
    }

    func uiColor(isDarkMode: Bool) -> UIColor {
        switch self {
        case .pink: return isDarkMode ? AppColors.UIColors.Dark.pink : AppColors.UIColors.Light.pink
        case .yellow: return isDarkMode ? AppColors.UIColors.Dark.yellow : AppColors.UIColors.Light.yellow
        case .green: return isDarkMode ? AppColors.UIColors.Dark.green : AppColors.UIColors.Light.green
        case .blue: return isDarkMode ? AppColors.UIColors.Dark.blue : AppColors.UIColors.Light.blue
        case .purple: return isDarkMode ? AppColors.UIColors.Dark.purple : AppColors.UIColors.Light.purple
        case .red: return isDarkMode ? AppColors.UIColors.Dark.red : AppColors.UIColors.Light.red
        }
    }
}
