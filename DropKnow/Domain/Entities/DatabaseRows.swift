import Foundation

/// Raw database row models. Field names intentionally match SQLite columns.
public struct DocumentRow: Codable, Equatable, Sendable {
    public let id: String
    public let watch_directory_id: String?
    public let file_name: String
    public let file_extension: String
    public let absolute_path: String
    public let file_hash: String
    public let file_size: Int64
    public let imported_at: String
    public let lifecycle_status: String
    public let current_stage: String
    public let block_reason: String
    public let event_status: String
    public let parse_status: String?
    public let summary_status: String?
    public let privacy_status: String?
    public let readiness_flags_json: String
    public let importance_score: Double
    public let last_error_code: String?
    public let last_error_message: String?

    public init(
        id: String,
        watch_directory_id: String?,
        file_name: String,
        file_extension: String,
        absolute_path: String,
        file_hash: String,
        file_size: Int64,
        imported_at: String,
        lifecycle_status: String,
        current_stage: String,
        block_reason: String,
        event_status: String,
        parse_status: String?,
        summary_status: String?,
        privacy_status: String?,
        readiness_flags_json: String,
        importance_score: Double,
        last_error_code: String?,
        last_error_message: String?
    ) {
        self.id = id
        self.watch_directory_id = watch_directory_id
        self.file_name = file_name
        self.file_extension = file_extension
        self.absolute_path = absolute_path
        self.file_hash = file_hash
        self.file_size = file_size
        self.imported_at = imported_at
        self.lifecycle_status = lifecycle_status
        self.current_stage = current_stage
        self.block_reason = block_reason
        self.event_status = event_status
        self.parse_status = parse_status
        self.summary_status = summary_status
        self.privacy_status = privacy_status
        self.readiness_flags_json = readiness_flags_json
        self.importance_score = importance_score
        self.last_error_code = last_error_code
        self.last_error_message = last_error_message
    }
}

public struct DocumentSummaryRow: Codable, Equatable, Sendable {
    public let document_id: String
    public let document_type: String
    public let one_line_summary: String
    public let action_required: String
    public let key_points_json: String
    public let time_signals_json: String
    public let location_signals_json: String
    public let supporting_snippets_json: String
    public let risk_flags_json: String
    public let confidence: Double
    public let model_provider: String
    public let model_name: String
    public let created_at: String
    public let updated_at: String

    public init(
        document_id: String,
        document_type: String,
        one_line_summary: String,
        action_required: String,
        key_points_json: String,
        time_signals_json: String,
        location_signals_json: String,
        supporting_snippets_json: String,
        risk_flags_json: String,
        confidence: Double,
        model_provider: String,
        model_name: String,
        created_at: String,
        updated_at: String
    ) {
        self.document_id = document_id
        self.document_type = document_type
        self.one_line_summary = one_line_summary
        self.action_required = action_required
        self.key_points_json = key_points_json
        self.time_signals_json = time_signals_json
        self.location_signals_json = location_signals_json
        self.supporting_snippets_json = supporting_snippets_json
        self.risk_flags_json = risk_flags_json
        self.confidence = confidence
        self.model_provider = model_provider
        self.model_name = model_name
        self.created_at = created_at
        self.updated_at = updated_at
    }
}

public struct DocumentEventRow: Codable, Equatable, Sendable {
    public let id: String
    public let document_id: String
    public let event_type: String
    public let title: String
    public let start_time: String?
    public let end_time: String?
    public let raw_time_text: String
    public let timezone: String?
    public let location: String?
    public let notes: String?
    public let evidence_snippet: String
    public let confidence: Double
    public let calendar_eligible: Int
    public let decision_status: String
    public let calendar_status: String
    public let calendar_event_identifier: String?
    public let created_at: String
    public let updated_at: String

    public init(
        id: String,
        document_id: String,
        event_type: String,
        title: String,
        start_time: String?,
        end_time: String?,
        raw_time_text: String,
        timezone: String?,
        location: String?,
        notes: String?,
        evidence_snippet: String,
        confidence: Double,
        calendar_eligible: Int,
        decision_status: String,
        calendar_status: String,
        calendar_event_identifier: String?,
        created_at: String,
        updated_at: String
    ) {
        self.id = id
        self.document_id = document_id
        self.event_type = event_type
        self.title = title
        self.start_time = start_time
        self.end_time = end_time
        self.raw_time_text = raw_time_text
        self.timezone = timezone
        self.location = location
        self.notes = notes
        self.evidence_snippet = evidence_snippet
        self.confidence = confidence
        self.calendar_eligible = calendar_eligible
        self.decision_status = decision_status
        self.calendar_status = calendar_status
        self.calendar_event_identifier = calendar_event_identifier
        self.created_at = created_at
        self.updated_at = updated_at
    }
}

public struct ParseJobRow: Codable, Equatable, Sendable {
    public let id: String
    public let document_id: String
    public let stage: String
    public let status: String
    public let provider_id: String?
    public let started_at: String?
    public let finished_at: String?
    public let duration_ms: Int?
    public let error_code: String?
    public let error_message: String?

    public init(
        id: String,
        document_id: String,
        stage: String,
        status: String,
        provider_id: String?,
        started_at: String?,
        finished_at: String?,
        duration_ms: Int?,
        error_code: String?,
        error_message: String?
    ) {
        self.id = id
        self.document_id = document_id
        self.stage = stage
        self.status = status
        self.provider_id = provider_id
        self.started_at = started_at
        self.finished_at = finished_at
        self.duration_ms = duration_ms
        self.error_code = error_code
        self.error_message = error_message
    }
}
