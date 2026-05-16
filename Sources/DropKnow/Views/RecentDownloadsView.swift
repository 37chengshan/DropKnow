import SwiftUI

struct RecentDownloadsView: View {
    @EnvironmentObject private var store: AppStore
    @SceneStorage("recentFileBucket") private var selectedBucketRaw = RecentFileBucket.all.rawValue
    @State private var renderState = RecentDownloadsRenderState.empty
    private let cardMinimumWidth: CGFloat = 210

    private var selectedBucket: RecentFileBucket {
        RecentFileBucket(rawValue: selectedBucketRaw) ?? .all
    }

    private var renderKey: RecentDownloadsRenderKey {
        RecentDownloadsRenderKey(
            filesHash: store.files.hashValue,
            selectedBucketRaw: selectedBucketRaw
        )
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                RecentDownloadsHeader()
                CategoryFilterBar(
                    selected: selectedBucket,
                    counts: renderState.counts
                ) { bucket in
                    selectedBucketRaw = bucket.rawValue
                }

                ScrollView {
                    GeometryReader { proxy in
                        let columns = adaptiveColumns(for: proxy.size.width)
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(renderState.groups) { group in
                                VStack(alignment: .leading, spacing: 7) {
                                    HStack(spacing: 6) {
                                        Label(group.bucket.title, systemImage: group.bucket.systemImage)
                                            .font(.caption.weight(.semibold))
                                        Text("\(group.files.count)")
                                            .font(.caption2.weight(.medium))
                                            .foregroundStyle(.secondary)
                                    }
                                    .foregroundStyle(.secondary)

                                    LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                                        ForEach(group.files) { file in
                                            FileGridCard(item: file, isSelected: store.selectedFileID == file.id)
                                        }
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                    }
                }
            }
            .frame(minWidth: 320, idealWidth: 520, maxWidth: 700)

            FileDetailView(file: store.selectedFile)
                .frame(minWidth: 420, idealWidth: 620)
        }
        .overlay {
            if store.files.isEmpty {
                EmptyStateView(
                    title: "还没有已解析文件",
                    message: "授权下载目录后导入最近 7 天文件，之后新文件会自动进入解析队列。",
                    systemImage: "tray"
                )
            }
        }
        .task(id: renderKey) {
            renderState = RecentDownloadsRenderState.build(files: store.files, selectedBucket: selectedBucket)
        }
    }

    private struct RecentDownloadsRenderKey: Hashable {
        var filesHash: Int
        var selectedBucketRaw: String
    }

    private func adaptiveColumns(for availableWidth: CGFloat) -> [GridItem] {
        let contentWidth = max(availableWidth - 24, cardMinimumWidth)
        let columnCount = max(Int(contentWidth / (cardMinimumWidth + 8)), 1)
        return Array(repeating: GridItem(.flexible(minimum: cardMinimumWidth), spacing: 8), count: columnCount)
    }

    private struct RecentDownloadsRenderState {
        var groups: [RecentFileGroup]
        var counts: [RecentFileBucket: Int]

        static let empty = RecentDownloadsRenderState(groups: [], counts: [.all: 0])

        static func build(files: [DropFile], selectedBucket: RecentFileBucket) -> RecentDownloadsRenderState {
            var counts: [RecentFileBucket: Int] = [.all: files.count]
            var bucketed: [RecentFileBucket: [RecentFileItem]] = [:]

            for file in files {
                let bucket = file.recentBucket
                counts[bucket, default: 0] += 1
                let item = RecentFileItem(
                    file: file,
                    bucket: bucket,
                    timeCount: file.events.reduce(into: 0) { count, event in
                        if event.startTime != nil { count += 1 }
                    },
                    hasHighConfidenceEvent: file.hasHighConfidenceEvent
                )
                bucketed[bucket, default: []].append(item)
            }

            let buckets = selectedBucket == .all ? RecentFileBucket.groupOrder : [selectedBucket]
            let groups: [RecentFileGroup] = buckets.compactMap { bucket in
                guard let items = bucketed[bucket], !items.isEmpty else { return nil }
                let sorted = items.sorted { $0.file.importedAt > $1.file.importedAt }
                return RecentFileGroup(bucket: bucket, files: sorted)
            }

            return RecentDownloadsRenderState(groups: groups, counts: counts)
        }
    }
}

