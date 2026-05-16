import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var store: AppStore
    @Binding var selection: AppSection

    private var listSelection: Binding<AppSection?> {
        Binding(
            get: { selection },
            set: { newValue in
                guard let newValue else { return }
                selection = newValue
            }
        )
    }

    var body: some View {
        List(selection: listSelection) {
            ForEach(AppSection.allCases) { section in
                Label(section.rawValue, systemImage: section.systemImage)
                    .tag(section)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            SidebarQuotaInset()
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
    }
}

private struct SidebarQuotaInset: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("额度")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            QuotaSummaryRow(title: "自动解析", value: "\(store.quotaSnapshot.parse.remaining) 剩余")
            QuotaSummaryRow(title: "问答", value: "\(store.quotaSnapshot.chat.remaining) 剩余")
            QuotaSummaryRow(title: "搜索", value: "\(store.quotaSnapshot.search.remaining) 剩余")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dropGlass(cornerRadius: 16)
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }
}

private struct QuotaSummaryRow: View {
    var title: String
    var value: String

    var body: some View {
        LabeledContent(title, value: value)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
