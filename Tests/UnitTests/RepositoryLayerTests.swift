import Foundation
#if canImport(XCTest)
import XCTest
#if canImport(DropKnow)
@testable import DropKnow
#endif

final class RepositoryLayerTests: XCTestCase {
    func testDocumentRepositoryCRUDAndListRecent() async {
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
}
#endif
