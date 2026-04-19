import Foundation

public enum WatchSourceType: String, Codable, Equatable, Sendable {
    case realtime
    case initial_scan
    case manual
}

public struct FileWatchEvent: Sendable, Equatable {
    public let file_url: URL
    public let source_type: WatchSourceType
    public let watch_directory_id: String?
    public let observed_at: String

    public init(
        file_url: URL,
        source_type: WatchSourceType,
        watch_directory_id: String?,
        observed_at: String
    ) {
        self.file_url = file_url
        self.source_type = source_type
        self.watch_directory_id = watch_directory_id
        self.observed_at = observed_at
    }
}

public enum WatchSkipReason: String, Codable, Equatable, Sendable {
    case temporary_file
    case duplicate
    case file_missing
    case file_changing
    case unsupported_entry
}

public enum WatcherEvent: Sendable, Equatable {
    case file_ready(FileWatchEvent)
    case file_skipped(
        file_url: URL,
        source_type: WatchSourceType,
        watch_directory_id: String?,
        reason: WatchSkipReason,
        error_code: ErrorCode?
    )
    case watch_failed(watch_directory_id: String?, error_code: ErrorCode, message: String)
    case initial_scan_started(watch_directory_id: String?)
    case initial_scan_completed(watch_directory_id: String?, imported_count: Int)
}

public protocol FileWatching: Sendable {
    func makeEventStream() async -> AsyncStream<WatcherEvent>
}

public actor MockFileWatcher: FileWatching {
    private var continuation: AsyncStream<WatcherEvent>.Continuation?

    public init() {}

    public func makeEventStream() async -> AsyncStream<WatcherEvent> {
        AsyncStream { continuation in
            self.continuation = continuation
        }
    }

    public func emitEvent(_ event: WatcherEvent) {
        continuation?.yield(event)
    }

    public func emitFile(_ event: FileWatchEvent) {
        continuation?.yield(.file_ready(event))
    }

    public func finish() {
        continuation?.finish()
    }
}
