import Foundation

/// DTOs used across repository/provider/viewmodel boundaries.
/// Field names intentionally align with database columns (snake_case).
public struct DocumentDTO: Codable, Equatable, Sendable {
    public let id: String
    public let watch_directory_id: String?
    public let file_name: String
    public let file_extension: String
    public let absolute_path: String
    public let file_hash: String
    public let file_size: Int64
    public let imported_at: String
    public let lifecycle_status: DocumentLifecycleStatus
    public let current_stage: DocumentStage
    public let block_reason: BlockReason
    public let event_status: DocumentEventStatus
    public let parse_status: String?
    public let summary_status: String?
    public let privacy_status: String?
    public let readiness_flags_json: String
    public let importance_score: Double
    public let last_error_code: ErrorCode?
    public let last_error_message: String?
}

public struct DocumentSummaryDTO: Codable, Equatable, Sendable {
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
}

public struct DocumentEventDTO: Codable, Equatable, Sendable {
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
    public let calendar_eligible: Bool
    public let decision_status: EventDecisionStatus
    public let calendar_status: CalendarStatus
    public let calendar_event_identifier: String?
    public let created_at: String
    public let updated_at: String
}

public struct ParseJobDTO: Codable, Equatable, Sendable {
    public let id: String
    public let document_id: String
    public let stage: DocumentStage
    public let status: ParseJobStatus
    public let provider_id: String?
    public let started_at: String?
    public let finished_at: String?
    public let duration_ms: Int?
    public let error_code: ErrorCode?
    public let error_message: String?
}
