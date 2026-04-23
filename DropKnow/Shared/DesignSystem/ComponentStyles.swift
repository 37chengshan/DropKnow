import SwiftUI

enum CardStyle {
    static let standardShape = RoundedRectangle(
        cornerRadius: DesignCornerRadius.medium,
        style: .continuous
    )

    static func standardFill() -> some View {
        RoundedRectangle(
            cornerRadius: DesignCornerRadius.medium,
            style: .continuous
        )
        .fill(DesignColors.cardBackground)
    }

    static func standardBorder() -> some View {
        RoundedRectangle(
            cornerRadius: DesignCornerRadius.medium,
            style: .continuous
        )
        .stroke(DesignColors.border, lineWidth: 1)
    }
}

enum BadgeStyle {
    static let capsule = Capsule()

    static let highPriorityPadding = EdgeInsets(
        top: 2,
        leading: 8,
        bottom: 2,
        trailing: 8
    )
}

struct ToastShadow {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat

    static let standard = ToastShadow(
        color: .black.opacity(0.08),
        radius: 14,
        x: 0,
        y: 8
    )
}

extension View {
    func toastShadow() -> some View {
        self.shadow(
            color: ToastShadow.standard.color,
            radius: ToastShadow.standard.radius,
            x: ToastShadow.standard.x,
            y: ToastShadow.standard.y
        )
    }
}
