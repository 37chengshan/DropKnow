import Foundation
import SQLite3

public enum SQLitePersistenceError: Error, LocalizedError {
    case openDatabase(message: String)
    case prepare(message: String, sql: String)
    case step(message: String, sql: String)
    case transaction(message: String)

    public var errorDescription: String? {
        switch self {
        case .openDatabase(let message):
            return "Failed to open SQLite database: \(message)"
        case .prepare(let message, let sql):
            return "Failed to prepare SQL [\(sql)]: \(message)"
        case .step(let message, let sql):
            return "Failed to execute SQL [\(sql)]: \(message)"
        case .transaction(let message):
            return "SQLite transaction failed: \(message)"
        }
    }
}

public actor SQLiteIngestionPersistence: RepositoryPersistenceBacking {
    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private let databaseURL: URL
    private var db: OpaquePointer?

    public init(configuration: DatabaseInitializer.Configuration) throws {
        self.databaseURL = configuration.databaseURL
        try DatabaseInitializer.initialize(configuration)
        self.db = try Self.openDatabase(at: configuration.databaseURL.path)
        if let db {
            try Self.executeRaw("PRAGMA foreign_keys = ON;", on: db)
            try Self.executeRaw("PRAGMA journal_mode = WAL;", on: db)
            try Self.executeRaw("PRAGMA busy_timeout = \(configuration.busyTimeoutMilliseconds);", on: db)
        }
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    public func findDuplicateDocument(file_hash: String, file_size: Int64, modified_at_fs: String?) async throws -> DocumentDTO? {
        _ = modified_at_fs
        let sql = """
        SELECT id, watch_directory_id, file_name, file_extension, absolute_path, file_hash, file_size,
               imported_at, lifecycle_status, current_stage, block_reason, event_status,
               parse_status, summary_status, privacy_status, readiness_flags_json, importance_score,
               last_error_code, last_error_message
        FROM documents
        WHERE file_hash = ? AND file_size = ?
        ORDER BY imported_at DESC
        LIMIT 1;
        """

        return try querySingle(sql: sql, bind: { statement in
            sqlite3_bind_text(statement, 1, (file_hash as NSString).utf8String, -1, Self.sqliteTransient)
            sqlite3_bind_int64(statement, 2, sqlite3_int64(file_size))
        }, map: Self.mapDocumentDTO)
    }

    public func createDocument(_ input: NewDocumentInput) async throws -> DocumentDTO {
        let id = "doc_\(UUID().uuidString.lowercased())"
        let sql = """
        INSERT INTO documents (
            id, watch_directory_id, file_name, file_extension, absolute_path, file_hash, file_size,
            created_at_fs, modified_at_fs, imported_at, source_type,
            lifecycle_status, current_stage, block_reason, event_status,
            parse_status, summary_status, privacy_status, readiness_flags_json,
            importance_score, last_error_code, last_error_message
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        try executePrepared(sql: sql) { statement in
            bindText(statement, index: 1, value: id)
            bindText(statement, index: 2, value: input.watch_directory_id)
            bindText(statement, index: 3, value: input.file_name)
            bindText(statement, index: 4, value: input.file_extension)
            bindText(statement, index: 5, value: input.absolute_path)
            bindText(statement, index: 6, value: input.file_hash)
            sqlite3_bind_int64(statement, 7, sqlite3_int64(input.file_size))
            bindText(statement, index: 8, value: input.created_at_fs)
            bindText(statement, index: 9, value: input.modified_at_fs)
            bindText(statement, index: 10, value: input.imported_at)
            bindText(statement, index: 11, value: input.source_type)
            bindText(statement, index: 12, value: DocumentLifecycleStatus.detected.rawValue)
            bindText(statement, index: 13, value: DocumentStage.import.rawValue)
            bindText(statement, index: 14, value: BlockReason.none.rawValue)
            bindText(statement, index: 15, value: DocumentEventStatus.none.rawValue)
            sqlite3_bind_null(statement, 16)
            sqlite3_bind_null(statement, 17)
            sqlite3_bind_null(statement, 18)
            bindText(statement, index: 19, value: "{}")
            sqlite3_bind_double(statement, 20, 0)
            sqlite3_bind_null(statement, 21)
            sqlite3_bind_null(statement, 22)
        }

        guard let created = try await fetchDocument(document_id: id) else {
            throw SQLitePersistenceError.step(message: "document not found after insert", sql: sql)
        }
        return created
    }

    public func updateDocument(document_id: String, update: DocumentPipelineUpdate) async throws -> DocumentDTO? {
        guard let current = try await fetchDocument(document_id: document_id) else {
            return nil
        }

        let merged = DocumentDTO(
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

        let sql = """
        UPDATE documents
        SET lifecycle_status = ?,
            current_stage = ?,
            block_reason = ?,
            event_status = ?,
            parse_status = ?,
            summary_status = ?,
            last_error_code = ?,
            last_error_message = ?
        WHERE id = ?;
        """

        try executePrepared(sql: sql) { statement in
            bindText(statement, index: 1, value: merged.lifecycle_status.rawValue)
            bindText(statement, index: 2, value: merged.current_stage.rawValue)
            bindText(statement, index: 3, value: merged.block_reason.rawValue)
            bindText(statement, index: 4, value: merged.event_status.rawValue)
            bindText(statement, index: 5, value: merged.parse_status)
            bindText(statement, index: 6, value: merged.summary_status)
            bindText(statement, index: 7, value: merged.last_error_code?.rawValue)
            bindText(statement, index: 8, value: merged.last_error_message)
            bindText(statement, index: 9, value: document_id)
        }

        return try await fetchDocument(document_id: document_id)
    }

    public func saveDocumentText(document_id: String, record: ParsedTextRecord) async throws {
        let sql = """
        INSERT INTO document_texts (
            document_id, extracted_title, plain_text, page_count, parser_type,
            language_hint, text_length, extracted_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(document_id) DO UPDATE SET
            extracted_title = excluded.extracted_title,
            plain_text = excluded.plain_text,
            page_count = excluded.page_count,
            parser_type = excluded.parser_type,
            language_hint = excluded.language_hint,
            text_length = excluded.text_length,
            extracted_at = excluded.extracted_at;
        """

        try executePrepared(sql: sql) { statement in
            bindText(statement, index: 1, value: document_id)
            bindText(statement, index: 2, value: record.extracted_title)
            bindText(statement, index: 3, value: record.plain_text)
            if let pageCount = record.page_count {
                sqlite3_bind_int(statement, 4, Int32(pageCount))
            } else {
                sqlite3_bind_null(statement, 4)
            }
            bindText(statement, index: 5, value: record.parser_type)
            bindText(statement, index: 6, value: record.language_hint)
            sqlite3_bind_int(statement, 7, Int32(record.text_length))
            bindText(statement, index: 8, value: record.extracted_at)
        }
    }

    public func saveSummary(document_id: String, summary: SummaryProviderResponse, provider: ProviderConfig) async throws {
        let now = PipelineClock.nowString()
        let keyPointsJSONString = Self.encodeJSONString(summary.key_points)
        let keyPointsFlattened = summary.key_points.joined(separator: " ")
        let sql = """
        INSERT INTO document_summaries (
            document_id, document_type, one_line_summary, action_required,
            key_points_json, key_points_flattened, time_signals_json, location_signals_json,
            supporting_snippets_json, risk_flags_json, confidence,
            model_provider, model_name, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(document_id) DO UPDATE SET
            document_type = excluded.document_type,
            one_line_summary = excluded.one_line_summary,
            action_required = excluded.action_required,
            key_points_json = excluded.key_points_json,
            key_points_flattened = excluded.key_points_flattened,
            time_signals_json = excluded.time_signals_json,
            location_signals_json = excluded.location_signals_json,
            supporting_snippets_json = excluded.supporting_snippets_json,
            risk_flags_json = excluded.risk_flags_json,
            confidence = excluded.confidence,
            model_provider = excluded.model_provider,
            model_name = excluded.model_name,
            updated_at = excluded.updated_at;
        """

        try executePrepared(sql: sql) { statement in
            bindText(statement, index: 1, value: document_id)
            bindText(statement, index: 2, value: summary.document_type)
            bindText(statement, index: 3, value: summary.one_line_summary)
            bindText(statement, index: 4, value: summary.action_required)
            bindText(statement, index: 5, value: keyPointsJSONString)
            bindText(statement, index: 6, value: keyPointsFlattened)
            bindText(statement, index: 7, value: Self.encodeJSONString(summary.time_signals))
            bindText(statement, index: 8, value: Self.encodeJSONString(summary.location_signals))
            bindText(statement, index: 9, value: Self.encodeJSONString(summary.supporting_snippets))
            bindText(statement, index: 10, value: Self.encodeJSONString(summary.risk_flags))
            sqlite3_bind_double(statement, 11, summary.confidence)
            bindText(statement, index: 12, value: provider.provider_type.rawValue)
            bindText(statement, index: 13, value: provider.model_name)
            bindText(statement, index: 14, value: now)
            bindText(statement, index: 15, value: now)
        }
    }

    public func saveEvents(document_id: String, events newEvents: [EventCandidateResponse]) async throws {
        try withTransaction {
            let deleteSQL = "DELETE FROM document_events WHERE document_id = ?;"
            try executePrepared(sql: deleteSQL) { statement in
                bindText(statement, index: 1, value: document_id)
            }

            let insertSQL = """
            INSERT INTO document_events (
                id, document_id, event_type, title, start_time, end_time, raw_time_text,
                timezone, location, notes, evidence_snippet, confidence,
                calendar_eligible, decision_status, calendar_status,
                calendar_event_identifier, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """

            let now = PipelineClock.nowString()
            for candidate in newEvents {
                try executePrepared(sql: insertSQL) { statement in
                    bindText(statement, index: 1, value: "evt_\(UUID().uuidString.lowercased())")
                    bindText(statement, index: 2, value: document_id)
                    bindText(statement, index: 3, value: candidate.event_type)
                    bindText(statement, index: 4, value: candidate.title)
                    bindText(statement, index: 5, value: candidate.start_time)
                    bindText(statement, index: 6, value: candidate.end_time)
                    bindText(statement, index: 7, value: candidate.raw_time_text)
                    bindText(statement, index: 8, value: nil)
                    bindText(statement, index: 9, value: candidate.location)
                    bindText(statement, index: 10, value: candidate.notes)
                    bindText(statement, index: 11, value: candidate.evidence_snippet)
                    sqlite3_bind_double(statement, 12, candidate.confidence)
                    sqlite3_bind_int(statement, 13, candidate.calendar_eligible ? 1 : 0)
                    bindText(statement, index: 14, value: EventDecisionStatus.suggested.rawValue)
                    bindText(statement, index: 15, value: CalendarStatus.not_added.rawValue)
                    bindText(statement, index: 16, value: nil)
                    bindText(statement, index: 17, value: now)
                    bindText(statement, index: 18, value: now)
                }
            }
        }
    }

    public func createParseJob(_ input: ParseJobCreateInput) async throws -> ParseJobDTO {
        let id = "job_\(UUID().uuidString.lowercased())"
        let providerID = try existingProviderID(input.provider_id)
        let sql = """
        INSERT INTO parse_jobs (
            id, document_id, stage, status, provider_id,
            started_at, finished_at, duration_ms, error_code, error_message
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        try executePrepared(sql: sql) { statement in
            bindText(statement, index: 1, value: id)
            bindText(statement, index: 2, value: input.document_id)
            bindText(statement, index: 3, value: input.stage.rawValue)
            bindText(statement, index: 4, value: input.status.rawValue)
            bindText(statement, index: 5, value: providerID)
            bindText(statement, index: 6, value: input.started_at)
            bindText(statement, index: 7, value: input.finished_at)
            if let duration = input.duration_ms {
                sqlite3_bind_int(statement, 8, Int32(duration))
            } else {
                sqlite3_bind_null(statement, 8)
            }
            bindText(statement, index: 9, value: input.error_code?.rawValue)
            bindText(statement, index: 10, value: input.error_message)
        }

        guard let created = await fetchParseJob(job_id: id) else {
            throw SQLitePersistenceError.step(message: "parse job not found after insert", sql: sql)
        }
        return created
    }

    public func updateParseJob(_ input: ParseJobUpdateInput) async throws -> ParseJobDTO? {
        guard let current = await fetchParseJob(job_id: input.job_id) else {
            return nil
        }

        let sql = """
        UPDATE parse_jobs
        SET status = ?,
            finished_at = ?,
            duration_ms = ?,
            error_code = ?,
            error_message = ?
        WHERE id = ?;
        """

        try executePrepared(sql: sql) { statement in
            bindText(statement, index: 1, value: input.status.rawValue)
            bindText(statement, index: 2, value: input.finished_at ?? current.finished_at)
            if let duration = input.duration_ms ?? current.duration_ms {
                sqlite3_bind_int(statement, 3, Int32(duration))
            } else {
                sqlite3_bind_null(statement, 3)
            }
            bindText(statement, index: 4, value: input.error_code?.rawValue)
            bindText(statement, index: 5, value: input.error_message)
            bindText(statement, index: 6, value: input.job_id)
        }

        return await fetchParseJob(job_id: input.job_id)
    }

    public func fetchDocument(document_id: String) async throws -> DocumentDTO? {
        let sql = """
        SELECT id, watch_directory_id, file_name, file_extension, absolute_path, file_hash, file_size,
               imported_at, lifecycle_status, current_stage, block_reason, event_status,
               parse_status, summary_status, privacy_status, readiness_flags_json, importance_score,
               last_error_code, last_error_message
        FROM documents
        WHERE id = ?
        LIMIT 1;
        """

        return try querySingle(sql: sql, bind: { statement in
            self.bindText(statement, index: 1, value: document_id)
        }, map: Self.mapDocumentDTO)
    }

    public func fetchParseJobs(document_id: String) async throws -> [ParseJobDTO] {
        let sql = """
        SELECT id, document_id, stage, status, provider_id, started_at, finished_at,
               duration_ms, error_code, error_message
        FROM parse_jobs
        WHERE document_id = ?
        ORDER BY started_at DESC, id DESC;
        """

        return try queryMany(sql: sql, bind: { statement in
            self.bindText(statement, index: 1, value: document_id)
        }, map: Self.mapParseJobDTO)
    }

    public func listRecentDocuments(limit: Int) async -> [DocumentDTO] {
        let sql = """
        SELECT id, watch_directory_id, file_name, file_extension, absolute_path, file_hash, file_size,
               imported_at, lifecycle_status, current_stage, block_reason, event_status,
               parse_status, summary_status, privacy_status, readiness_flags_json, importance_score,
               last_error_code, last_error_message
        FROM documents
        ORDER BY imported_at DESC
        LIMIT ?;
        """

        return (try? queryMany(sql: sql, bind: { statement in
            sqlite3_bind_int(statement, 1, Int32(max(limit, 0)))
        }, map: Self.mapDocumentDTO)) ?? []
    }

    public func deleteDocument(document_id: String) async -> Bool {
        let sql = "DELETE FROM documents WHERE id = ?;"
        do {
            try executePrepared(sql: sql) { statement in
                bindText(statement, index: 1, value: document_id)
            }
            guard let db else {
                return false
            }
            return sqlite3_changes(db) > 0
        } catch {
            return false
        }
    }

    public func allDocumentTexts() async -> [String: ParsedTextRecord] {
        let sql = """
        SELECT document_id, extracted_title, plain_text, page_count, parser_type,
               language_hint, text_length, extracted_at
        FROM document_texts;
        """

        let records = (try? queryMany(sql: sql, bind: nil, map: Self.mapDocumentTextPair)) ?? []
        return Dictionary(uniqueKeysWithValues: records)
    }

    public func fetchDocumentText(document_id: String) async throws -> ParsedTextRecord? {
        let sql = """
        SELECT document_id, extracted_title, plain_text, page_count, parser_type,
               language_hint, text_length, extracted_at
        FROM document_texts
        WHERE document_id = ?
        LIMIT 1;
        """

        return try querySingle(sql: sql, bind: { statement in
            self.bindText(statement, index: 1, value: document_id)
        }, map: { statement in
            let (_, record) = Self.mapDocumentTextPair(statement)
            return record
        })
    }

    public func deleteDocumentText(document_id: String) async -> Bool {
        let sql = "DELETE FROM document_texts WHERE document_id = ?;"
        do {
            try executePrepared(sql: sql) { statement in
                bindText(statement, index: 1, value: document_id)
            }
            guard let db else {
                return false
            }
            return sqlite3_changes(db) > 0
        } catch {
            return false
        }
    }

    public func fetchSummary(document_id: String) async -> DocumentSummaryDTO? {
        let sql = """
        SELECT document_id, document_type, one_line_summary, action_required,
               key_points_json, time_signals_json, location_signals_json,
               supporting_snippets_json, risk_flags_json, confidence,
               model_provider, model_name, created_at, updated_at
        FROM document_summaries
        WHERE document_id = ?
        LIMIT 1;
        """

        return try? querySingle(sql: sql, bind: { statement in
            self.bindText(statement, index: 1, value: document_id)
        }, map: Self.mapDocumentSummaryDTO)
    }

    public func listRecentSummaries(limit: Int) async -> [DocumentSummaryDTO] {
        let sql = """
        SELECT document_id, document_type, one_line_summary, action_required,
               key_points_json, time_signals_json, location_signals_json,
               supporting_snippets_json, risk_flags_json, confidence,
               model_provider, model_name, created_at, updated_at
        FROM document_summaries
        ORDER BY updated_at DESC
        LIMIT ?;
        """

        return (try? queryMany(sql: sql, bind: { statement in
            sqlite3_bind_int(statement, 1, Int32(max(limit, 0)))
        }, map: Self.mapDocumentSummaryDTO)) ?? []
    }

    public func deleteSummary(document_id: String) async -> Bool {
        let sql = "DELETE FROM document_summaries WHERE document_id = ?;"
        do {
            try executePrepared(sql: sql) { statement in
                bindText(statement, index: 1, value: document_id)
            }
            guard let db else {
                return false
            }
            return sqlite3_changes(db) > 0
        } catch {
            return false
        }
    }

    public func fetchEvents(document_id: String) async -> [DocumentEventDTO] {
        let sql = """
        SELECT id, document_id, event_type, title, start_time, end_time, raw_time_text,
               timezone, location, notes, evidence_snippet, confidence,
               calendar_eligible, decision_status, calendar_status,
               calendar_event_identifier, created_at, updated_at
        FROM document_events
        WHERE document_id = ?
        ORDER BY updated_at DESC, id DESC;
        """

        return (try? queryMany(sql: sql, bind: { statement in
            self.bindText(statement, index: 1, value: document_id)
        }, map: Self.mapDocumentEventDTO)) ?? []
    }

    public func listRecentEvents(limit: Int) async -> [DocumentEventDTO] {
        let sql = """
        SELECT id, document_id, event_type, title, start_time, end_time, raw_time_text,
               timezone, location, notes, evidence_snippet, confidence,
               calendar_eligible, decision_status, calendar_status,
               calendar_event_identifier, created_at, updated_at
        FROM document_events
        ORDER BY updated_at DESC, id DESC
        LIMIT ?;
        """

        return (try? queryMany(sql: sql, bind: { statement in
            sqlite3_bind_int(statement, 1, Int32(max(limit, 0)))
        }, map: Self.mapDocumentEventDTO)) ?? []
    }

    public func upsertEvent(_ event: DocumentEventDTO) async {
        let sql = """
        INSERT INTO document_events (
            id, document_id, event_type, title, start_time, end_time, raw_time_text,
            timezone, location, notes, evidence_snippet, confidence,
            calendar_eligible, decision_status, calendar_status,
            calendar_event_identifier, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            event_type = excluded.event_type,
            title = excluded.title,
            start_time = excluded.start_time,
            end_time = excluded.end_time,
            raw_time_text = excluded.raw_time_text,
            timezone = excluded.timezone,
            location = excluded.location,
            notes = excluded.notes,
            evidence_snippet = excluded.evidence_snippet,
            confidence = excluded.confidence,
            calendar_eligible = excluded.calendar_eligible,
            decision_status = excluded.decision_status,
            calendar_status = excluded.calendar_status,
            calendar_event_identifier = excluded.calendar_event_identifier,
            updated_at = excluded.updated_at;
        """

        try? executePrepared(sql: sql) { statement in
            bindText(statement, index: 1, value: event.id)
            bindText(statement, index: 2, value: event.document_id)
            bindText(statement, index: 3, value: event.event_type)
            bindText(statement, index: 4, value: event.title)
            bindText(statement, index: 5, value: event.start_time)
            bindText(statement, index: 6, value: event.end_time)
            bindText(statement, index: 7, value: event.raw_time_text)
            bindText(statement, index: 8, value: event.timezone)
            bindText(statement, index: 9, value: event.location)
            bindText(statement, index: 10, value: event.notes)
            bindText(statement, index: 11, value: event.evidence_snippet)
            sqlite3_bind_double(statement, 12, event.confidence)
            sqlite3_bind_int(statement, 13, event.calendar_eligible ? 1 : 0)
            bindText(statement, index: 14, value: event.decision_status.rawValue)
            bindText(statement, index: 15, value: event.calendar_status.rawValue)
            bindText(statement, index: 16, value: event.calendar_event_identifier)
            bindText(statement, index: 17, value: event.created_at)
            bindText(statement, index: 18, value: event.updated_at)
        }
    }

    public func deleteEvent(event_id: String) async -> Bool {
        let sql = "DELETE FROM document_events WHERE id = ?;"
        do {
            try executePrepared(sql: sql) { statement in
                bindText(statement, index: 1, value: event_id)
            }
            guard let db else {
                return false
            }
            return sqlite3_changes(db) > 0
        } catch {
            return false
        }
    }

    public func saveDocumentChunk(document_id: String, chunk_index: Int, content: String, content_preview: String, char_count: Int) async throws {
        let chunkID = "\(document_id)_chunk_\(chunk_index)"
        let sql = """
        INSERT INTO document_chunks (id, document_id, chunk_index, content, content_preview, char_count, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            content = excluded.content,
            content_preview = excluded.content_preview,
            char_count = excluded.char_count;
        """

        try executePrepared(sql: sql) { statement in
            bindText(statement, index: 1, value: chunkID)
            bindText(statement, index: 2, value: document_id)
            sqlite3_bind_int(statement, 3, Int32(chunk_index))
            bindText(statement, index: 4, value: content)
            bindText(statement, index: 5, value: content_preview)
            sqlite3_bind_int(statement, 6, Int32(char_count))
            bindText(statement, index: 7, value: PipelineClock.nowString())
        }
    }

    public func searchChunks(query: String, limit: Int) async throws -> [ChunkSearchResult] {
        let ftsQuery = """
        SELECT dc.id, dc.document_id, dc.chunk_index, dc.content, dc.content_preview, dc.char_count
        FROM document_chunks_fts fts
        JOIN document_chunks dc ON dc.rowid = fts.rowid
        WHERE document_chunks_fts MATCH ?
        ORDER BY rank
        LIMIT ?;
        """

        return try queryMany(sql: ftsQuery, bind: { [self] statement in
            self.bindText(statement, index: 1, value: query)
            sqlite3_bind_int(statement, 2, Int32(max(limit, 0)))
        }, map: Self.mapChunkSearchResult)
    }

    public func listRecentParseJobs(limit: Int) async -> [ParseJobDTO] {
        let sql = """
        SELECT id, document_id, stage, status, provider_id, started_at, finished_at,
               duration_ms, error_code, error_message
        FROM parse_jobs
        ORDER BY started_at DESC, id DESC
        LIMIT ?;
        """

        return (try? queryMany(sql: sql, bind: { statement in
            sqlite3_bind_int(statement, 1, Int32(max(limit, 0)))
        }, map: Self.mapParseJobDTO)) ?? []
    }

    public func fetchParseJob(job_id: String) async -> ParseJobDTO? {
        let sql = """
        SELECT id, document_id, stage, status, provider_id, started_at, finished_at,
               duration_ms, error_code, error_message
        FROM parse_jobs
        WHERE id = ?
        LIMIT 1;
        """

        return try? querySingle(sql: sql, bind: { statement in
            self.bindText(statement, index: 1, value: job_id)
        }, map: Self.mapParseJobDTO)
    }

    public func deleteParseJob(job_id: String) async -> Bool {
        let sql = "DELETE FROM parse_jobs WHERE id = ?;"
        do {
            try executePrepared(sql: sql) { statement in
                bindText(statement, index: 1, value: job_id)
            }
            guard let db else {
                return false
            }
            return sqlite3_changes(db) > 0
        } catch {
            return false
        }
    }

    private func withTransaction(_ operation: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE;")
        do {
            try operation()
            try execute("COMMIT;")
        } catch {
            _ = try? execute("ROLLBACK;")
            throw SQLitePersistenceError.transaction(message: error.localizedDescription)
        }
    }

    private func execute(_ sql: String) throws {
        guard let db else {
            throw SQLitePersistenceError.openDatabase(message: "database is closed")
        }

        var errorMessagePointer: UnsafeMutablePointer<Int8>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorMessagePointer)
        guard result == SQLITE_OK else {
            let message = errorMessagePointer.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(db))
            if let errorMessagePointer {
                sqlite3_free(errorMessagePointer)
            }
            throw SQLitePersistenceError.step(message: message, sql: sql)
        }
    }

    private func executePrepared(sql: String, bind: (OpaquePointer) -> Void) throws {
        guard let db else {
            throw SQLitePersistenceError.openDatabase(message: "database is closed")
        }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLitePersistenceError.prepare(message: String(cString: sqlite3_errmsg(db)), sql: sql)
        }

        defer {
            sqlite3_finalize(statement)
        }

        bind(statement)
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE || result == SQLITE_ROW else {
            throw SQLitePersistenceError.step(message: String(cString: sqlite3_errmsg(db)), sql: sql)
        }
    }

    private func querySingle<T>(
        sql: String,
        bind: ((OpaquePointer) -> Void)?,
        map: (OpaquePointer) throws -> T
    ) throws -> T? {
        guard let db else {
            throw SQLitePersistenceError.openDatabase(message: "database is closed")
        }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLitePersistenceError.prepare(message: String(cString: sqlite3_errmsg(db)), sql: sql)
        }

        defer {
            sqlite3_finalize(statement)
        }

        bind?(statement)
        let step = sqlite3_step(statement)
        if step == SQLITE_DONE {
            return nil
        }
        guard step == SQLITE_ROW else {
            throw SQLitePersistenceError.step(message: String(cString: sqlite3_errmsg(db)), sql: sql)
        }

        return try map(statement)
    }

    private func queryMany<T>(
        sql: String,
        bind: ((OpaquePointer) -> Void)?,
        map: (OpaquePointer) throws -> T
    ) throws -> [T] {
        guard let db else {
            throw SQLitePersistenceError.openDatabase(message: "database is closed")
        }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLitePersistenceError.prepare(message: String(cString: sqlite3_errmsg(db)), sql: sql)
        }

        defer {
            sqlite3_finalize(statement)
        }

        bind?(statement)

        var items: [T] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE {
                break
            }
            guard step == SQLITE_ROW else {
                throw SQLitePersistenceError.step(message: String(cString: sqlite3_errmsg(db)), sql: sql)
            }
            items.append(try map(statement))
        }

        return items
    }

    private static func openDatabase(at path: String) throws -> OpaquePointer {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(path, &db, flags, nil)
        guard result == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            if let db {
                sqlite3_close(db)
            }
            throw SQLitePersistenceError.openDatabase(message: message)
        }
        return db
    }

    private static func executeRaw(_ sql: String, on db: OpaquePointer) throws {
        var errorMessagePointer: UnsafeMutablePointer<Int8>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorMessagePointer)
        guard result == SQLITE_OK else {
            let message = errorMessagePointer.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(db))
            if let errorMessagePointer {
                sqlite3_free(errorMessagePointer)
            }
            throw SQLitePersistenceError.step(message: message, sql: sql)
        }
    }

    private func existingProviderID(_ providerID: String?) throws -> String? {
        guard let providerID else {
            return nil
        }

        let sql = "SELECT 1 FROM providers WHERE id = ? LIMIT 1;"
        let exists = try querySingle(sql: sql, bind: { statement in
            self.bindText(statement, index: 1, value: providerID)
        }, map: { _ in true })

        return exists == true ? providerID : nil
    }

    private func bindText(_ statement: OpaquePointer, index: Int32, value: String?) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_text(statement, index, (value as NSString).utf8String, -1, Self.sqliteTransient)
    }

    private static func textColumn(_ statement: OpaquePointer, index: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: pointer)
    }

    private static func mapDocumentDTO(_ statement: OpaquePointer) throws -> DocumentDTO {
        let lifecycleRaw = textColumn(statement, index: 8) ?? DocumentLifecycleStatus.unknown.rawValue
        let stageRaw = textColumn(statement, index: 9) ?? DocumentStage.unknown.rawValue
        let blockReasonRaw = textColumn(statement, index: 10) ?? BlockReason.unknown.rawValue
        let eventStatusRaw = textColumn(statement, index: 11) ?? DocumentEventStatus.unknown.rawValue
        let errorCodeRaw = textColumn(statement, index: 17)

        return DocumentDTO(
            id: textColumn(statement, index: 0) ?? "",
            watch_directory_id: textColumn(statement, index: 1),
            file_name: textColumn(statement, index: 2) ?? "",
            file_extension: textColumn(statement, index: 3) ?? "",
            absolute_path: textColumn(statement, index: 4) ?? "",
            file_hash: textColumn(statement, index: 5) ?? "",
            file_size: Int64(sqlite3_column_int64(statement, 6)),
            imported_at: textColumn(statement, index: 7) ?? "",
            lifecycle_status: DocumentLifecycleStatus(rawValue: lifecycleRaw) ?? .unknown,
            current_stage: DocumentStage(rawValue: stageRaw) ?? .unknown,
            block_reason: BlockReason(rawValue: blockReasonRaw) ?? .unknown,
            event_status: DocumentEventStatus(rawValue: eventStatusRaw) ?? .unknown,
            parse_status: textColumn(statement, index: 12),
            summary_status: textColumn(statement, index: 13),
            privacy_status: textColumn(statement, index: 14),
            readiness_flags_json: textColumn(statement, index: 15) ?? "{}",
            importance_score: sqlite3_column_double(statement, 16),
            last_error_code: errorCodeRaw.map { ErrorCode(rawValue: $0) ?? .unknown },
            last_error_message: textColumn(statement, index: 18)
        )
    }

    private static func mapDocumentTextPair(_ statement: OpaquePointer) -> (String, ParsedTextRecord) {
        let documentID = textColumn(statement, index: 0) ?? ""
        let pageCount = sqlite3_column_type(statement, 3) == SQLITE_NULL ? nil : Int(sqlite3_column_int(statement, 3))
        let record = ParsedTextRecord(
            extracted_title: textColumn(statement, index: 1),
            plain_text: textColumn(statement, index: 2) ?? "",
            page_count: pageCount,
            parser_type: textColumn(statement, index: 4) ?? "",
            language_hint: textColumn(statement, index: 5),
            text_length: Int(sqlite3_column_int(statement, 6)),
            extracted_at: textColumn(statement, index: 7) ?? ""
        )
        return (documentID, record)
    }

    private static func mapDocumentSummaryDTO(_ statement: OpaquePointer) -> DocumentSummaryDTO {
        DocumentSummaryDTO(
            document_id: textColumn(statement, index: 0) ?? "",
            document_type: textColumn(statement, index: 1) ?? "",
            one_line_summary: textColumn(statement, index: 2) ?? "",
            action_required: textColumn(statement, index: 3) ?? "",
            key_points_json: textColumn(statement, index: 4) ?? "[]",
            time_signals_json: textColumn(statement, index: 5) ?? "[]",
            location_signals_json: textColumn(statement, index: 6) ?? "[]",
            supporting_snippets_json: textColumn(statement, index: 7) ?? "[]",
            risk_flags_json: textColumn(statement, index: 8) ?? "[]",
            confidence: sqlite3_column_double(statement, 9),
            model_provider: textColumn(statement, index: 10) ?? "",
            model_name: textColumn(statement, index: 11) ?? "",
            created_at: textColumn(statement, index: 12) ?? "",
            updated_at: textColumn(statement, index: 13) ?? ""
        )
    }

    private static func mapDocumentEventDTO(_ statement: OpaquePointer) -> DocumentEventDTO {
        let decisionRaw = textColumn(statement, index: 13) ?? EventDecisionStatus.unknown.rawValue
        let calendarRaw = textColumn(statement, index: 14) ?? CalendarStatus.unknown.rawValue

        return DocumentEventDTO(
            id: textColumn(statement, index: 0) ?? "",
            document_id: textColumn(statement, index: 1) ?? "",
            event_type: textColumn(statement, index: 2) ?? "",
            title: textColumn(statement, index: 3) ?? "",
            start_time: textColumn(statement, index: 4),
            end_time: textColumn(statement, index: 5),
            raw_time_text: textColumn(statement, index: 6) ?? "",
            timezone: textColumn(statement, index: 7),
            location: textColumn(statement, index: 8),
            notes: textColumn(statement, index: 9),
            evidence_snippet: textColumn(statement, index: 10) ?? "",
            confidence: sqlite3_column_double(statement, 11),
            calendar_eligible: sqlite3_column_int(statement, 12) == 1,
            decision_status: EventDecisionStatus(rawValue: decisionRaw) ?? .unknown,
            calendar_status: CalendarStatus(rawValue: calendarRaw) ?? .unknown,
            calendar_event_identifier: textColumn(statement, index: 15),
            created_at: textColumn(statement, index: 16) ?? "",
            updated_at: textColumn(statement, index: 17) ?? ""
        )
    }

    private static func mapParseJobDTO(_ statement: OpaquePointer) -> ParseJobDTO {
        let stageRaw = textColumn(statement, index: 2) ?? DocumentStage.unknown.rawValue
        let statusRaw = textColumn(statement, index: 3) ?? ParseJobStatus.unknown.rawValue
        let duration = sqlite3_column_type(statement, 7) == SQLITE_NULL ? nil : Int(sqlite3_column_int(statement, 7))
        let errorCode = textColumn(statement, index: 8).map { ErrorCode(rawValue: $0) ?? .unknown }

        return ParseJobDTO(
            id: textColumn(statement, index: 0) ?? "",
            document_id: textColumn(statement, index: 1) ?? "",
            stage: DocumentStage(rawValue: stageRaw) ?? .unknown,
            status: ParseJobStatus(rawValue: statusRaw) ?? .unknown,
            provider_id: textColumn(statement, index: 4),
            started_at: textColumn(statement, index: 5),
            finished_at: textColumn(statement, index: 6),
            duration_ms: duration,
            error_code: errorCode,
            error_message: textColumn(statement, index: 9)
        )
    }

    private static func mapChunkSearchResult(_ statement: OpaquePointer) -> ChunkSearchResult {
        ChunkSearchResult(
            chunk_id: textColumn(statement, index: 0) ?? "",
            document_id: textColumn(statement, index: 1) ?? "",
            chunk_index: Int(sqlite3_column_int(statement, 2)),
            content: textColumn(statement, index: 3) ?? "",
            content_preview: textColumn(statement, index: 4) ?? "",
            char_count: Int(sqlite3_column_int(statement, 5))
        )
    }

    private static func encodeJSONString<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return text
    }
}
