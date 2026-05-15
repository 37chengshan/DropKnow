import SwiftUI

struct FileDetailView: View {
    @EnvironmentObject private var store: AppStore
    var file: DropFile?
    @State private var renderState = FileDetailRenderState.empty

    var body: some View {
        Group {
            if let file {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            DetailHeader(
                                file: file,
                                fileSizeText: renderState.fileSizeText,
                                modifiedAtText: renderState.modifiedAtText,
                                textLengthText: renderState.textLengthText
                            )

                            if file.parsedStatus == .sensitiveGate {
                                SensitiveGateView(file: file)
                            } else {
                                if file.sensitivityStatus != .clear {
                                    SensitiveStatusSection(file: file)
                                }

                                if let summary = file.summary {
                                    SummarySection(summary: summary)
                                        .id(FileDetailSectionAnchor.summary)
                                }

                                if let explanation = renderState.importanceExplanation {
                                    ExplanationSection(explanation: explanation, systemImage: "exclamationmark.circle")
                                        .id(FileDetailSectionAnchor.importance)
                                }

                                if let calendarExplanation = renderState.calendarExplanation {
                                    ExplanationSection(explanation: calendarExplanation, systemImage: "calendar.badge.clock")
                                        .id(FileDetailSectionAnchor.calendarReason)
                                }

                                if !file.events.isEmpty {
                                    EventsSection(file: file)
                                        .id(FileDetailSectionAnchor.events)
                                }

                                if !file.snippets.isEmpty {
                                    SemanticSnippetsSection(snippets: file.snippets)
                                        .id(FileDetailSectionAnchor.snippets)
                                }

                                if file.snippets.isEmpty, file.ragIndexState == .indexed {
                                    WarningSection(message: "该文件已索引，但当前详情没有保存可展示片段。你仍可打开原文件核验。")
                                        .id(FileDetailSectionAnchor.snippets)
                                }

                                if !file.events.isEmpty {
                                    EvidenceSnippetsSection(snippets: renderState.evidenceSnippets)
                                }

                                if let error = file.errorMessage, !error.isEmpty {
                                    WarningSection(message: error)
                                }
                            }
                        }
                        .padding(18)
                        .frame(maxWidth: 900, alignment: .leading)
                    }
                    .task(id: renderKey(for: file)) {
                        renderState = buildRenderState(for: file)
                    }
                    .onAppear {
                        applyPendingFocus(using: proxy, for: file.id)
                    }
                    .onChange(of: file.id) {
                        applyPendingFocus(using: proxy, for: file.id)
                    }
                    .onChange(of: store.detailFocusRequest?.id) {
                        applyPendingFocus(using: proxy, for: file.id)
                    }
                }
            } else {
                EmptyStateView(title: "选择一个文件", message: "文件详情会显示摘要、事件候选、证据片段和操作入口。", systemImage: "doc.text.magnifyingglass")
            }
        }
    }

    private func renderKey(for file: DropFile) -> FileDetailRenderKey {
        FileDetailRenderKey(
            fileID: file.id,
            fileHash: file.hashValue,
            highlightedEventID: store.highlightedDetailEventID
        )
    }

    private func buildRenderState(for file: DropFile) -> FileDetailRenderState {
        FileDetailRenderState(
            evidenceSnippets: eventSnippets(for: file),
            importanceExplanation: store.importanceExplanation(for: file),
            calendarExplanation: store.calendarExplanation(for: file, highlightedEventID: store.highlightedDetailEventID),
            fileSizeText: ByteCountFormatter.dropFileSize.string(fromByteCount: file.fileSize),
            modifiedAtText: DateFormatter.dropShort.string(from: file.modifiedAt),
            textLengthText: "\(file.textLength)"
        )
    }

    private func eventSnippets(for file: DropFile) -> [String] {
        var seen = Set<String>()
        return file.events.compactMap { event in
            let snippet = event.evidence.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !snippet.isEmpty, !seen.contains(snippet) else { return nil }
            seen.insert(snippet)
            return snippet
        }
    }

    private func applyPendingFocus(using proxy: ScrollViewProxy, for fileID: DropFile.ID) {
        guard let request = store.detailFocusRequest,
              request.fileID == fileID else { return }
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo(request.anchor, anchor: .top)
            }
            store.clearDetailFocusRequest(id: request.id)
        }
    }

    private struct FileDetailRenderKey: Hashable {
        var fileID: DropFile.ID
        var fileHash: Int
        var highlightedEventID: EventCandidate.ID?
    }

    private struct FileDetailRenderState {
        var evidenceSnippets: [String]
        var importanceExplanation: FileExplanation?
        var calendarExplanation: FileExplanation?
        var fileSizeText: String
        var modifiedAtText: String
        var textLengthText: String

        static let empty = FileDetailRenderState(
            evidenceSnippets: [],
            importanceExplanation: nil,
            calendarExplanation: nil,
            fileSizeText: "",
            modifiedAtText: "",
            textLengthText: ""
        )
    }
}

