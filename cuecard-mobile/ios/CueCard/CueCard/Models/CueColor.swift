import SwiftUI

/// The color every delivery cue is drawn in.
///
/// One color covers the whole app — the choice lives in Settings, not in the
/// script — so changing it recolors every cue in every script at once.
///
/// The raw value is persisted with the settings, so it has to stay stable once
/// shipped: renaming a case resets that user's choice back to the default.
enum CueColor: String, Codable, CaseIterable, Identifiable {
    case pink
    case yellow
    case green
    case blue
    case purple
    case red

    var id: String { rawValue }

    /// What cues are drawn in until the user picks something else.
    static let `default`: CueColor = .pink

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
