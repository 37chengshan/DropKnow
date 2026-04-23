import SwiftUI

extension Color {
    init(hex: String) {
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
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

enum DesignColors {
    // MARK: - Primary (Teal)
    static let primary = Color(hex: "0D9488")
    static let primaryLight = Color(hex: "14B8A6")
    static let primaryDark = Color(hex: "134E4A")

    // MARK: - Accent (CTA)
    static let accent = Color(hex: "F97316")

    // MARK: - Background
    static let cardBackground = Color(nsColor: .windowBackgroundColor)
    static let backgroundPrimary = Color(nsColor: .windowBackgroundColor)
    static let backgroundSecondary = Color(nsColor: .controlBackgroundColor)

    // MARK: - Text
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let textMuted = Color.secondary.opacity(0.7)

    // MARK: - Status
    static let success = Color.green
    static let warning = Color.orange
    static let error = Color.red
    static let info = Color.blue

    // MARK: - Border
    static let border = Color.secondary.opacity(0.2)
    static let borderStrong = Color.secondary.opacity(0.4)

    // MARK: - Priority
    static let highPriorityBackground = Color.red.opacity(0.15)
    static let highPriorityText = Color.red
}
