import Foundation

public typealias EventExtractionProviderRequest = ProviderDocumentContextRequest

public struct EventCandidateResponse: Codable, Equatable, Sendable {
    public let event_type: String
    public let title: String
    public let start_time: String?
    public let end_time: String?
    public let raw_time_text: String
    public let location: String?
    public let notes: String?
    public let evidence_snippet: String
    public let confidence: Double
    public let calendar_eligible: Bool

    public init(
        event_type: String,
        title: String,
        start_time: String?,
        end_time: String?,
        raw_time_text: String,
        location: String?,
        notes: String?,
        evidence_snippet: String,
        confidence: Double,
        calendar_eligible: Bool
    ) {
        self.event_type = event_type
        self.title = title
        self.start_time = start_time
        self.end_time = end_time
        self.raw_time_text = raw_time_text
        self.location = location
        self.notes = notes
        self.evidence_snippet = evidence_snippet
        self.confidence = confidence
        self.calendar_eligible = calendar_eligible
    }
}

public struct EventExtractionProviderResponse: Codable, Equatable, Sendable {
    public let event_candidates: [EventCandidateResponse]

    public init(event_candidates: [EventCandidateResponse]) {
        self.event_candidates = event_candidates
    }
}

enum EventExtractionSchemaValidator {
    static func validate(_ response: EventExtractionProviderResponse) throws {
        for candidate in response.event_candidates {
            guard !candidate.event_type.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ProviderError.schema_validation_failed(message: "event_type must not be empty")
            }
            guard !candidate.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ProviderError.schema_validation_failed(message: "title must not be empty")
            }
            guard !candidate.raw_time_text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ProviderError.schema_validation_failed(message: "raw_time_text must not be empty")
            }
            guard !candidate.evidence_snippet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ProviderError.schema_validation_failed(message: "evidence_snippet must not be empty")
            }
            guard (0...1).contains(candidate.confidence) else {
                throw ProviderError.schema_validation_failed(message: "confidence must be within [0, 1]")
            }
        }
    }
}
