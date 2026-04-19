import Foundation

public struct SearchQARetrievedItem: Codable, Equatable, Sendable {
    public let document_id: String
    public let chunk_id: String
    public let file_name: String
    public let snippet: String

    public init(document_id: String, chunk_id: String, file_name: String, snippet: String) {
        self.document_id = document_id
        self.chunk_id = chunk_id
        self.file_name = file_name
        self.snippet = snippet
    }
}

public struct SearchQAProviderRequest: Codable, Equatable, Sendable {
    public let question: String
    public let reference_date: String
    public let user_timezone: String
    public let retrieved_items: [SearchQARetrievedItem]

    public init(
        question: String,
        reference_date: String,
        user_timezone: String,
        retrieved_items: [SearchQARetrievedItem]
    ) {
        self.question = question
        self.reference_date = reference_date
        self.user_timezone = user_timezone
        self.retrieved_items = retrieved_items
    }
}

public enum QAAnswerType: String, UnknownCaseCodable {
    case direct_answer
    case summary_answer
    case not_found
    case uncertain
    case unknown

    public static let unknownCase: Self = .unknown
}

public struct CitationResponse: Codable, Equatable, Sendable {
    public let document_id: String
    public let chunk_id: String
    public let file_name: String
    public let evidence_snippet: String

    public init(document_id: String, chunk_id: String, file_name: String, evidence_snippet: String) {
        self.document_id = document_id
        self.chunk_id = chunk_id
        self.file_name = file_name
        self.evidence_snippet = evidence_snippet
    }
}

public struct SearchQAProviderResponse: Codable, Equatable, Sendable {
    public let answer: String
    public let answer_type: QAAnswerType
    public let confidence: Double
    public let citations: [CitationResponse]

    public init(answer: String, answer_type: QAAnswerType, confidence: Double, citations: [CitationResponse]) {
        self.answer = answer
        self.answer_type = answer_type
        self.confidence = confidence
        self.citations = citations
    }
}

enum SearchQASchemaValidator {
    static func validate(_ response: SearchQAProviderResponse) throws {
        guard (0...1).contains(response.confidence) else {
            throw ProviderError.schema_validation_failed(message: "confidence must be within [0, 1]")
        }

        if response.answer_type == .not_found {
            guard response.citations.isEmpty else {
                throw ProviderError.schema_validation_failed(message: "not_found answer must have empty citations")
            }
        }

        for citation in response.citations {
            guard !citation.document_id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ProviderError.schema_validation_failed(message: "citation.document_id must not be empty")
            }
            guard !citation.chunk_id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ProviderError.schema_validation_failed(message: "citation.chunk_id must not be empty")
            }
            guard !citation.file_name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ProviderError.schema_validation_failed(message: "citation.file_name must not be empty")
            }
            guard !citation.evidence_snippet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ProviderError.schema_validation_failed(message: "citation.evidence_snippet must not be empty")
            }
        }
    }
}
