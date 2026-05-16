import SwiftUI

struct QueuePage: View {
    @EnvironmentObject private var store: AppStore
    @Binding var selectedSection: AppSection
    @State private var selectedKind: QueueKindFilter = .all
    @State private var selectedStatus: QueueStatusFilter = .all
    @State private var renderState = QueuePageRenderState.empty
    @Environment(\.dropTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    private var renderKey: QueuePageRenderKey {
        QueuePageRenderKey(
            itemsHash: store.queueItems.hashValue,
            selectedKind: selectedKind,
            selectedStatus: selectedStatus,
            selectedQueueItemID: store.selectedQueueItemID
        )
    }

    private struct QueuePageRenderKey: Hashable {
        var itemsHash: Int
        var selectedKind: QueueKindFilter
        var selectedStatus: QueueStatusFilter
        var selectedQueueItemID: UUID?
    }

    private struct QueuePageRenderState {
        var filteredItems: [QueueDisplayItem]
        var selectedItem: QueueDisplayItem?

        static let empty = QueuePageRenderState(filteredItems: [], selectedItem: nil)

        static func build(
            items: [QueueDisplayItem],
            selectedKind: QueueKindFilter,
            selectedStatus: QueueStatusFilter,
            selectedQueueItemID: UUID?
        ) -> QueuePageRenderState {
            let filtered = items.filter { item in
                (selectedKind == .all || item.kind == selectedKind.kind) &&
                    (selectedStatus == .all || item.status == selectedStatus.status)
            }

            let selected: QueueDisplayItem?
            if let selectedQueueItemID {
                selected = filtered.first { $0.jobID == selectedQueueItemID } ?? items.first { $0.jobID == selectedQueueItemID }
            } else {
                selected = filtered.first
            }

            return QueuePageRenderState(filteredItems: filtered, selectedItem: selected)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HeaderStrip(
                title: "处理队列",
                subtitle: "集中查看解析、精修和索引任务；失败任务可在这里重试和排障。"
            )

            QueueOverviewStrip()
                .padding(.horizontal, 12)
                .padding(.bottom, 10)

            QueueFilterBar(
                selectedKind: $selectedKind,
                selectedStatus: $selectedStatus
            )

            if renderState.filteredItems.isEmpty {
                Spacer()
                EmptyStateView(
                    title: "当前没有匹配任务",
                    message: "队列会显示解析、精修和索引任务。你可以切换筛选器查看失败、运行中或已完成的任务。",
                    systemImage: "list.bullet.rectangle.portrait"
                )
                Spacer()
            } else {
                QueueContentLayout(
                    items: renderState.filteredItems,
                    selectedItem: renderState.selectedItem,
                    selectedQueueItemID: $store.selectedQueueItemID,
                    selectedSection: $selectedSection
                )
            }
        }
        .task(id: renderKey) {
            renderState = QueuePageRenderState.build(
                items: store.queueItems,
                selectedKind: selectedKind,
                selectedStatus: selectedStatus,
                selectedQueueItemID: store.selectedQueueItemID
            )
        }
    }
}

private struct QueueContentLayout: View {
    let items: [QueueDisplayItem]
    let selectedItem: QueueDisplayItem?
    @Binding var selectedQueueItemID: UUID?
    @Binding var selectedSection: AppSection

    var body: some View {
        GeometryReader { proxy in
            let shouldShowDetail = proxy.size.width >= 820
            let detailWidth = min(max(proxy.size.width * 0.34, 360), 460)

            HStack(spacing: 0) {
                List(items, selection: $selectedQueueItemID) { item in
                    QueueRow(item: item)
                        .tag(item.jobID)
                }
                .listStyle(.inset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if shouldShowDetail {
                    Divider()

                    QueueDetailPane(item: selectedItem, selectedSection: $selectedSection)
                        .frame(width: detailWidth)
                        .frame(maxHeight: .infinity)
                }
            }
        }
    }
}

private struct QueueOverviewStrip: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dropTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = theme.palette(for: colorScheme)
        HStack(spacing: 10) {
            QueueSummaryCard(
                title: "解析队列",
                queued: store.parseQueueSummary.queued,
                running: store.parseQueueSummary.running,
                failed: store.parseQueueSummary.failed,
                tint: palette.accentBlue
            )
            QueueSummaryCard(
                title: "索引队列",
                queued: store.indexQueueSummary.queued,
                running: store.indexQueueSummary.running,
                failed: store.indexQueueSummary.failed,
                tint: palette.accentOrange
            )
            QueueQuotaCard()
        }
    }
}

