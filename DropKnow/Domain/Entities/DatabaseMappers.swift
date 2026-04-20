import Foundation

public enum DatabaseRowMapper {
    public static func toDTO(_ row: DocumentRow) -> DocumentDTO {
        DocumentDTO(
            id: row.id,
            watch_directory_id: row.watch_directory_id,
            file_name: row.file_name,
            file_extension: row.file_extension,
            absolute_path: row.absolute_path,
            file_hash: row.file_hash,
            file_size: row.file_size,
            imported_at: row.imported_at,
            lifecycle_status: DocumentLifecycleStatus(databaseValue: row.lifecycle_status),
            current_stage: DocumentStage(databaseValue: row.current_stage),
            block_reason: BlockReason(databaseValue: row.block_reason),
            event_status: DocumentEventStatus(databaseValue: row.event_status),
            parse_status: row.parse_status,
            summary_status: row.summary_status,
            privacy_status: row.privacy_status,
            readiness_flags_json: row.readiness_flags_json,
            importance_score: row.importance_score,
            last_error_code: row.last_error_code.map { ErrorCode(databaseValue: $0) },
            last_error_message: row.last_error_message
        )
    }

    public static func toDTO(_ row: DocumentSummaryRow) -> DocumentSummaryDTO {
        DocumentSummaryDTO(
            document_id: row.document_id,
            document_type: row.document_type,
            one_line_summary: row.one_line_summary,
            action_required: row.action_required,
            key_points_json: row.key_points_json,
            time_signals_json: row.time_signals_json,
            location_signals_json: row.location_signals_json,
            supporting_snippets_json: row.supporting_snippets_json,
            risk_flags_json: row.risk_flags_json,
            confidence: row.confidence,
            model_provider: row.model_provider,
            model_name: row.model_name,
            created_at: row.created_at,
            updated_at: row.updated_at
        )
    }

    public static func toDTO(_ row: DocumentEventRow) -> DocumentEventDTO {
        DocumentEventDTO(
            id: row.id,
            document_id: row.document_id,
            event_type: row.event_type,
            title: row.title,
            start_time: row.start_time,
            end_time: row.end_time,
            raw_time_text: row.raw_time_text,
            timezone: row.timezone,
            location: row.location,
            notes: row.notes,
            evidence_snippet: row.evidence_snippet,
            confidence: row.confidence,
            calendar_eligible: row.calendar_eligible == 1,
            decision_status: EventDecisionStatus(databaseValue: row.decision_status),
            calendar_status: CalendarStatus(databaseValue: row.calendar_status),
            calendar_event_identifier: row.calendar_event_identifier,
            created_at: row.created_at,
            updated_at: row.updated_at
        )
    }

    public static func toDTO(_ row: ParseJobRow) -> ParseJobDTO {
        ParseJobDTO(
            id: row.id,
            document_id: row.document_id,
            stage: DocumentStage(databaseValue: row.stage),
            status: ParseJobStatus(databaseValue: row.status),
            provider_id: row.provider_id,
            started_at: row.started_at,
            finished_at: row.finished_at,
            duration_ms: row.duration_ms,
            error_code: row.error_code.map { ErrorCode(databaseValue: $0) },
            error_message: row.error_message
        )
    }

    public static func toDomain(_ dto: DocumentDTO) -> Document {
        Document(
            id: dto.id,
            watchDirectoryID: dto.watch_directory_id,
            fileName: dto.file_name,
            fileExtension: dto.file_extension,
            absolutePath: dto.absolute_path,
            fileHash: dto.file_hash,
            fileSize: dto.file_size,
            importedAt: dto.imported_at,
            lifecycleStatus: dto.lifecycle_status,
            currentStage: dto.current_stage,
            blockReason: dto.block_reason,
            eventStatus: dto.event_status,
            parseStatus: dto.parse_status,
            summaryStatus: dto.summary_status,
            privacyStatus: dto.privacy_status,
            readinessFlagsJSON: dto.readiness_flags_json,
            importanceScore: dto.importance_score,
            lastErrorCode: dto.last_error_code,
            lastErrorMessage: dto.last_error_message
        )
    }

    public static func toDomain(_ dto: DocumentSummaryDTO) -> DocumentSummary {
        DocumentSummary(
            documentID: dto.document_id,
            documentType: dto.document_type,
            oneLineSummary: dto.one_line_summary,
            actionRequired: dto.action_required,
            keyPointsJSON: dto.key_points_json,
            timeSignalsJSON: dto.time_signals_json,
            locationSignalsJSON: dto.location_signals_json,
            supportingSnippetsJSON: dto.supporting_snippets_json,
            riskFlagsJSON: dto.risk_flags_json,
            confidence: dto.confidence,
            modelProvider: dto.model_provider,
            modelName: dto.model_name,
            createdAt: dto.created_at,
            updatedAt: dto.updated_at
        )
    }

    public static func toDomain(_ dto: DocumentEventDTO) -> DocumentEvent {
        DocumentEvent(
            id: dto.id,
            documentID: dto.document_id,
            eventType: dto.event_type,
            title: dto.title,
            startTime: dto.start_time,
            endTime: dto.end_time,
            rawTimeText: dto.raw_time_text,
            timezone: dto.timezone,
            location: dto.location,
            notes: dto.notes,
            evidenceSnippet: dto.evidence_snippet,
            confidence: dto.confidence,
            calendarEligible: dto.calendar_eligible,
            decisionStatus: dto.decision_status,
            calendarStatus: dto.calendar_status,
            calendarEventIdentifier: dto.calendar_event_identifier,
            createdAt: dto.created_at,
            updatedAt: dto.updated_at
        )
    }

    public static func toDomain(_ dto: ParseJobDTO) -> ParseJob {
        ParseJob(
            id: dto.id,
            documentID: dto.document_id,
            stage: dto.stage,
            status: dto.status,
            providerID: dto.provider_id,
            startedAt: dto.started_at,
            finishedAt: dto.finished_at,
            durationMS: dto.duration_ms,
            errorCode: dto.error_code,
            errorMessage: dto.error_message
        )
    }
}
