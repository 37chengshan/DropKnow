import CryptoKit
import Foundation

struct FileFingerprint: Equatable {
    var contentHash: String
    var modifiedAt: Date
    var fileSize: Int64
    var computedAt: Date
}

struct ProcessingRuntime: Equatable {
    var parserVersion: String
    var summaryVersion: String
    var refineModel: String
    var embeddingProvider: String
    var embeddingModel: String
    var embeddingDimension: Int

    static var current: ProcessingRuntime {
        let env = ProcessInfo.processInfo.environment
        return ProcessingRuntime(
            parserVersion: "parser-v1-2026-04-27",
            summaryVersion: "summary-v1-2026-04-27",
            refineModel: env["DROPKNOW_CHAT_MODEL"] ?? "qwen3.5-flash",
            embeddingProvider: "dashscope",
            embeddingModel: env["DROPKNOW_EMBEDDING_MODEL"] ?? "tongyi-embedding-vision-flash-2026-03-06",
            embeddingDimension: Int(env["DROPKNOW_EMBEDDING_DIMENSION"] ?? "") ?? 768
        )
    }
}

enum FileFingerprintService {
    static func fingerprint(for url: URL) throws -> FileFingerprint {
        let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        let digest = SHA256.hash(data: data)
        let hash = digest.map { String(format: "%02x", $0) }.joined()
        return FileFingerprint(
            contentHash: hash,
            modifiedAt: values.contentModificationDate ?? Date(),
            fileSize: Int64(values.fileSize ?? data.count),
            computedAt: Date()
        )
    }
}

enum FileProcessingPolicy {
    static func shouldSkipProcessing(
        existing: DropFile?,
        fingerprint: FileFingerprint,
        runtime: ProcessingRuntime,
        forceReprocess: Bool
    ) -> Bool {
        guard !forceReprocess,
              let existing,
              existing.parsedStatus == .parsed,
              existing.contentHash == fingerprint.contentHash,
              existing.indexedContentHash == fingerprint.contentHash,
              existing.indexedAt != nil,
              existing.parserVersion == runtime.parserVersion,
              existing.summaryVersion == runtime.summaryVersion,
              existing.embeddingProvider == runtime.embeddingProvider,
              existing.embeddingModel == runtime.embeddingModel,
              existing.embeddingDimension == runtime.embeddingDimension else {
            return false
        }

        if shouldRefineRemotely(priority: existing.priorityLevel, events: existing.events) {
            return existing.refinedContentHash == fingerprint.contentHash &&
                existing.refinedAt != nil &&
                existing.refineModel == runtime.refineModel
        }

        return true
    }

    static func shouldRefineRemotely(priority: PriorityLevel, events: [EventCandidate]) -> Bool {
        priority == .high || events.contains { $0.confidence >= 0.72 }
    }
}

enum StoredFilesLoadStatus: Equatable {
    case loadedState
    case missingState
    case corruptedState
}

struct StoredFilesLoadResult {
    var files: [DropFile]
    var status: StoredFilesLoadStatus
    var errorMessage: String?
    var backupURL: URL?
}

enum StoredFileStateStore {
    static func load(from url: URL) -> StoredFilesLoadResult {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return StoredFilesLoadResult(files: [], status: .missingState, errorMessage: nil, backupURL: nil)
        }

        do {
            let data = try Data(contentsOf: url)
            let files = try decoder.decode([DropFile].self, from: data)
            return StoredFilesLoadResult(files: files, status: .loadedState, errorMessage: nil, backupURL: nil)
        } catch {
            let backupURL = backupCorruptedState(at: url)
            return StoredFilesLoadResult(
                files: [],
                status: .corruptedState,
                errorMessage: error.localizedDescription,
                backupURL: backupURL
            )
        }
    }

    static func save(_ files: [DropFile], to url: URL) throws {
        let data = try encoder.encode(files)
        try data.write(to: url, options: .atomic)
    }

    private static func backupCorruptedState(at url: URL) -> URL? {
        let backupURL = url.deletingPathExtension().appendingPathExtension("corrupted.json")
        do {
            if FileManager.default.fileExists(atPath: backupURL.path) {
                try FileManager.default.removeItem(at: backupURL)
            }
            try FileManager.default.moveItem(at: url, to: backupURL)
            return backupURL
        } catch {
            return nil
        }
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

enum AutoImportSafetyPolicy {
    static let maxAutoBatchSize = 5

    static func minimumModifiedAt(for loadStatus: StoredFilesLoadStatus, sessionStartedAt: Date) -> Date? {
        switch loadStatus {
        case .loadedState:
            return nil
        case .missingState, .corruptedState:
            return sessionStartedAt
        }
    }

    static func autoImportLimit(dailyParseLimit: Int) -> Int {
        max(0, min(dailyParseLimit, maxAutoBatchSize))
    }
}

struct HistoricalImportDiscovery: Equatable {
    var totalHistoricalCount: Int
    var recentCandidateCount: Int
}

struct HistoricalImportPromptState: Equatable {
    var totalHistoricalCount: Int
    var recentCandidateCount: Int
    var recentDays: Int
    var loadStatus: StoredFilesLoadStatus
}

enum HistoricalImportPlanner {
    static func discover(
        in directories: [String],
        recentDays: Int,
        referenceDate: Date,
        now: Date = Date()
    ) -> HistoricalImportDiscovery {
        let recentCutoff = Calendar.current.date(byAdding: .day, value: -recentDays, to: now) ?? .distantPast
        let manager = FileManager.default
        var totalHistoricalCount = 0
        var recentCandidateCount = 0

        for directory in directories {
            guard let enumerator = manager.enumerator(
                at: URL(fileURLWithPath: directory, isDirectory: true),
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator {
                guard DocumentParser.kind(for: url) != .unsupported,
                      let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                      values.isRegularFile == true else {
                    continue
                }

                let modifiedAt = values.contentModificationDate ?? .distantPast
                guard modifiedAt < referenceDate else { continue }
                totalHistoricalCount += 1
                if modifiedAt >= recentCutoff {
                    recentCandidateCount += 1
                }
            }
        }

        return HistoricalImportDiscovery(
            totalHistoricalCount: totalHistoricalCount,
            recentCandidateCount: recentCandidateCount
        )
    }

    static func promptState(
        for loadStatus: StoredFilesLoadStatus,
        directories: [String],
        recentDays: Int,
        referenceDate: Date,
        now: Date = Date()
    ) -> HistoricalImportPromptState? {
        guard loadStatus != .loadedState else { return nil }
        let discovery = discover(
            in: directories,
            recentDays: recentDays,
            referenceDate: referenceDate,
            now: now
        )
        guard discovery.totalHistoricalCount > 0 else { return nil }
        return HistoricalImportPromptState(
            totalHistoricalCount: discovery.totalHistoricalCount,
            recentCandidateCount: discovery.recentCandidateCount,
            recentDays: recentDays,
            loadStatus: loadStatus
        )
    }
}
