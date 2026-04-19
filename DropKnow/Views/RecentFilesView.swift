import SwiftUI

public struct RecentFilesView: View {
    @State private var viewModel: RecentFilesViewModel

    public init(viewModel: RecentFilesViewModel) {
        _viewModel = State(initialValue: viewModel)
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
                    SummaryCard(
                        file_name: item.file_name,
                        summary: item.subtitle,
                        action_required: nil
                    )
                    .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
            }
        }
        .task {
            await viewModel.load()
        }
    }
}
