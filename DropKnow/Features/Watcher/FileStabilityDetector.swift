import Foundation

public protocol FileStabilityDetecting: Sendable {
    func waitUntilStable(file_url: URL) async throws -> StableFileMetadata
}

public struct FileStabilityDetector: FileStabilityDetecting {
    private let checks: Int
    private let interval_ms: UInt64

    public init(checks: Int = 2, interval_ms: UInt64 = 300) {
        self.checks = max(checks, 1)
        self.interval_ms = max(interval_ms, 50)
    }

    public func waitUntilStable(file_url: URL) async throws -> StableFileMetadata {
        var previous: (size: Int64, modified: String?)?
        var stableHits = 0

        for _ in 0..<(checks + 1) {
            let metadata = try readMetadata(file_url)
            let current = (size: metadata.file_size, modified: metadata.modified_at_fs)
            if let previous, previous == current {
                stableHits += 1
                if stableHits >= checks {
                    return metadata
                }
            } else {
                stableHits = 0
            }
            previous = current
            try await Task.sleep(nanoseconds: interval_ms * 1_000_000)
        }

        throw IngestionPipelineError.file_not_stable
    }

    private func readMetadata(_ url: URL) throws -> StableFileMetadata {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw IngestionPipelineError.file_missing
        }

        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .creationDateKey])
        let fileSize = Int64(values.fileSize ?? 0)

        return StableFileMetadata(
            file_size: fileSize,
            created_at_fs: values.creationDate.map { PipelineClock.format($0) },
            modified_at_fs: values.contentModificationDate.map { PipelineClock.format($0) }
        )
    }
}
