import SwiftUI

struct ImportantRemindersView: View {
    @EnvironmentObject private var store: AppStore
    var openFile: (DropFile) -> Void

    private var items: [ReminderItem] {
        store.files.flatMap(ReminderItem.items(for:))
            .sorted { lhs, rhs in
                switch (lhs.date, rhs.date) {
                case let (left?, right?):
                    return left < right
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return lhs.file.importedAt > rhs.file.importedAt
                }
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            HeaderStrip(title: "重要提醒", subtitle: "按可行动事项展示：考试、截止、报名、缴费、面试、会议")

            if items.isEmpty {
                Spacer()
                EmptyStateView(title: "暂无可行动提醒", message: "只有识别到明确时间或明确待办的文件会出现在这里。", systemImage: "bell")
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(items) { item in
                            ReminderActionCard(item: item, openFile: openFile)
                        }
                    }
                    .padding()
                }
            }
        }
    }
}

private struct ReminderActionCard: View {
    @EnvironmentObject private var store: AppStore
    var item: ReminderItem
    var openFile: (DropFile) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: item.systemImage)
                    .foregroundStyle(item.prominent ? Color.red : Color.accentColor)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(item.file.fileName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                StatusPill(text: item.kindLabel, systemImage: item.prominent ? "exclamationmark.circle.fill" : "circle.fill", prominent: item.prominent)
            }

            if let date = item.date {
                Label(DateFormatter.dropShort.string(from: date), systemImage: "calendar")
                    .font(.caption)
            }

            if let evidence = item.evidence, !evidence.isEmpty {
                Text(evidence)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .dropInsetMaterial(cornerRadius: 8)
            }

            HStack {
                if let event = item.event {
                    Button {
                        Task { await store.addEventToCalendar(eventID: event.id, in: item.file.id) }
                    } label: {
                        Label(event.calendarStatus == .added ? "已加入" : "加入日历", systemImage: "calendar.badge.plus")
                    }
                    .dropProminentActionStyle()
                    .disabled(!store.canWriteCalendar(for: event))
                    .help(store.calendarWriteHelp(for: event))
                }

                Button {
                    store.openFile(item.file)
                } label: {
                    Label("打开原文件", systemImage: "arrow.up.right.square")
                }
                .dropSecondaryActionStyle()

                Button {
                    openFile(item.file)
                } label: {
                    Label("查看详情", systemImage: "sidebar.right")
                }
                .dropSecondaryActionStyle()

                Button {
                    store.navigateToFile(
                        fileID: item.file.id,
                        anchor: item.explanationAnchor,
                        eventID: item.event?.id
                    )
                } label: {
                    Label("查看为何提醒", systemImage: "questionmark.circle")
                }
                .dropSecondaryActionStyle()

                Spacer()

                Button {
                    Task { await store.ignoreFile(item.file) }
                } label: {
                    Label("忽略文件", systemImage: "checkmark")
                }
                .dropSecondaryActionStyle()
            }
            .font(.caption)
        }
        .padding(14)
        .dropGlass(cornerRadius: 14, interactive: true)
        .onTapGesture {
            openFile(item.file)
        }
    }
}

private struct ReminderItem: Identifiable {
    var id: String
    var file: DropFile
    var event: EventCandidate?
    var title: String
    var kindLabel: String
    var date: Date?
    var evidence: String?
    var prominent: Bool

    var systemImage: String {
        event == nil ? "text.badge.checkmark" : "calendar.badge.clock"
    }

    var explanationAnchor: FileDetailSectionAnchor {
        event == nil ? .importance : .calendarReason
    }

    static func items(for file: DropFile) -> [ReminderItem] {
        guard file.parsedStatus == .parsed,
              !isNonActionable(file) else {
            return []
        }

        let events = file.events
            .filter(isActionable)
            .sorted { lhs, rhs in
                switch (lhs.startTime, rhs.startTime) {
                case let (left?, right?):
                    return left < right
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return lhs.confidence > rhs.confidence
                }
            }

        if !events.isEmpty {
            return events.map { event in
                ReminderItem(
                    id: "\(file.id.uuidString)-\(event.id.uuidString)",
                    file: file,
                    event: event,
                    title: event.title,
                    kindLabel: event.eventType.rawValue,
                    date: event.startTime,
                    evidence: event.evidence,
                    prominent: [.exam, .assignmentDeadline, .registrationDeadline, .paymentDeadline].contains(event.eventType)
                )
            }
        }

        guard hasImportantSignal(file) else { return [] }
        return [
            ReminderItem(
                id: file.id.uuidString,
                file: file,
                event: nil,
                title: file.summary?.oneLineSummary ?? file.fileName,
                kindLabel: file.summary?.fileTypeLabel ?? "待确认",
                date: nil,
                evidence: nil,
                prominent: true
            )
        ]
    }

    private static func isActionable(_ event: EventCandidate) -> Bool {
        if [.exam, .assignmentDeadline, .registrationDeadline, .paymentDeadline, .interview, .meeting].contains(event.eventType) && event.confidence >= 0.72 {
            return true
        }
        return event.eventType == .campusActivity &&
            event.startTime != nil &&
            event.evidence.range(of: #"大赛|竞赛|比赛|决赛|赛区"#, options: .regularExpression) != nil
    }

    private static func isNonActionable(_ file: DropFile) -> Bool {
        let text = classificationText(for: file)
        if PriorityClassifier.isLowValue(text: text, fileName: file.fileName) {
            return true
        }
        let labels = ["代码/配置", "阅读材料", "课程资料"]
        return labels.contains { text.localizedCaseInsensitiveContains($0) }
    }

    private static func hasImportantSignal(_ file: DropFile) -> Bool {
        guard file.priorityLevel == .high else { return false }
        let text = classificationText(for: file).lowercased()
        return [
            "考试", "补考", "截止", "ddl", "deadline", "报名", "缴费", "面试", "宣讲",
            "会议", "大赛通知", "课堂作业", "作业", "答辩", "提交", "作品提交"
        ].contains { text.contains($0.lowercased()) }
    }

    private static func classificationText(for file: DropFile) -> String {
        [
            file.fileName,
            file.summary?.fileTypeLabel ?? "",
            file.summary?.oneLineSummary ?? "",
            file.summary?.keyPoints.joined(separator: "\n") ?? "",
            file.snippets.joined(separator: "\n")
        ].joined(separator: "\n")
    }
}
