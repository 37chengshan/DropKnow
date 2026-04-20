import SwiftUI

public struct RecentFilesView: View {
    @State private var viewModel: RecentFilesViewModel
    @State private var expandedIDs: Set<String> = []
    private let refreshToken: Int

    public init(viewModel: RecentFilesViewModel, refreshToken: Int = 0) {
        _viewModel = State(initialValue: viewModel)
        self.refreshToken = refreshToken
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
                        .overlay(alignment: .bottomTrailing) {
                            Text(isExpanded ? "收起重点" : "点击展开重点")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.trailing, 4)
                                .padding(.bottom, 4)
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