private struct QueueSummaryCard: View {
    var title: String
    var queued: Int
    var running: Int
    var failed: Int
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "tray.2")
                .font(.headline)
                .foregroundStyle(tint)

            HStack(spacing: 10) {
                QueueMetric(label: "排队", value: queued.description)
                QueueMetric(label: "运行", value: running.description)
                QueueMetric(label: "失败", value: failed.description)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .dropGlass(cornerRadius: 16)
    }
}

private struct QueueQuotaCard: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dropTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = theme.palette(for: colorScheme)
        VStack(alignment: .leading, spacing: 8) {
            Label("今日额度", systemImage: "gauge.with.needle")
                .font(.headline)
                .foregroundStyle(palette.accentGreen)

            HStack(spacing: 10) {
                QueueMetric(label: "解析", value: quotaValue(store.quotaSnapshot.parse))
                QueueMetric(label: "搜索", value: quotaValue(store.quotaSnapshot.search))
                QueueMetric(label: "问答", value: quotaValue(store.quotaSnapshot.chat))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .dropGlass(cornerRadius: 16)
    }

    private func quotaValue(_ counter: QuotaCounter) -> String {
        "\(counter.used)/\(counter.limit)"
    }
}

private struct QueueMetric: View {
    var label: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.monospacedDigit().weight(.semibold))
        }
    }
}

private struct QueueFilterBar: View {
    @Binding var selectedKind: QueueKindFilter
    @Binding var selectedStatus: QueueStatusFilter

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(QueueKindFilter.allCases) { filter in
                        FilterChip(label: filter.label, isSelected: selectedKind == filter) {
                            selectedKind = filter
                        }
                    }
                }
                .padding(.horizontal, 12)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(QueueStatusFilter.allCases) { filter in
                        FilterChip(label: filter.label, isSelected: selectedStatus == filter) {
                            selectedStatus = filter
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
        }
        .padding(.bottom, 8)
    }
}

private struct FilterChip: View {
    var label: String
    var isSelected: Bool
    var action: () -> Void
    @Environment(\.dropTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = theme.palette(for: colorScheme)
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .dropInsetMaterial(cornerRadius: 999, borderTint: isSelected ? palette.accentOrange.opacity(0.5) : nil)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? palette.accentOrange : palette.textPrimary)
    }
}

private struct QueueRow: View {
    var item: QueueDisplayItem
    @Environment(\.dropTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = theme.palette(for: colorScheme)
        HStack(spacing: 10) {
            Image(systemName: item.kind == .parse ? "doc.text.magnifyingglass" : "internaldrive")
                .foregroundStyle(color(for: item.status, palette: palette))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.fileName)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(item.kind.label)
                    Text("·")
                    Text(item.statusText)
                    Text("·")
                    Text(item.trigger.label)
                    Text("·")
                    Text("\(item.attemptCount)/\(item.maxAttempts)")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }

    private func color(for status: QueueDisplayStatus, palette: DropTheme.Palette) -> Color {
        switch status {
        case .failed: palette.danger
        case .running: palette.warning
        case .blocked: palette.warning
        case .completed: palette.success
        default: palette.textSecondary
        }
    }
}

