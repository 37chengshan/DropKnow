import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

public struct MenuBarSceneView: View {
    private let container: DropKnowV1Container
    private let refreshToken: Int
    @Environment(\.openWindow) private var openWindow
    @State private var isProcessing: Bool = false
    @State private var toastBanner: ToastBannerView.Model?
    @State private var lastSeenEventCount: Int = 0

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
        .task {
            await monitorNotificationEvents()
        }
        .overlay(alignment: .top) {
            if let banner = toastBanner {
                ToastBannerView(model: banner) {
                    toastBanner = nil
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: toastBanner != nil)
    }

    private var statusHeader: some View {
        VStack(spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("DropKnow")
                        .font(.title3.weight(.semibold))
                    HStack(spacing: 4) {
                        Circle()
                            .fill(isProcessing ? Color.orange : Color.green)
                            .frame(width: 6, height: 6)
                        Text(isProcessing ? "处理中" : "空闲")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                ProcessingStatusBadge(isProcessing: isProcessing)
            }
            HStack {
                Text("最近刷新：\(refreshToken > 0 ? "已更新" : "启动中")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
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

    private func monitorNotificationEvents() async {
        let eventBus = container.eventBus
        lastSeenEventCount = eventBus.events.count

        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 500_000_000)

            let currentCount = eventBus.events.count
            guard currentCount > lastSeenEventCount else { continue }

            let newEvents = eventBus.events.suffix(currentCount - lastSeenEventCount)
            for event in newEvents {
                if case .notification_requested(let document_id) = event {
                    await showDocumentImportedBanner(document_id: document_id)
                }
            }
            lastSeenEventCount = currentCount
        }
    }

    private func showDocumentImportedBanner(document_id: String) async {
        let docResult = await container.documentRepository.get(id: document_id)
        let fileName: String
        switch docResult {
        case .success(let doc):
            fileName = doc?.file_name ?? "文档"
        case .failure:
            fileName = "文档"
        }

        await MainActor.run {
            toastBanner = ToastBannerView.Model(
                title: "文档已导入",
                message: fileName,
                style: .success
            )
        }

        try? await Task.sleep(nanoseconds: 3_000_000_000)
        await MainActor.run {
            if toastBanner?.title == "文档已导入" && toastBanner?.message == fileName {
                toastBanner = nil
            }
        }
    }
}

struct ProcessingStatusBadge: View {
    let isProcessing: Bool

    var body: some View {
        HStack(spacing: 4) {
            if isProcessing {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 12, height: 12)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            }
            Text(isProcessing ? "处理中" : "就绪")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.8))
        .clipShape(Capsule())
    }
}

#Preview {
    MenuBarSceneView()
}
