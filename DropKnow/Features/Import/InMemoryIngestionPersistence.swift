import Foundation

public actor InMemoryIngestionPersistence: RepositoryPersistenceBacking {
    private var documents: [String: DocumentDTO] = [:]
    private var parseJobs: [String: ParseJobDTO] = [:]
    private var parseJobsByDocument: [String: [String]] = [:]
    private var texts: [String: ParsedTextRecord] = [:]
    private var summaries: [String: DocumentSummaryDTO] = [:]
    private var events: [String: [DocumentEventDTO]] = [:]

    public init() {}

    public func findDuplicateDocument(file_hash: String, file_size: Int64, modified_at_fs: String?) async throws -> DocumentDTO? {
        _ = modified_at_fs
        return documents.values.first {
            $0.file_hash == file_hash &&
            $0.file_size == file_size
        }
    }

    public func createDocument(_ input: NewDocumentInput) async throws -> DocumentDTO {
        let id = "doc_\(UUID().uuidString.lowercased())"
        let dto = DocumentDTO(
            id: id,
            watch_directory_id: input.watch_directory_id,
            file_name: input.file_name,
            file_extension: input.file_extension,
            absolute_path: input.absolute_path,
            file_hash: input.file_hash,
            file_size: input.file_size,
            imported_at: input.imported_at,
            lifecycle_status: .detected,
            current_stage: .import,
            block_reason: .none,
            event_status: .none,
            parse_status: nil,
            summary_status: nil,
            privacy_status: nil,
            readiness_flags_json: "{}",
            importance_score: 0,
            last_error_code: nil,
            last_error_message: nil
        )
        documents[id] = dto
        return dto
    }

    public func updateDocument(document_id: String, update: DocumentPipelineUpdate) async throws -> DocumentDTO? {
        guard let current = documents[document_id] else {
            return nil
        }

        let updated = DocumentDTO(
            id: current.id,
            watch_directory_id: current.watch_directory_id,
            file_name: current.file_name,
            file_extension: current.file_extension,
            absolute_path: current.absolute_path,
            file_hash: current.file_hash,
            file_size: current.file_size,
            imported_at: current.imported_at,
            lifecycle_status: update.lifecycle_status ?? current.lifecycle_status,
            current_stage: update.current_stage ?? current.current_stage,
            block_reason: update.block_reason ?? current.block_reason,
            event_status: update.event_status ?? current.event_status,
            parse_status: update.parse_status ?? current.parse_status,
            summary_status: update.summary_status ?? current.summary_status,
            privacy_status: current.privacy_status,
            readiness_flags_json: current.readiness_flags_json,
            importance_score: current.importance_score,
            last_error_code: update.last_error_code,
            last_error_message: update.last_error_message
        )

        documents[document_id] = updated
        return updated
    }

    public func saveDocumentText(document_id: String, record: ParsedTextRecord) async throws {
        texts[document_id] = record
    }

    public func saveSummary(document_id: String, summary: SummaryProviderResponse, provider: ProviderConfig) async throws {
        let now = PipelineClock.nowString()
        let dto = DocumentSummaryDTO(
            document_id: document_id,
            document_type: summary.document_type,
            one_line_summary: summary.one_line_summary,
            action_required: summary.action_required,
            key_points_json: Self.encodeJSONString(summary.key_points),
            time_signals_json: Self.encodeJSONString(summary.time_signals),
            location_signals_json: Self.encodeJSONString(summary.location_signals),
            supporting_snippets_json: Self.encodeJSONString(summary.supporting_snippets),
            risk_flags_json: Self.encodeJSONString(summary.risk_flags),
            confidence: summary.confidence,
            model_provider: provider.provider_type.rawValue,
            model_name: provider.model_name,
            created_at: now,
            updated_at: now
        )
        summaries[document_id] = dto
    }

    public func saveEvents(document_id: String, events newEvents: [EventCandidateResponse]) async throws {
        let now = PipelineClock.nowString()
        let mapped = newEvents.map { candidate in
            DocumentEventDTO(
                id: "evt_\(UUID().uuidString.lowercased())",
                document_id: document_id,
                event_type: candidate.event_type,
                title: candidate.title,
                start_time: candidate.start_time,
                end_time: candidate.end_time,
                raw_time_text: candidate.raw_time_text,
                timezone: nil,
                location: candidate.location,
                notes: candidate.notes,
                evidence_snippet: candidate.evidence_snippet,
                confidence: candidate.confidence,
                calendar_eligible: candidate.calendar_eligible,
                decision_status: .suggested,
                calendar_status: .not_added,
                calendar_event_identifier: nil,
                created_at: now,
                updated_at: now
            )
        }
        events[document_id] = mapped
    }

    public func createParseJob(_ input: ParseJobCreateInput) async throws -> ParseJobDTO {
        let id = "job_\(UUID().uuidString.lowercased())"
        let job = ParseJobDTO(
            id: id,
            document_id: input.document_id,
            stage: input.stage,
            status: input.status,
            provider_id: input.provider_id,
            started_at: input.started_at,
            finished_at: input.finished_at,
            duration_ms: input.duration_ms,
            error_code: input.error_code,
            error_message: input.error_message
        )

        parseJobs[id] = job
        var existing = parseJobsByDocument[input.document_id, default: []]
        existing.append(id)
        parseJobsByDocument[input.document_id] = existing
        return job
    }

    public func updateParseJob(_ input: ParseJobUpdateInput) async throws -> ParseJobDTO? {
        guard let current = parseJobs[input.job_id] else {
            return nil
        }

        let updated = ParseJobDTO(
            id: current.id,
            document_id: current.document_id,
            stage: current.stage,
            status: input.status,
            provider_id: current.provider_id,
            started_at: current.started_at,
            finished_at: input.finished_at ?? current.finished_at,
            duration_ms: input.duration_ms ?? current.duration_ms,
            error_code: input.error_code,
            error_message: input.error_message
        )

        parseJobs[input.job_id] = updated
        return updated
    }

    public func fetchDocument(document_id: String) async throws -> DocumentDTO? {
        documents[document_id]
    }

    public func fetchParseJobs(document_id: String) async throws -> [ParseJobDTO] {
        let ids = parseJobsByDocument[document_id, default: []]
        return ids.compactMap { parseJobs[$0] }
    }

    public func listRecentDocuments(limit: Int) async -> [DocumentDTO] {
        documents.values
            .sorted { $0.imported_at > $1.imported_at }
            .prefix(max(limit, 0))
            .map { $0 }
    }

    public func upsertDocument(_ document: DocumentDTO) {
        documents[document.id] = document
    }

    public func deleteDocument(document_id: String) async -> Bool {
        let existed = documents.removeValue(forKey: document_id) != nil
        texts.removeValue(forKey: document_id)
        summaries.removeValue(forKey: document_id)
        events.removeValue(forKey: document_id)

        let ids = parseJobsByDocument.removeValue(forKey: document_id) ?? []
        for id in ids {
            parseJobs.removeValue(forKey: id)
        }

        return existed
    }

    public func allDocumentTexts() async -> [String: ParsedTextRecord] {
        texts
    }

    public func fetchDocumentText(document_id: String) async throws -> ParsedTextRecord? {
        texts[document_id]
    }

    public func deleteDocumentText(document_id: String) async -> Bool {
        texts.removeValue(forKey: document_id) != nil
    }

    public func fetchSummary(document_id: String) async -> DocumentSummaryDTO? {
        summaries[document_id]
    }

    public func listRecentSummaries(limit: Int) async -> [DocumentSummaryDTO] {
        summaries.values
            .sorted { $0.updated_at > $1.updated_at }
            .prefix(max(limit, 0))
            .map { $0 }
    }

    public func deleteSummary(document_id: String) async -> Bool {
        summaries.removeValue(forKey: document_id) != nil
    }

    public func fetchEvents(document_id: String) async -> [DocumentEventDTO] {
        events[document_id, default: []]
    }

    public func listRecentEvents(limit: Int) async -> [DocumentEventDTO] {
        events.values
            .flatMap { $0 }
            .sorted { $0.updated_at > $1.updated_at }
            .prefix(max(limit, 0))
            .map { $0 }
    }

    public func upsertEvent(_ event: DocumentEventDTO) async {
        var existing = events[event.document_id, default: []]
        if let index = existing.firstIndex(where: { $0.id == event.id }) {
            existing[index] = event
        } else {
            existing.append(event)
        }
        events[event.document_id] = existing
    }

    public func deleteEvent(event_id: String) async -> Bool {
        var deleted = false
        var copied = events

        for (documentID, list) in copied {
            let filtered = list.filter { $0.id != event_id }
            if filtered.count != list.count {
                copied[documentID] = filtered
                deleted = true
            }
        }

        events = copied
        return deleted
    }

    public func listRecentParseJobs(limit: Int) async -> [ParseJobDTO] {
        parseJobs.values
            .sorted { ($0.started_at ?? "") > ($1.started_at ?? "") }
            .prefix(max(limit, 0))
            .map { $0 }
    }

    public func fetchParseJob(job_id: String) async -> ParseJobDTO? {
        parseJobs[job_id]
    }

    public func deleteParseJob(job_id: String) async -> Bool {
        guard let job = parseJobs.removeValue(forKey: job_id) else {
            return false
        }

        let filtered = parseJobsByDocument[job.document_id, default: []].filter { $0 != job_id }
        parseJobsByDocument[job.document_id] = filtered
        return true
    }

    public func saveDocumentChunk(document_id: String, chunk_index: Int, content: String, content_preview: String, char_count: Int) async throws {
        // No-op for in-memory implementation
    }

    public func searchChunks(query: String, limit: Int) async throws -> [ChunkSearchResult] {
        // No-op for in-memory implementation - returns empty results
        return []
    }

    private static func encodeJSONString<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return text
    }
}
