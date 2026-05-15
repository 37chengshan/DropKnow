import SwiftUI

extension View {
    @ViewBuilder
    func dropGlass(cornerRadius: CGFloat = 12, interactive: Bool = false) -> some View {
        modifier(DropGlassModifier(cornerRadius: cornerRadius, interactive: interactive))
    }

    @ViewBuilder
    func dropWorkingBorderBeam(isActive: Bool, cornerRadius: CGFloat = 12) -> some View {
        modifier(DropWorkingBorderBeamModifier(isActive: isActive, cornerRadius: cornerRadius))
    }
}

private struct DropGlassModifier: ViewModifier {
    @Environment(\.dropTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    var cornerRadius: CGFloat
    var interactive: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let palette = theme.palette(for: colorScheme)
        if #available(macOS 26.0, *) {
            content.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay(shape.stroke(palette.border, lineWidth: theme.metrics.borderWidth))
        }
    }
}

private struct DropWorkingBorderBeamModifier: ViewModifier {
    @Environment(\.dropTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotation = 0.0

    var isActive: Bool
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let palette = theme.palette(for: colorScheme)

        content
            .overlay {
                shape
                    .stroke(palette.border, lineWidth: theme.metrics.borderWidth)
            }
            .overlay {
                if isActive {
                    AngularGradient(
                        colors: [
                            palette.accentOrange.opacity(0.06),
                            palette.accentOrange,
                            palette.accentBlue,
                            palette.accentOrange.opacity(0.06)
                        ],
                        center: .center
                    )
                    .rotationEffect(.degrees(reduceMotion ? 0 : rotation))
                    .mask(
                        shape.stroke(lineWidth: max(theme.metrics.borderWidth * 3, 2.5))
                    )
                    .opacity(reduceMotion ? 0.72 : 0.94)
                    .shadow(color: palette.accentOrange.opacity(reduceMotion ? 0.12 : 0.18), radius: 10)
                    .allowsHitTesting(false)
                }
            }
            .onAppear {
                updateAnimation()
            }
            .onChange(of: isActive) {
                updateAnimation()
            }
            .onChange(of: reduceMotion) {
                updateAnimation()
            }
    }

    private func updateAnimation() {
        guard isActive, !reduceMotion else {
            rotation = 0
            return
        }

        rotation = 0
        withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: false)) {
            rotation = 360
        }
    }
}
