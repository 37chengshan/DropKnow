import Foundation
#if canImport(XCTest)
import XCTest
#if canImport(DropKnow)
@testable import DropKnow
#endif

final class IngestionPipelineIntegrationTests: XCTestCase {
    func testPipelineSmokeRunWritesDocumentAndJobs() async {
        let environment = try? makeSQLiteEnvironment()
        guard let environment else {
            XCTFail("failed to create sqlite environment")
            return
        }

        let container = DropKnowV1Container(mode: .sqlite(databaseURL: environment.databaseURL, sqlDirectoryURL: environment.sqlDirectoryURL))
        let runner = EndToEndSmokeRunner(container: container)
        let report = await runner.runSingleDocument(
            fileName: "integration_pipeline.txt",
            content: "明天下午四点去体检中心复查。"
        )

        XCTAssertFalse(report.recent_documents.isEmpty)

        guard let document = report.recent_documents.first else {
            XCTFail("expected a document")
            return
        }

        XCTAssertEqual(document.current_stage, .done)
        XCTAssertEqual(document.lifecycle_status, .ready)
        XCTAssertTrue(document.event_status == .has_candidate || document.event_status == .has_calendar_event)

        let stages = Set(report.parse_jobs.map { $0.stage })
        XCTAssertTrue(stages.contains(.import))
        XCTAssertTrue(stages.contains(.parse))
        XCTAssertTrue(stages.contains(.gate))
        XCTAssertTrue(stages.contains(.summary))
        XCTAssertTrue(stages.contains(.event_extract))
        XCTAssertTrue(stages.contains(.index))
        XCTAssertTrue(stages.contains(.notify))
        XCTAssertFalse(report.events.isEmpty)
    }

    func testSQLiteReopenAfterIngestRetainsRecentAndDetailData() async {
        guard let environment = try? makeSQLiteEnvironment() else {
            XCTFail("failed to create sqlite environment")
            return
        }

        let firstContainer = DropKnowV1Container(mode: .sqlite(databaseURL: environment.databaseURL, sqlDirectoryURL: environment.sqlDirectoryURL))
        let firstResult = await firstContainer.runDemoFlow(
            fileName: "reopen_success.txt",
            content: "后天下午五点在杭州进行项目复盘。",
            sourceType: .manual
        )

        guard case .ready(let documentID) = firstResult else {
            XCTFail("expected ready ingestion result")
            return
        }

        let reopenedContainer = DropKnowV1Container(mode: .sqlite(databaseURL: environment.databaseURL, sqlDirectoryURL: environment.sqlDirectoryURL))

        let recentResult = await reopenedContainer.documentRepository.listRecent(limit: 10)
        guard case .success(let docs) = recentResult else {
            XCTFail("expected recent documents query success")
            return
        }
        XCTAssertTrue(docs.contains(where: { $0.id == documentID }))

        let detailDoc = await reopenedContainer.documentRepository.get(id: documentID)
        guard case .success(let doc) = detailDoc else {
            XCTFail("expected detail document query success")
            return
        }
        XCTAssertEqual(doc?.id, documentID)

        let summary = await reopenedContainer.summaryRepository.get(document_id: documentID)
        guard case .success(let summaryDTO) = summary else {
            XCTFail("expected summary query success")
            return
        }
        XCTAssertEqual(summaryDTO?.document_id, documentID)

        let events = await reopenedContainer.eventRepository.get(document_id: documentID)
        guard case .success(let eventList) = events else {
            XCTFail("expected event query success")
            return
        }
        XCTAssertFalse(eventList.isEmpty)

        let jobs = await reopenedContainer.parseJobRepository.listRecent(limit: 20)
        guard case .success(let parseJobs) = jobs else {
            XCTFail("expected parse jobs query success")
            return
        }
        XCTAssertTrue(parseJobs.contains(where: { $0.document_id == documentID && $0.stage == .summary }))
    }