private struct DetailHeader: View {
    @EnvironmentObject private var store: AppStore
    var file: DropFile
    var fileSizeText: String
    var modifiedAtText: String
    var textLengthText: String
    @Environment(\.dropTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = theme.palette(for: colorScheme)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: file.fileKind.systemImage)
                    .font(.system(size: 28))
                    .foregroundStyle(file.priorityLevel == .high ? palette.danger : palette.accentOrange)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 6) {
                    Text(file.fileName)
                        .font(theme.typography.heading(.title3, weight: .semibold))
                        .lineLimit(2)
                    Text(file.filePath)
                        .font(theme.typography.body(.caption))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    StatusPill(text: file.priorityLevel.rawValue, systemImage: file.priorityLevel.systemImage, prominent: file.priorityLevel == .high)
                    Button {
                        store.openFile(file)
                    } label: {
                        Label("打开原文件", systemImage: "arrow.up.right.square")
                    }
                    .font(.caption)
                    .buttonStyle(DropSecondaryButtonStyle())
                }
            }

            HStack(spacing: 14) {
                MetadataItem(title: "状态", value: file.parsedStatus.rawValue)
                MetadataItem(title: "大小", value: fileSizeText)
                MetadataItem(title: "修改时间", value: modifiedAtText)
                MetadataItem(title: "文本长度", value: textLengthText)
            }
        }
        .padding(14)
        .dropGlass(cornerRadius: 14)
    }
}

private struct SummarySection: View {
    var summary: FileSummary

    var body: some View {
        DetailSection(title: "通知型摘要", systemImage: "text.badge.checkmark") {
            VStack(alignment: .leading, spacing: 10) {
                Text(summary.oneLineSummary)
                    .font(.headline)

                HStack(spacing: 10) {
                    StatusPill(text: summary.fileTypeLabel, systemImage: "tag")
                    StatusPill(text: summary.actionHint, systemImage: "figure.walk")
                    if let keyTime = summary.keyTime {
                        StatusPill(text: keyTime, systemImage: "calendar")
                    }
                    if let keyLocation = summary.keyLocation {
                        StatusPill(text: keyLocation, systemImage: "mappin.and.ellipse")
                    }
                }

                VStack(alignment: .leading, spacing: 7) {
                    ForEach(summary.keyPoints, id: \.self) { point in
                        Label(point, systemImage: "checkmark.circle")
                            .labelStyle(.titleAndIcon)
                            .lineLimit(3)
                    }
                }
                .font(.callout)
            }
        }
    }
}

private struct EventsSection: View {
    @EnvironmentObject private var store: AppStore
    var file: DropFile
    @Environment(\.dropTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = theme.palette(for: colorScheme)
        DetailSection(title: "事件候选", systemImage: "calendar.badge.clock") {
            VStack(spacing: 10) {
                if !store.canUseCalendarWrite, file.events.contains(where: { $0.startTime != nil }) {
                    UpgradeNudge(
                        text: "订阅版可把高置信度时间候选直接加入系统日历。",
                        trigger: .calendar
                    )
                }
                ForEach(file.events) { event in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(event.title)
                                    .font(.headline)
                                Text(event.evidence)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                            }
                            Spacer()
                            Text("\(Int(event.confidence * 100))%")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(event.confidence >= 0.72 ? palette.success : palette.textSecondary)
                        }

                        HStack {
                            if let start = event.startTime {
                                Label(DateFormatter.dropShort.string(from: start), systemImage: "clock")
                            } else {
                                Label("需确认时间", systemImage: "questionmark.circle")
                            }
                            if let location = event.location {
                                Label(location, systemImage: "mappin")
                            }
                            Spacer()
                            Button {
                                Task { await store.addEventToCalendar(eventID: event.id, in: file.id) }
                            } label: {
                                Label(calendarButtonTitle(for: event), systemImage: "calendar.badge.plus")
                            }
                            .disabled(!store.canWriteCalendar(for: event))
                            .help(store.calendarWriteHelp(for: event))
                        }
                        .font(.caption)
                    }
                    .padding(12)
                    .background(palette.surfaceSubtle, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(palette.border, lineWidth: theme.metrics.borderWidth)
                    )
                }
            }
        }
    }

    private func calendarButtonTitle(for event: EventCandidate) -> String {
        if event.calendarStatus == .added { return "已加入" }
        if event.startTime == nil { return "缺少时间" }
        if event.confidence < 0.72 { return "待确认" }
        return "加入日历"
    }
}

