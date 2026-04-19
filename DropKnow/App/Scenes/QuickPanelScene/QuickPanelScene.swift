import SwiftUI

public struct QuickPanelSceneView: View {
    @State private var query: String = ""
    @State private var viewModel: SearchViewModel

    public init(container: DropKnowV1Container = DropKnowV1Container()) {
        _viewModel = State(initialValue: container.makeSearchViewModel())
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("输入问题", text: $query)
            Button("搜索") {
                Task {
                    await viewModel.ask(query)
                }
            }
            .buttonStyle(.borderedProminent)

            Text("状态：\(viewModel.status.rawValue)")
                .font(.footnote)
                .foregroundStyle(.secondary)

            ScrollView {
                Text(viewModel.answer)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .frame(minWidth: 360, minHeight: 240)
    }
}
