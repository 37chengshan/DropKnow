import SwiftUI

public struct SummaryCard: View {
    public let file_name: String
    public let summary: String
    public let action_required: String?

    public init(file_name: String, summary: String, action_required: String? = nil) {
        self.file_name = file_name
        self.summary = summary
        self.action_required = action_required
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(file_name)
                .font(.headline)
            Text(summary)
                .font(.body)
                .foregroundStyle(.primary)
            if let action_required, !action_required.isEmpty {
                Text("建议动作：\(action_required)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
}
