import SwiftUI

public struct EvidenceSnippetList: View {
    public let snippets: [String]

    public init(snippets: [String]) {
        self.snippets = snippets
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("证据片段")
                .font(.headline)
            if snippets.isEmpty {
                Text("暂无证据")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(snippets.enumerated()), id: \ .offset) { index, snippet in
                    Text("\(index + 1). \(snippet)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }
}
