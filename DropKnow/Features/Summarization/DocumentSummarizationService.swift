import Foundation

public protocol DocumentSummarizing: Sendable {
    func summarize(context: ProviderDocumentContextRequest) async throws -> SummaryProviderResponse
}

public struct DocumentSummarizationService: DocumentSummarizing {
    private let provider: any SummaryProviding

    public init(provider: any SummaryProviding) {
        self.provider = provider
    }

    public func summarize(context: ProviderDocumentContextRequest) async throws -> SummaryProviderResponse {
        try await provider.generate(request: context)
    }
}