private struct QueueDetailPane: View {
    @EnvironmentObject private var store: AppStore
    var item: QueueDisplayItem?
    @Binding var selectedSection: AppSection
    @Environment(\.dropTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if let item {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        queueHeader(item)
                        queueMeta(item)
                        if let lastError = item.lastError, !lastError.isEmpty {
                            WarningSection(message: lastError)
                        }
                        actionSection(item)
                    }
                    .padding(18)
                    .frame(maxWidth: 900, alignment: .leading)
                }
            } else {
                EmptyStateView(
                    title: "选择一个任务",
                    message: "这里会显示任务状态、最近错误、重试信息和关联文件操作。",
                    systemImage: "checklist"
                )
            }
        }
    }

    @ViewBuilder
    private func queueHeader(_ item: QueueDisplayItem) -> some View {
        let palette = theme.palette(for: colorScheme)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: item.kind == .parse ? "doc.text.magnifyingglass" : "internaldrive")
                    .font(.system(size: 24))
                    .foregroundStyle(item.status == .failed ? palette.danger : palette.accentOrange)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.fileName)
                        .font(.title3.weight(.semibold))
                    Text(item.filePath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                StatusPill(text: item.statusText, systemImage: pillImage(for: item.status), prominent: item.status == .failed)
            }
        }
        .padding(14)
        .dropGlass(cornerRadius: 16)
    }

    @ViewBuilder
    private func queueMeta(_ item: QueueDisplayItem) -> some View {
        DetailSection(title: "任务信息", systemImage: "info.circle") {
            HStack(spacing: 16) {
                MetadataItem(title: "类型", value: item.kind.label)
                MetadataItem(title: "触发来源", value: item.trigger.label)
                MetadataItem(title: "重试次数", value: "\(item.attemptCount)/\(item.maxAttempts)")
                if let lastAttemptAt = item.lastAttemptAt {
                    MetadataItem(title: "最近尝试", value: DateFormatter.dropShort.string(from: lastAttemptAt))
                }
                if let nextRetryAt = item.nextRetryAt {
                    MetadataItem(title: "下次重试", value: DateFormatter.dropShort.string(from: nextRetryAt))
                }
            }
        }
    }

    @ViewBuilder
    private func actionSection(_ item: QueueDisplayItem) -> some View {
        DetailSection(title: "任务操作", systemImage: "bolt.horizontal") {
            HStack {
                Button {
                    Task { await store.retrySelectedQueueItem() }
                } label: {
                    Label("重试所选任务", systemImage: "arrow.clockwise")
                }
                .dropProminentActionStyle()
                .disabled(item.status != .failed)

                Button {
                    store.openFileForQueueItem(item)
                } label: {
                    Label("打开关联文件", systemImage: "arrow.up.right.square")
                }
                .dropSecondaryActionStyle()

                Button {
                    store.focusFileForQueueItem(item)
                    selectedSection = .recent
                } label: {
                    Label("定位到最近下载", systemImage: "sidebar.right")
                }
                .dropSecondaryActionStyle()

                Spacer()

                if store.hasFailedJobs {
                    Button {
                        Task { await store.retryFailedJobs() }
                    } label: {
                        Label("重试全部失败任务", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .dropSecondaryActionStyle()
                }
            }
            .font(.caption)
        }
    }

    private func pillImage(for status: QueueDisplayStatus) -> String {
        switch status {
        case .queued: "clock"
        case .running: "bolt.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .blocked: "hand.raised.fill"
        case .skipped: "arrowshape.turn.up.forward"
        case .completed: "checkmark.circle.fill"
        }
    }
}

private enum QueueKindFilter: String, CaseIterable, Identifiable {
    case all
    case parse
    case index

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: "全部"
        case .parse: "解析"
        case .index: "索引"
        }
    }

    var kind: QueueItemKind? {
        switch self {
        case .all: nil
        case .parse: .parse
        case .index: .index
        }
    }
}

private enum QueueStatusFilter: String, CaseIterable, Identifiable {
    case all
    case queued
    case running
    case failed
    case blocked
    case skipped
    case completed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: "全部状态"
        case .queued: "排队中"
        case .running: "运行中"
        case .failed: "已失败"
        case .blocked: "已阻塞"
        case .skipped: "已跳过"
        case .completed: "已完成"
        }
    }

    var status: QueueDisplayStatus? {
        switch self {
        case .all: nil
        case .queued: .queued
        case .running: .running
        case .failed: .failed
        case .blocked: .blocked
        case .skipped: .skipped
        case .completed: .completed
        }
    }
}
