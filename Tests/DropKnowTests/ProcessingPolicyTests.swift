import XCTest
@testable import DropKnow

final class ProcessingPolicyTests: XCTestCase {
    func testSkipsUnchangedParsedFileWhenLedgerMatches() {
        let now = Date()
        let runtime = ProcessingRuntime(
            parserVersion: "parser-v1",
            summaryVersion: "summary-v1",
            refineModel: "qwen-test",
            embeddingProvider: "dashscope",
            embeddingModel: "embedding-test",
            embeddingDimension: 768
        )
        let existing = makeFile(
            parserVersion: runtime.parserVersion,
            summaryVersion: runtime.summaryVersion,
            refinedContentHash: "same-hash",
            refinedAt: now,
            embeddingProvider: runtime.embeddingProvider,
            embeddingModel: runtime.embeddingModel,
            embeddingDimension: runtime.embeddingDimension,
            indexedContentHash: "same-hash",
            indexedAt: now,
            contentHash: "same-hash"
        )
        let fingerprint = FileFingerprint(
            contentHash: "same-hash",
            modifiedAt: now,
            fileSize: 128,
            computedAt: now
        )

        XCTAssertTrue(
            FileProcessingPolicy.shouldSkipProcessing(
                existing: existing,
                fingerprint: fingerprint,
                runtime: runtime,
                forceReprocess: false
            )
        )
    }

    func testDoesNotSkipWhenEmbeddingConfigChanges() {
        let now = Date()
        let existing = makeFile(
            parserVersion: "parser-v1",
            summaryVersion: "summary-v1",
            refinedContentHash: "same-hash",
            refinedAt: now,
            embeddingProvider: "dashscope",
            embeddingModel: "embedding-old",
            embeddingDimension: 768,
            indexedContentHash: "same-hash",
            indexedAt: now,
            contentHash: "same-hash"
        )
        let fingerprint = FileFingerprint(
            contentHash: "same-hash",
            modifiedAt: now,
            fileSize: 128,
            computedAt: now
        )
        let runtime = ProcessingRuntime(
            parserVersion: "parser-v1",
            summaryVersion: "summary-v1",
            refineModel: "qwen-test",
            embeddingProvider: "dashscope",
            embeddingModel: "embedding-new",
            embeddingDimension: 768
        )

        XCTAssertFalse(
            FileProcessingPolicy.shouldSkipProcessing(
                existing: existing,
                fingerprint: fingerprint,
                runtime: runtime,
                forceReprocess: false
            )
        )
    }

    func testForceReprocessOverridesSkip() {
        let now = Date()
        let runtime = ProcessingRuntime(
            parserVersion: "parser-v1",
            summaryVersion: "summary-v1",
            refineModel: "qwen-test",
            embeddingProvider: "dashscope",
            embeddingModel: "embedding-test",
            embeddingDimension: 768
        )
        let existing = makeFile(
            parserVersion: runtime.parserVersion,
            summaryVersion: runtime.summaryVersion,
            refinedContentHash: "same-hash",
            refinedAt: now,
            embeddingProvider: runtime.embeddingProvider,
            embeddingModel: runtime.embeddingModel,
            embeddingDimension: runtime.embeddingDimension,
            indexedContentHash: "same-hash",
            indexedAt: now,
            contentHash: "same-hash"
        )
        let fingerprint = FileFingerprint(
            contentHash: "same-hash",
            modifiedAt: now,
            fileSize: 128,
            computedAt: now
        )

        XCTAssertFalse(
            FileProcessingPolicy.shouldSkipProcessing(
                existing: existing,
                fingerprint: fingerprint,
                runtime: runtime,
                forceReprocess: true
            )
        )
    }

    func testOnlyImportantFilesUseRemoteRefine() {
        XCTAssertFalse(FileProcessingPolicy.shouldRefineRemotely(priority: .low, events: []))
        XCTAssertTrue(FileProcessingPolicy.shouldRefineRemotely(priority: .high, events: []))
        XCTAssertTrue(
            FileProcessingPolicy.shouldRefineRemotely(
                priority: .normal,
                events: [
                    EventCandidate(
                        eventType: .exam,
                        title: "高数考试",
                        startTime: Date(),
                        endTime: nil,
                        location: nil,
                        note: "",
                        evidence: "考试时间为 5 月 1 日",
                        confidence: 0.9,
                        calendarStatus: .candidate
                    )
                ]
            )
        )
    }

    func testMissingOrCorruptedStateRestrictsAutoScanToSessionStart() {
        let start = Date(timeIntervalSince1970: 1_234)
        XCTAssertEqual(
            AutoImportSafetyPolicy.minimumModifiedAt(for: .missingState, sessionStartedAt: start),
            start
        )
        XCTAssertEqual(
            AutoImportSafetyPolicy.minimumModifiedAt(for: .corruptedState, sessionStartedAt: start),
            start
        )
        XCTAssertNil(AutoImportSafetyPolicy.minimumModifiedAt(for: .loadedState, sessionStartedAt: start))
    }

    func testAutoScanBatchSizeRespectsSafetyCap() {
        XCTAssertEqual(AutoImportSafetyPolicy.autoImportLimit(dailyParseLimit: 2), 2)
        XCTAssertEqual(AutoImportSafetyPolicy.autoImportLimit(dailyParseLimit: 99), AutoImportSafetyPolicy.maxAutoBatchSize)
    }

    private func makeFile(
        parserVersion: String?,
        summaryVersion: String?,
        refinedContentHash: String?,
        refinedAt: Date?,
        embeddingProvider: String?,
        embeddingModel: String?,
        embeddingDimension: Int?,
        indexedContentHash: String?,
        indexedAt: Date?,
        contentHash: String?
    ) -> DropFile {
        DropFile(
            fileName: "通知.pdf",
            filePath: "/tmp/notice.pdf",
            sourceDirectory: "/tmp",
            fileKind: .pdf,
            importedAt: Date(timeIntervalSince1970: 10),
            modifiedAt: Date(timeIntervalSince1970: 10),
            fileSize: 128,
            textLength: 256,
            parsedStatus: .parsed,
            sensitivityStatus: .clear,
            priorityLevel: .high,
            summary: FileSummary(
                fileTypeLabel: "考试安排",
                actionHint: "现在阅读",
                keyTime: nil,
                keyLocation: nil,
                keyPoints: ["5 月 1 日考试"],
                oneLineSummary: "考试安排"
            ),
            events: [],
            snippets: ["考试时间为 5 月 1 日"],
            errorMessage: nil,
            contentHash: contentHash,
            fingerprintComputedAt: Date(timeIntervalSince1970: 10),
            parserVersion: parserVersion,
            summaryVersion: summaryVersion,
            refineModel: "qwen-test",
            embeddingProvider: embeddingProvider,
            embeddingModel: embeddingModel,
            embeddingDimension: embeddingDimension,
            indexedContentHash: indexedContentHash,
            indexedAt: indexedAt,
            refinedContentHash: refinedContentHash,
            refinedAt: refinedAt
        )
    }
}
