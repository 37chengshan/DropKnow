import XCTest
@testable import DropKnow

final class RAGSearchContractTests: XCTestCase {
    func testSearchResultDefaultsRemainRenderable() {
        let result = SearchResult(answer: "没有找到足够相关的证据。", hits: [], engine: "zvec", warning: nil)

        XCTAssertEqual(result.queryMode, .fileSearch)
        XCTAssertTrue(result.hits.isEmpty)
        XCTAssertEqual(result.diagnostics.topK, 0)
        XCTAssertFalse(result.diagnostics.emptyIndex)
        XCTAssertNil(result.warning)
    }

    func testSearchHitCarriesEvidenceLocation() {
        let hit = SearchHit(
            id: "chunk-1",
            fileID: UUID(),
            fileName: "高数考试通知.txt",
            filePath: "/tmp/高数考试通知.txt",
            snippet: "高数考试时间为 5 月 20 日 10:00，地点 A101。",
            score: 0.91,
            chunkIndex: 2,
            revisionID: "rev-1",
            matchReason: "命中考试时间"
        )

        XCTAssertEqual(hit.chunkIndex, 2)
        XCTAssertEqual(hit.revisionID, "rev-1")
        XCTAssertEqual(hit.matchReason, "命中考试时间")
    }

    func testDiagnosticsDescribeFallbackAndIndexState() {
        let diagnostics = SearchDiagnostics(
            embeddingEngine: "local-hash",
            embeddingModel: "test-local",
            chatModel: "qwen3.5-flash",
            topK: 6,
            chatUsed: false,
            fallbackReason: "MISSING_API_KEY",
            indexedFileCount: 3,
            chunkCount: 9,
            activeRevisionCount: 3,
            emptyIndex: false,
            providerConfigured: false
        )

        XCTAssertEqual(diagnostics.fallbackReason, "MISSING_API_KEY")
        XCTAssertEqual(diagnostics.indexedFileCount, 3)
        XCTAssertFalse(diagnostics.providerConfigured)
    }
}
