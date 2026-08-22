import SwiftUI
import UIKit

// MARK: - Hex color helper

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }

    /// Adaptive color with separate light / dark values.
    init(light: UInt32, dark: UInt32) {
        self.init(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }

    func withAlphaComponents(_ alpha: Double) -> Color {
        opacity(alpha)
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Flux brand palette (mirrors flux_colors.dart)

enum FluxColors {
    // Accents (same in light and dark).
    static let blue = Color(hex: 0x3E8BFF)
    static let violet = Color(hex: 0x8A5CFF)
    static let cyan = Color(hex: 0x4AC8F0)
    static let online = Color(hex: 0x34C77B)
    static let danger = Color(hex: 0xFF4D5E)
    static let warning = Color(hex: 0xFFB020)
    static let gold = Color(hex: 0xFFB020)

    // Adaptive surfaces & text.
    static let background = Color(light: 0xF7F8FA, dark: 0x0E1016)
    static let surface = Color(light: 0xFFFFFF, dark: 0x181B25)
    static let surfaceGray = Color(light: 0xF2F3F7, dark: 0x232735)
    static let separator = Color(light: 0xE8EAF0, dark: 0x262A38)
    static let textPrimary = Color(light: 0x12141C, dark: 0xFFFFFF)
    static let textSecondary = Color(light: 0x8A8FA3, dark: 0x9AA1B5)
    static let textTertiary = Color(light: 0xB6BAC9, dark: 0x6E7488)
    static let blueSoft = Color(light: 0xEAF2FF, dark: 0x1A2A45)
    static let violetSoft = Color(light: 0xF1EBFF, dark: 0x2A2342)
    static let cardSecondary = Color(light: 0xFFFFFF, dark: 0x1E2230)

    /// Signature Flux gradient (blue → purple).
    static let gradient = LinearGradient(
        colors: [Color(hex: 0x4E9BFF), Color(hex: 0x8A5CFF)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    /// Deep gradient for the in-call screen.
    static let gradientCall = LinearGradient(
        colors: [Color(hex: 0x3E6BFF), Color(hex: 0x7C4DFF), Color(hex: 0x9C5CFF)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static let gradientSoft = LinearGradient(
        colors: [Color(hex: 0xE4EFFF), Color(hex: 0xEFE8FF)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    /// Deterministic gradient for generated avatars / banners.
    static func avatarGradient(_ seed: String) -> LinearGradient {
        let options: [[Color]] = [
            [Color(hex: 0x5EA2FF), Color(hex: 0x8A5CFF)],
            [Color(hex: 0x4AC8F0), Color(hex: 0x5EA2FF)],
            [Color(hex: 0x8A5CFF), Color(hex: 0xC05CFF)],
            [Color(hex: 0x5C7CFF), Color(hex: 0x4AC8F0)],
            [Color(hex: 0xA06BFF), Color(hex: 0x5E8BFF)],
        ]
        var hash = 7
        for scalar in seed.unicodeScalars {
            hash = hash &* 31 &+ Int(scalar.value)
        }
        let colors = options[abs(hash) % options.count]
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static func bannerGradient(_ seed: String) -> LinearGradient {
        let options: [[Color]] = [
            [Color(hex: 0x4E9BFF), Color(hex: 0x8A5CFF)],
            [Color(hex: 0x4AC8F0), Color(hex: 0x4E9BFF)],
            [Color(hex: 0x8A5CFF), Color(hex: 0xC05CFF)],
            [Color(hex: 0x34C77B), Color(hex: 0x4AC8F0)],
            [Color(hex: 0xFFB020), Color(hex: 0xFF4D5E)],
        ]
        var hash = 7
        for scalar in seed.unicodeScalars {
            hash = hash &* 31 &+ Int(scalar.value)
        }
        let colors = options[abs(hash) % options.count]
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Motion tokens (mirror FluxMotion)

enum FluxMotion {
    static let springAnimation = Animation.spring(response: 0.42, dampingFraction: 0.78)
    static let decelAnimation = Animation.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.34)
    static let slowDecelAnimation = Animation.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.52)
}
