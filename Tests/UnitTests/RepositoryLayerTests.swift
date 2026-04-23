import Foundation
#if canImport(XCTest)
import XCTest
#if canImport(DropKnow)
@testable import DropKnow
#endif

final class RepositoryLayerTests: XCTestCase {
    func testInMemoryDocumentRepositoryCRUDAndListRecent() async {
        let persistence = InMemoryIngestionPersistence()
        let repository = DocumentRepository(persistence: persistence)

        let createResult = await repository.create(
            NewDocumentInput(
                watch_directory_id: nil,
                file_name: "repo-test.txt",
                file_extension: "txt",
                absolute_path: "/tmp/repo-test.txt",
                file_hash: "hash_repo_test",
                file_size: 10,
                created_at_fs: nil,
                modified_at_fs: nil,
                imported_at: PipelineClock.nowString(),
                source_type: WatchSourceType.manual.rawValue
            )
        )

        guard case .success(let created) = createResult else {
            XCTFail("create should succeed")
            return
        }

        let getResult = await repository.get(id: created.id)
        guard case .success(let fetched) = getResult else {
            XCTFail("get should succeed")
            return
        }
        XCTAssertEqual(fetched?.id, created.id)

        let updateResult = await repository.update(
            document_id: created.id,
            update: DocumentPipelineUpdate(lifecycle_status: .processing, current_stage: .parse)
        )
        guard case .success(let updated) = updateResult else {
            XCTFail("update should succeed")
            return
        }
        XCTAssertEqual(updated?.lifecycle_status, .processing)

        let listResult = await repository.listRecent(limit: 10)
        guard case .success(let docs) = listResult else {
            XCTFail("listRecent should succeed")
            return
        }
        XCTAssertTrue(docs.contains(where: { $0.id == created.id }))

        let deleteResult = await repository.delete(id: created.id)
        guard case .success(let deleted) = deleteResult else {
            XCTFail("delete should succeed")
            return
        }
        XCTAssertTrue(deleted)
    }

