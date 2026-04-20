import SwiftUI

public struct ToastBannerView: View {
    public let title: String
    public let message: String
    public let style: DropKnowAppModel.Banner.Style
    public let onDismiss: (() -> Void)?

    public init(
        title: String,
        message: String,
        style: DropKnowAppModel.Banner.Style,
        onDismiss: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.style = style
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(accentColor.opacity(0.9))
                .frame(width: 10, height: 10)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button("关闭") {
                onDismiss?()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.regularMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(accentColor.opacity(0.25), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 14, x: 0, y: 8)
        .frame(maxWidth: 420, alignment: .trailing)
    }

    private var accentColor: Color {
        switch style {
        case .info:
            return .blue
        case .success:
            return .green
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }
}
