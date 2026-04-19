import Foundation

public protocol ImportServiceProtocol: Sendable {
    func runImport(document_id: String) async throws
}

public protocol ParseServiceProtocol: Sendable {
    func runParse(file_url: URL) async throws -> ParsedFileOutput
}

public protocol GateServiceProtocol: Sendable {
    func runGate(plain_text: String, reference_date: String) async -> PrivacyGateDecision
}

public protocol SummaryServiceProtocol: Sendable {
    func runSummary(context: ProviderDocumentContextRequest) async throws -> SummaryProviderResponse
}

public protocol EventServiceProtocol: Sendable {
    func runEventExtraction(context: ProviderDocumentContextRequest) async throws -> EventExtractionProviderResponse
}
