import Foundation

public actor DirectoryWatcherService: FileWatching {
    private let registrations: [WatchDirectoryRegistration]
    private let directoryAuthorizer: any DirectoryAuthorizing
    private let scanner: any RecentFileScanning
    private let stabilityDetector: any FileStabilityDetecting
    private let deduper: WatchEventDeduper

    private let poll_interval_ms: UInt64
    private let debounce_ms: UInt64
    private let initial_scan_days: Int

    private var continuation: AsyncStream<WatcherEvent>.Continuation?
    private var watchTask: Task<Void, Never>?

    public init(
        registrations: [WatchDirectoryRegistration],
        directoryAuthorizer: any DirectoryAuthorizing = DefaultDirectoryAuthorizer(),
        scanner: any RecentFileScanning = DefaultRecentFileScanner(),
        stabilityDetector: any FileStabilityDetecting = FileStabilityDetector(),
        deduper: WatchEventDeduper = WatchEventDeduper(),
        poll_interval_ms: UInt64 = 1_000,
        debounce_ms: UInt64 = 350,
        initial_scan_days: Int = 7
    ) {
        self.registrations = registrations
        self.directoryAuthorizer = directoryAuthorizer
        self.scanner = scanner
        self.stabilityDetector = stabilityDetector
        self.deduper = deduper
        self.poll_interval_ms = max(poll_interval_ms, 200)
        self.debounce_ms = max(debounce_ms, 50)
        self.initial_scan_days = max(initial_scan_days, 0)
    }

    deinit {
        watchTask?.cancel()
    }

    public func makeEventStream() async -> AsyncStream<WatcherEvent> {
        AsyncStream { continuation in
            self.continuation = continuation
            self.startIfNeeded()
        }
    }

    public func stop() async {
        watchTask?.cancel()
        watchTask = nil
        continuation?.finish()
        continuation = nil
    }

    private func startIfNeeded() {
        guard watchTask == nil else { return }

        watchTask = Task.detached(priority: .utility) {
            await self.runWatchLoop()
        }
    }

    private func runWatchLoop() async {
        let selected = directoryAuthorizer.normalizeForV1(registrations)
        if selected.isEmpty {
            await emit(.watch_failed(watch_directory_id: nil, error_code: .watch_permission_denied, message: "no active watch directories"))
            return
        }

        var authorized: [AuthorizedWatchDirectory] = []
        for registration in selected {
            do {
                let item = try directoryAuthorizer.authorize(registration)
                authorized.append(item)
            } catch let authError as DirectoryAuthorizationError {
                await emit(
                    .watch_failed(
                        watch_directory_id: registration.id,
                        error_code: authError.errorCode,
                        message: "authorization failed: \(authError)"
                    )
                )
                WatcherLogger.log(
                    .error,
                    "Directory authorization failed",
                    context: ["watch_directory_id": registration.id, "path": registration.path_hint, "error": "\(authError)"]
                )
            } catch {
                await emit(
                    .watch_failed(
                        watch_directory_id: registration.id,
                        error_code: .watch_permission_denied,
                        message: "authorization failed: \(error.localizedDescription)"
                    )
                )
            }
        }

        guard !authorized.isEmpty else {
            return
        }

        let stableEmitter = DebouncedStableFileEmitter(
            debounce_ms: debounce_ms,
            stabilityDetector: stabilityDetector,
            deduper: deduper,
            emit: { [weak self] event in
                guard let self else { return }
                await self.emit(event)
            }
        )

        var snapshots: [String: [String: RecentFileCandidate]] = [:]

        for directory in authorized {
            do {
                let snapshot = try scanner.snapshot(directory: directory)
                snapshots[directory.id] = snapshot

                await emit(.initial_scan_started(watch_directory_id: directory.id))

                let recent = try scanner.enumerateRecentFiles(directory: directory, days: initial_scan_days)
                var importedCount = 0
                for candidate in recent {
                    if TemporaryFileFilter.shouldSkip(candidate.file_url) {
                        continue
                    }
                    importedCount += 1
                    await stableEmitter.submit(
                        file_url: candidate.file_url,
                        source_type: .initial_scan,
                        watch_directory_id: directory.id
                    )
                }

                await emit(.initial_scan_completed(watch_directory_id: directory.id, imported_count: importedCount))
                WatcherLogger.log(
                    .info,
                    "Initial scan completed",
                    context: ["watch_directory_id": directory.id, "imported_count": "\(importedCount)"]
                )
            } catch {
                await emit(
                    .watch_failed(
                        watch_directory_id: directory.id,
                        error_code: .watch_permission_denied,
                        message: "initial scan failed: \(error.localizedDescription)"
                    )
                )
                WatcherLogger.log(
                    .error,
                    "Initial scan failed",
                    context: ["watch_directory_id": directory.id, "error": error.localizedDescription]
                )
            }
        }

        while !Task.isCancelled {
            for directory in authorized {
                do {
                    let previous = snapshots[directory.id, default: [:]]
                    let current = try scanner.snapshot(directory: directory)

                    for (path, candidate) in current {
                        let previousCandidate = previous[path]
                        if previousCandidate == nil || hasChanged(from: previousCandidate, to: candidate) {
                            await stableEmitter.submit(
                                file_url: candidate.file_url,
                                source_type: .realtime,
                                watch_directory_id: directory.id
                            )
                        }
                    }

                    snapshots[directory.id] = current
                } catch {
                    await emit(
                        .watch_failed(
                            watch_directory_id: directory.id,
                            error_code: .watch_permission_denied,
                            message: "realtime polling failed: \(error.localizedDescription)"
                        )
                    )
                }
            }

            do {
                try await Task.sleep(nanoseconds: poll_interval_ms * 1_000_000)
            } catch {
                break
            }
        }

        await stableEmitter.cancelAll()
    }

    private func hasChanged(from old: RecentFileCandidate?, to new: RecentFileCandidate) -> Bool {
        guard let old else { return true }
        return old.file_size != new.file_size || old.modified_at_fs != new.modified_at_fs
    }

    private func emit(_ event: WatcherEvent) async {
        continuation?.yield(event)
        switch event {
        case .file_ready(let fileEvent):
            WatcherLogger.log(
                .info,
                "File ready",
                context: [
                    "source_type": fileEvent.source_type.rawValue,
                    "watch_directory_id": fileEvent.watch_directory_id ?? "nil",
                    "path": fileEvent.file_url.path
                ]
            )
        case .file_skipped(let fileURL, let sourceType, let directoryID, let reason, let errorCode):
            WatcherLogger.log(
                .debug,
                "File skipped",
                context: [
                    "source_type": sourceType.rawValue,
                    "watch_directory_id": directoryID ?? "nil",
                    "path": fileURL.path,
                    "reason": reason.rawValue,
                    "error_code": errorCode?.rawValue ?? "none"
                ]
            )
        case .watch_failed(let directoryID, let errorCode, let message):
            WatcherLogger.log(
                .error,
                "Watch failed",
                context: [
                    "watch_directory_id": directoryID ?? "nil",
                    "error_code": errorCode.rawValue,
                    "message": message
                ]
            )
        case .initial_scan_started(let directoryID):
            WatcherLogger.log(.info, "Initial scan started", context: ["watch_directory_id": directoryID ?? "nil"])
        case .initial_scan_completed(let directoryID, let count):
            WatcherLogger.log(.info, "Initial scan completed", context: ["watch_directory_id": directoryID ?? "nil", "count": "\(count)"])
        }
    }
}
