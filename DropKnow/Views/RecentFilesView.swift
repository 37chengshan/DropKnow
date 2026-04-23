import SwiftUI

public struct RecentFilesView: View {
    @State private var viewModel: RecentFilesViewModel
    @State private var expandedIDs: Set<String> = []
    private let refreshToken: Int
    private let onSelectDocument: ((String) -> Void)?

    public init(viewModel: RecentFilesViewModel, refreshToken: Int = 0, onSelectDocument: ((String) -> Void)? = nil) {
        _viewModel = State(initialValue: viewModel)
        self.refreshToken = refreshToken
        self.onSelectDocument = onSelectDocument
    }

    public var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                ProgressView("加载最近文件...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .empty:
                Text("暂无最近文件")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .error(let message):
                VStack(spacing: 8) {
                    Text("加载失败")
                        .font(.headline)
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded:
                List(viewModel.items, id: \.document_id) { item in
                    let isExpanded = expandedIDs.contains(item.document_id)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 8) {
                            StatusBadge(
                                text: item.statusBadgeText,
                                color: item.statusColor
                            )

                            VStack(alignment: .leading, spacing: 6) {
                                Button {
                                    if isExpanded {
                                        expandedIDs.remove(item.document_id)
                                    } else {
                                        expandedIDs.insert(item.document_id)
                                    }
                                } label: {
                                    SummaryCard(
                                        file_name: item.file_name,
                                        summary: item.subtitle,
                                        action_required: nil
                                    )
                                }
                                .buttonStyle(.plain)
                                .onTapGesture {
                                    onSelectDocument?(item.document_id)
                                }

                                HStack(spacing: 12) {
                                    Text(isExpanded ? "收起重点" : "展开重点")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)

                                    Spacer()

                                    QuickActionButton(
                                        icon: "eye",
                                        label: "预览"
                                    ) {
                                        // TODO: 预览文档
                                    }

                                    QuickActionButton(
                                        icon: "folder",
                                        label: "Finder"
                                    ) {
                                        // TODO: 在 Finder 中显示
                                    }
                                }
                            }
                        }

                        if isExpanded && !item.key_points.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("重点")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                ForEach(item.key_points, id: \.self) { point in
                                    HStack(alignment: .top, spacing: 6) {
                                        Text("•")
                                        Text(point)
                                    }
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.leading, 12)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .animation(.easeInOut(duration: 0.18), value: isExpanded)
                    .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
            }
        }
        .task(id: refreshToken) {
            await viewModel.load()
        }
    }
}

struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

struct QuickActionButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                Text(label)
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }
}
