import Foundation

public struct RecentFileSnapshot: Equatable, Sendable {
    public let document_id: String
    public let file_name: String
    public let lifecycle_status: DocumentLifecycleStatus
    public let block_reason: BlockReason
    public let summary_text: String?
    public let key_points: [String]
    public let last_error_code: ErrorCode?
    public let imported_at: String

    public init(
        document_id: String,
        file_name: String,
        lifecycle_status: DocumentLifecycleStatus,
        block_reason: BlockReason,
        summary_text: String?,
        key_points: [String],
        last_error_code: ErrorCode?,
        imported_at: String
    ) {
        self.document_id = document_id
        self.file_name = file_name
        self.lifecycle_status = lifecycle_status
        self.block_reason = block_reason
        self.summary_text = summary_text
        self.key_points = key_points
        self.last_error_code = last_error_code
        self.imported_at = imported_at
    }
}

public struct ImportantReminderSnapshot: Equatable, Sendable {
    public let event_id: String
    public let document_id: String
    public let file_name: String
    public let title: String
    public let raw_time_text: String
    public let evidence_snippet: String
    public let event_status: DocumentEventStatus
    public let confidence: Double

    public init(
        event_id: String,
        document_id: String,
        file_name: String,
        title: String,
        raw_time_text: String,
        evidence_snippet: String,
        event_status: DocumentEventStatus,
        confidence: Double
    ) {
        self.event_id = event_id
        self.document_id = document_id
        self.file_name = file_name
        self.title = title
        self.raw_time_text = raw_time_text
        self.evidence_snippet = evidence_snippet
        self.event_status = event_status
        self.confidence = confidence
    }
}

public struct DocumentDetailSnapshot: Equatable, Sendable {
    public let document: DocumentDTO
    public let summary: DocumentSummaryDTO?
    public let events: [DocumentEventDTO]

    public init(document: DocumentDTO, summary: DocumentSummaryDTO?, events: [DocumentEventDTO]) {
        self.document = document
        self.summary = summary
        self.events = events
    }
}

public struct SearchSnapshot: Equatable, Sendable {
    public struct SearchResultItem: Equatable, Sendable {
        public let document_id: String
        public let file_name: String
        public let title: String
        public let subtitle: String
        public let evidence: String

        public init(document_id: String, file_name: String, title: String, subtitle: String, evidence: String) {
            self.document_id = document_id
            self.file_name = file_name
            self.title = title
            self.subtitle = subtitle
            self.evidence = evidence
        }
    }

    public let status: SearchStatus
    public let mode: QuickMode
    public let answer: String
    public let citations: [CitationResponse]
    public let results: [SearchResultItem]
    public let block_reason: SearchBlockReason

    public init(
        status: SearchStatus,
        mode: QuickMode,
        answer: String,
        citations: [CitationResponse],
        results: [SearchResultItem],
        block_reason: SearchBlockReason = .none
    ) {
        self.status = status
        self.mode = mode
        self.answer = answer
        self.citations = citations
        self.results = results
        self.block_reason = block_reason
    }
}
