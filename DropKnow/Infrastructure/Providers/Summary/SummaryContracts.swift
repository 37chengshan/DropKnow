import Foundation

public typealias SummaryProviderRequest = ProviderDocumentContextRequest

public struct SummaryTimeSignal: Codable, Equatable, Sendable {
    public let raw_time_text: String
    public let normalized_time: String?
    public let signal_type: String?

    public init(raw_time_text: String, normalized_time: String?, signal_type: String?) {
        self.raw_time_text = raw_time_text
        self.normalized_time = normalized_time
        self.signal_type = signal_type
    }
}

public struct SummaryProviderResponse: Codable, Equatable, Sendable {
    public let document_type: String
    public let one_line_summary: String
    public let action_required: String
    public let key_points: [String]
    public let time_signals: [SummaryTimeSignal]
    public let location_signals: [String]
    public let supporting_snippets: [String]
    public let risk_flags: [String]
    public let confidence: Double

    public init(
        document_type: String,
        one_line_summary: String,
        action_required: String,
        key_points: [String],
        time_signals: [SummaryTimeSignal],
        location_signals: [String],
        supporting_snippets: [String],
        risk_flags: [String],
        confidence: Double
    ) {
        self.document_type = document_type
        self.one_line_summary = one_line_summary
        self.action_required = action_required
        self.key_points = key_points
        self.time_signals = time_signals
        self.location_signals = location_signals
        self.supporting_snippets = supporting_snippets
        self.risk_flags = risk_flags
        self.confidence = confidence
    }
}

enum SummarySchemaValidator {
    static func validate(_ response: SummaryProviderResponse) throws {
        guard !response.document_type.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProviderError.schema_validation_failed(message: "document_type must not be empty")
        }
        guard !response.one_line_summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProviderError.schema_validation_failed(message: "one_line_summary must not be empty")
        }
        guard !response.action_required.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProviderError.schema_validation_failed(message: "action_required must not be empty")
        }
        guard !response.supporting_snippets.isEmpty else {
            throw ProviderError.schema_validation_failed(message: "supporting_snippets must contain at least one item")
        }
        guard (0...1).contains(response.confidence) else {
            throw ProviderError.schema_validation_failed(message: "confidence must be within [0, 1]")
        }

        for signal in response.time_signals {
            guard !signal.raw_time_text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ProviderError.schema_validation_failed(message: "time_signals.raw_time_text must not be empty")
            }
        }

        let normalized = response.risk_flags.map { $0.lowercased() }
        if normalized.contains("none") || normalized.contains("no_risk") {
            throw ProviderError.schema_validation_failed(message: "risk_flags must be [] when there is no risk")
        }
    }
}