    func testSQLiteReopenKeepsBlockedAndPartialStates() async {
        guard let environment = try? makeSQLiteEnvironment() else {
            XCTFail("failed to create sqlite environment")
            return
        }

        let container = DropKnowV1Container(mode: .sqlite(databaseURL: environment.databaseURL, sqlDirectoryURL: environment.sqlDirectoryURL))

        let blockedCreate = await container.documentRepository.create(
            NewDocumentInput(
                watch_directory_id: nil,
                file_name: "blocked.docx",
                file_extension: "docx",
                absolute_path: "/tmp/blocked.docx",
                file_hash: "blocked_hash",
                file_size: 100,
                created_at_fs: nil,
                modified_at_fs: nil,
                imported_at: PipelineClock.nowString(),
                source_type: WatchSourceType.manual.rawValue
            )
        )

        guard case .success(let blockedDoc) = blockedCreate else {
            XCTFail("failed to create blocked doc")
            return
        }

        _ = await container.documentRepository.update(
            document_id: blockedDoc.id,
            update: DocumentPipelineUpdate(
                lifecycle_status: .blocked,
                current_stage: .gate,
                block_reason: .privacy_confirmation_required,
                last_error_code: .gate_sensitive_confirmation_required,
                last_error_message: "waiting user confirmation"
            )
        )

        let partialCreate = await container.documentRepository.create(
            NewDocumentInput(
                watch_directory_id: nil,
                file_name: "partial.txt",
                file_extension: "txt",
                absolute_path: "/tmp/partial.txt",
                file_hash: "partial_hash",
                file_size: 200,
                created_at_fs: nil,
                modified_at_fs: nil,
                imported_at: PipelineClock.nowString(),
                source_type: WatchSourceType.manual.rawValue
            )
        )

        guard case .success(let partialDoc) = partialCreate else {
            XCTFail("failed to create partial doc")
            return
        }

        let summaryProvider = ProviderConfig(
            provider_id: "provider_summary_mock",
            provider_type: .qwen,
            model_name: "qwen-plus",
            base_url: "mock://summary"
        )
        _ = await container.summaryRepository.create(
            document_id: partialDoc.id,
            summary: SummaryProviderResponse(
                document_type: "general_notice",
                one_line_summary: "摘要成功但事件失败",
                action_required: "检查失败原因",
                key_points: ["摘要已写入"],
                time_signals: [],
                location_signals: [],
                supporting_snippets: ["摘要成功"],
                risk_flags: [],
                confidence: 0.8
            ),
            provider: summaryProvider
        )
        _ = await container.documentRepository.update(
            document_id: partialDoc.id,
            update: DocumentPipelineUpdate(
                lifecycle_status: .failed,
                current_stage: .event_extract,
                summary_status: "success",
                last_error_code: .event_invalid_json,
                last_error_message: "event extraction failed"
            )
        )

        let reopened = DropKnowV1Container(mode: .sqlite(databaseURL: environment.databaseURL, sqlDirectoryURL: environment.sqlDirectoryURL))

        let blockedFetch = await reopened.documentRepository.get(id: blockedDoc.id)
        guard case .success(let blockedAfterReopen) = blockedFetch else {
            XCTFail("failed to fetch blocked doc after reopen")
            return
        }
        XCTAssertEqual(blockedAfterReopen?.lifecycle_status, .blocked)
        XCTAssertEqual(blockedAfterReopen?.block_reason, .privacy_confirmation_required)

        let partialFetch = await reopened.documentRepository.get(id: partialDoc.id)
        guard case .success(let partialAfterReopen) = partialFetch else {
            XCTFail("failed to fetch partial doc after reopen")
            return
        }
        XCTAssertEqual(partialAfterReopen?.lifecycle_status, .failed)
        XCTAssertEqual(partialAfterReopen?.summary_status, "success")
        XCTAssertEqual(partialAfterReopen?.last_error_code, .event_invalid_json)

        let partialSummary = await reopened.summaryRepository.get(document_id: partialDoc.id)
        guard case .success(let partialSummaryDTO) = partialSummary else {
            XCTFail("failed to fetch partial summary after reopen")
            return
        }
        XCTAssertEqual(partialSummaryDTO?.document_id, partialDoc.id)
    }

    private func makeSQLiteEnvironment() throws -> (databaseURL: URL, sqlDirectoryURL: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dropknow-integration-tests-\(UUID().uuidString.lowercased())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let sqlDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("DropKnow/Infrastructure/Database", isDirectory: true)

        return (databaseURL: root.appendingPathComponent("dropknow.sqlite3"), sqlDirectoryURL: sqlDirectory)
    }
}
#endif