private struct RecentDownloadsHeader: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HeaderStrip(
                title: "最近下载",
                subtitle: "监听授权目录中新落地的 PDF、DOCX、TXT 和 Markdown 文件"
            )

            HStack(spacing: 10) {
                StatusPill(text: "处理中 \(store.parseQueueSummary.running + store.indexQueueSummary.running)", systemImage: "bolt.fill")
                StatusPill(text: "排队 \(store.parseQueueSummary.queued + store.indexQueueSummary.queued)", systemImage: "clock")
                StatusPill(text: "失败 \(store.parseQueueSummary.failed + store.indexQueueSummary.failed)", systemImage: "exclamationmark.triangle", prominent: store.hasFailedJobs)
                Spacer()
                if store.hasFailedJobs {
                    Button {
                        Task { await store.retryFailedJobs() }
                    } label: {
                        Label("重试失败任务", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }
}

struct FileGridCard: View {
    @EnvironmentObject private var store: AppStore
    var item: RecentFileItem
    var isSelected: Bool
    @Environment(\.dropTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = theme.palette(for: colorScheme)
        let indexState = item.file.ragIndexState
        HStack(spacing: 8) {
            Image(systemName: item.file.fileKind.systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.file.fileName)
                    .font(.callout.weight(isSelected ? .semibold : .regular))
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Text(item.bucket.shortTitle)
                    Text("·")
                    Text(item.file.recentProcessingStatusLabel)
                    if item.timeCount > 1 {
                        Text("· \(item.timeCount) 个时间")
                    } else if item.hasHighConfidenceEvent {
                        Text("· 日程")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 6) {
                RecentFileIndexBadge(state: indexState)

                Button {
                    store.openFile(item.file)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.textSecondary)
                .help("打开原文件")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
        .frame(height: 66)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture {
            store.selectedFileID = item.file.id
        }
        .dropInsetMaterial(cornerRadius: 8, borderTint: isSelected ? palette.accentOrange.opacity(0.5) : nil)
    }

    private var iconColor: Color {
        let palette = theme.palette(for: colorScheme)
        if item.file.priorityLevel == .high { return palette.danger }
        if item.bucket == .issue { return palette.warning }
        if isSelected { return palette.accentOrange }
        return palette.textSecondary
    }
}

private struct RecentFileIndexBadge: View {
    var state: RAGIndexState
    @Environment(\.dropTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = theme.palette(for: colorScheme)
        let presentation = state.recentBadgePresentation
        Label(presentation.label, systemImage: presentation.systemImage)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .foregroundStyle(foregroundColor(for: presentation.tone, palette: palette))
            .dropInsetMaterial(cornerRadius: 999, borderTint: backgroundColor(for: presentation.tone, palette: palette))
    }

    private func foregroundColor(for tone: RecentFileIndexTone, palette: DropTheme.Palette) -> Color {
        switch tone {
        case .success:
            return palette.success
        case .warning:
            return palette.warning
        case .danger:
            return palette.danger
        case .neutral:
            return palette.textSecondary
        }
    }

    private func backgroundColor(for tone: RecentFileIndexTone, palette: DropTheme.Palette) -> Color {
        switch tone {
        case .success:
            return palette.success.opacity(0.14)
        case .warning:
            return palette.warning.opacity(0.14)
        case .danger:
            return palette.danger.opacity(0.14)
        case .neutral:
            return palette.surfaceSubtle
        }
    }
}

private extension DropFile {
    var recentProcessingStatusLabel: String {
        switch parsedStatus {
        case .queued:
            "等待处理"
        case .parsing:
            "处理中"
        case .sensitiveGate:
            "等待确认"
        case .parsed:
            "已完成"
        case .failed:
            "处理失败"
        case .ignored:
            "已忽略"
        }
    }
}

private struct RecentFileIndexBadgePresentation {
    var label: String
    var systemImage: String
    var tone: RecentFileIndexTone
}

private enum RecentFileIndexTone {
    case neutral
    case success
    case warning
    case danger
}

private extension RAGIndexState {
    var recentBadgePresentation: RecentFileIndexBadgePresentation {
        switch self {
        case .notIndexed:
            RecentFileIndexBadgePresentation(label: "未入索引", systemImage: "tray", tone: .neutral)
        case .indexing:
            RecentFileIndexBadgePresentation(label: "索引中", systemImage: "arrow.triangle.2.circlepath", tone: .warning)
        case .indexed:
            RecentFileIndexBadgePresentation(label: "已就绪", systemImage: "checkmark.circle.fill", tone: .success)
        case .stale:
            RecentFileIndexBadgePresentation(label: "需重建", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90", tone: .warning)
        case .failed:
            RecentFileIndexBadgePresentation(label: "处理失败", systemImage: "exclamationmark.triangle.fill", tone: .danger)
        case .blocked:
            RecentFileIndexBadgePresentation(label: "不可索引", systemImage: "hand.raised.fill", tone: .warning)
        }
    }
}

private struct CategoryFilterBar: View {
    var selected: RecentFileBucket
    var counts: [RecentFileBucket: Int]
    var onSelect: (RecentFileBucket) -> Void
    @Environment(\.dropTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = theme.palette(for: colorScheme)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(RecentFileBucket.filterOrder) { bucket in
                    Button {
                        onSelect(bucket)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: bucket.systemImage)
                            Text(bucket.shortTitle)
                            Text("\(counts[bucket, default: 0])")
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .dropInsetMaterial(cornerRadius: 999, borderTint: selected == bucket ? palette.accentOrange.opacity(0.5) : nil)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selected == bucket ? palette.accentOrange : palette.textPrimary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }
}

private struct RecentFileGroup: Identifiable {
    var bucket: RecentFileBucket
    var files: [RecentFileItem]

    var id: String { bucket.rawValue }
}

struct RecentFileItem: Identifiable {
    var file: DropFile
    var bucket: RecentFileBucket
    var timeCount: Int
    var hasHighConfidenceEvent: Bool

    var id: DropFile.ID { file.id }
}

enum RecentFileBucket: String, CaseIterable, Identifiable {
    case all = "all"
    case awaiting = "awaiting"
    case action = "action"
    case issue = "issue"
    case study = "study"
    case development = "development"
    case normal = "normal"

    var id: String { rawValue }

    static let filterOrder: [RecentFileBucket] = [.all, .awaiting, .action, .issue, .study, .development, .normal]
    static let groupOrder: [RecentFileBucket] = [.awaiting, .action, .issue, .study, .development, .normal]

    var sortIndex: Int {
        Self.groupOrder.firstIndex(of: self) ?? 99
    }

    var title: String {
        switch self {
        case .all: "全部文件"
        case .awaiting: "待处理"
        case .action: "通知/待办"
        case .issue: "解析问题"
        case .study: "学习资料"
        case .development: "开发/代码"
        case .normal: "普通文件"
        }
    }

    var shortTitle: String {
        switch self {
        case .all: "全部"
        case .awaiting: "待处理"
        case .action: "待办"
        case .issue: "问题"
        case .study: "资料"
        case .development: "开发"
        case .normal: "普通"
        }
    }

    var systemImage: String {
        switch self {
        case .all: "square.grid.2x2"
        case .awaiting: "hand.raised"
        case .action: "bell.badge"
        case .issue: "exclamationmark.triangle"
        case .study: "book"
        case .development: "curlybraces"
        case .normal: "doc.text"
        }
    }

    static func counts(in files: [DropFile]) -> [RecentFileBucket: Int] {
        var result: [RecentFileBucket: Int] = [.all: files.count]
        for file in files {
            result[file.recentBucket, default: 0] += 1
        }
        return result
    }
}

private extension DropFile {
    var recentBucket: RecentFileBucket {
        switch parsedStatus {
        case .queued, .parsing, .sensitiveGate:
            return .awaiting
        case .failed:
            return .issue
        case .ignored:
            return .normal
        case .parsed:
            break
        }

        if hasImportantRecentSignal || hasActionableRecentEvent {
            return .action
        }

        if looksLikeDevelopmentFile {
            return .development
        }

        if looksLikeStudyMaterial {
            return .study
        }

        return .normal
    }

    var recentTimeCount: Int {
        events.filter { $0.startTime != nil }.count
    }

    var hasActionableRecentEvent: Bool {
        events.contains {
            ([.exam, .assignmentDeadline, .registrationDeadline, .paymentDeadline, .interview, .meeting].contains($0.eventType) && $0.confidence >= 0.72) ||
                ($0.eventType == .campusActivity && $0.startTime != nil && $0.evidence.range(of: #"大赛|竞赛|比赛|决赛|赛区"#, options: .regularExpression) != nil)
        }
    }

    var hasImportantRecentSignal: Bool {
        guard priorityLevel == .high else { return false }
        let text = recentClassificationText.lowercased()
        return [
            "考试", "补考", "截止", "ddl", "deadline", "报名", "缴费", "面试", "宣讲",
            "会议", "大赛通知", "通知", "课堂作业", "作业", "答辩", "提交", "作品提交", "日程"
        ].contains { text.contains($0.lowercased()) }
    }

    var looksLikeDevelopmentFile: Bool {
        let text = recentClassificationText
        return ["代码/配置", "readme", "agents.md", "development", "github", "执行文档", "任务单", "重构", "架构", "benchmark", "codex", "迁移方案", "技术方案"]
            .contains { text.localizedCaseInsensitiveContains($0) }
    }

    var looksLikeStudyMaterial: Bool {
        let text = recentClassificationText
        if PriorityClassifier.isLowValue(text: text, fileName: fileName), !looksLikeDevelopmentFile {
            return true
        }
        return ["课程资料", "阅读材料", "讲义", "板书", "高数", "课堂实验", "词根", "教程", "story", "rashomon", "eidgah", "zh-", "ja-", "hi-", "th-"]
            .contains { text.localizedCaseInsensitiveContains($0) }
    }

    var recentClassificationText: String {
        [
            fileName,
            summary?.fileTypeLabel ?? "",
            summary?.oneLineSummary ?? "",
            summary?.keyPoints.joined(separator: "\n") ?? ""
        ].joined(separator: "\n")
    }
}

struct FileListRow: View {
    var file: DropFile

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: file.fileKind.systemImage)
                .foregroundStyle(file.priorityLevel == .high ? .red : .secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(file.fileName)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(file.fileKind.rawValue)
                    Text(file.parsedStatus.rawValue)
                    if file.hasHighConfidenceEvent {
                        Text("有日程")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            Image(systemName: file.priorityLevel.systemImage)
                .foregroundStyle(file.priorityLevel == .high ? Color.red : Color.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct HeaderStrip: View {
    var title: String
    var subtitle: String
    @Environment(\.dropTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = theme.palette(for: colorScheme)
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(theme.typography.heading(.title2, weight: .semibold))
            Text(subtitle)
                .font(theme.typography.body(.callout))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
}

struct EmptyStateView: View {
    var title: String
    var message: String
    var systemImage: String
    @Environment(\.dropTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = theme.palette(for: colorScheme)
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 42))
                .foregroundStyle(palette.textSecondary)
            Text(title)
                .font(theme.typography.heading(.title3, weight: .semibold))
            Text(message)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .padding(28)
        .dropGlass(cornerRadius: 18)
    }
}
