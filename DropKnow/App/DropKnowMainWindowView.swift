import SwiftUI

struct DropKnowMainWindowView: View {
    private enum BootstrapState: Equatable {
        case loading
        case ready
        case failed(String)
    }

    private let container: DropKnowV1Container

    @State private var bootstrapState: BootstrapState = .loading

    init(container: DropKnowV1Container = DropKnowV1Container()) {
        self.container = container
    }

    var body: some View {
        Group {
            switch bootstrapState {
            case .loading:
                ProgressView("正在准备 DropKnow...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .ready:
                TabView {
                    MenuBarSceneView(container: container)
                        .tabItem {
                            Label("总览", systemImage: "tray.full")
                        }

                    QuickPanelSceneView(container: container)
                        .tabItem {
                            Label("搜索", systemImage: "magnifyingglass")
                        }
                }
            case .failed(let message):
                VStack(spacing: 12) {
                    Text("启动失败")
                        .font(.headline)
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("重试") {
                        bootstrapState = .loading
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: bootstrapState) {
            guard bootstrapState == .loading else { return }
            await bootstrapIfNeeded()
        }
    }

    private func bootstrapIfNeeded() async {
        let recentResult = await container.dashboardService.fetchRecentFiles(limit: 1)

        switch recentResult {
        case .success(let snapshots):
            if snapshots.isEmpty {
                _ = await container.runDemoFlow()
            }
            bootstrapState = .ready
        case .failure(let failure):
            bootstrapState = .failed(failure.message)
        }
    }
}

#Preview {
    DropKnowMainWindowView()
}
