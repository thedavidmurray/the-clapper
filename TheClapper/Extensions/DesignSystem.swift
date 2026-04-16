import SwiftUI

// MARK: - Edgeless Design System (adapted for The Clapper)
// Based on Edgeless "Warm Dusk" palette from photoMerge
// Adapted with a more pro-creator, audio-focused feel

extension Color {
    // === BACKGROUNDS ===
    static let edgelessBackground = Color(hex: "0C0C0E")
    static let edgelessSurface = Color(hex: "161618")
    static let edgelessSurfaceLight = Color(hex: "1E1E22")
    static let edgelessSurfaceElevated = Color(hex: "28282E")

    // === ACCENT -- Soft Coral (Edgeless brand) ===
    static let edgelessAccent = Color(hex: "E8856C")
    static let edgelessAccentLight = Color(hex: "F0A08A")

    // === RECORDING -- Vivid Red for record state ===
    static let recordingRed = Color(hex: "FF3B30")
    static let recordingRedMuted = Color(hex: "FF3B30").opacity(0.2)

    // === AUDIO -- Electric Indigo for sound visualization ===
    static let audioIndigo = Color(hex: "818CF8")
    static let audioIndigoMuted = Color(hex: "818CF8").opacity(0.15)

    // === SUCCESS -- Sage (Edgeless brand) ===
    static let edgelessSage = Color(hex: "7CB5A0")
    static let edgelessSageMuted = Color(hex: "7CB5A0").opacity(0.15)

    // === TEXT ===
    static let edgelessTextPrimary = Color(hex: "F2F0ED")
    static let edgelessTextSecondary = Color(hex: "9B9893")
    static let edgelessTextTertiary = Color(hex: "5C5955")

    // === SEMANTIC ===
    static let edgelessWarning = Color(hex: "E8C170")
    static let edgelessError = Color(hex: "E87070")
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Typography (SF Pro system fonts)

extension Font {
    static let edgelessDisplay = Font.system(size: 32, weight: .bold, design: .rounded)
    static let edgelessTitle = Font.system(size: 24, weight: .semibold, design: .rounded)
    static let edgelessHeadline = Font.system(size: 18, weight: .semibold, design: .rounded)
    static let edgelessBody = Font.system(size: 16, weight: .regular, design: .default)
    static let edgelessBodyMedium = Font.system(size: 16, weight: .medium, design: .default)
    static let edgelessCaption = Font.system(size: 14, weight: .medium, design: .default)
    static let edgelessSmall = Font.system(size: 12, weight: .medium, design: .default)
    static let edgelessBadge = Font.system(size: 11, weight: .semibold, design: .monospaced)
}

// MARK: - Spacing

enum Spacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let base: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
    static let xxxl: CGFloat = 64
}

enum Radius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let full: CGFloat = 999
}
