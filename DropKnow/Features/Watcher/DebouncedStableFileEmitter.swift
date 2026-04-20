import Foundation

actor DebouncedStableFileEmitter {
    private let debounce_ms: UInt64
    private let stabilityDetector: any FileStabilityDetecting
    private let fingerprintService: any FileFingerprinting
    private let deduper: WatchEventDeduper
    private let emit: @Sendable (WatcherEvent) async -> Void

    private var pending: [String: Task<Void, Never>] = [:]

    init(
        debounce_ms: UInt64,
        stabilityDetector: any FileStabilityDetecting,
        fingerprintService: any FileFingerprinting = SHA256FileFingerprintService(),
        deduper: WatchEventDeduper,
        emit: @escaping @Sendable (WatcherEvent) async -> Void
    ) {
        self.debounce_ms = max(debounce_ms, 50)
        self.stabilityDetector = stabilityDetector
        self.fingerprintService = fingerprintService
        self.deduper = deduper
        self.emit = emit
    }

    func submit(file_url: URL, source_type: WatchSourceType, watch_directory_id: String?) {
        if TemporaryFileFilter.shouldSkip(file_url) {
            Task.detached(priority: .utility) { [emit] in
                await emit(
                .file_skipped(
                    file_url: file_url,
                    source_type: source_type,
                    watch_directory_id: watch_directory_id,
                    reason: .temporary_file,
                    error_code: .import_temp_file_skipped
                )
                )
            }
            return
        }

        let key = file_url.path
        pending[key]?.cancel()

        pending[key] = Task.detached(priority: .utility) { [debounce_ms, stabilityDetector, fingerprintService, deduper, emit] in
            do {
                try await Task.sleep(nanoseconds: debounce_ms * 1_000_000)
                let stable = try await stabilityDetector.waitUntilStable(file_url: file_url)
                let fingerprint = try await fingerprintService.fingerprint(file_url: file_url, metadata: stable)
                let signature = WatchDedupeSignature(
                    file_hash: fingerprint.file_hash,
                    file_size: stable.file_size,
                    modified_at_fs: stable.modified_at_fs
                )

                let isNew = await deduper.insertIfNew(signature)
                if !isNew {
                    await emit(
                        .file_skipped(
                            file_url: file_url,
                            source_type: source_type,
                            watch_directory_id: watch_directory_id,
                            reason: .duplicate,
                            error_code: .import_duplicate_ignored
                        )
                    )
                    return
                }

                await emit(
                    .file_ready(
                        FileWatchEvent(
                            file_url: file_url,
                            source_type: source_type,
                            watch_directory_id: watch_directory_id,
                            observed_at: PipelineClock.nowString()
                        )
                    )
                )
            } catch let error as IngestionPipelineError {
                switch error {
                case .file_missing:
                    await emit(
                        .file_skipped(
                            file_url: file_url,
                            source_type: source_type,
                            watch_directory_id: watch_directory_id,
                            reason: .file_missing,
                            error_code: .import_file_missing_after_detected
                        )
                    )
                case .file_not_stable:
                    await emit(
                        .file_skipped(
                            file_url: file_url,
                            source_type: source_type,
                            watch_directory_id: watch_directory_id,
                            reason: .file_changing,
                            error_code: .import_file_changed_during_parse
                        )
                    )
                default:
                    await emit(
                        .file_skipped(
                            file_url: file_url,
                            source_type: source_type,
                            watch_directory_id: watch_directory_id,
                            reason: .unsupported_entry,
                            error_code: .import_file_changed_during_parse
                        )
                    )
                }
            } catch {
                await emit(
                    .file_skipped(
                        file_url: file_url,
                        source_type: source_type,
                        watch_directory_id: watch_directory_id,
                        reason: .unsupported_entry,
                        error_code: .import_file_changed_during_parse
                    )
                )
            }
        }
    }

    func cancelAll() {
        for task in pending.values {
            task.cancel()
        }
        pending.removeAll()
    }
}
