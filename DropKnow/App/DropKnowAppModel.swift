import AppKit
import Foundation
import Observation

@MainActor
@Observable
public final class DropKnowAppModel {
    public struct QuotaDisplaySnapshot: Equatable, Sendable {
        public let parseUsed: Int
        public let parseLimit: Int
        public let qaUsed: Int
        public let qaLimit: Int
        public let searchUsed: Int
        public let searchLimit: Int

        public init(parseUsed: Int, parseLimit: Int, qaUsed: Int, qaLimit: Int, searchUsed: Int, searchLimit: Int) {
            self.parseUsed = parseUsed
            self.parseLimit = parseLimit
            self.qaUsed = qaUsed
            self.qaLimit = qaLimit
            self.searchUsed = searchUsed
            self.searchLimit = searchLimit
        }

        public static let empty = QuotaDisplaySnapshot(
            parseUsed: 0,
            parseLimit: 5,
            qaUsed: 0,
            qaLimit: 5,
            searchUsed: 0,
            searchLimit: 10
        )
    }

    public struct Banner: Equatable, Sendable {
        public enum Style: String, Sendable {
            case info
            case success
            case warning
            case error
        }

        public let title: String
        public let message: String
        public let style: Style

        public init(title: String, message: String, style: Style = .info) {
            self.title = title
            self.message = message
            self.style = style
        }
    }

    public private(set) var watchRegistrations: [WatchDirectoryRegistration] = []
    public private(set) var banner: Banner?
    public private(set) var watcherStatusText: String = "未启动"
    public private(set) var contentRevision: Int = 0
    public private(set) var settingsMessage: String?
    public private(set) var quotaSnapshot: QuotaDisplaySnapshot = .empty

    public let container: DropKnowV1Container

    private let defaults = UserDefaults.standard
    private let authorizer = DefaultDirectoryAuthorizer()
    private var watchTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var isStarted = false
    private var currentOrchestrator: WatchOrchestrator?

    private let watchRegistrationsKey = "dropknow.watch.registrations.v1"

    public init(container: DropKnowV1Container) {
        self.container = container
    }

    public func start() async {
        guard !isStarted else { return }
        isStarted = true
        loadWatchRegistrations()
        await refreshQuotaSnapshot()
        await startWatcher()
    }

    public func addCustomDirectory() async {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "选择"
        panel.message = "选择一个要监听的自定义目录"

        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            return
        }

        do {
            let bookmarkData = try selectedURL.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )

            let custom = WatchDirectoryRegistration(
                id: "watch_custom_1",
                display_name: selectedURL.lastPathComponent.isEmpty ? "自定义目录" : selectedURL.lastPathComponent,
                path_hint: selectedURL.path,
                bookmark_data: bookmarkData,
                is_default_downloads: false,
                is_active: true
            )