private struct ExplanationSection: View {
    var explanation: FileExplanation
    var systemImage: String
    @Environment(\.dropTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = theme.palette(for: colorScheme)
        DetailSection(title: explanation.headline, systemImage: systemImage) {
            VStack(alignment: .leading, spacing: 10) {
                Text(explanation.summary)
                    .foregroundStyle(palette.textSecondary)

                ForEach(explanation.signals, id: \.self) { signal in
                    VStack(alignment: .leading, spacing: 4) {
                        Label(signal.title, systemImage: signal.prominent ? "checkmark.circle.fill" : "info.circle")
                            .foregroundStyle(signal.prominent ? .primary : .secondary)
                        Text(signal.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(palette.surfaceSubtle, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(palette.border, lineWidth: theme.metrics.borderWidth)
                    )
                }
            }
        }
    }
}

private struct SensitiveGateView: View {
    @EnvironmentObject private var store: AppStore
    var file: DropFile
    @Environment(\.dropTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = theme.palette(for: colorScheme)
        DetailSection(title: "敏感文件确认", systemImage: "hand.raised") {
            Text(store.sensitiveStatusMessage(for: file))
                .foregroundStyle(palette.textSecondary)

            HStack {
                Button {
                    Task { await store.allowSensitiveFile(file) }
                } label: {
                    Label("本次解析", systemImage: "checkmark.shield")
                }
                .buttonStyle(DropPrimaryButtonStyle())

                Button {
                    Task { await store.trustDirectory(for: file) }
                } label: {
                    Label("信任该目录", systemImage: "folder.badge.gearshape")
                }
                .buttonStyle(DropSecondaryButtonStyle())

                Button(role: .destructive) {
                    Task { await store.ignoreFile(file) }
                } label: {
                    Label("永不解析此文件", systemImage: "xmark.shield")
                }
                .buttonStyle(DropSecondaryButtonStyle())
            }
        }
    }
}

private struct SensitiveStatusSection: View {
    @EnvironmentObject private var store: AppStore
    var file: DropFile
    @Environment(\.dropTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = theme.palette(for: colorScheme)
        DetailSection(title: store.sensitiveStatusTitle(for: file), systemImage: "lock.shield") {
            Text(store.sensitiveStatusMessage(for: file))
                .foregroundStyle(palette.textSecondary)
        }
    }
}

private struct SemanticSnippetsSection: View {
    var snippets: [String]
    @Environment(\.dropTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = theme.palette(for: colorScheme)
        DetailSection(title: "语义索引片段", systemImage: "quote.bubble") {
            if snippets.isEmpty {
                Text("暂无片段")
                    .foregroundStyle(palette.textSecondary)
            } else {
                ForEach(snippets.indices, id: \.self) { index in
                    let snippet = snippets[index]
                    Text(snippet)
                        .font(.callout)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(5)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(palette.surfaceSubtle, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(palette.border, lineWidth: theme.metrics.borderWidth)
                        )
                }
            }
        }
    }
}

private struct EvidenceSnippetsSection: View {
    var snippets: [String]
    @Environment(\.dropTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = theme.palette(for: colorScheme)
        DetailSection(title: "事件证据片段", systemImage: "text.quote") {
            if snippets.isEmpty {
                Text("暂无片段")
                    .foregroundStyle(palette.textSecondary)
            } else {
                ForEach(snippets.indices, id: \.self) { index in
                    let snippet = snippets[index]
                    Text(snippet)
                        .font(.callout)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(5)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(palette.surfaceSubtle, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(palette.border, lineWidth: theme.metrics.borderWidth)
                        )
                }
            }
        }
    }
}

struct WarningSection: View {
    var message: String
    @Environment(\.dropTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = theme.palette(for: colorScheme)
        Label(message, systemImage: "exclamationmark.triangle")
            .foregroundStyle(palette.warning)
            .padding(12)
            .dropGlass(cornerRadius: 12)
    }
}

struct DetailSection<Content: View>: View {
    var title: String
    var systemImage: String
    @ViewBuilder var content: Content
    @Environment(\.dropTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = theme.palette(for: colorScheme)
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(theme.typography.heading(.headline, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dropGlass(cornerRadius: 14)
    }
}

private struct UpgradeNudge: View {
    @EnvironmentObject private var store: AppStore
    var text: String
    var trigger: UpgradeTrigger
    @Environment(\.dropTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = theme.palette(for: colorScheme)
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(palette.accentOrange)
            Text(text)
                .font(.caption)
                .foregroundStyle(palette.textSecondary)
            Spacer()
            Button("升级解锁") {
                store.openUpgradePage(trigger: trigger)
            }
            .font(.caption)
            .buttonStyle(DropSecondaryButtonStyle())
        }
        .padding(10)
        .background(palette.accentOrange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(palette.border, lineWidth: theme.metrics.borderWidth)
        )
    }
}

struct StatusPill: View {
    var text: String
    var systemImage: String
    var prominent = false
    @Environment(\.dropTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = theme.palette(for: colorScheme)
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(prominent ? palette.danger.opacity(0.14) : palette.surfaceSubtle, in: Capsule())
            .foregroundStyle(prominent ? palette.danger : palette.textSecondary)
    }
}

struct MetadataItem: View {
    var title: String
    var value: String
    @Environment(\.dropTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = theme.palette(for: colorScheme)
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(palette.textSecondary)
            Text(value)
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
    }
}
