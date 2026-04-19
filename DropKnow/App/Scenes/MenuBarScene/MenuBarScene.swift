import SwiftUI

public struct MenuBarSceneView: View {
    @State private var selectedTab: Int = 0
    private let container: DropKnowV1Container

    public init(container: DropKnowV1Container = DropKnowV1Container()) {
        self.container = container
    }

    public var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text("最近文件").tag(0)
                Text("重要提醒").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(12)

            Group {
                if selectedTab == 0 {
                    RecentFilesView(viewModel: container.makeRecentFilesViewModel())
                } else {
                    ImportantView(viewModel: container.makeImportantRemindersViewModel())
                }
            }
        }
        .frame(minWidth: 380, minHeight: 460)
    }
}

#Preview {
    MenuBarSceneView()
}