            watchRegistrations.removeAll { !$0.is_default_downloads }
            watchRegistrations.append(custom)
            watchRegistrations = authorizer.normalizeForV1(watchRegistrations)
            persistWatchRegistrations()
            settingsMessage = "已添加自定义目录，监听将立即更新。"
            await restartWatcher()
        } catch {
            settingsMessage = "添加自定义目录失败：\(error.localizedDescription)"
        }
    }

    public func setDirectoryActive(id: String, isActive: Bool) async {
        guard let index = watchRegistrations.firstIndex(where: { $0.id == id }) else { return }
        watchRegistrations[index] = WatchDirectoryRegistration(
            id: watchRegistrations[index].id,
            display_name: watchRegistrations[index].display_name,
            path_hint: watchRegistrations[index].path_hint,
            bookmark_data: watchRegistrations[index].bookmark_data,
            is_default_downloads: watchRegistrations[index].is_default_downloads,
            is_active: isActive
        )

        watchRegistrations = authorizer.normalizeForV1(watchRegistrations)
        persistWatchRegistrations()
        settingsMessage = "目录状态已更新。"
        await restartWatcher()
    }

    public func removeCustomDirectory() async {
        watchRegistrations.removeAll { !$0.is_default_downloads }
        watchRegistrations = authorizer.normalizeForV1(watchRegistrations)
        persistWatchRegistrations()
        settingsMessage = "已移除自定义目录。"
        await restartWatcher()
    }

    public func closeBanner() {
        banner = nil
    }

    private func loadWatchRegistrations() {
        if let data = defaults.data(forKey: watchRegistrationsKey),
           let decoded = try? JSONDecoder().decode([WatchDirectoryRegistration].self, from: data) {
            watchRegistrations = authorizer.normalizeForV1(decoded)
        } else {
            watchRegistrations = [authorizer.defaultDownloadsRegistration()]
            persistWatchRegistrations()
        }
    }

    private func persistWatchRegistrations() {
        do {
            let data = try JSONEncoder().encode(watchRegistrations)
            defaults.set(data, forKey: watchRegistrationsKey)
        } catch {
            settingsMessage = "保存目录配置失败：\(error.localizedDescription)"
        }
    }

    private func startWatcher() async {
        await currentOrchestrator?.stop()
        watchTask?.cancel()

        let registrations = authorizer.normalizeForV1(watchRegistrations)
        watchRegistrations = registrations
        persistWatchRegistrations()

        watcherStatusText = registrations.isEmpty ? "未配置监听目录" : "正在监听 \(registrations.map { $0.display_name }.joined(separator: " / "))"

        let watcher = DirectoryWatcherService(registrations: registrations)
        let orchestrator = WatchOrchestrator(watcher: watcher, coordinator: container.bundle.coordinator)
        currentOrchestrator = orchestrator

        watchTask = Task { [weak self] in
            guard let self else { return }
            let model = self
            await orchestrator.run(
                onEvent: { event in
                    Task { @MainActor in
                        model.handleWatcherEvent(event)
                    }
                },
                onIngestionResult: { fileEvent, result in
                    Task { @MainActor in
                        model.handleIngestionResult(fileEvent: fileEvent, result: result)
                    }
                }
            )
        }
    }

    private func restartWatcher() async {
        await startWatcher()
    }

    private func handleWatcherEvent(_ event: WatcherEvent) {
        switch event {
        case .initial_scan_started(let directoryID):
            let name = watchRegistrations.first(where: { $0.id == directoryID })?.display_name ?? "监听目录"
            showBanner(title: "开始首次扫描", message: "正在扫描 \(name) 最近 7 天的文件", style: .info)
        case .initial_scan_completed(let directoryID, let importedCount):
            let name = watchRegistrations.first(where: { $0.id == directoryID })?.display_name ?? "监听目录"
            showBanner(title: "首次扫描完成", message: "\(name) 已纳入 \(importedCount) 个文件", style: .success)
            scheduleContentRefresh()
        case .watch_failed(_, let errorCode, let message):
            showBanner(title: "监听失败", message: "\(errorCode.rawValue)：\(message)", style: .error)
        case .file_ready, .file_skipped:
            break
        }
    }

    private func handleIngestionResult(fileEvent: FileWatchEvent, result: IngestionResult) {
        scheduleContentRefresh()

        guard fileEvent.source_type != .initial_scan else {
            return
        }

        switch result {
        case .ready:
            showBanner(title: "已解析", message: fileEvent.file_url.lastPathComponent, style: .success)
        case .duplicate:
            showBanner(title: "已跳过重复文件", message: fileEvent.file_url.lastPathComponent, style: .info)
        case .unsupported_file:
            showBanner(title: "不支持的文件", message: fileEvent.file_url.lastPathComponent, style: .warning)
        case .waiting_user_confirmation:
            showBanner(title: "等待确认", message: fileEvent.file_url.lastPathComponent, style: .warning)
        case .quota_blocked:
            showBanner(title: "额度不足", message: fileEvent.file_url.lastPathComponent, style: .warning)
        case .provider_failed(_, let errorCode):
            showBanner(title: "解析失败", message: "\(fileEvent.file_url.lastPathComponent) · \(errorCode.rawValue)", style: .error)
        case .failed(_, let errorCode):
            showBanner(title: "解析失败", message: "\(fileEvent.file_url.lastPathComponent) · \(errorCode.rawValue)", style: .error)
        }
    }

    private func scheduleContentRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            await MainActor.run {
                self?.contentRevision += 1
            }
            await self?.refreshQuotaSnapshot()
        }
    }

    private func refreshQuotaSnapshot() async {
        let snapshot = await container.subscriptionService.fetchQuotaSnapshot(reference_date: Self.referenceDateString())
        quotaSnapshot = QuotaDisplaySnapshot(
            parseUsed: snapshot.parse_used,
            parseLimit: snapshot.parse_limit,
            qaUsed: snapshot.qa_used,
            qaLimit: snapshot.qa_limit,
            searchUsed: snapshot.advanced_search_used,
            searchLimit: snapshot.advanced_search_limit
        )
    }

    private static func referenceDateString() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private func showBanner(title: String, message: String, style: Banner.Style) {
        banner = Banner(title: title, message: message, style: style)
    }
}
