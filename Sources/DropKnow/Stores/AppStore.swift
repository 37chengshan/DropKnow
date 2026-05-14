import AppKit
import Foundation

struct AppStoreEnvironment {
    var databaseURL: URL
    var settingsURL: URL
    var runtimeURL: URL
    var startMonitor: Bool
    var startProcessingOnLaunch: Bool

    static var live: AppStoreEnvironment {
        AppStoreEnvironment(
            databaseURL: AppPaths.databaseURL,
            settingsURL: AppPaths.settingsURL,
            runtimeURL: AppPaths.runtimeURL,
            startMonitor: true,
            startProcessingOnLaunch: true
        )
    }

    static func temporary(
        baseURL: URL,
        startMonitor: Bool = false,
        startProcessingOnLaunch: Bool = false
    ) -> AppStoreEnvironment {
        AppStoreEnvironment(
            databaseURL: baseURL.appendingPathComponent("dropknow_state.json"),
            settingsURL: baseURL.appendingPathComponent("settings.json"),
            runtimeURL: baseURL.appendingPathComponent("dropknow_runtime.json"),
            startMonitor: startMonitor,
            startProcessingOnLaunch: startProcessingOnLaunch
        )
    }
}

@MainActor
final class AppStore: ObservableObject {
    @Published var settings: DropSettings
    @Published var files: [DropFile]
    @Published var selectedFileID: DropFile.ID?
    @Published var selectedQueueItemID: UUID?
    @Published var queueItems: [QueueDisplayItem]
    @Published var quotaSnapshot: QuotaSnapshot
    @Published var parseQueueSummary: ProcessingQueueSummary
    @Published var indexQueueSummary: ProcessingQueueSummary
    @Published var hasFailedJobs: Bool
    @Published var searchQuery = ""
    @Published var searchResult: SearchResult?
    @Published var searchQuotaWarning: String?
    @Published var searchErrorMessage: String?
    @Published var chatMessages: [ChatMessage] = [
        ChatMessage(role: .assistant, text: "可以直接问通用问题；如果你问下载文件里的内容，例如“4C 大赛有哪些时间节点？”我会附上相关文件卡片。")
    ]
    @Published var toastMessage: String?
    @Published var alertMessage: String?
    @Published var alertKind: AlertKind?
    @Published var ragUnavailableReason: String?
    @Published var isImporting = false
    @Published var isSearching = false
    @Published var isRebuildingIndex = false
    @Published var historicalImportPrompt: HistoricalImportPromptState?
    @Published var pendingNavigation: SectionNavigationRequest?
    @Published var detailFocusRequest: DetailFocusRequest?
    @Published var highlightedDetailEventID: EventCandidate.ID?
    @Published var activeUpgradeTrigger: UpgradeTrigger?

    private let monitor = DirectoryMonitor()
    private let rag: any RAGServing
    private let calendarService = CalendarService()
    private lazy var notifications = NotificationService.shared
    private let processingRuntime: ProcessingRuntime
    private let processingEngine: ProcessingEngine
    private let environment: AppStoreEnvironment
    private let sessionStartedAt: Date
    private let autoImportMinimumModifiedAt: Date?
    private let providerConfigurationLoader: () -> ProviderConfiguration
    private var processingTask: Task<Void, Never>?
    private var retryWakeTask: Task<Void, Never>?
    private var pendingSearchTask: Task<Void, Never>?
    private var activeSearchTask: Task<Void, Never>?
    private var activeSearchRequestID: UUID?
    private var activeSearchUserMessageID: UUID?
    private var lastSubmittedQuery: String?

    convenience init() {
        let environment = AppStoreEnvironment.live
        let fileLoadResult = Self.loadStoredFiles(from: environment.databaseURL)
        let runtimeLoadResult = Self.loadRuntimeState(from: environment.runtimeURL)
        self.init(
            settings: Self.loadSettings(from: environment.settingsURL),
            files: fileLoadResult.files,
            storedFilesStatus: fileLoadResult.status,
            storedFilesBackupURL: fileLoadResult.backupURL,
            runtimeState: runtimeLoadResult.state,
            runtimeErrorMessage: runtimeLoadResult.errorMessage,
            runtimeBackupURL: runtimeLoadResult.backupURL,
            environment: environment
        )
    }

    init(
        settings initialSettings: DropSettings,
        files initialFiles: [DropFile] = [],
        storedFilesStatus: StoredFilesLoadStatus = .loadedState,
        storedFilesBackupURL: URL? = nil,
        runtimeState initialRuntime: RuntimeState = .empty,
        runtimeErrorMessage: String? = nil,
        runtimeBackupURL: URL? = nil,
        rag: any RAGServing = RAGService(),
        environment: AppStoreEnvironment = .live,
        providerConfigurationLoader: @escaping () -> ProviderConfiguration = { ProviderConfiguration.load() },
        sessionStartedAt: Date = Date()
    ) {
        let normalizedSettings = Self.normalizedSettings(initialSettings)
        let restoredFiles = Self.restoreLoadedFiles(initialFiles)

        self.settings = normalizedSettings.settings
        self.files = restoredFiles
        self.selectedFileID = restoredFiles.first?.id
        self.selectedQueueItemID = nil
        self.queueItems = Self.makeQueueItems(from: initialRuntime)
        self.quotaSnapshot = QuotaService.snapshot(settings: normalizedSettings.settings, usage: initialRuntime.dailyUsage, now: sessionStartedAt)
        self.parseQueueSummary = Self.makeParseQueueSummary(from: initialRuntime.parseJobs)
        self.indexQueueSummary = Self.makeIndexQueueSummary(from: initialRuntime.indexJobs)
        self.hasFailedJobs = Self.hasFailedJobs(in: initialRuntime)
        self.processingRuntime = .current
        self.rag = rag
        self.environment = environment
        self.providerConfigurationLoader = providerConfigurationLoader
        self.processingEngine = ProcessingEngine(initialState: initialRuntime, runtimeURL: environment.runtimeURL, recoveredAt: sessionStartedAt)
        self.sessionStartedAt = sessionStartedAt
        self.autoImportMinimumModifiedAt = AutoImportSafetyPolicy.minimumModifiedAt(for: storedFilesStatus, sessionStartedAt: sessionStartedAt)
        self.historicalImportPrompt = Self.makeHistoricalImportPrompt(
            settings: normalizedSettings.settings,
            loadStatus: storedFilesStatus,
            sessionStartedAt: sessionStartedAt
        )

        let seenPaths = Set(restoredFiles.map(\.filePath))
            .union(initialRuntime.parseJobs.map(\.filePath))
            .union(initialRuntime.indexJobs.map(\.filePath))
        if environment.startMonitor {
            monitor.markSeen(Array(seenPaths))
            monitor.onTick = { [weak self] in
                Task { await self?.scanForNewFiles() }
            }
            monitor.start()
        }
        notifications.onOpenFile = { [weak self] fileID, anchor in
            Task { @MainActor [weak self] in
                self?.navigateToFile(fileID: fileID, anchor: anchor)
            }
        }

        var alerts: [String] = []
        if storedFilesStatus == .corruptedState {
            let backupPath = storedFilesBackupURL?.path ?? "Application Support"
            alerts.append("文件状态损坏，已切换到保护模式。本次仅监听本次启动后的新文件。备份位置：\(backupPath)")
        }
        if let runtimeError = runtimeErrorMessage {
            let backupPath = runtimeBackupURL?.path ?? "Application Support"
            alerts.append("后台队列状态损坏，已重置运行时队列。备份位置：\(backupPath)。错误：\(runtimeError)")
        }
        if normalizedSettings.didTrimWatchDirectories {
            alerts.append(watchDirectoryLimitMessage)
        }
        if normalizedSettings.didClampImportWindow {
            alerts.append(initialImportWindowMessage)
        }
        if !alerts.isEmpty {
            alertMessage = alerts.joined(separator: "\n\n")
            alertKind = .generic
        }

        if environment.startProcessingOnLaunch {
            Task {
                await refreshRuntimeSnapshot()
                startProcessingIfNeeded()
            }
        }
    }

    var selectedFile: DropFile? {
        guard let selectedFileID else { return files.first }
        return files.first { $0.id == selectedFileID }
    }

