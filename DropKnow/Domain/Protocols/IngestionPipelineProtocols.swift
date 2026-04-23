import Foundation

public struct NewDocumentInput: Sendable {
    public let watch_directory_id: String?
    public let file_name: String
    public let file_extension: String
    public let absolute_path: String
    public let file_hash: String
    public let file_size: Int64
    public let created_at_fs: String?
    public let modified_at_fs: String?
    public let imported_at: String
    public let source_type: String

    public init(
        watch_directory_id: String?,
        file_name: String,
        file_extension: String,
        absolute_path: String,
        file_hash: String,
        file_size: Int64,
        created_at_fs: String?,
        modified_at_fs: String?,
        imported_at: String,
        source_type: String
    ) {
        self.watch_directory_id = watch_directory_id
        self.file_name = file_name
        self.file_extension = file_extension
        self.absolute_path = absolute_path
        self.file_hash = file_hash
        self.file_size = file_size
        self.created_at_fs = created_at_fs
        self.modified_at_fs = modified_at_fs
        self.imported_at = imported_at
        self.source_type = source_type
    }
}

public struct DocumentPipelineUpdate: Sendable {
    public let lifecycle_status: DocumentLifecycleStatus?
    public let current_stage: DocumentStage?
    public let block_reason: BlockReason?
    public let event_status: DocumentEventStatus?
    public let parse_status: String?
    public let summary_status: String?
    public let last_error_code: ErrorCode?
    public let last_error_message: String?

    public init(
        lifecycle_status: DocumentLifecycleStatus? = nil,
        current_stage: DocumentStage? = nil,
        block_reason: BlockReason? = nil,
        event_status: DocumentEventStatus? = nil,
        parse_status: String? = nil,
        summary_status: String? = nil,
        last_error_code: ErrorCode? = nil,
        last_error_message: String? = nil
    ) {
        self.lifecycle_status = lifecycle_status
        self.current_stage = current_stage
        self.block_reason = block_reason
        self.event_status = event_status
        self.parse_status = parse_status
        self.summary_status = summary_status
        self.last_error_code = last_error_code
        self.last_error_message = last_error_message
    }
}

public struct ParsedTextRecord: Sendable {
    public let extracted_title: String?
    public let plain_text: String
    public let page_count: Int?
    public let parser_type: String
    public let language_hint: String?
    public let text_length: Int
    public let extracted_at: String

    public init(
        extracted_title: String?,
        plain_text: String,
        page_count: Int?,
        parser_type: String,
        language_hint: String?,
        text_length: Int,
        extracted_at: String
    ) {
        self.extracted_title = extracted_title
        self.plain_text = plain_text
        self.page_count = page_count
        self.parser_type = parser_type
        self.language_hint = language_hint
        self.text_length = text_length
        self.extracted_at = extracted_at
    }
}

public struct ParseJobCreateInput: Sendable {
    public let document_id: String
    public let stage: DocumentStage
    public let status: ParseJobStatus
    public let provider_id: String?
    public let started_at: String?
    public let finished_at: String?
    public let duration_ms: Int?
    public let error_code: ErrorCode?
    public let error_message: String?

    public init(
        document_id: String,
        stage: DocumentStage,
        status: ParseJobStatus,
        provider_id: String? = nil,
        started_at: String? = nil,
        finished_at: String? = nil,
        duration_ms: Int? = nil,
        error_code: ErrorCode? = nil,
        error_message: String? = nil
    ) {
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

public struct ParseJobUpdateInput: Sendable {
    public let job_id: String
    public let status: ParseJobStatus
    public let finished_at: String?
    public let duration_ms: Int?
    public let error_code: ErrorCode?
    public let error_message: String?

    public init(
        job_id: String,
        status: ParseJobStatus,
        finished_at: String? = nil,
        duration_ms: Int? = nil,
        error_code: ErrorCode? = nil,
        error_message: String? = nil
    ) {
        self.job_id = job_id
        self.status = status
        self.finished_at = finished_at
        self.duration_ms = duration_ms
        self.error_code = error_code
        self.error_message = error_message
    }
}

public protocol IngestionPersistence: Sendable {
    func findDuplicateDocument(file_hash: String, file_size: Int64, modified_at_fs: String?) async throws -> DocumentDTO?
    func createDocument(_ input: NewDocumentInput) async throws -> DocumentDTO
    func updateDocument(document_id: String, update: DocumentPipelineUpdate) async throws -> DocumentDTO?
    func saveDocumentText(document_id: String, record: ParsedTextRecord) async throws
    func fetchDocumentText(document_id: String) async throws -> ParsedTextRecord?
    func saveSummary(document_id: String, summary: SummaryProviderResponse, provider: ProviderConfig) async throws
    func saveEvents(document_id: String, events: [EventCandidateResponse]) async throws
    func saveDocumentChunk(document_id: String, chunk_index: Int, content: String, content_preview: String, char_count: Int) async throws
    func searchChunks(query: String, limit: Int) async throws -> [ChunkSearchResult]

    func createParseJob(_ input: ParseJobCreateInput) async throws -> ParseJobDTO
    func updateParseJob(_ input: ParseJobUpdateInput) async throws -> ParseJobDTO?

    func fetchDocument(document_id: String) async throws -> DocumentDTO?
    func fetchParseJobs(document_id: String) async throws -> [ParseJobDTO]
}

public protocol PipelineEventPublishing {
    func publish(_ event: PipelineEvent)
}

public enum PipelineEvent: Sendable, Equatable {
    case document_updated(document_id: String)
    case ingestion_finished(document_id: String)
    case ingestion_failed(document_id: String, error_code: ErrorCode)
    case notification_requested(document_id: String)
}
