import SwiftUI

/// App colors matching cuecard-app design system
struct AppColors {
    // MARK: - Dark Mode Colors
    struct Dark {
        static let background = Color(hex: "#000000")
        static let textPrimary = Color.white
        static let textSecondary = Color(hex: "#a8a6a6")
        static let yellow = Color(hex: "#febc2e")
        static let green = Color(hex: "#19c332")
        static let pink = Color(hex: "#ff6adf")
        static let red = Color(hex: "#ff605c")
        static let blue = Color(hex: "#4da6ff")
        static let purple = Color(hex: "#b07cff")
    }

    // MARK: - Light Mode Colors
    struct Light {
        static let background = Color(hex: "#f7f4ef")
        static let textPrimary = Color(hex: "#141312")
        static let textSecondary = Color(hex: "#5f5b55")
        static let yellow = Color(hex: "#b36a00")
        static let green = Color(hex: "#0c7a29")
        static let pink = Color(hex: "#b82a82")
        static let red = Color(hex: "#c23a36")
        static let blue = Color(hex: "#1462c4")
        static let purple = Color(hex: "#6b3fbe")
    }

    // MARK: - UIColor versions for UIKit
    struct UIColors {
        struct Dark {
            static let background = UIColor(hex: "#000000")
            static let textPrimary = UIColor.white
            static let textSecondary = UIColor(hex: "#a8a6a6")
            static let yellow = UIColor(hex: "#febc2e")
            static let green = UIColor(hex: "#19c332")
            static let pink = UIColor(hex: "#ff6adf")
            static let red = UIColor(hex: "#ff605c")
            static let blue = UIColor(hex: "#4da6ff")
            static let purple = UIColor(hex: "#b07cff")
        }

        struct Light {
            static let background = UIColor(hex: "#f7f4ef")
            static let textPrimary = UIColor(hex: "#141312")
            static let textSecondary = UIColor(hex: "#5f5b55")
            static let yellow = UIColor(hex: "#b36a00")
            static let green = UIColor(hex: "#0c7a29")
            static let pink = UIColor(hex: "#b82a82")
            static let red = UIColor(hex: "#c23a36")
            static let blue = UIColor(hex: "#1462c4")
            static let purple = UIColor(hex: "#6b3fbe")
        }
    }
}

// MARK: - Environment-aware colors
extension AppColors {
    /// Get background color based on color scheme
    static func background(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Dark.background : Light.background
    }

    /// Get primary text color based on color scheme
    static func textPrimary(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Dark.textPrimary : Light.textPrimary
    }

    /// Get secondary text color based on color scheme
    static func textSecondary(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Dark.textSecondary : Light.textSecondary
    }

    /// Get yellow accent color based on color scheme
    static func yellow(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Dark.yellow : Light.yellow
    }

    /// Get green accent color based on color scheme
    static func green(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Dark.green : Light.green
    }

    /// Get pink accent color based on color scheme
    static func pink(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Dark.pink : Light.pink
    }

    /// Get red accent color based on color scheme
    static func red(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Dark.red : Light.red
    }

    /// Get blue accent color based on color scheme
    static func blue(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Dark.blue : Light.blue
    }

    /// Get purple accent color based on color scheme
    static func purple(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Dark.purple : Light.purple
    }
}

// MARK: - Timer color helper
extension AppColors {
    /// Get timer color based on remaining time and total duration
    /// - Green: > 50% time remaining
    /// - Yellow: 20-50% time remaining
    /// - Red: < 20% time remaining or overtime
    static func timerColor(remainingSeconds: Int, totalSeconds: Int, colorScheme: ColorScheme) -> Color {
        guard totalSeconds > 0 else {
            return green(for: colorScheme)
        }

        let percentage = Double(remainingSeconds) / Double(totalSeconds)

        if remainingSeconds < 0 {
            return red(for: colorScheme) // Overtime
        } else if percentage <= 0.2 {
            return yellow(for: colorScheme)
        } else {
            return green(for: colorScheme)
        }
    }

    /// UIColor version for UIKit
    static func timerUIColor(remainingSeconds: Int, totalSeconds: Int, isDarkMode: Bool) -> UIColor {
        guard totalSeconds > 0 else {
            return isDarkMode ? UIColors.Dark.green : UIColors.Light.green
        }

        let percentage = Double(remainingSeconds) / Double(totalSeconds)

        if remainingSeconds < 0 {
            return isDarkMode ? UIColors.Dark.red : UIColors.Light.red
        } else if percentage <= 0.2 {
            return isDarkMode ? UIColors.Dark.yellow : UIColors.Light.yellow
        } else {
            return isDarkMode ? UIColors.Dark.green : UIColors.Light.green
        }
    }
}

// MARK: - Color hex initializer
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - UIColor hex initializer
extension UIColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: CGFloat(a) / 255
        )
    }
}
