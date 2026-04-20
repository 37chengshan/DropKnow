import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

public struct MenuBarSceneView: View {
    private let container: DropKnowV1Container
    private let refreshToken: Int
    @Environment(\.openWindow) private var openWindow
    @State private var isProcessing: Bool = false

    public init(container: DropKnowV1Container = DropKnowV1Container(), refreshToken: Int = 0) {
        self.container = container
        self.refreshToken = refreshToken
    }

    public var body: some View {
        VStack(spacing: 12) {
            statusHeader

            VStack(alignment: .leading, spacing: 8) {
                Text("重要提醒")
                    .font(.headline)
                ImportantView(viewModel: container.makeImportantRemindersViewModel(), refreshToken: refreshToken)
                    .frame(minHeight: 140, maxHeight: 180)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("最近文件")
                    .font(.headline)
                RecentFilesView(viewModel: container.makeRecentFilesViewModel(), refreshToken: refreshToken)
                    .frame(minHeight: 220)
            }

            quickActions
        }
        .padding(12)
        .frame(minWidth: 380, minHeight: 460)
        .task(id: refreshToken) {
            await refreshProcessingStatus()
        }
    }

    private var statusHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("DropKnow")
                    .font(.title3.weight(.semibold))
                Text("最近刷新：\(refreshToken > 0 ? "已更新" : "启动中")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(isProcessing ? "处理状态：处理中" : "处理状态：空闲")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("状态总览")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.thinMaterial)
                .clipShape(Capsule())
        }
    }

    private var quickActions: some View {
        HStack(spacing: 10) {
            Button("打开搜索") {
                openWindow(id: "quick-panel")
            }
            .buttonStyle(.borderedProminent)

            Button("打开设置") {
                #if canImport(AppKit)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                #endif
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func refreshProcessingStatus() async {
        let result = await container.parseJobRepository.listRecent(limit: 80)
        switch result {
        case .success(let jobs):
            isProcessing = jobs.contains(where: { $0.status == .running || $0.status == .queued })
        case .failure:
            isProcessing = false
        }
    }
}

#Preview {
    MenuBarSceneView()
}
