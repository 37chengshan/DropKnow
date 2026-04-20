import Foundation

public actor WatchOrchestrator {
    private let watcher: any FileWatching
    private let coordinator: IngestionCoordinator
    private let timezoneID: String

    public init(
        watcher: any FileWatching,
        coordinator: IngestionCoordinator,
        timezoneID: String = TimeZone.current.identifier
    ) {
        self.watcher = watcher
        self.coordinator = coordinator
        self.timezoneID = timezoneID
    }

    public func run() async {
        await run(onEvent: nil, onIngestionResult: nil)
    }

    public func run(
        onEvent: (@Sendable (WatcherEvent) async -> Void)?,
        onIngestionResult: (@Sendable (FileWatchEvent, IngestionResult) async -> Void)?
    ) async {
        let stream = await watcher.makeEventStream()
        for await event in stream {
            if let onEvent {
                await onEvent(event)
            }

            switch event {
            case .file_ready(let fileEvent):
                let request = IngestionRequest(
                    file_url: fileEvent.file_url,
                    source_type: fileEvent.source_type.rawValue,
                    watch_directory_id: fileEvent.watch_directory_id,
                    reference_date: Self.referenceDateString(),
                    user_timezone: timezoneID
                )

                Task.detached(priority: .utility) {
                    let result = await self.coordinator.ingest(request)
                    if let onIngestionResult {
                        await onIngestionResult(fileEvent, result)
                    }
                }
            case .file_skipped:
                continue
            case .watch_failed:
                continue
            case .initial_scan_started:
                continue
            case .initial_scan_completed:
                continue
            }
        }
    }

    public func stop() async {
        await watcher.stop()
    }

    public func ingestNow(file_url: URL, source_type: String = "manual", watch_directory_id: String? = nil) async -> IngestionResult {
        let request = IngestionRequest(
            file_url: file_url,
            source_type: source_type,
            watch_directory_id: watch_directory_id,
            reference_date: Self.referenceDateString(),
            user_timezone: timezoneID
        )
        return await coordinator.ingest(request)
    }

    private static func referenceDateString() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
