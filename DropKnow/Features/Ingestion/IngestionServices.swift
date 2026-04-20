import Foundation

public struct ImportService: ImportServiceProtocol {
    public init() {}

    public func runImport(document_id: String) async throws {
        _ = document_id
    }
}

public struct ParseService: ParseServiceProtocol {
    private let parser: any DocumentParsing

    public init(parser: any DocumentParsing = DefaultDocumentParsingService()) {
        self.parser = parser
    }

    public func runParse(file_url: URL) async throws -> ParsedFileOutput {
        try await parser.parse(file_url: file_url)
    }
}

public struct GateService: GateServiceProtocol {
    private let gate: any PrivacyGateChecking

    public init(gate: any PrivacyGateChecking) {
        self.gate = gate
    }

    public func runGate(plain_text: String, reference_date: String) async -> PrivacyGateDecision {
        await gate.evaluate(
            plain_text: plain_text,
            reference_date: reference_date,
            requires_manual_confirmation: false
        )
    }
}

public struct SummaryService: SummaryServiceProtocol {
    private let summarizer: any DocumentSummarizing

    public init(summarizer: any DocumentSummarizing) {
        self.summarizer = summarizer
    }

    public func runSummary(context: ProviderDocumentContextRequest) async throws -> SummaryProviderResponse {
        try await summarizer.summarize(context: context)
    }
}

public struct EventService: EventServiceProtocol {
    private let extractor: any DocumentEventExtracting

    public init(extractor: any DocumentEventExtracting) {
        self.extractor = extractor
    }

    public func runEventExtraction(context: ProviderDocumentContextRequest) async throws -> EventExtractionProviderResponse {
        try await extractor.extract(context: context)
    }
}
