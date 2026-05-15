import Foundation
import XCTest
@testable import DropKnow

@MainActor
final class ChatWorkingStateTests: XCTestCase {
    func testIsChatWorkingTracksDebounceAndInFlightSearch() async throws {
        let rag = DelayedChatWorkingRAGService(delayNanoseconds: 180_000_000)
        let store = makeStore(rag: rag)
        store.searchQuery = "查文件 考试时间"

        store.submitSearch(debounceNanoseconds: 80_000_000)

        XCTAssertTrue(store.isSearchDebouncing)
        XCTAssertTrue(store.isChatWorking)

        try await waitUntil("search starts after debounce") {
            store.isSearching && !store.isSearchDebouncing
        }

        XCTAssertTrue(store.isChatWorking)

        try await waitUntil("search finishes") {
            !store.isChatWorking
        }

        XCTAssertFalse(store.isSearching)
        XCTAssertFalse(store.isSearchDebouncing)
        let searchQueries = await rag.searchQueries
        XCTAssertEqual(searchQueries, ["查文件 考试时间"])
    }

    func testCancelSearchImmediatelyStopsChatWorkingState() async throws {
        let rag = DelayedChatWorkingRAGService(delayNanoseconds: 250_000_000)
        let store = makeStore(rag: rag)
        store.searchQuery = "查文件 取消测试"

        store.submitSearch(debounceNanoseconds: 200_000_000)

        XCTAssertTrue(store.isSearchDebouncing)
        XCTAssertTrue(store.isChatWorking)

        store.cancelSearch()

        XCTAssertFalse(store.isSearchDebouncing)
        XCTAssertFalse(store.isSearching)
        XCTAssertFalse(store.isChatWorking)

        try await Task.sleep(nanoseconds: 300_000_000)

        let searchQueries = await rag.searchQueries
        XCTAssertTrue(searchQueries.isEmpty)
        XCTAssertFalse(store.chatMessages.contains { $0.text == "查文件 取消测试" })
    }

    private func makeStore(
        settings: DropSettings = .defaults(),
        rag: any RAGServing
    ) -> AppStore {
        let baseURL = try! makeTempDirectory()
        return AppStore(
            settings: settings,
            rag: rag,
            environment: .temporary(baseURL: baseURL),
            providerConfigurationLoader: {
                ProviderConfiguration(
                    apiKey: "test-key",
                    configURL: baseURL.appendingPathComponent("providers.local.json")
                )
            }
        )
    }

    private func waitUntil(
        _ description: String,
        timeoutNanoseconds: UInt64 = 1_500_000_000,
        pollNanoseconds: UInt64 = 10_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while !condition() {
            if DispatchTime.now().uptimeNanoseconds >= deadline {
                XCTFail("Timed out waiting for \(description)")
                return
            }
            try await Task.sleep(nanoseconds: pollNanoseconds)
        }
    }

    private func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private actor DelayedChatWorkingRAGService: RAGServing {
    let delayNanoseconds: UInt64
    private(set) var searchQueries: [String] = []
    private(set) var chatQueries: [String] = []

    init(delayNanoseconds: UInt64) {
        self.delayNanoseconds = delayNanoseconds
    }

    func indexBatch(files: [RAGBatchIndexFile]) async -> RAGIndexOutcome {
        RAGIndexOutcome(
            succeeded: true,
            warning: nil,
            results: files.map { RAGBatchIndexResult(fileID: $0.fileID, revisionID: $0.revisionID) }
        )
    }

    func search(query: String, topK: Int) async throws -> SearchResult {
        searchQueries.append(query)
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        return SearchResult(
            answer: "answer:\(query)",
            hits: [],
            engine: "delayed-stub",
            warning: nil,
            queryMode: .fileSearch,
            diagnostics: SearchDiagnostics(
                embeddingEngine: "delayed-stub",
                embeddingModel: "stub-embedding",
                chatModel: nil,
                topK: topK,
                chatUsed: false,
                fallbackReason: nil,
                indexedFileCount: 1,
                chunkCount: 1,
                activeRevisionCount: 1,
                emptyIndex: false,
                providerConfigured: true
            )
        )
    }

    func chat(query: String) async throws -> SearchResult {
        chatQueries.append(query)
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        return SearchResult(
            answer: "answer:\(query)",
            hits: [],
            engine: "delayed-stub",
            warning: nil,
            queryMode: .generalChat,
            diagnostics: SearchDiagnostics(
                embeddingEngine: "delayed-stub",
                embeddingModel: "stub-embedding",
                chatModel: "stub-chat",
                topK: 0,
                chatUsed: true,
                fallbackReason: nil,
                indexedFileCount: 1,
                chunkCount: 1,
                activeRevisionCount: 1,
                emptyIndex: false,
                providerConfigured: true
            )
        )
    }

    func diagnostics() async throws -> SearchDiagnostics {
        SearchDiagnostics(
            embeddingEngine: "delayed-stub",
            embeddingModel: "stub-embedding",
            chatModel: "stub-chat",
            topK: 6,
            chatUsed: false,
            fallbackReason: nil,
            indexedFileCount: 1,
            chunkCount: 1,
            activeRevisionCount: 1,
            emptyIndex: false,
            providerConfigured: true
        )
    }

    func refine(
        fileName: String,
        text: String,
        summary: FileSummary,
        priority: PriorityLevel,
        events: [EventCandidate]
    ) async -> RAGProcessResponse? {
        nil
    }
}
