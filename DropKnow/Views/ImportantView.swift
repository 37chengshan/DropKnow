import SwiftUI

public struct ImportantView: View {
    @State private var viewModel: ImportantRemindersViewModel
    private let refreshToken: Int

    public init(viewModel: ImportantRemindersViewModel, refreshToken: Int = 0) {
        _viewModel = State(initialValue: viewModel)
        self.refreshToken = refreshToken
    }

    public var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                ProgressView("加载提醒...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .empty:
                Text("暂无提醒")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .error(let message):
                VStack(spacing: 8) {
                    Text("提醒加载失败")
                        .font(.headline)
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded:
                List(viewModel.items, id: \.event_id) { item in
                    ImportantEventCard(
                        title: item.title,
                        time_text: item.time_text,
                        file_name: item.file_name,
                        evidence: item.evidence_snippet,
                        high_priority: item.is_high_priority
                    )
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
