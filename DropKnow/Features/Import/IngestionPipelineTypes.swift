import Foundation

public struct IngestionRequest: Sendable {
    public let file_url: URL
    public let source_type: String
    public let watch_directory_id: String?
    public let reference_date: String
    public let user_timezone: String

    public init(
        file_url: URL,
        source_type: String = "manual",
        watch_directory_id: String? = nil,
        reference_date: String,
        user_timezone: String
    ) {
        self.file_url = file_url
        self.source_type = source_type
        self.watch_directory_id = watch_directory_id
        self.reference_date = reference_date
        self.user_timezone = user_timezone
    }
}

public enum IngestionResult: Sendable, Equatable {
    case ready(document_id: String)
    case duplicate(existing_document_id: String)
    case unsupported_file(document_id: String)
    case waiting_user_confirmation(document_id: String)
    case quota_blocked(document_id: String)
    case provider_failed(document_id: String, error_code: ErrorCode)
    case failed(document_id: String?, error_code: ErrorCode)
}

public struct StableFileMetadata: Sendable {
    public let file_size: Int64
    public let created_at_fs: String?
    public let modified_at_fs: String?

    public init(file_size: Int64, created_at_fs: String?, modified_at_fs: String?) {
        self.file_size = file_size
        self.created_at_fs = created_at_fs
        self.modified_at_fs = modified_at_fs
    }
}

public struct FileFingerprint: Sendable {
    public let file_hash: String
    public let file_size: Int64
    public let modified_at_fs: String?

    public init(file_hash: String, file_size: Int64, modified_at_fs: String?) {
        self.file_hash = file_hash
        self.file_size = file_size
        self.modified_at_fs = modified_at_fs
    }
}

public struct ParsedFileOutput: Sendable {
    public let extracted_title: String?
    public let plain_text: String
    public let page_count: Int?
    public let parser_type: String
    public let language_hint: String?

    public init(
        extracted_title: String?,
        plain_text: String,
        page_count: Int?,
        parser_type: String,
        language_hint: String?
    ) {
        self.extracted_title = extracted_title
        self.plain_text = plain_text
        self.page_count = page_count
        self.parser_type = parser_type
        self.language_hint = language_hint
    }
}

public enum IngestionBranch: Sendable, Equatable {
    case proceed
    case stop(IngestionResult)
}

public enum IngestionPipelineError: Error, Sendable, Equatable {
    case file_missing
    case file_not_stable
    case interrupted(document_id: String, stage: DocumentStage)
    case parse_unsupported_type
    case parse_failed(message: String)
    case gate_confirmation_required
    case gate_policy_blocked
    case quota_exceeded
    case provider_failed(error_code: ErrorCode, message: String)
    case storage_failed(message: String)
}