    var providerStatus: RAGProviderStatus {
        if let reason = ragUnavailableReason, !reason.isEmpty {
            return RAGProviderStatus(
                mode: .unavailable,
                headline: "RAG 依赖未就绪",
                detail: reason
            )
        }
        let config = providerConfigurationLoader()
        if config.hasAPIKey {
            return RAGProviderStatus(
                mode: .remoteReady,
                headline: "远端模型已配置",
                detail: "embedding/问答/精修均可用"
            )
        }
        return RAGProviderStatus(
            mode: .localFallback,
            headline: "未配置 API Key",
            detail: "已启用本地降级模式：索引/搜索可用，问答/精修不可用"
        )
    }

    var providerConfigURL: URL {
        providerConfigurationLoader().configURL
    }

    var shouldOfferCalendarSettings: Bool {
        alertKind == .calendar
    }

    var shouldOfferProviderSettings: Bool {
        alertKind == .provider
    }

    func openProviderSettings() {
        pendingNavigation = SectionNavigationRequest(section: .settings)
        activateAppIfPossible()
    }

    func openProviderConfigLocation() {
        let url = providerConfigURL
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }

    var importantFiles: [DropFile] {
        files
            .filter {
                $0.parsedStatus != .ignored &&
                !Self.isNonActionable($0) &&
                (Self.hasImportantSignal($0) || Self.hasActionableEvent($0))
            }
            .sorted { $0.importedAt > $1.importedAt }
    }

    var planCapabilities: PlanCapabilities {
        settings.subscriptionPlan.capabilities
    }

    var effectiveImportRecentDays: Int {
        min(settings.importRecentDays, planCapabilities.allowedInitialImportWindowDays)
    }

    var canUseCalendarWrite: Bool {
        planCapabilities.canUseCalendarWrite
    }

    var canAddWatchDirectory: Bool {
        settings.watchDirectories.count < planCapabilities.maxWatchDirectories
    }

    var isInitialImportWindowFixed: Bool {
        !planCapabilities.canCustomizeInitialImportWindow
    }

    var currentPlanName: String {
        settings.subscriptionPlan.rawValue
    }

    static var watchDirectoryLimitMessage: String {
        "免费版最多可监听 1 个目录，升级后可添加更多目录。"
    }

    static var calendarWriteDisabledMessage: String {
        "免费版仅展示事件候选，升级后可写入系统日历。"
    }

    static var initialImportWindowMessage: String {
        "免费版首次导入固定最近 7 天。"
    }

    var watchDirectoryLimitMessage: String {
        Self.watchDirectoryLimitMessage
    }

    var calendarWriteDisabledMessage: String {
        Self.calendarWriteDisabledMessage
    }

    var initialImportWindowMessage: String {
        Self.initialImportWindowMessage
    }

    var upgradeCTAURL: URL? {
        URL(string: "https://dropknow.app/upgrade")
    }

    func navigateToFile(fileID: UUID, anchor: FileDetailSectionAnchor? = nil, eventID: EventCandidate.ID? = nil) {
        selectedFileID = fileID
        highlightedDetailEventID = eventID
        if let anchor {
            detailFocusRequest = DetailFocusRequest(fileID: fileID, anchor: anchor)
        }
        pendingNavigation = SectionNavigationRequest(section: .recent)
        activateAppIfPossible()
    }

    func openUpgradePage(trigger: UpgradeTrigger) {
        activeUpgradeTrigger = trigger
        pendingNavigation = SectionNavigationRequest(section: .subscription)
        activateAppIfPossible()
    }

    func consumePendingNavigation() {
        pendingNavigation = nil
    }

    func clearDetailFocusRequest(id: UUID) {
        guard detailFocusRequest?.id == id else { return }
        detailFocusRequest = nil
    }