    func testSQLiteRepositoryCRUDAndReopenStillReadable() async throws {
        let environment = try makeSQLiteEnvironment()

        let firstPersistence = try SQLiteIngestionPersistence(configuration: environment.configuration)
        let tx = InMemoryRepositoryTransactionManager()
        let documentRepository = DocumentRepository(persistence: firstPersistence, transaction: tx)
        let textRepository = DocumentTextRepository(persistence: firstPersistence, transaction: tx)
        let summaryRepository = SummaryRepository(persistence: firstPersistence, transaction: tx)
        let eventRepository = EventRepository(persistence: firstPersistence, transaction: tx)
        let parseJobRepository = ParseJobRepository(persistence: firstPersistence, transaction: tx)

        let createResult = await documentRepository.create(
            NewDocumentInput(
                watch_directory_id: nil,
                file_name: "sqlite-repo-test.txt",
                file_extension: "txt",
                absolute_path: "/tmp/sqlite-repo-test.txt",
                file_hash: "hash_sqlite_repo_test",
                file_size: 10,
                created_at_fs: nil,
                modified_at_fs: nil,
                imported_at: PipelineClock.nowString(),
                source_type: WatchSourceType.manual.rawValue
            )
        )

        guard case .success(let created) = createResult else {
            XCTFail("sqlite create document should succeed")
            return
        }

        let textResult = await textRepository.create(
            document_id: created.id,
            record: ParsedTextRecord(
                extracted_title: "SQLite Repo Test",
                plain_text: "明天下午三点在上海开会。",
                page_count: 1,
                parser_type: "txt",
                language_hint: "zh",
                text_length: 12,
                extracted_at: PipelineClock.nowString()
            )
        )
        guard case .success = textResult else {
            XCTFail("sqlite create document text should succeed")
            return
        }

        let summary = SummaryProviderResponse(
            document_type: "event_notice",
            one_line_summary: "明天下午三点有会议",
            action_required: "准备会议材料",
            key_points: ["会议时间已明确"],
            time_signals: [SummaryTimeSignal(raw_time_text: "明天下午三点", normalized_time: nil, signal_type: "datetime")],
            location_signals: ["上海"],
            supporting_snippets: ["明天下午三点在上海开会"],
            risk_flags: [],
            confidence: 0.92
        )
        let provider = ProviderConfig(
            provider_id: "provider_summary_mock",
            provider_type: .qwen,
            model_name: "qwen-plus",
            base_url: "mock://summary"
        )

        let summaryResult = await summaryRepository.create(document_id: created.id, summary: summary, provider: provider)
        guard case .success(let savedSummary) = summaryResult else {
            XCTFail("sqlite create summary should succeed")
            return
        }
        XCTAssertEqual(savedSummary?.document_id, created.id)

        let events = [
            EventCandidateResponse(
                event_type: "meeting",
                title: "项目周会",
                start_time: nil,
                end_time: nil,
                raw_time_text: "明天下午三点",
                location: "上海",
                notes: "携带资料",
                evidence_snippet: "明天下午三点在上海开会",
                confidence: 0.87,
                calendar_eligible: true
            )
        ]
        let eventResult = await eventRepository.create(document_id: created.id, events: events)
        guard case .success(let savedEvents) = eventResult else {
            XCTFail("sqlite create events should succeed")
            return
        }
        XCTAssertEqual(savedEvents.count, 1)

        let parseCreate = await parseJobRepository.create(
            ParseJobCreateInput(
                document_id: created.id,
                stage: .parse,
                status: .running,
                provider_id: nil,
                started_at: PipelineClock.nowString()
            )
        )
        guard case .success(let createdJob) = parseCreate else {
            XCTFail("sqlite create parse job should succeed")
            return
        }

        let parseUpdate = await parseJobRepository.update(
            ParseJobUpdateInput(
                job_id: createdJob.id,
                status: .success,
                finished_at: PipelineClock.nowString(),
                duration_ms: 120
            )
        )
        guard case .success(let updatedJob) = parseUpdate else {
            XCTFail("sqlite update parse job should succeed")
            return
        }
        XCTAssertEqual(updatedJob?.status, .success)

        let secondPersistence = try SQLiteIngestionPersistence(configuration: environment.configuration)
        let documentRepositoryReopened = DocumentRepository(persistence: secondPersistence, transaction: tx)
        let summaryRepositoryReopened = SummaryRepository(persistence: secondPersistence, transaction: tx)
        let eventRepositoryReopened = EventRepository(persistence: secondPersistence, transaction: tx)
        let parseJobRepositoryReopened = ParseJobRepository(persistence: secondPersistence, transaction: tx)

        let reopenedDocument = await documentRepositoryReopened.get(id: created.id)
        guard case .success(let fetchedDocument) = reopenedDocument else {
            XCTFail("sqlite get document after reopen should succeed")
            return
        }
        XCTAssertEqual(fetchedDocument?.id, created.id)

        let reopenedSummary = await summaryRepositoryReopened.get(document_id: created.id)
        guard case .success(let fetchedSummary) = reopenedSummary else {
            XCTFail("sqlite get summary after reopen should succeed")
            return
        }
        XCTAssertEqual(fetchedSummary?.document_id, created.id)

        let reopenedEvents = await eventRepositoryReopened.get(document_id: created.id)
        guard case .success(let fetchedEvents) = reopenedEvents else {
            XCTFail("sqlite get events after reopen should succeed")
            return
        }
        XCTAssertEqual(fetchedEvents.count, 1)

        let reopenedJobs = await parseJobRepositoryReopened.listRecent(limit: 10)
        guard case .success(let fetchedJobs) = reopenedJobs else {
            XCTFail("sqlite list parse jobs after reopen should succeed")
            return
        }
        XCTAssertTrue(fetchedJobs.contains(where: { $0.document_id == created.id }))
    }

    private func makeSQLiteEnvironment() throws -> (root: URL, configuration: DatabaseInitializer.Configuration) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dropknow-tests-\(UUID().uuidString.lowercased())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let sqlDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("DropKnow/Infrastructure/Database", isDirectory: true)

        let configuration = DatabaseInitializer.Configuration(
            databaseURL: root.appendingPathComponent("dropknow.sqlite3"),
            schemaSQLURL: sqlDirectory.appendingPathComponent("schema.sql"),
            migrationV1SQLURL: sqlDirectory.appendingPathComponent("migration_v1.sql")
        )

        return (root: root, configuration: configuration)
    }
}
#endif
