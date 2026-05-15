import Foundation

protocol RAGServing: Sendable {
    func indexBatch(files: [RAGBatchIndexFile]) async -> RAGIndexOutcome
    func search(query: String, topK: Int) async throws -> SearchResult
    func chat(query: String) async throws -> SearchResult
    func diagnostics() async throws -> SearchDiagnostics
    func refine(
        fileName: String,
        text: String,
        summary: FileSummary,
        priority: PriorityLevel,
        events: [EventCandidate]
    ) async -> RAGProcessResponse?
}

extension RAGService: RAGServing {}
