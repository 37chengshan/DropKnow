import SwiftUI

public struct ImportantEventCard: View {
    public let title: String
    public let time_text: String
    public let file_name: String
    public let evidence: String
    public let high_priority: Bool

    public init(
        title: String,
        time_text: String,
        file_name: String,
        evidence: String,
        high_priority: Bool
    ) {
        self.title = title
        self.time_text = time_text
        self.file_name = file_name
        self.evidence = evidence
        self.high_priority = high_priority
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                if high_priority {
                    Text("高优先")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            Text(time_text)
                .font(.subheadline)
            Text(file_name)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(evidence)
                .font(.footnote)
                .lineLimit(3)
                .foregroundStyle(.secondary)
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