    func openUpgradeCTA() {
        guard let url = upgradeCTAURL else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func importanceExplanation(for file: DropFile) -> FileExplanation? {
        guard file.parsedStatus == .parsed else { return nil }

        let text = Self.persistedText(for: file).lowercased()
        var signals: [ExplanationSignal] = []

        let highConfidenceEvents = file.events
            .filter { $0.confidence >= 0.72 }
            .sorted { $0.confidence > $1.confidence }

        if let primaryEvent = highConfidenceEvents.first {
            let detail = primaryEvent.startTime.map(DateFormatter.dropShort.string(from:)) ?? "已识别到待确认时间"
            signals.append(
                ExplanationSignal(
                    title: "高置信度事件",
                    detail: "\(primaryEvent.eventType.rawValue) · \(detail)",
                    prominent: true
                )
            )
        }

        let matchedKeywords = Self.matchedImportantKeywords(in: text)
        if !matchedKeywords.isEmpty {
            signals.append(
                ExplanationSignal(
                    title: "命中关键通知词",
                    detail: matchedKeywords.prefix(3).joined(separator: " / "),
                    prominent: true
                )
            )
        }

        if let keyTime = file.summary?.keyTime, !keyTime.isEmpty {
            signals.append(
                ExplanationSignal(
                    title: "提炼出关键时间",
                    detail: keyTime
                )
            )
        }

        if file.priorityLevel == .high {
            signals.append(
                ExplanationSignal(
                    title: "优先级策略",
                    detail: "当前规则认为这份文件更像通知、DDL、考试或报名类信息。"
                )
            )
        }

        guard !signals.isEmpty else { return nil }
        return FileExplanation(
            headline: "为什么这份文件被判重要",
            summary: highConfidenceEvents.isEmpty
                ? "这份文件命中了通知型关键词或关键句，因此被提升为优先处理。"
                : "这份文件识别到了高置信度的时间/待办线索，因此被提升为优先处理。",
            signals: signals
        )
    }

    func calendarExplanation(for file: DropFile, highlightedEventID: EventCandidate.ID? = nil) -> FileExplanation? {
        let sortedEvents = file.events.sorted(by: Self.sortEventsForExplanation)
        guard let primaryEvent = highlightedEventID.flatMap({ targetID in
            sortedEvents.first(where: { $0.id == targetID })
        }) ?? sortedEvents.first else { return nil }

        var signals: [ExplanationSignal] = []
        if let start = primaryEvent.startTime {
            signals.append(
                ExplanationSignal(
                    title: "识别到日期时间",
                    detail: DateFormatter.dropShort.string(from: start),
                    prominent: primaryEvent.confidence >= 0.72
                )
            )
        } else {
            signals.append(
                ExplanationSignal(
                    title: "识别到日期文本",
                    detail: "已命中日期线索，但还缺少精确时间。"
                )
            )
        }

        signals.append(
            ExplanationSignal(
                title: "事件类型",
                detail: "\(primaryEvent.eventType.rawValue) · 置信度 \(Int(primaryEvent.confidence * 100))%"
            )
        )

        if let location = primaryEvent.location, !location.isEmpty {
            signals.append(
                ExplanationSignal(
                    title: "提取到地点",
                    detail: location
                )
            )
        }

        let evidence = primaryEvent.evidence.trimmingCharacters(in: .whitespacesAndNewlines)
        if !evidence.isEmpty {
            signals.append(
                ExplanationSignal(
                    title: "证据片段",
                    detail: String(evidence.prefix(80))
                )
            )
        }

        return FileExplanation(
            headline: "为什么触发日历候选",
            summary: primaryEvent.confidence >= 0.72
                ? "这份文件识别到了可行动的时间安排，因此生成了高置信度日历候选。"
                : "这份文件识别到了日期线索，但仍建议你先人工确认后再加入日历。",
            signals: signals
        )
    }

    func explanationAnchor(for file: DropFile) -> FileDetailSectionAnchor {
        file.hasHighConfidenceEvent ? .calendarReason : .importance
    }

    func searchSnippet(for hit: SearchHit) -> String {
        let current = hit.snippet.trimmingCharacters(in: .whitespacesAndNewlines)
        if !current.isEmpty, current != hit.fileName {
            return current
        }
        guard let file = files.first(where: { $0.id == hit.fileID || $0.filePath == hit.filePath || $0.fileName == hit.fileName }) else {
            return current
        }
        if let evidence = file.events.sorted(by: Self.sortEventsForExplanation).first?.evidence,
           !evidence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return String(evidence.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        }
        if let summary = file.summary?.oneLineSummary, !summary.isEmpty {
            return summary
        }
        return file.snippets.first ?? current
    }

    func parsedFileNotification(for file: DropFile, trigger: ProcessingTrigger) -> ParsedFileNotificationDescriptor? {
        guard trigger == .auto, file.parsedStatus == .parsed else { return nil }

        if let event = file.events
            .filter({ $0.confidence >= 0.72 && $0.startTime != nil })
            .sorted(by: Self.sortEventsForExplanation)
            .first {
            let timeText = event.startTime.map(DateFormatter.dropShort.string(from:)) ?? "待确认时间"
            let locationText = event.location?.isEmpty == false ? " · \(event.location!)" : ""
            return ParsedFileNotificationDescriptor(
                fileID: file.id,
                title: "落知发现关键时间",
                subtitle: file.fileName,
                body: "\(event.title) · \(timeText)\(locationText) · 因识别到高置信度时间安排",
                anchor: .events
            )
        }

        guard file.priorityLevel == .high,
              let explanation = importanceExplanation(for: file),
              let firstReason = explanation.signals.first?.detail,
              let summary = file.summary?.oneLineSummary,
              !summary.isEmpty else {
            return nil
        }
        return ParsedFileNotificationDescriptor(
            fileID: file.id,
            title: "落知发现重点文件",
            subtitle: file.fileName,
            body: "\(summary) · \(firstReason)",
            anchor: .importance
        )
    }

    func chooseDirectory() {
        guard canAddWatchDirectory else {
            toastMessage = watchDirectoryLimitMessage
            openUpgradePage(trigger: .directoryLimit)
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "授权目录"
        if panel.runModal() == .OK, let url = panel.url {
            switch addWatchDirectoryPath(url.path) {
            case .added:
                Task { await importRecentFiles(showToast: true) }
            case .duplicate:
                toastMessage = "该目录已在监听中"
            case .blocked(let message):
                alertMessage = message
                alertKind = .generic
            }
        }
    }

    @discardableResult
    func addWatchDirectoryPath(_ path: String) -> WatchDirectoryAddResult {
        if settings.watchDirectories.contains(path) {
            return .duplicate
        }
        guard canAddWatchDirectory else {
            return .blocked(message: watchDirectoryLimitMessage)
        }
        settings.watchDirectories.append(path)
        saveSettings()
        return .added
    }

    func removeDirectory(_ directory: String) {
        settings.watchDirectories.removeAll { $0 == directory }
        settings.trustedDirectories.removeAll { $0 == directory }
        saveSettings()
    }

    func importRecentFiles(showToast: Bool) async {
        guard !isImporting else { return }
        isImporting = true
        defer { isImporting = false }

        let start = ContinuousClock().now
        let urls = recentSupportedFiles()
        monitor.markSeen(urls.map(\.path))
        var enqueued = 0
        for url in urls {
            if await enqueueParse(url: url, trigger: .initialImport) {
                enqueued += 1
            }
        }
        if showToast {
            toastMessage = "已加入处理队列：\(enqueued) 个文件"
        }
        historicalImportPrompt = nil
        PerfTrace.log(
            name: "import.recentFiles",
            start: start,
            success: true,
            metadata: [
                "directories": "\(settings.watchDirectories.count)",
                "files": "\(urls.count)",
                "enqueued": "\(enqueued)"
            ]
        )
    }

    func dismissHistoricalImportPrompt() {
        historicalImportPrompt = nil
    }

    func scanForNewFiles() async {
        guard settings.autoParseNewFiles else { return }
        let limit = AutoImportSafetyPolicy.autoImportLimit(dailyParseLimit: settings.dailyParseLimit)
        guard limit > 0 else { return }
        let urls = monitor.newStableFiles(
            in: settings.watchDirectories,
            modifiedAfter: autoImportMinimumModifiedAt,
            limit: limit
        )
        for url in urls {
            _ = await enqueueParse(url: url, trigger: .auto, showQuotaToast: false)
        }
    }

    func reparseSelection() async {
        guard let selectedFile else { return }
        _ = await enqueueParse(
            url: URL(fileURLWithPath: selectedFile.filePath),
            trigger: .manualReparse
        )
    }

    func rebuildSemanticIndex() async {
        guard !isRebuildingIndex else { return }
        isRebuildingIndex = true
        defer { isRebuildingIndex = false }

        let start = ContinuousClock().now
        let candidates = files.filter { file in
            file.parsedStatus == .parsed &&
            FileManager.default.fileExists(atPath: file.filePath) &&
            DocumentParser.kind(for: URL(fileURLWithPath: file.filePath)) != .unsupported &&
            needsIndexBackfill(file)
        }

        var enqueued = 0
        for file in candidates {
            let url = URL(fileURLWithPath: file.filePath)
            if await enqueueParse(url: url, trigger: .manualBackfill) {
                enqueued += 1
            }
        }
        toastMessage = "已加入补齐索引队列：\(enqueued) 个文件"
        PerfTrace.log(
            name: "index.backfill.enqueue",
            start: start,
            success: true,
            metadata: [
                "candidates": "\(candidates.count)",
                "enqueued": "\(enqueued)"
            ]
        )
    }

    func retryFailedJobs() async {
        let retried = await processingEngine.retryFailedJobs(now: Date())
        await refreshRuntimeSnapshot()
        if retried > 0 {
            toastMessage = "已重试失败任务：\(retried) 个"
            startProcessingIfNeeded()
        }
    }

    func retrySelectedQueueItem() async {
        guard let selectedQueueItemID else { return }
        let retried = await processingEngine.retryJob(id: selectedQueueItemID, now: Date())
        await refreshRuntimeSnapshot()
        if retried {
            toastMessage = "已重试所选任务"
            startProcessingIfNeeded()
        }
    }

    func allowSensitiveFile(_ file: DropFile) async {
        _ = await enqueueParse(
            url: URL(fileURLWithPath: file.filePath),
            trigger: .manualReparse,
            forceAllowSensitive: true
        )
    }

    func ignoreFile(_ file: DropFile) async {
        update(file.id) {
            $0.parsedStatus = .ignored
            $0.errorMessage = nil
        }
        saveFiles()
        await processingEngine.discardJobs(for: file.id, now: Date())
        await refreshRuntimeSnapshot()
    }

    func trustDirectory(for file: DropFile) async {
        let directory = URL(fileURLWithPath: file.filePath).deletingLastPathComponent().path
        if !settings.trustedDirectories.contains(directory) {
            settings.trustedDirectories.append(directory)
            saveSettings()
        }
        await allowSensitiveFile(file)
    }

    func openSelectedFile() {
        guard let selectedFile else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: selectedFile.filePath))
    }

    func openFile(_ file: DropFile) {
        NSWorkspace.shared.open(URL(fileURLWithPath: file.filePath))
    }

