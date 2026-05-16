import SwiftUI

struct DropTheme {
    struct Palette {
        var background: Color
        var surface: Color
        var surfaceSubtle: Color
        var border: Color
        var textPrimary: Color
        var textSecondary: Color
        var textTertiary: Color
        var accentOrange: Color
        var accentBlue: Color
        var accentGreen: Color
        var selectionFill: Color
        var selectionText: Color
        var danger: Color
        var warning: Color
        var success: Color
    }

    struct Typography {
        var headingFamilyName: String
        var bodyFamilyName: String

        func heading(_ style: Font.TextStyle, weight: Font.Weight = .semibold) -> Font {
            Font.custom(headingFamilyName, size: size(for: style), relativeTo: style).weight(weight)
        }

        func body(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
            Font.custom(bodyFamilyName, size: size(for: style), relativeTo: style).weight(weight)
        }

        private func size(for style: Font.TextStyle) -> CGFloat {
            switch style {
            case .largeTitle: 34
            case .title: 28
            case .title2: 22
            case .title3: 20
            case .headline: 17
            case .subheadline: 15
            case .body: 17
            case .callout: 16
            case .footnote: 13
            case .caption: 12
            case .caption2: 11
            default: 17
            }
        }
    }

    struct Metrics {
        var cornerRadius: CGFloat
        var cornerRadiusSmall: CGFloat
        var borderWidth: CGFloat
        var padding: CGFloat
        var paddingSmall: CGFloat
    }

    var typography: Typography
    var metrics: Metrics

    func palette(for scheme: ColorScheme) -> Palette {
        let dark = Color(red: 20 / 255, green: 20 / 255, blue: 19 / 255)
        let light = Color(red: 250 / 255, green: 249 / 255, blue: 245 / 255)
        let midGray = Color(red: 176 / 255, green: 174 / 255, blue: 165 / 255)
        let lightGray = Color(red: 232 / 255, green: 230 / 255, blue: 220 / 255)
        let orange = Color(red: 217 / 255, green: 119 / 255, blue: 87 / 255)
        let blue = Color(red: 106 / 255, green: 155 / 255, blue: 204 / 255)
        let green = Color(red: 120 / 255, green: 140 / 255, blue: 93 / 255)

        switch scheme {
        case .dark:
            return Palette(
                background: dark,
                surface: Color.white.opacity(0.06),
                surfaceSubtle: Color.white.opacity(0.035),
                border: Color.white.opacity(0.14),
                textPrimary: light,
                textSecondary: light.opacity(0.78),
                textTertiary: midGray.opacity(0.92),
                accentOrange: orange,
                accentBlue: blue,
                accentGreen: green,
                selectionFill: orange.opacity(0.86),
                selectionText: dark,
                danger: Color.red,
                warning: Color.orange,
                success: Color.green
            )
        default:
            return Palette(
                background: light,
                surface: Color.white.opacity(0.7),
                surfaceSubtle: lightGray.opacity(0.55),
                border: dark.opacity(0.12),
                textPrimary: dark,
                textSecondary: dark.opacity(0.74),
                textTertiary: midGray,
                accentOrange: orange,
                accentBlue: blue,
                accentGreen: green,
                selectionFill: orange,
                selectionText: light,
                danger: Color.red,
                warning: Color.orange,
                success: Color.green
            )
        }
    }

    static let anthropic = DropTheme(
        typography: Typography(headingFamilyName: "Poppins", bodyFamilyName: "Lora"),
        metrics: Metrics(cornerRadius: 12, cornerRadiusSmall: 8, borderWidth: 1, padding: 16, paddingSmall: 10)
    )
}

private struct DropThemeKey: EnvironmentKey {
    static let defaultValue = DropTheme.anthropic
}

extension EnvironmentValues {
    var dropTheme: DropTheme {
        get { self[DropThemeKey.self] }
        set { self[DropThemeKey.self] = newValue }
    }
}

extension View {
    func dropTheme(_ theme: DropTheme) -> some View {
        environment(\.dropTheme, theme)
    }
}
