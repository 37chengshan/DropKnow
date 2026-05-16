import SwiftUI

struct DropPrimaryButtonStyle: ButtonStyle {
    @Environment(\.dropTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let palette = theme.palette(for: colorScheme)
        let fill = isEnabled ? palette.accentOrange : palette.border
        let pressed = configuration.isPressed ? 0.82 : 1
        return configuration.label
            .foregroundStyle(isEnabled ? palette.selectionText : palette.textTertiary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(fill.opacity(pressed), in: RoundedRectangle(cornerRadius: theme.metrics.cornerRadiusSmall, style: .continuous))
    }
}

struct DropSecondaryButtonStyle: ButtonStyle {
    @Environment(\.dropTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let palette = theme.palette(for: colorScheme)
        let pressedOpacity = configuration.isPressed ? 0.7 : 1
        return configuration.label
            .foregroundStyle(isEnabled ? palette.accentOrange : palette.textTertiary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(palette.surface.opacity(configuration.isPressed ? 0.65 : 1), in: RoundedRectangle(cornerRadius: theme.metrics.cornerRadiusSmall, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: theme.metrics.cornerRadiusSmall, style: .continuous)
                    .stroke((isEnabled ? palette.border : palette.border.opacity(0.6)).opacity(pressedOpacity), lineWidth: theme.metrics.borderWidth)
            )
    }
}

struct DropTextFieldStyle: TextFieldStyle {
    @Environment(\.dropTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    func _body(configuration: TextField<_Label>) -> some View {
        let palette = theme.palette(for: colorScheme)
        return configuration
            .textFieldStyle(.plain)
            .font(theme.typography.body(.callout))
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(palette.surfaceSubtle, in: RoundedRectangle(cornerRadius: theme.metrics.cornerRadiusSmall, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: theme.metrics.cornerRadiusSmall, style: .continuous)
                    .stroke((isEnabled ? palette.border : palette.border.opacity(0.6)), lineWidth: theme.metrics.borderWidth)
            )
    }
}

struct DropToggleStyle: ToggleStyle {
    @Environment(\.dropTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let palette = theme.palette(for: colorScheme)
        let fill = configuration.isOn ? palette.accentOrange : palette.border.opacity(0.8)
        let knob = configuration.isOn ? palette.selectionText : palette.background

        return HStack {
            configuration.label
            Spacer(minLength: 10)
            RoundedRectangle(cornerRadius: 999, style: .continuous)
                .fill(isEnabled ? fill : palette.border.opacity(0.55))
                .frame(width: 42, height: 24)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(knob)
                        .padding(3)
                }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard isEnabled else { return }
            configuration.isOn.toggle()
        }
    }
}

extension View {
    func dropCard() -> some View {
        modifier(DropCardModifier())
    }

    func dropFieldChrome(isFocused: Bool, isError: Bool = false) -> some View {
        modifier(DropFieldChromeModifier(isFocused: isFocused, isError: isError))
    }
}

private struct DropCardModifier: ViewModifier {
    @Environment(\.dropTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let palette = theme.palette(for: colorScheme)
        return content
            .padding(theme.metrics.padding)
            .background(palette.surfaceSubtle, in: RoundedRectangle(cornerRadius: theme.metrics.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: theme.metrics.cornerRadius, style: .continuous)
                    .stroke(palette.border, lineWidth: theme.metrics.borderWidth)
            )
    }
}

private struct DropFieldChromeModifier: ViewModifier {
    @Environment(\.dropTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    var isFocused: Bool
    var isError: Bool

    func body(content: Content) -> some View {
        let palette = theme.palette(for: colorScheme)
        let border = isError ? palette.danger : (isFocused ? palette.accentOrange : palette.border)
        return content
            .overlay(
                RoundedRectangle(cornerRadius: theme.metrics.cornerRadiusSmall, style: .continuous)
                    .stroke(border.opacity(isFocused || isError ? 0.95 : 1), lineWidth: theme.metrics.borderWidth)
            )
    }
}
