import XCTest
@testable import DropKnow

final class RAGSearchContractTests: XCTestCase {
    private let decoder = JSONDecoder()

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

    func testLegacySearchResultDecodeDefaultsMissingFields() throws {
        let data = Data(
            """
            {
              "answer": "旧版结果",
              "hits": [],
              "engine": "zvec",
              "warning": null
            }
            """.utf8
        )

        let result = try decoder.decode(SearchResult.self, from: data)

        XCTAssertEqual(result.answer, "旧版结果")
        XCTAssertEqual(result.queryMode, .fileSearch)
        XCTAssertEqual(result.diagnostics, .empty)
    }

    func testLegacySearchResultDecodePartialDiagnosticsFallsBackPerField() throws {
        let data = Data(
            """
            {
              "answer": "部分诊断结果",
              "hits": [],
              "engine": "zvec",
              "diagnostics": {
                "topK": 6,
                "emptyIndex": true
              }
            }
            """.utf8
        )

        let result = try decoder.decode(SearchResult.self, from: data)

        XCTAssertEqual(result.diagnostics.topK, 6)
        XCTAssertTrue(result.diagnostics.emptyIndex)
        XCTAssertNil(result.diagnostics.embeddingEngine)
        XCTAssertNil(result.diagnostics.embeddingModel)
        XCTAssertNil(result.diagnostics.chatModel)
        XCTAssertFalse(result.diagnostics.chatUsed)
        XCTAssertNil(result.diagnostics.fallbackReason)
        XCTAssertEqual(result.diagnostics.indexedFileCount, 0)
        XCTAssertEqual(result.diagnostics.chunkCount, 0)
        XCTAssertEqual(result.diagnostics.activeRevisionCount, 0)
        XCTAssertFalse(result.diagnostics.providerConfigured)
    }

    func testLegacySearchHitDecodeDefaultsMissingEvidenceFields() throws {
        let fileID = UUID()
        let data = Data(
            """
            {
              "id": "chunk-legacy",
              "fileID": "\(fileID.uuidString)",
              "fileName": "通知.txt",
              "filePath": "/tmp/通知.txt",
              "snippet": "这是旧版命中片段",
              "score": 0.42
            }
            """.utf8
        )

        let hit = try decoder.decode(SearchHit.self, from: data)

        XCTAssertEqual(hit.id, "chunk-legacy")
        XCTAssertEqual(hit.fileID, fileID)
        XCTAssertNil(hit.chunkIndex)
        XCTAssertNil(hit.revisionID)
        XCTAssertNil(hit.matchReason)
    }

    func testRAGProcessResponseDecodesExtendedSearchContractFields() throws {
        let data = Data(
            """
            {
              "ok": true,
              "engine": "zvec",
              "answer": "本地降级结果",
              "queryMode": "localFallback",
              "diagnostics": {
                "topK": 4,
                "chatUsed": false,
                "fallbackReason": "LOCAL_FALLBACK"
              },
              "hits": [
                {
                  "id": "chunk-1",
                  "fileID": "11111111-1111-1111-1111-111111111111",
                  "fileName": "高数考试通知.txt",
                  "filePath": "/tmp/高数考试通知.txt",
                  "snippet": "高数考试时间为 5 月 20 日 10:00，地点 A101。",
                  "score": 0.91,
                  "chunkIndex": 2,
                  "revisionID": "rev-1"
                }
              ]
            }
            """.utf8
        )

        let response = try decoder.decode(RAGProcessResponse.self, from: data)

        XCTAssertTrue(response.ok)
        XCTAssertEqual(response.queryMode, .localFallback)
        XCTAssertEqual(response.diagnostics?.topK, 4)
        XCTAssertEqual(response.diagnostics?.chatUsed, false)
        XCTAssertEqual(response.diagnostics?.fallbackReason, "LOCAL_FALLBACK")
        XCTAssertEqual(response.hits?.first?.chunkIndex, 2)
        XCTAssertEqual(response.hits?.first?.revisionID, "rev-1")
    }

    func testDropFileRAGIndexStateIndexedBecomesStaleWhenContentHashChanges() {
        var file = makeFile(
            parsedStatus: .parsed,
            contentHash: "abc",
            indexedContentHash: "abc",
            indexedAt: Date()
        )

        XCTAssertEqual(file.ragIndexState, .indexed)

        file.contentHash = "xyz"
        XCTAssertEqual(file.ragIndexState, .stale)
    }

    func testDropFileRAGIndexStateFailed() {
        let file = makeFile(parsedStatus: .failed)

        XCTAssertEqual(file.ragIndexState, .failed)
    }

    func testDropFileRAGIndexStateBlocked() {
        let sensitive = makeFile(parsedStatus: .sensitiveGate)
        let ignored = makeFile(parsedStatus: .ignored)

        XCTAssertEqual(sensitive.ragIndexState, .blocked)
        XCTAssertEqual(ignored.ragIndexState, .blocked)
    }

    func testDropFileRAGIndexStateParsingWithoutContentHashIsNotIndexed() {
        let file = makeFile(parsedStatus: .parsing, contentHash: nil)

        XCTAssertEqual(file.ragIndexState, .notIndexed)
    }

    func testDropFileRAGIndexStateParsingWithContentHashIsIndexing() {
        let file = makeFile(parsedStatus: .parsing, contentHash: "abc")

        XCTAssertEqual(file.ragIndexState, .indexing)
    }

    private func makeFile(
        parsedStatus: ParseStatus,
        contentHash: String? = nil,
        indexedContentHash: String? = nil,
        indexedAt: Date? = nil
    ) -> DropFile {
        DropFile(
            fileName: "test.txt",
            filePath: "/tmp/test.txt",
            sourceDirectory: "/tmp",
            fileKind: .text,
            importedAt: Date(timeIntervalSince1970: 1),
            modifiedAt: Date(timeIntervalSince1970: 2),
            fileSize: 12,
            textLength: 34,
            parsedStatus: parsedStatus,
            sensitivityStatus: .clear,
            priorityLevel: .normal,
            summary: nil,
            events: [],
            snippets: [],
            errorMessage: nil,
            contentHash: contentHash,
            fingerprintComputedAt: nil,
            parserVersion: nil,
            summaryVersion: nil,
            refineModel: nil,
            embeddingProvider: nil,
            embeddingModel: nil,
            embeddingDimension: nil,
            indexedContentHash: indexedContentHash,
            indexedAt: indexedAt,
            refinedContentHash: nil,
            refinedAt: nil,
            activeIndexRevision: nil
        )
    }
}
