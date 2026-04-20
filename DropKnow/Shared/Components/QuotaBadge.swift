import SwiftUI

public struct QuotaBadge: View {
    public let label: String
    public let used: Int
    public let limit: Int

    public init(label: String, used: Int, limit: Int) {
        self.label = label
        self.used = used
        self.limit = max(limit, 1)
    }

    public var body: some View {
        let ratio = min(Double(used) / Double(limit), 1.0)

        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            ProgressView(value: ratio)
            Text("\(used)/\(limit)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
