import XCTest
@testable import DropKnow

final class ProcessingEngineTests: XCTestCase {
    func testEnqueueParseDeduplicatesActiveFilePath() async {
        let engine = ProcessingEngine(initialState: .empty, recoveredAt: Date(timeIntervalSince1970: 0))
        let path = "/tmp/notice.pdf"

        let first = await engine.enqueueParse(
            ParseJob(fileID: UUID(), fileName: "通知.pdf", filePath: path, trigger: .auto)
        )
        let second = await engine.enqueueParse(
            ParseJob(fileID: UUID(), fileName: "通知.pdf", filePath: path, trigger: .manualReparse)
        )

        let snapshot = await engine.snapshot()
        XCTAssertTrue(first)
        XCTAssertFalse(second)
        XCTAssertEqual(snapshot.parseJobs.count, 1)
    }

    func testParseSuccessCreatesQueuedIndexJobAndConsumesQuota() async {
        let engine = ProcessingEngine(initialState: .empty, recoveredAt: Date(timeIntervalSince1970: 0))
        let job = ParseJob(
            fileID: UUID(),
            fileName: "通知.pdf",
            filePath: "/tmp/notice.pdf",
            trigger: .initialImport
        )
        await engine.enqueueParse(job)

        let workItem = await engine.nextWorkItem(now: Date(timeIntervalSince1970: 10))
        guard case .parse(let runningJob)? = workItem else {
            return XCTFail("Expected parse work item")
        }

        let indexSeed = ProcessingIndexSeed(
            fileID: runningJob.fileID,
            fileName: runningJob.fileName,
            filePath: runningJob.filePath,
            contentHash: "hash-1",
            requiresRefine: false,
            chunks: ["a", "b"],
            refineText: "body",
            summary: sampleSummary(),
            priorityLevel: .high,
            events: []
        )
        await engine.completeParseParsed(jobID: runningJob.id, indexSeed: indexSeed, now: Date(timeIntervalSince1970: 12))
        let snapshot = await engine.snapshot()

        XCTAssertEqual(snapshot.dailyUsage.parseUsed, 1)
        XCTAssertEqual(snapshot.parseJobs.first?.status, .parsed)
        XCTAssertEqual(snapshot.indexJobs.count, 1)
        XCTAssertEqual(snapshot.indexJobs.first?.status, .queued)
    }

    func testSkippedParseDoesNotConsumeQuotaOrCreateIndexJob() async {
        let engine = ProcessingEngine(initialState: .empty, recoveredAt: Date(timeIntervalSince1970: 0))
        await engine.enqueueParse(
            ParseJob(fileID: UUID(), fileName: "通知.pdf", filePath: "/tmp/notice.pdf", trigger: .initialImport)
        )

        guard case .parse(let runningJob)? = await engine.nextWorkItem(now: Date(timeIntervalSince1970: 10)) else {
            return XCTFail("Expected parse work item")
        }

        await engine.completeParseSkipped(jobID: runningJob.id, now: Date(timeIntervalSince1970: 11))
        let snapshot = await engine.snapshot()

        XCTAssertEqual(snapshot.dailyUsage.parseUsed, 0)
        XCTAssertEqual(snapshot.parseJobs.first?.status, .skippedUnchanged)
        XCTAssertTrue(snapshot.indexJobs.isEmpty)
    }

    func testBlockedSensitiveParseDoesNotConsumeQuotaOrCreateIndexJob() async {
        let engine = ProcessingEngine(initialState: .empty, recoveredAt: Date(timeIntervalSince1970: 0))
        await engine.enqueueParse(
            ParseJob(fileID: UUID(), fileName: "通知.pdf", filePath: "/tmp/notice.pdf", trigger: .initialImport)
        )

        guard case .parse(let runningJob)? = await engine.nextWorkItem(now: Date(timeIntervalSince1970: 10)) else {
            return XCTFail("Expected parse work item")
        }

        await engine.completeParseBlocked(jobID: runningJob.id, now: Date(timeIntervalSince1970: 11))
        let snapshot = await engine.snapshot()

        XCTAssertEqual(snapshot.dailyUsage.parseUsed, 0)
        XCTAssertEqual(snapshot.parseJobs.first?.status, .blockedSensitive)
        XCTAssertTrue(snapshot.indexJobs.isEmpty)
    }

