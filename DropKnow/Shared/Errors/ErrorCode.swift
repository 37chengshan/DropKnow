import Foundation

public enum RetryDisposition: String, Codable, Equatable, Sendable {
    case auto_retry
    case repair_then_retry_once
    case no_auto_retry
}

public enum ErrorCode: String, UnknownCaseCodable {
    // Watch / Import
    case watch_permission_denied
    case watch_bookmark_access_failed
    case import_temp_file_skipped
    case import_file_missing_after_detected
    case import_duplicate_ignored
    case import_file_changed_during_parse

    // Parse
    case parse_unsupported_type
    case parse_pdf_failed
    case parse_docx_failed
    case parse_empty_text
    case parse_scanned_document_unsupported

    // Gate
    case gate_sensitive_confirmation_required
    case gate_sensitive_blocked
    case gate_policy_blocked

    // Summary / Event
    case summary_provider_timeout
    case summary_invalid_json
    case summary_provider_auth_failed
    case summary_provider_rate_limited
    case summary_provider_service_unavailable
    case event_invalid_json
    case event_no_candidate
    case event_low_confidence

    // Search / QA
    case search_quota_exceeded
    case search_feature_locked
    case search_empty_index
    case search_retrieval_failed
    case qa_provider_timeout
    case qa_invalid_json

    // Calendar
    case calendar_feature_locked
    case calendar_permission_denied
    case calendar_write_failed
    case calendar_event_expired

    // Quota / Feature / DB / Network
    case quota_parse_exceeded
    case quota_qa_exceeded
    case quota_advanced_search_exceeded
    case feature_directory_limit_reached
    case db_write_failed
    case db_read_failed
    case index_write_failed
    case fts_query_failed
    case network_offline
    case provider_auth_failed
    case provider_rate_limited
    case provider_service_unavailable

    // Fallback
    case unknown

    public static let unknownCase: Self = .unknown

    public var retryDisposition: RetryDisposition {
        switch self {
        case .summary_provider_timeout,
             .summary_provider_rate_limited,
             .summary_provider_service_unavailable,
             .qa_provider_timeout,
             .network_offline,
             .import_file_changed_during_parse,
             .import_temp_file_skipped:
            return .auto_retry

        case .summary_invalid_json,
             .event_invalid_json,
             .qa_invalid_json:
            return .repair_then_retry_once

        case .watch_permission_denied,
             .watch_bookmark_access_failed,
             .import_file_missing_after_detected,
             .import_duplicate_ignored,
             .parse_unsupported_type,
             .parse_pdf_failed,
             .parse_docx_failed,
             .parse_empty_text,
             .parse_scanned_document_unsupported,
             .gate_sensitive_confirmation_required,
             .gate_sensitive_blocked,
             .gate_policy_blocked,
             .summary_provider_auth_failed,
             .event_no_candidate,
             .event_low_confidence,
             .search_quota_exceeded,
             .search_feature_locked,
             .search_empty_index,
             .search_retrieval_failed,
             .calendar_feature_locked,
             .calendar_permission_denied,
             .calendar_write_failed,
             .calendar_event_expired,
             .quota_parse_exceeded,
             .quota_qa_exceeded,
             .quota_advanced_search_exceeded,
             .feature_directory_limit_reached,
             .db_write_failed,
             .db_read_failed,
             .index_write_failed,
             .fts_query_failed,
             .provider_auth_failed,
             .unknown:
            return .no_auto_retry

        case .provider_rate_limited,
             .provider_service_unavailable:
            return .auto_retry
        }
    }

    public var isRetryable: Bool {
        retryDisposition == .auto_retry || retryDisposition == .repair_then_retry_once
    }
}
