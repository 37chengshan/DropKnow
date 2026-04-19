import Foundation

public protocol DocumentEventExtracting: Sendable {
    func extract(context: ProviderDocumentContextRequest) async throws -> EventExtractionProviderResponse
}

public struct DocumentEventExtractionService: DocumentEventExtracting {
    private let provider: any EventExtractionProviding

    public init(provider: any EventExtractionProviding) {
        self.provider = provider
    }

    public func extract(context: ProviderDocumentContextRequest) async throws -> EventExtractionProviderResponse {
        try await provider.generate(request: context)
    }
}