    func testFailureRetriesTwiceThenFails() async {
        let engine = ProcessingEngine(initialState: .empty, recoveredAt: Date(timeIntervalSince1970: 0))
        await engine.enqueueParse(
            ParseJob(fileID: UUID(), fileName: "通知.pdf", filePath: "/tmp/notice.pdf", trigger: .initialImport)
        )

        guard case .parse(let firstAttempt)? = await engine.nextWorkItem(now: Date(timeIntervalSince1970: 10)) else {
            return XCTFail("Expected first parse work item")
        }
        await engine.failParse(jobID: firstAttempt.id, error: "network", now: Date(timeIntervalSince1970: 11))

        guard case .parse(let secondAttempt)? = await engine.nextWorkItem(now: Date(timeIntervalSince1970: 50)) else {
            return XCTFail("Expected second parse work item")
        }
        await engine.failParse(jobID: secondAttempt.id, error: "network", now: Date(timeIntervalSince1970: 51))

        guard case .parse(let thirdAttempt)? = await engine.nextWorkItem(now: Date(timeIntervalSince1970: 400)) else {
            return XCTFail("Expected third parse work item")
        }
        await engine.failParse(jobID: thirdAttempt.id, error: "network", now: Date(timeIntervalSince1970: 401))

        let snapshot = await engine.snapshot()
        XCTAssertEqual(snapshot.parseJobs.first?.status, .failed)
        XCTAssertEqual(snapshot.parseJobs.first?.attemptCount, 3)
    }

    func testRecoveryMovesRunningJobsBackToQueued() async {
        let recoveredAt = Date(timeIntervalSince1970: 500)
        let initialState = RuntimeState(
            parseJobs: [
                ParseJob(
                    id: UUID(),
                    fileID: UUID(),
                    fileName: "通知.pdf",
                    filePath: "/tmp/notice.pdf",
                    trigger: .auto,
                    status: .parsing,
                    attemptCount: 1,
                    maxAttempts: 3,
                    lastError: nil,
                    lastAttemptAt: Date(timeIntervalSince1970: 450),
                    nextRetryAt: nil,
                    forceAllowSensitive: false,
                    createdAt: Date(timeIntervalSince1970: 400)
                )
            ],
            indexJobs: [
                IndexJob(
                    id: UUID(),
                    fileID: UUID(),
                    fileName: "通知.pdf",
                    filePath: "/tmp/notice.pdf",
                    contentHash: "hash-1",
                    trigger: .auto,
                    status: .indexing,
                    attemptCount: 1,
                    maxAttempts: 3,
                    lastError: nil,
                    lastAttemptAt: Date(timeIntervalSince1970: 460),
                    nextRetryAt: nil,
                    requiresRefine: false,
                    chunks: ["a"],
                    refineText: "body",
                    summary: sampleSummary(),
                    priorityLevel: .high,
                    events: [],
                    revisionID: "rev-1",
                    createdAt: Date(timeIntervalSince1970: 420)
                )
            ],
            dailyUsage: .empty(dayKey: "1970-01-01"),
            lastRecoveredAt: nil
        )
        let engine = ProcessingEngine(initialState: initialState, recoveredAt: recoveredAt)
        let snapshot = await engine.snapshot()

        XCTAssertEqual(snapshot.parseJobs.first?.status, .queued)
        XCTAssertEqual(snapshot.indexJobs.first?.status, .queued)
        XCTAssertEqual(snapshot.lastRecoveredAt, recoveredAt)
    }

    func testEarliestRetryDateReturnsDelayedQueuedJob() async {
        let nextRetryAt = Date(timeIntervalSince1970: 120)
        let initialState = RuntimeState(
            parseJobs: [
                ParseJob(
                    id: UUID(),
                    fileID: UUID(),
                    fileName: "通知.pdf",
                    filePath: "/tmp/notice.pdf",
                    trigger: .auto,
                    status: .queued,
                    attemptCount: 1,
                    maxAttempts: 3,
                    lastError: "network",
                    lastAttemptAt: Date(timeIntervalSince1970: 90),
                    nextRetryAt: nextRetryAt,
                    forceAllowSensitive: false,
                    createdAt: Date(timeIntervalSince1970: 80)
                )
            ],
            indexJobs: [],
            dailyUsage: .empty(dayKey: "1970-01-01"),
            lastRecoveredAt: nil
        )
        let engine = ProcessingEngine(initialState: initialState, recoveredAt: Date(timeIntervalSince1970: 0))
        let retryDate = await engine.earliestRetryDate(now: Date(timeIntervalSince1970: 100))

        XCTAssertEqual(retryDate, nextRetryAt)
    }

    private func sampleSummary() -> FileSummary {
        FileSummary(
            fileTypeLabel: "考试安排",
            actionHint: "现在阅读",
            keyTime: nil,
            keyLocation: nil,
            keyPoints: ["5月1日考试"],
            oneLineSummary: "考试安排"
        )
    }
}