    func revealSelectedFile() {
        guard let selectedFile else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: selectedFile.filePath)])
    }

    func openFileForQueueItem(_ item: QueueDisplayItem) {
        if let file = files.first(where: { $0.id == item.fileID }) {
            openFile(file)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.filePath)])
        }
    }

    func focusFileForQueueItem(_ item: QueueDisplayItem) {
        selectedFileID = item.fileID
    }

    func addEventToCalendar(eventID: EventCandidate.ID, in fileID: DropFile.ID) async {
        guard canUseCalendarWrite else {
            toastMessage = calendarWriteDisabledMessage
            openUpgradePage(trigger: .calendar)
            return
        }
        guard let file = files.first(where: { $0.id == fileID }),
              let event = file.events.first(where: { $0.id == eventID }) else {
            return
        }

        do {
            try await calendarService.add(event: event, file: file)
            update(fileID) { file in
                if let index = file.events.firstIndex(where: { $0.id == eventID }) {
                    file.events[index].calendarStatus = .added
                }
            }
            saveFiles()
            toastMessage = "已加入日历：\(event.title)"
            notifications.notifyCalendarAdded(title: event.title)
        } catch {
            alertMessage = "加入日历失败：\(error.localizedDescription)"
            alertKind = .calendar
        }
    }

    func openCalendarPrivacySettings() {
        calendarService.openCalendarPrivacySettings()
    }

    func markCalendarAdded(eventID: EventCandidate.ID, in fileID: DropFile.ID) {
        update(fileID) { file in
            if let index = file.events.firstIndex(where: { $0.id == eventID }) {
                file.events[index].calendarStatus = .added
            }
        }
        saveFiles()
    }

    func canWriteCalendar(for event: EventCandidate) -> Bool {
        canUseCalendarWrite && event.canAddToCalendar
    }

    func calendarWriteHelp(for event: EventCandidate) -> String {
        guard canUseCalendarWrite else { return calendarWriteDisabledMessage }
        if event.calendarStatus == .added { return "该事件已加入日历" }
        if event.startTime == nil { return "需要先识别到具体日期才能写入日历" }
        if event.confidence < 0.72 { return "当前置信度较低，建议先在详情页确认时间与事件类型" }
        if !event.hasClockTime { return "未识别到具体时刻，将按全天事件写入" }
        return "写入系统日历"
    }

    func sensitiveRemoteDecision(
        for filePath: String,
        detectedStatus: SensitivityStatus,
        forceAllowSensitive: Bool
    ) -> SensitiveRemoteDecision {
        let directory = URL(fileURLWithPath: filePath).deletingLastPathComponent().path
        if detectedStatus == .trusted || settings.trustedDirectories.contains(directory) {
            return .allow(.trustedDirectory)
        }
        guard detectedStatus == .suspected else {
            return .allow(.clear)
        }
        guard settings.sensitiveAlwaysAsk else {
            return .allow(.clear)
        }
        if forceAllowSensitive {
            return .allow(.oneTimeApproval)
        }
        return .block(message: "该文件疑似包含成绩、身份、缴费或个人信息，默认不会发送到远端服务。你可以仅本次允许、信任目录，或忽略此文件。")
    }

    func sensitiveStatusTitle(for file: DropFile) -> String {
        if file.parsedStatus == .sensitiveGate {
            return "敏感文件待确认"
        }
        switch file.sensitivityStatus {
        case .trusted:
            return "敏感文件已按信任目录处理"
        case .approvedOnce:
            return "敏感文件已按单次授权处理"
        case .suspected:
            return "敏感策略"
        case .clear:
            return "敏感策略"
        }
    }

    func sensitiveStatusMessage(for file: DropFile) -> String {
        if file.parsedStatus == .sensitiveGate {
            return "该文件疑似包含成绩、身份、缴费或个人信息，默认不会发送到远端服务。你可以仅本次允许、信任目录，或忽略此文件。"
        }
        switch file.sensitivityStatus {
        case .trusted:
            return "该目录已被信任，后续同目录的敏感文件会继续进入远端精修和索引。"
        case .approvedOnce:
            return "该文件已通过单次授权完成处理；当前结果会保留，但后续同目录文件仍会再次询问。"
        case .suspected:
            return "该文件命中了敏感策略，默认不会发送到远端服务。"
        case .clear:
            return "当前文件未命中敏感策略。"
        }
    }

    func runtimeStateSnapshot() async -> RuntimeState {
        await processingEngine.snapshot()
    }

    func persistSettings() {
        saveSettings()
    }

    func performSearch() async {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        if isSearching, let messageID = activeSearchUserMessageID {
            chatMessages.removeAll { $0.id == messageID }
        }

        let requestID = UUID()
        activeSearchRequestID = requestID

        searchQuotaWarning = nil
        searchErrorMessage = nil
        activeUpgradeTrigger = nil
        lastSubmittedQuery = query

        let userMessage = ChatMessage(role: .user, text: query)
        chatMessages.append(userMessage)
        activeSearchUserMessageID = userMessage.id

        searchQuery = ""
        isSearching = true
        defer {
            if activeSearchRequestID == requestID {
                isSearching = false
                activeSearchUserMessageID = nil
                activeSearchTask = nil
            }
        }

        let start = ContinuousClock().now
        let shouldSearchFiles = shouldSearchFiles(for: query)
        var perfMode = shouldSearchFiles ? "file" : "chat"
        var perfEngine = ""
        var perfHits = 0
        var perfOk = true
        defer {
            PerfTrace.log(
                name: "search.perform",
                start: start,
                success: perfOk,
                metadata: [
                    "engine": perfEngine,
                    "hits": "\(perfHits)",
                    "mode": perfMode
                ]
            )
        }

        do {
            var result: SearchResult
            if shouldSearchFiles {
                let decision = await processingEngine.canConsumeUserQuota(.search, settings: settings, now: Date())
                guard decision.allowed else {
                    await refreshRuntimeSnapshot()
                    let warning = decision.message ?? "今日高级搜索额度已用尽"
                    if activeSearchRequestID == requestID {
                        searchQuotaWarning = warning
                        activeUpgradeTrigger = .searchQuota
                        result = fallbackSearch(query: query, warning: warning)
                        searchResult = result
                        chatMessages.append(ChatMessage(role: .assistant, text: result.answer, result: result))
                        perfEngine = result.engine
                        perfHits = result.hits.count
                    }
                    return
                }
                result = try await rag.search(query: query, topK: 6)
                ragUnavailableReason = nil
                result.hits = bindFileIDs(result.hits)
                _ = await processingEngine.consumeUserQuota(.search, settings: settings, now: Date())
                await refreshRuntimeSnapshot()
            } else {
                let decision = await processingEngine.canConsumeUserQuota(.chat, settings: settings, now: Date())
                guard decision.allowed else {
                    await refreshRuntimeSnapshot()
                    let warning = decision.message ?? "今日问答额度已用尽"
                    if activeSearchRequestID == requestID {
                        searchQuotaWarning = warning
                        activeUpgradeTrigger = .chatQuota
                        result = SearchResult(
                            answer: warning,
                            hits: [],
                            engine: "quota",
                            warning: warning,
                            queryMode: .quotaBlocked
                        )
                        searchResult = result
                        chatMessages.append(ChatMessage(role: .assistant, text: result.answer, result: result))
                        perfEngine = result.engine
                        perfHits = result.hits.count
                    }
                    return
                }
                guard providerConfigurationLoader().hasAPIKey else {
                    let warning = "未配置 DashScope API Key，通用问答暂不可用。你仍可提问“查文件 …”来检索已解析文件；或在设置页配置 providers.local.json / DASHSCOPE_API_KEY。"
                    if activeSearchRequestID == requestID {
                        result = SearchResult(
                            answer: warning,
                            hits: [],
                            engine: "local",
                            warning: "未配置 API Key",
                            queryMode: .errorFallback
                        )
                        searchResult = result
                        chatMessages.append(ChatMessage(role: .assistant, text: result.answer, result: result))
                        perfEngine = result.engine
                        perfHits = result.hits.count
                    }
                    return
                }
                result = try await rag.chat(query: query)
                ragUnavailableReason = nil
                _ = await processingEngine.consumeUserQuota(.chat, settings: settings, now: Date())
                await refreshRuntimeSnapshot()
            }
            guard activeSearchRequestID == requestID else { return }
            searchResult = result
            chatMessages.append(ChatMessage(role: .assistant, text: result.answer, result: result))
            perfEngine = result.engine
            perfHits = result.hits.count
        } catch is CancellationError {
            return
        } catch {
            guard activeSearchRequestID == requestID else { return }
            perfOk = false
            if let ragError = error as? RAGError {
                let errorText = ragError.localizedDescription
                searchErrorMessage = errorText
                alertKind = ragError.suggestedAlertKind
                alertMessage = errorText
                if ragError.suggestedAlertKind == .provider {
                    ragUnavailableReason = errorText
                }
            } else {
                let errorText = error.localizedDescription
                searchErrorMessage = errorText
                alertKind = .generic
                alertMessage = errorText
            }
            perfEngine = "error"
            let result = fallbackSearch(query: query, warning: "检索暂不可用：\(searchErrorMessage ?? "未知错误")")
            searchResult = result
            chatMessages.append(ChatMessage(role: .assistant, text: result.answer, result: result))
            perfEngine = result.engine
            perfHits = result.hits.count
        }
    }

    func submitSearch(debounceNanoseconds: UInt64 = 250_000_000) {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        pendingSearchTask?.cancel()
        pendingSearchTask = Task { [weak self] in
            if debounceNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: debounceNanoseconds)
            }
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.activeSearchTask?.cancel()
                self.activeSearchTask = Task { @MainActor in
                    await self.performSearch()
                }
            }
        }
    }

    func cancelSearch() {
        pendingSearchTask?.cancel()
        pendingSearchTask = nil

        activeSearchTask?.cancel()
        activeSearchTask = nil

        if let messageID = activeSearchUserMessageID {
            chatMessages.removeAll { $0.id == messageID }
        }

        activeSearchRequestID = nil
        activeSearchUserMessageID = nil
        isSearching = false
    }

    func retryLastSearch() {
        guard let lastSubmittedQuery else { return }
        searchQuery = lastSubmittedQuery
        submitSearch(debounceNanoseconds: 0)
    }

    private func shouldSearchFiles(for query: String) -> Bool {
        let content = query.lowercased()
        let fileSignals = [
            "文件", "文档", "下载", "资料", "原文", "证据", "来源", "这份", "这篇",
            "通知", "作业", "考试", "报名", "缴费", "截止", "ddl", "deadline",
            "日程", "时间节点", "加入日历", "课程", "高数", "答辩", "大赛", "4c",
            "最近", "我有哪些", "有没有需要", "需要处理"
        ]
        return fileSignals.contains { content.contains($0) }
    }

    @discardableResult
    private func enqueueParse(
        url: URL,
        trigger: ProcessingTrigger,
        forceAllowSensitive: Bool = false,
        showQuotaToast: Bool = true
    ) async -> Bool {
        let decision = await processingEngine.canEnqueueParse(settings: settings, now: Date())
        guard decision.allowed else {
            await refreshRuntimeSnapshot()
            if showQuotaToast {
                toastMessage = decision.message
            }
            activeUpgradeTrigger = .parseQuota
            return false
        }

        let existing = existingFile(for: url, preferredID: nil)
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let skeleton = DropFile(
            id: existing?.id ?? UUID(),
            fileName: url.lastPathComponent,
            filePath: url.path,
            sourceDirectory: url.deletingLastPathComponent().path,
            fileKind: DocumentParser.kind(for: url),
            importedAt: existing?.importedAt ?? Date(),
            modifiedAt: values?.contentModificationDate ?? Date(),
            fileSize: Int64(values?.fileSize ?? 0),
            textLength: existing?.textLength ?? 0,
            parsedStatus: .queued,
            sensitivityStatus: existing?.sensitivityStatus ?? .clear,
            priorityLevel: existing?.priorityLevel ?? .normal,
            summary: existing?.summary,
            events: existing?.events ?? [],
            snippets: existing?.snippets ?? [],
            errorMessage: nil,
            contentHash: existing?.contentHash,
            fingerprintComputedAt: existing?.fingerprintComputedAt,
            parserVersion: existing?.parserVersion,
            summaryVersion: existing?.summaryVersion,
            refineModel: existing?.refineModel,
            embeddingProvider: existing?.embeddingProvider,
            embeddingModel: existing?.embeddingModel,
            embeddingDimension: existing?.embeddingDimension,
            indexedContentHash: existing?.indexedContentHash,
            indexedAt: existing?.indexedAt,
            refinedContentHash: existing?.refinedContentHash,
            refinedAt: existing?.refinedAt,
            activeIndexRevision: existing?.activeIndexRevision
        )
        upsert(skeleton)
        saveFiles()

        let enqueued = await processingEngine.enqueueParse(
            ParseJob(
                fileID: skeleton.id,
                fileName: skeleton.fileName,
                filePath: skeleton.filePath,
                trigger: trigger,
                forceAllowSensitive: forceAllowSensitive
            ),
            now: Date()
        )
        await refreshRuntimeSnapshot()
        if enqueued {
            startProcessingIfNeeded()
        }
        return enqueued
    }

    private func startProcessingIfNeeded() {
        guard environment.startProcessingOnLaunch else { return }
        retryWakeTask?.cancel()
        retryWakeTask = nil
        guard processingTask == nil else { return }
        processingTask = Task { [weak self] in
            guard let self else { return }
            await self.runProcessingLoop()
            await MainActor.run {
                self.processingTask = nil
            }
        }
    }

    private func runProcessingLoop() async {
        while true {
            guard let workItem = await processingEngine.nextWorkItem(now: Date()) else {
                await refreshRuntimeSnapshot()
                await scheduleRetryWakeIfNeeded()
                return
            }

            switch workItem {
            case .parse(let job):
                await handleParse(job)
            case .refine(let job):
                await handleRefine(job)
            case .indexBatch(let jobs):
                await handleIndexBatch(jobs)
            }
        }
    }

    private func scheduleRetryWakeIfNeeded() async {
        let now = Date()
        guard let retryAt = await processingEngine.earliestRetryDate(now: now) else {
            retryWakeTask?.cancel()
            retryWakeTask = nil
            return
        }

        retryWakeTask?.cancel()
        retryWakeTask = Task { [weak self] in
            let delay = max(0, retryAt.timeIntervalSinceNow)
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.retryWakeTask = nil
                self?.startProcessingIfNeeded()
            }
        }
    }

    private func handleParse(_ job: ParseJob) async {
        let start = ContinuousClock().now
        let url = URL(fileURLWithPath: job.filePath)
        let fileKind = DocumentParser.kind(for: url)
        let existing = existingFile(for: url, preferredID: job.fileID)

        do {
            let fingerprint = try FileFingerprintService.fingerprint(for: url)

            if FileProcessingPolicy.shouldSkipProcessing(
                existing: existing,
                fingerprint: fingerprint,
                runtime: processingRuntime,
                forceReprocess: false
            ) {
                await processingEngine.completeParseSkipped(jobID: job.id, now: Date())
                await refreshRuntimeSnapshot()
                PerfTrace.log(
                    name: "parse.job",
                    start: start,
                    success: true,
                    metadata: [
                        "kind": fileKind.rawValue,
                        "result": "skipped",
                        "trigger": job.trigger.rawValue
                    ]
                )
                return
            }

            let baseFile = DropFile(
                id: existing?.id ?? job.fileID,
                fileName: url.lastPathComponent,
                filePath: url.path,
                sourceDirectory: url.deletingLastPathComponent().path,
                fileKind: fileKind,
                importedAt: existing?.importedAt ?? Date(),
                modifiedAt: fingerprint.modifiedAt,
                fileSize: fingerprint.fileSize,
                textLength: 0,
                parsedStatus: .parsing,
                sensitivityStatus: existing?.sensitivityStatus ?? .clear,
                priorityLevel: existing?.priorityLevel ?? .normal,
                summary: existing?.summary,
                events: existing?.events ?? [],
                snippets: existing?.snippets ?? [],
                errorMessage: nil,
                contentHash: fingerprint.contentHash,
                fingerprintComputedAt: fingerprint.computedAt,
                parserVersion: processingRuntime.parserVersion,
                summaryVersion: processingRuntime.summaryVersion,
                refineModel: existing?.refineModel,
                embeddingProvider: existing?.embeddingProvider,
                embeddingModel: existing?.embeddingModel,
                embeddingDimension: existing?.embeddingDimension,
                indexedContentHash: existing?.indexedContentHash,
                indexedAt: existing?.indexedAt,
                refinedContentHash: existing?.refinedContentHash,
                refinedAt: existing?.refinedAt,
                activeIndexRevision: existing?.activeIndexRevision
            )
            upsert(baseFile)
            saveFiles()

            let trustedDirectories = settings.trustedDirectories
            let parsed = try await Task.detached {
                try await DocumentParser.parse(url: url, trustedDirectories: trustedDirectories)
            }.value

            let sensitiveDecision = sensitiveRemoteDecision(
                for: baseFile.filePath,
                detectedStatus: parsed.sensitivity,
                forceAllowSensitive: job.forceAllowSensitive
            )
            if case .block(let message) = sensitiveDecision {
                update(baseFile.id) { file in
                    file.textLength = parsed.text.count
                    file.sensitivityStatus = parsed.sensitivity
                    file.parsedStatus = .sensitiveGate
                    file.priorityLevel = .normal
                    file.summary = nil
                    file.events = []
                    file.snippets = []
                    file.errorMessage = nil
                }
                saveFiles()
                await processingEngine.completeParseBlocked(jobID: job.id, now: Date())
                toastMessage = message
                if let file = files.first(where: { $0.id == baseFile.id }) {
                    notifications.notifySensitiveGate(file)
                }
                await refreshRuntimeSnapshot()
                PerfTrace.log(
                    name: "parse.job",
                    start: start,
                    success: true,
                    metadata: [
                        "kind": fileKind.rawValue,
                        "result": "blocked",
                        "trigger": job.trigger.rawValue
                    ]
                )
                return
            }

            update(baseFile.id) { file in
                file.textLength = parsed.text.count
                file.sensitivityStatus = resolvedSensitivityStatus(
                    detectedStatus: parsed.sensitivity,
                    decision: sensitiveDecision
                )
                file.parsedStatus = .parsing
                file.priorityLevel = parsed.priority
                file.errorMessage = nil
            }
            saveFiles()

            let hasAPIKey = providerConfigurationLoader().hasAPIKey
            let seed = ProcessingIndexSeed(
                fileID: baseFile.id,
                fileName: baseFile.fileName,
                filePath: baseFile.filePath,
                contentHash: fingerprint.contentHash,
                requiresRefine: FileProcessingPolicy.shouldRefineRemotely(priority: parsed.priority, events: parsed.events) && hasAPIKey,
                chunks: parsed.chunks,
                refineText: String(parsed.text.prefix(5000)),
                summary: parsed.summary,
                priorityLevel: parsed.priority,
                events: parsed.events
            )
            await processingEngine.completeParseParsed(jobID: job.id, indexSeed: seed, now: Date())
            await refreshRuntimeSnapshot()
            PerfTrace.log(
                name: "parse.job",
                start: start,
                success: true,
                metadata: [
                    "chunks": "\(parsed.chunks.count)",
                    "kind": fileKind.rawValue,
                    "result": "parsed",
                    "trigger": job.trigger.rawValue
                ]
            )
        } catch {
            update(job.fileID) {
                $0.parsedStatus = .failed
                $0.errorMessage = error.localizedDescription
            }
            saveFiles()
            await processingEngine.failParse(jobID: job.id, error: error.localizedDescription, now: Date())
            await refreshRuntimeSnapshot()
            PerfTrace.log(
                name: "parse.job",
                start: start,
                success: false,
                metadata: [
                    "kind": fileKind.rawValue,
                    "result": "failed",
                    "trigger": job.trigger.rawValue
                ]
            )
        }
    }

    private func handleRefine(_ job: IndexJob) async {
        if !providerConfigurationLoader().hasAPIKey {
            await processingEngine.completeRefine(
                jobID: job.id,
                summary: job.summary,
                priorityLevel: job.priorityLevel,
                events: job.events,
                now: Date()
            )
            await refreshRuntimeSnapshot()
            return
        }

        await processingEngine.recordInternalUsage(.refine, now: Date())
        await refreshRuntimeSnapshot()

        if let refined = await rag.refine(
            fileName: job.fileName,
            text: job.refineText,
            summary: job.summary,
            priority: job.priorityLevel,
            events: job.events
        ) {
            let summary = refined.summary ?? job.summary
            let priority = refined.priorityLevel ?? job.priorityLevel
            let events = refined.keepEvents == false ? [] : job.events
            await processingEngine.completeRefine(
                jobID: job.id,
                summary: summary,
                priorityLevel: priority,
                events: events,
                now: Date()
            )
        } else {
            await processingEngine.failIndex(jobID: job.id, error: "远端精修失败", now: Date())
        }
        await refreshRuntimeSnapshot()
    }

    private func handleIndexBatch(_ jobs: [IndexJob]) async {
        let start = ContinuousClock().now
        let totalChunks = jobs.reduce(0) { $0 + $1.chunks.count }
        let requestFiles = jobs.map { job in
            RAGBatchIndexFile(
                fileID: job.fileID.uuidString,
                fileName: job.fileName,
                filePath: job.filePath,
                contentHash: job.contentHash,
                revisionID: job.revisionID,
                chunks: job.chunks
            )
        }
        let outcome = await rag.indexBatch(files: requestFiles)
        let now = Date()

        if let warning = outcome.warning, warning.localizedCaseInsensitiveContains("缺少 zvec") {
            ragUnavailableReason = warning
        } else if outcome.succeeded {
            ragUnavailableReason = nil
        }

        if outcome.succeeded {
            let revisionMap = Dictionary(uniqueKeysWithValues: outcome.results.map { ($0.fileID, $0.revisionID) })
            for job in jobs {
                guard let fileIndex = files.firstIndex(where: { $0.id == job.fileID }) else { continue }
                files[fileIndex].priorityLevel = job.priorityLevel
                files[fileIndex].summary = job.summary
                files[fileIndex].events = job.events
                files[fileIndex].snippets = Array(job.chunks.prefix(5))
                files[fileIndex].parsedStatus = .parsed
                files[fileIndex].errorMessage = outcome.warning
                files[fileIndex].embeddingProvider = processingRuntime.embeddingProvider
                files[fileIndex].embeddingModel = processingRuntime.embeddingModel
                files[fileIndex].embeddingDimension = processingRuntime.embeddingDimension
                files[fileIndex].indexedContentHash = job.contentHash
                files[fileIndex].indexedAt = now
                files[fileIndex].activeIndexRevision = revisionMap[job.fileID.uuidString] ?? job.revisionID
                if job.didRefine {
                    files[fileIndex].refinedContentHash = job.contentHash
                    files[fileIndex].refinedAt = now
                    files[fileIndex].refineModel = processingRuntime.refineModel
                }
            }
            saveFiles()

            await processingEngine.completeIndexBatch(
                jobs.map {
                    QueueIndexCompletion(
                        jobID: $0.id,
                        revisionID: revisionMap[$0.fileID.uuidString] ?? $0.revisionID
                    )
                },
                totalChunkCount: jobs.reduce(0) { $0 + $1.chunks.count },
                now: now
            )

            if let firstFile = jobs.compactMap({ job in files.first(where: { $0.id == job.fileID }) }).first,
               firstFile.priorityLevel != .low {
                toastMessage = "\(firstFile.fileName)：\(firstFile.summary?.oneLineSummary ?? "已完成索引")"
            }

            for job in jobs {
                guard let file = files.first(where: { $0.id == job.fileID }),
                      let descriptor = parsedFileNotification(for: file, trigger: job.trigger) else {
                    continue
                }
                notifications.notifyParsedFile(descriptor)
            }
        } else {
            for job in jobs {
                await processingEngine.failIndex(jobID: job.id, error: outcome.warning ?? "批量索引失败", now: now)
            }
            for job in jobs {
                update(job.fileID) {
                    $0.parsedStatus = .failed
                    $0.errorMessage = outcome.warning ?? "批量索引失败"
                }
            }
            saveFiles()
        }

        await refreshRuntimeSnapshot()
        PerfTrace.log(
            name: "index.batch",
            start: start,
            success: outcome.succeeded,
            metadata: [
                "chunks": "\(totalChunks)",
                "files": "\(jobs.count)"
            ]
        )
    }

    private func refreshRuntimeSnapshot() async {
        let state = await processingEngine.snapshot()
        quotaSnapshot = QuotaService.snapshot(settings: settings, usage: state.dailyUsage, now: Date())
        parseQueueSummary = Self.makeParseQueueSummary(from: state.parseJobs)
        indexQueueSummary = Self.makeIndexQueueSummary(from: state.indexJobs)
        queueItems = Self.makeQueueItems(from: state)
        hasFailedJobs = Self.hasFailedJobs(in: state)
        synchronizeFileStatuses(with: state)
    }

    private func synchronizeFileStatuses(with state: RuntimeState) {
        var changed = false
        let activeParseByFile = Dictionary(grouping: state.parseJobs.filter { [.queued, .parsing, .blockedSensitive, .failed, .skippedUnchanged].contains($0.status) }, by: \.fileID)
        let activeIndexByFile = Dictionary(grouping: state.indexJobs.filter { [.queued, .refining, .indexing, .failed].contains($0.status) }, by: \.fileID)

        for index in files.indices {
            let fileID = files[index].id
            if let parseJob = activeParseByFile[fileID]?.sorted(by: Self.sortParseJobs).first {
                let newStatus: ParseStatus
                switch parseJob.status {
                case .queued:
                    newStatus = .queued
                case .parsing:
                    newStatus = .parsing
                case .blockedSensitive:
                    newStatus = .sensitiveGate
                case .failed:
                    newStatus = .failed
                case .skippedUnchanged:
                    newStatus = .parsed
                case .parsed:
                    newStatus = files[index].parsedStatus
                }
                if files[index].parsedStatus != newStatus {
                    files[index].parsedStatus = newStatus
                    changed = true
                }
                if files[index].errorMessage != parseJob.lastError {
                    files[index].errorMessage = parseJob.lastError
                    changed = true
                }
                continue
            }

            if let indexJob = activeIndexByFile[fileID]?.sorted(by: Self.sortIndexJobs).first {
                let newStatus: ParseStatus = indexJob.status == .failed ? .failed : .parsing
                if files[index].parsedStatus != newStatus {
                    files[index].parsedStatus = newStatus
                    changed = true
                }
                if files[index].errorMessage != indexJob.lastError {
                    files[index].errorMessage = indexJob.lastError
                    changed = true
                }
            }
        }

        if changed {
            saveFiles()
        }
    }

    private func recentSupportedFiles() -> [URL] {
        let start = ContinuousClock().now
        let cutoff = Calendar.current.date(byAdding: .day, value: -effectiveImportRecentDays, to: Date()) ?? .distantPast
        let manager = FileManager.default
        var urls: [URL] = []
        for directory in settings.watchDirectories {
            guard let enumerator = manager.enumerator(
                at: URL(fileURLWithPath: directory, isDirectory: true),
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator {
                guard DocumentParser.kind(for: url) != .unsupported,
                      let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                      values.isRegularFile == true,
                      (values.contentModificationDate ?? .distantPast) >= cutoff else { continue }
                urls.append(url)
            }
        }
        let sorted = urls.sorted { lhs, rhs in
            let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return l > r
        }
        PerfTrace.log(
            name: "import.recent.discover",
            start: start,
            success: true,
            metadata: [
                "directories": "\(settings.watchDirectories.count)",
                "found": "\(sorted.count)"
            ]
        )
        return sorted
    }

    private func bindFileIDs(_ hits: [SearchHit]) -> [SearchHit] {
        var seen = Set<String>()
        return hits.compactMap { hit in
            var bound = hit
            bound.fileID = files.first(where: { $0.filePath == hit.filePath || $0.fileName == hit.fileName })?.id
            let key = bound.fileID?.uuidString ?? bound.filePath
            guard !seen.contains(key) else { return nil }
            seen.insert(key)
            return bound
        }
    }

    private func fallbackSearch(query: String, warning: String) -> SearchResult {
        let tokens = query.lowercased().split(separator: " ").map(String.init)
        let hits = files.compactMap { file -> SearchHit? in
            let haystack = ([file.fileName, file.summary?.oneLineSummary ?? ""] + file.snippets).joined(separator: "\n")
            let score = tokens.reduce(0.0) { partial, token in
                partial + (haystack.lowercased().contains(token) ? 1.0 : 0.0)
            }
            guard score > 0 || haystack.localizedCaseInsensitiveContains(query) else { return nil }
            return SearchHit(
                id: file.id.uuidString,
                fileID: file.id,
                fileName: file.fileName,
                filePath: file.filePath,
                snippet: file.summary?.oneLineSummary ?? file.snippets.first ?? "",
                score: score
            )
        }
        .sorted { $0.score > $1.score }

        let answer = hits.first.map { "最相关的是《\($0.fileName)》：\($0.snippet)" } ?? "没有在已解析文件中找到相关证据。"
        return SearchResult(
            answer: answer,
            hits: Array(hits.prefix(6)),
            engine: "local-fallback",
            warning: warning,
            queryMode: .localFallback
        )
    }

    private func upsert(_ file: DropFile) {
        if let index = files.firstIndex(where: { $0.id == file.id || $0.filePath == file.filePath }) {
            files[index] = file
        } else {
            files.insert(file, at: 0)
            selectedFileID = selectedFileID ?? file.id
        }
    }

    private func update(_ id: DropFile.ID, mutate: (inout DropFile) -> Void) {
        guard let index = files.firstIndex(where: { $0.id == id }) else { return }
        mutate(&files[index])
    }

    private func saveFiles() {
        do {
            try StoredFileStateStore.save(files, to: environment.databaseURL)
        } catch {
            toastMessage = "保存文件状态失败：\(error.localizedDescription)"
        }
    }

    private func saveSettings() {
        do {
            let normalized = Self.normalizedSettings(settings).settings
            if normalized != settings {
                settings = normalized
            }
            let data = try JSONEncoder.dropKnow.encode(settings)
            try data.write(to: environment.settingsURL, options: .atomic)
        } catch {
            toastMessage = "保存设置失败：\(error.localizedDescription)"
        }
    }

    private func needsIndexBackfill(_ file: DropFile) -> Bool {
        if file.contentHash == nil || file.indexedContentHash == nil || file.indexedAt == nil || file.activeIndexRevision == nil {
            return true
        }
        if file.parserVersion != processingRuntime.parserVersion || file.summaryVersion != processingRuntime.summaryVersion {
            return true
        }
        if file.embeddingProvider != processingRuntime.embeddingProvider ||
            file.embeddingModel != processingRuntime.embeddingModel ||
            file.embeddingDimension != processingRuntime.embeddingDimension {
            return true
        }
        if FileProcessingPolicy.shouldRefineRemotely(priority: file.priorityLevel, events: file.events) {
            return file.refinedContentHash == nil || file.refinedAt == nil || file.refineModel != processingRuntime.refineModel
        }
        return false
    }

    private func existingFile(for url: URL, preferredID: DropFile.ID?) -> DropFile? {
        if let preferredID, let file = files.first(where: { $0.id == preferredID }) {
            return file
        }
        return files.first { $0.filePath == url.path }
    }

    private static func loadStoredFiles(from url: URL) -> StoredFilesLoadResult {
        StoredFileStateStore.load(from: url)
    }

    private static func loadRuntimeState(from url: URL) -> RuntimeStateLoadResult {
        RuntimeStateStore.load(from: url)
    }

    private static func makeHistoricalImportPrompt(
        settings: DropSettings,
        loadStatus: StoredFilesLoadStatus,
        sessionStartedAt: Date
    ) -> HistoricalImportPromptState? {
        HistoricalImportPlanner.promptState(
            for: loadStatus,
            directories: settings.watchDirectories,
            recentDays: min(settings.importRecentDays, settings.subscriptionPlan.capabilities.allowedInitialImportWindowDays),
            referenceDate: sessionStartedAt,
            now: sessionStartedAt
        )
    }

    private static func makeParseQueueSummary(from jobs: [ParseJob]) -> ProcessingQueueSummary {
        ProcessingQueueSummary(
            queued: jobs.filter { $0.status == .queued }.count,
            running: jobs.filter { $0.status == .parsing }.count,
            failed: jobs.filter { $0.status == .failed }.count
        )
    }

    private static func makeIndexQueueSummary(from jobs: [IndexJob]) -> ProcessingQueueSummary {
        ProcessingQueueSummary(
            queued: jobs.filter { $0.status == .queued }.count,
            running: jobs.filter { $0.status == .refining || $0.status == .indexing }.count,
            failed: jobs.filter { $0.status == .failed }.count
        )
    }

    private static func hasFailedJobs(in state: RuntimeState) -> Bool {
        state.parseJobs.contains { $0.status == .failed } || state.indexJobs.contains { $0.status == .failed }
    }

    private static func makeQueueItems(from state: RuntimeState) -> [QueueDisplayItem] {
        let parseItems = state.parseJobs.map { job in
            QueueDisplayItem(
                jobID: job.id,
                fileID: job.fileID,
                fileName: job.fileName,
                filePath: job.filePath,
                kind: .parse,
                trigger: job.trigger,
                status: queueStatus(for: job.status),
                statusText: queueStatus(for: job.status).label,
                attemptCount: job.attemptCount,
                maxAttempts: job.maxAttempts,
                lastError: job.lastError,
                lastAttemptAt: job.lastAttemptAt,
                nextRetryAt: job.nextRetryAt
            )
        }
        let indexItems = state.indexJobs.map { job in
            QueueDisplayItem(
                jobID: job.id,
                fileID: job.fileID,
                fileName: job.fileName,
                filePath: job.filePath,
                kind: .index,
                trigger: job.trigger,
                status: queueStatus(for: job.status),
                statusText: queueStatus(for: job.status).label,
                attemptCount: job.attemptCount,
                maxAttempts: job.maxAttempts,
                lastError: job.lastError,
                lastAttemptAt: job.lastAttemptAt,
                nextRetryAt: job.nextRetryAt
            )
        }
        return (parseItems + indexItems).sorted { lhs, rhs in
            let leftDate = lhs.lastAttemptAt ?? .distantPast
            let rightDate = rhs.lastAttemptAt ?? .distantPast
            if leftDate != rightDate {
                return leftDate > rightDate
            }
            return lhs.fileName < rhs.fileName
        }
    }

    private static func queueStatus(for status: ParseJobStatus) -> QueueDisplayStatus {
        switch status {
        case .queued: .queued
        case .parsing: .running
        case .blockedSensitive: .blocked
        case .parsed: .completed
        case .skippedUnchanged: .skipped
        case .failed: .failed
        }
    }

    private static func queueStatus(for status: IndexJobStatus) -> QueueDisplayStatus {
        switch status {
        case .queued: .queued
        case .refining, .indexing: .running
        case .indexed: .completed
        case .failed: .failed
        }
    }

    private static func sortParseJobs(_ lhs: ParseJob, _ rhs: ParseJob) -> Bool {
        let left = lhs.lastAttemptAt ?? lhs.createdAt
        let right = rhs.lastAttemptAt ?? rhs.createdAt
        return left > right
    }

    private static func sortIndexJobs(_ lhs: IndexJob, _ rhs: IndexJob) -> Bool {
        let left = lhs.lastAttemptAt ?? lhs.createdAt
        let right = rhs.lastAttemptAt ?? rhs.createdAt
        return left > right
    }

    private static func restoreLoadedFiles(_ loadedFiles: [DropFile]) -> [DropFile] {
        var files = loadedFiles
        let staleCutoff = Date().addingTimeInterval(-600)
        for index in files.indices {
            if files[index].parsedStatus == .ignored {
                continue
            }

            if [.queued, .parsing].contains(files[index].parsedStatus) && files[index].importedAt < staleCutoff {
                files[index].parsedStatus = .failed
                files[index].errorMessage = "上次解析中断，可手动重新解析"
            }

            let persistedText = persistedText(for: files[index])

            if ![SensitivityStatus.trusted, .approvedOnce].contains(files[index].sensitivityStatus),
               SensitiveFileDetector.detect(fileName: files[index].fileName, text: persistedText) == .suspected {
                files[index].parsedStatus = .sensitiveGate
                files[index].sensitivityStatus = .suspected
                files[index].priorityLevel = .normal
                files[index].summary = nil
                files[index].events = []
                files[index].snippets = []
                files[index].errorMessage = nil
                continue
            }

            if PriorityClassifier.isLowValue(text: persistedText, fileName: files[index].fileName) {
                files[index].priorityLevel = .low
                files[index].events = []
                let lower = persistedText.lowercased()
                let label: String
                if lower.contains("import ") || lower.contains("function ") || lower.contains("readme") || lower.contains("package.json") {
                    label = "代码/配置"
                } else if lower.contains("板书") || lower.contains("讲义") || lower.contains("lecture") || lower.contains("教程") {
                    label = "课程资料"
                } else {
                    label = "阅读材料"
                }
                files[index].summary = FileSummary(
                    fileTypeLabel: label,
                    actionHint: "可忽略",
                    keyTime: nil,
                    keyLocation: nil,
                    keyPoints: ["未识别到明确通知或待办", "不纳入重要提醒"],
                    oneLineSummary: "\(label)，暂无明确待办事项。"
                )
            } else if files[index].parsedStatus == .parsed, files[index].summary != nil {
                files[index].summary = SummaryBuilder.build(
                    fileName: files[index].fileName,
                    text: persistedText,
                    chunks: [persistedText],
                    events: files[index].events,
                    priority: files[index].priorityLevel
                )
            }
        }
        return files
    }

    private static func isNonActionable(_ file: DropFile) -> Bool {
        PriorityClassifier.isLowValue(text: persistedText(for: file), fileName: file.fileName)
    }

    private static func hasActionableEvent(_ file: DropFile) -> Bool {
        let actionable: Set<EventType> = [.exam, .assignmentDeadline, .registrationDeadline, .paymentDeadline, .interview, .meeting]
        return file.events.contains {
            (actionable.contains($0.eventType) && $0.confidence >= 0.72) ||
                ($0.eventType == .campusActivity && $0.startTime != nil && $0.evidence.range(of: #"大赛|竞赛|比赛|决赛|赛区"#, options: .regularExpression) != nil)
        }
    }

    private static func hasImportantSignal(_ file: DropFile) -> Bool {
        guard file.priorityLevel == .high else { return false }
        let text = persistedText(for: file).lowercased()
        return !matchedImportantKeywords(in: text).isEmpty
    }

    private static func matchedImportantKeywords(in text: String) -> [String] {
        let actionSignals = [
            "考试", "补考", "截止", "ddl", "deadline", "报名", "缴费", "面试", "宣讲",
            "会议", "大赛通知", "通知", "课堂作业", "作业", "答辩", "提交", "作品提交", "日程"
        ]
        return actionSignals.filter { text.contains($0.lowercased()) }
    }

    private static func sortEventsForExplanation(_ lhs: EventCandidate, _ rhs: EventCandidate) -> Bool {
        if lhs.confidence != rhs.confidence {
            return lhs.confidence > rhs.confidence
        }
        switch (lhs.startTime, rhs.startTime) {
        case let (left?, right?):
            return left < right
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            return lhs.title < rhs.title
        }
    }

    private static func persistedText(for file: DropFile) -> String {
        [
            file.fileName,
            file.summary?.fileTypeLabel ?? "",
            file.summary?.oneLineSummary ?? "",
            file.summary?.keyPoints.joined(separator: "\n") ?? "",
            file.snippets.joined(separator: "\n")
        ].joined(separator: "\n")
    }

    private static func loadSettings(from url: URL) -> DropSettings {
        guard let data = try? Data(contentsOf: url),
              let settings = try? JSONDecoder.dropKnow.decode(DropSettings.self, from: data) else {
            return .defaults()
        }
        return settings
    }

    private func resolvedSensitivityStatus(
        detectedStatus: SensitivityStatus,
        decision: SensitiveRemoteDecision
    ) -> SensitivityStatus {
        switch decision {
        case .allow(.trustedDirectory):
            return .trusted
        case .allow(.oneTimeApproval):
            return .approvedOnce
        case .allow(.clear), .block:
            return detectedStatus
        }
    }

    private func activateAppIfPossible() {
        guard !ProcessInfo.processInfo.arguments.contains(where: { $0.localizedCaseInsensitiveContains("xctest") }) else { return }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private static func normalizedSettings(_ settings: DropSettings) -> SettingsNormalizationResult {
        var normalized = settings
        let capabilities = normalized.subscriptionPlan.capabilities
        let didTrimWatchDirectories = normalized.watchDirectories.count > capabilities.maxWatchDirectories
        if didTrimWatchDirectories {
            normalized.watchDirectories = Array(normalized.watchDirectories.prefix(capabilities.maxWatchDirectories))
            let allowedDirectories = Set(normalized.watchDirectories)
            normalized.trustedDirectories.removeAll { !allowedDirectories.contains($0) }
        }

        let didClampImportWindow = normalized.importRecentDays > capabilities.allowedInitialImportWindowDays
        if didClampImportWindow {
            normalized.importRecentDays = capabilities.allowedInitialImportWindowDays
        }

        return SettingsNormalizationResult(
            settings: normalized,
            didTrimWatchDirectories: didTrimWatchDirectories,
            didClampImportWindow: didClampImportWindow
        )
    }
}

private struct SettingsNormalizationResult {
    var settings: DropSettings
    var didTrimWatchDirectories: Bool
    var didClampImportWindow: Bool
}

private extension JSONEncoder {
    static var dropKnow: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var dropKnow: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

enum AlertKind: Hashable {
    case generic
    case calendar
    case provider
}
