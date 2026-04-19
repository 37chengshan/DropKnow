import Foundation

public protocol SummaryProviding: Sendable {
    func generate(request: SummaryProviderRequest) async throws -> SummaryProviderResponse
}

public protocol EventExtractionProviding: Sendable {
    func generate(request: EventExtractionProviderRequest) async throws -> EventExtractionProviderResponse
}

public protocol SearchQAProviding: Sendable {
    func generate(request: SearchQAProviderRequest) async throws -> SearchQAProviderResponse
}
