import Foundation

public actor IngestionCoordinator {
    private let persistence: any IngestionPersistence
    private let stabilityDetector: any FileStabilityDetecting
    private let fingerprintService: any FileFingerprinting
    private let parsingService: any DocumentParsing
    private let privacyGate: any PrivacyGateChecking
    private let summarizationService: any DocumentSummarizing
    private let eventExtractionService: any DocumentEventExtracting
    private let eventPublisher: any PipelineEventPublishing

    private let summaryProviderID: String
    private let eventProviderID: String
    private var interruptedDocumentIDs: Set<String> = []

    public init(
        persistence: any IngestionPersistence,
        stabilityDetector: any FileStabilityDetecting,
        fingerprintService: any FileFingerprinting,
        parsingService: any DocumentParsing,
        privacyGate: any PrivacyGateChecking,
        summarizationService: any DocumentSummarizing,
        eventExtractionService: any DocumentEventExtracting,
        eventPublisher: any PipelineEventPublishing,
        summaryProviderID: String,
        eventProviderID: String
    ) {
        self.persistence = persistence
        self.stabilityDetector = stabilityDetector
        self.fingerprintService = fingerprintService
        self.parsingService = parsingService
        self.privacyGate = privacyGate
        self.summarizationService = summarizationService
        self.eventExtractionService = eventExtractionService
        self.eventPublisher = eventPublisher
        self.summaryProviderID = summaryProviderID
        self.eventProviderID = eventProviderID
    }

    public func ingest(_ request: IngestionRequest) async -> IngestionResult {
        do {
            let stableMetadata = try await stabilityDetector.waitUntilStable(file_url: request.file_url)
            let fingerprint = try await fingerprintService.fingerprint(file_url: request.file_url, metadata: stableMetadata)

            if let duplicate = try await persistence.findDuplicateDocument(
                file_hash: fingerprint.file_hash,
                file_size: fingerprint.file_size,
                modified_at_fs: fingerprint.modified_at_fs
            ) {
                return .duplicate(existing_document_id: duplicate.id)
            }

            let newDocument = try await persistence.createDocument(
                NewDocumentInput(
                    watch_directory_id: request.watch_directory_id,
                    file_name: request.file_url.lastPathComponent,
                    file_extension: request.file_url.pathExtension.lowercased(),
                    absolute_path: request.file_url.path,
                    file_hash: fingerprint.file_hash,
                    file_size: fingerprint.file_size,
                    created_at_fs: stableMetadata.created_at_fs,
                    modified_at_fs: stableMetadata.modified_at_fs,
                    imported_at: PipelineClock.nowString(),
                    source_type: request.source_type
                )
            )

            let documentID = newDocument.id
            interruptedDocumentIDs.remove(documentID)
        eventPublisher.publish(.document_updated(document_id: documentID))
            return try await processPipeline(document_id: documentID, request: request, start_stage: .import)
        } catch let pipelineError as IngestionPipelineError {
            return await handleTopLevelPipelineError(pipelineError)
        } catch {
            return .failed(document_id: nil, error_code: .db_write_failed)
        }
    }

    public func requestInterruption(document_id: String) {
        interruptedDocumentIDs.insert(document_id)
    }

    public func clearInterruption(document_id: String) {
        interruptedDocumentIDs.remove(document_id)
    }

    public func recover(document_id: String, request: IngestionRequest) async -> IngestionResult {
        do {
            guard let existing = try await persistence.fetchDocument(document_id: document_id) else {
                return .failed(document_id: document_id, error_code: .db_read_failed)
            }

            interruptedDocumentIDs.remove(document_id)
            let startStage = normalizedRecoveryStage(for: existing.current_stage)
            if startStage == .done {
                return .ready(document_id: document_id)
            }

            return try await processPipeline(document_id: document_id, request: request, start_stage: startStage)
        } catch let pipelineError as IngestionPipelineError {
            return await handleTopLevelPipelineError(pipelineError)
        } catch {
            return .failed(document_id: document_id, error_code: .db_read_failed)
        }
    }

    private func processPipeline(
        document_id: String,
        request: IngestionRequest,
        start_stage: DocumentStage
    ) async throws -> IngestionResult {
        let startRank = stageRank(start_stage)

        if startRank <= stageRank(.import) {
            let importResult = try await runImportStage(document_id: document_id)
            if case .stop(let result) = importResult {
                return result
            }
        }

        var parsedOutput: ParsedFileOutput?
        if startRank <= stageRank(.event_extract) {
            let parseResult = try await runParseStage(document_id: document_id, request: request)
            switch parseResult {
            case .parsed(let parsed):
                parsedOutput = parsed
            case .terminal(let result):
                return result
            }
        }

        if startRank <= stageRank(.gate) {
            guard let parsedOutput else {
                throw IngestionPipelineError.storage_failed(message: "missing parsed output for gate stage")
            }

            let gateResult = try await runGateStage(document_id: document_id, request: request, parsed: parsedOutput)
            if case .stop(let result) = gateResult {
                return result
            }
        }

        if startRank <= stageRank(.summary) {
            guard let parsedOutput else {
                throw IngestionPipelineError.storage_failed(message: "missing parsed output for summary stage")
            }

            let summaryResult = try await runSummaryStage(document_id: document_id, request: request, parsed: parsedOutput)
            if case .stop(let result) = summaryResult {
                return result
            }
        }

        if startRank <= stageRank(.event_extract) {
            guard let parsedOutput else {
                throw IngestionPipelineError.storage_failed(message: "missing parsed output for event stage")
            }

            let eventsResult = try await runEventExtractionStage(document_id: document_id, request: request, parsed: parsedOutput)
            if case .stop(let result) = eventsResult {
                return result
            }
        }

        if startRank <= stageRank(.index) {
            _ = try await runIndexStage(document_id: document_id)
        }

        if startRank <= stageRank(.notify) {
            _ = try await runNotifyStage(document_id: document_id, source_type: request.source_type)
        }

        return try await finalizeDocumentReady(document_id: document_id)
    }

    private func finalizeDocumentReady(document_id: String) async throws -> IngestionResult {
        _ = try await persistence.updateDocument(
            document_id: document_id,
            update: DocumentPipelineUpdate(
                lifecycle_status: .ready,
                current_stage: .done,
                block_reason: BlockReason.none,
                last_error_code: nil,
                last_error_message: nil
            )
        )

        interruptedDocumentIDs.remove(document_id)
        eventPublisher.publish(.document_updated(document_id: document_id))
        eventPublisher.publish(.ingestion_finished(document_id: document_id))
        return .ready(document_id: document_id)
    }

    private func normalizedRecoveryStage(for stage: DocumentStage) -> DocumentStage {
        switch stage {
        case .index, .notify, .done:
            return stage
        case .unknown:
            return .import
        case .import, .parse, .gate, .summary, .event_extract:
            return .parse
        }
    }

    private func stageRank(_ stage: DocumentStage) -> Int {
        switch stage {
        case .import:
            return 0
        case .parse:
            return 1
        case .gate:
            return 2
        case .summary:
            return 3
        case .event_extract:
            return 4
        case .index:
            return 5
        case .notify:
            return 6
        case .done:
            return 7
        case .unknown:
            return 0
        }
    }

    private func runImportStage(document_id: String) async throws -> IngestionBranch {
        let handle = try await beginStage(document_id: document_id, stage: .import, provider_id: nil)
        try await completeStageSuccess(handle)
        return .proceed
    }

    private func runParseStage(document_id: String, request: IngestionRequest) async throws -> ParseStageOutcome {
        let handle = try await beginStage(document_id: document_id, stage: .parse, provider_id: nil)
        do {
            let parsed = try await parsingService.parse(file_url: request.file_url)
            try await persistence.saveDocumentText(
                document_id: document_id,
                record: ParsedTextRecord(
                    extracted_title: parsed.extracted_title,
                    plain_text: parsed.plain_text,
                    page_count: parsed.page_count,
                    parser_type: parsed.parser_type,
                    language_hint: parsed.language_hint,
                    text_length: parsed.plain_text.count,
                    extracted_at: PipelineClock.nowString()
                )
            )

            _ = try await persistence.updateDocument(
                document_id: document_id,
                update: DocumentPipelineUpdate(
                    parse_status: "success",
                    last_error_code: nil,
                    last_error_message: nil
                )
            )

            try await completeStageSuccess(handle)
            return .parsed(parsed)
        } catch {
            let code = mapParseErrorCode(file_url: request.file_url, error: error)
            let isUnsupported = code == .parse_unsupported_type
            _ = try await persistence.updateDocument(
                document_id: document_id,
                update: DocumentPipelineUpdate(
                    lifecycle_status: .blocked,
                    current_stage: .parse,
                    block_reason: .unsupported_type,
                    parse_status: code == .parse_unsupported_type ? "unsupported" : "failed",
                    last_error_code: code,
                    last_error_message: String(describing: error)
                )
            )
            try await completeStageFailure(handle, error_code: code, message: String(describing: error))
            try await markStagesSkipped(
                document_id: document_id,
                stages: [.gate, .summary, .event_extract, .index, .notify],
                error_code: code,
                error_message: "pipeline stopped after parse failure"
            )
            eventPublisher.publish(.ingestion_failed(document_id: document_id, error_code: code))
            if isUnsupported {
                return .terminal(.unsupported_file(document_id: document_id))
            }
            return .terminal(.failed(document_id: document_id, error_code: code))
        }
    }

    private func runGateStage(
        document_id: String,
        request: IngestionRequest,
        parsed: ParsedFileOutput
    ) async throws -> IngestionBranch {
        let handle = try await beginStage(document_id: document_id, stage: .gate, provider_id: nil)

        let decision = await privacyGate.evaluate(
            plain_text: parsed.plain_text,
            reference_date: request.reference_date,
            requires_manual_confirmation: false
        )

        switch decision {
        case .allow:
            try await completeStageSuccess(handle)
            return .proceed

        case .requires_confirmation:
            try await completeStageSuccess(handle, error_code: .gate_sensitive_confirmation_required, message: "waiting user confirmation")
            _ = try await persistence.updateDocument(
                document_id: document_id,
                update: DocumentPipelineUpdate(
                    lifecycle_status: .waiting_user_confirmation,
                    current_stage: .gate,
                    block_reason: .privacy_confirmation_required,
                    last_error_code: .gate_sensitive_confirmation_required,
                    last_error_message: "requires user confirmation"
                )
            )
            try await markStagesSkipped(
                document_id: document_id,
                stages: [.summary, .event_extract, .index, .notify],
                error_code: .gate_sensitive_confirmation_required,
                error_message: "waiting user confirmation"
            )
            eventPublisher.publish(.document_updated(document_id: document_id))
            return .stop(.waiting_user_confirmation(document_id: document_id))

        case .blocked_policy:
            try await completeStageFailure(handle, error_code: .gate_policy_blocked, message: "blocked by policy")
            _ = try await persistence.updateDocument(
                document_id: document_id,
                update: DocumentPipelineUpdate(
                    lifecycle_status: .blocked,
                    current_stage: .gate,
                    block_reason: .policy_blocked,
                    last_error_code: .gate_policy_blocked,
                    last_error_message: "blocked by policy"
                )
            )
            try await markStagesSkipped(
                document_id: document_id,
                stages: [.summary, .event_extract, .index, .notify],
                error_code: .gate_policy_blocked,
                error_message: "policy blocked"
            )
            eventPublisher.publish(.ingestion_failed(document_id: document_id, error_code: .gate_policy_blocked))
            return .stop(.failed(document_id: document_id, error_code: .gate_policy_blocked))

        case .blocked_quota:
            try await completeStageFailure(handle, error_code: .quota_parse_exceeded, message: "quota exceeded")
            _ = try await persistence.updateDocument(
                document_id: document_id,
                update: DocumentPipelineUpdate(
                    lifecycle_status: .blocked,
                    current_stage: .gate,
                    block_reason: .quota_exceeded,
                    last_error_code: .quota_parse_exceeded,
                    last_error_message: "parse quota exceeded"
                )
            )
            try await markStagesSkipped(
                document_id: document_id,
                stages: [.summary, .event_extract, .index, .notify],
                error_code: .quota_parse_exceeded,
                error_message: "quota blocked"
            )
            eventPublisher.publish(.ingestion_failed(document_id: document_id, error_code: .quota_parse_exceeded))
            return .stop(.quota_blocked(document_id: document_id))
        }
    }

    private func runSummaryStage(
        document_id: String,
        request: IngestionRequest,
        parsed: ParsedFileOutput
    ) async throws -> IngestionBranch {
        let handle = try await beginStage(document_id: document_id, stage: .summary, provider_id: summaryProviderID)

        do {
            let response = try await summarizationService.summarize(
                context: ProviderDocumentContextRequest(
                    document_id: document_id,
                    file_name: request.file_url.lastPathComponent,
                    file_extension: request.file_url.pathExtension.lowercased(),
                    reference_date: request.reference_date,
                    user_timezone: request.user_timezone,
                    plain_text: parsed.plain_text,
                    language_hint: parsed.language_hint
                )
            )

            let providerConfig = ProviderConfig(
                provider_id: summaryProviderID,
                provider_type: .qwen,
                model_name: "mock",
                base_url: "mock://summary"
            )
            try await persistence.saveSummary(document_id: document_id, summary: response, provider: providerConfig)
            _ = try await persistence.updateDocument(
                document_id: document_id,
                update: DocumentPipelineUpdate(summary_status: "success", last_error_code: nil, last_error_message: nil)
            )
            try await completeStageSuccess(handle)
            return .proceed
        } catch {
            let code = ProviderErrorMapper.toErrorCode(error: error, task: .summary)
            try await completeStageFailure(handle, error_code: code, message: String(describing: error))
            _ = try await persistence.updateDocument(
                document_id: document_id,
                update: DocumentPipelineUpdate(
                    lifecycle_status: .failed,
                    current_stage: .summary,
                    block_reason: BlockReason.none,
                    summary_status: "failed",
                    last_error_code: code,
                    last_error_message: String(describing: error)
                )
            )
            try await markStagesSkipped(
                document_id: document_id,
                stages: [.event_extract, .index, .notify],
                error_code: code,
                error_message: "summary failed"
            )
            eventPublisher.publish(.ingestion_failed(document_id: document_id, error_code: code))
            return .stop(.provider_failed(document_id: document_id, error_code: code))
        }
    }

    private func runEventExtractionStage(
        document_id: String,
        request: IngestionRequest,
        parsed: ParsedFileOutput
    ) async throws -> IngestionBranch {
        let handle = try await beginStage(document_id: document_id, stage: .event_extract, provider_id: eventProviderID)

        do {
            let response = try await eventExtractionService.extract(
                context: ProviderDocumentContextRequest(
                    document_id: document_id,
                    file_name: request.file_url.lastPathComponent,
                    file_extension: request.file_url.pathExtension.lowercased(),
                    reference_date: request.reference_date,
                    user_timezone: request.user_timezone,
                    plain_text: parsed.plain_text,
                    language_hint: parsed.language_hint
                )
            )

            try await persistence.saveEvents(document_id: document_id, events: response.event_candidates)
            _ = try await persistence.updateDocument(
                document_id: document_id,
                update: DocumentPipelineUpdate(
                    event_status: response.event_candidates.isEmpty ? DocumentEventStatus.none : .has_candidate,
                    last_error_code: nil,
                    last_error_message: nil
                )
            )
            try await completeStageSuccess(handle)
            return .proceed
        } catch {
            let code = ProviderErrorMapper.toErrorCode(error: error, task: .event_candidates)
            try await completeStageFailure(handle, error_code: code, message: String(describing: error))
            _ = try await persistence.updateDocument(
                document_id: document_id,
                update: DocumentPipelineUpdate(
                    lifecycle_status: .failed,
                    current_stage: .event_extract,
                    block_reason: BlockReason.none,
                    last_error_code: code,
                    last_error_message: String(describing: error)
                )
            )
            try await markStagesSkipped(
                document_id: document_id,
                stages: [.index, .notify],
                error_code: code,
                error_message: "event extraction failed"
            )
            eventPublisher.publish(.ingestion_failed(document_id: document_id, error_code: code))
            return .stop(.provider_failed(document_id: document_id, error_code: code))
        }
    }

    private func runIndexStage(document_id: String) async throws -> IngestionBranch {
        let handle = try await beginStage(document_id: document_id, stage: .index, provider_id: nil)
        do {
            guard let textRecord = try await persistence.fetchDocumentText(document_id: document_id) else {
                try await completeStageSuccess(handle)
                return .proceed
            }

            let plainText = textRecord.plain_text
            let chunks = chunkText(plainText)

            for (index, chunk) in chunks.enumerated() {
                let preview = String(chunk.prefix(200))
                try await persistence.saveDocumentChunk(
                    document_id: document_id,
                    chunk_index: index,
                    content: chunk,
                    content_preview: preview,
                    char_count: chunk.count
                )
            }

            try await completeStageSuccess(handle)
            return .proceed
        } catch {
            try await completeStageFailure(handle, error_code: .db_write_failed, message: String(describing: error))
            return .proceed
        }
    }

    private func chunkText(_ text: String, minSize: Int = 300, maxSize: Int = 500) -> [String] {
        guard !text.isEmpty else { return [] }

        var chunks: [String] = []
        var currentChunk = ""
        let lines = text.components(separatedBy: .newlines)
        let nonEmptyLines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        for line in nonEmptyLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            if currentChunk.isEmpty {
                currentChunk = trimmed
            } else if currentChunk.count + trimmed.count + 1 <= maxSize {
                currentChunk += " " + trimmed
            } else {
                if currentChunk.count >= minSize {
                    chunks.append(currentChunk)
                    currentChunk = trimmed
                } else {
                    currentChunk += " " + trimmed
                }
            }

            if currentChunk.count > maxSize {
                let endIndex = currentChunk.index(currentChunk.startIndex, offsetBy: maxSize)
                let part = String(currentChunk[..<endIndex])
                chunks.append(part)
                currentChunk = String(currentChunk[endIndex...])
            }
        }

        if currentChunk.count >= minSize {
            chunks.append(currentChunk)
        } else if !chunks.isEmpty {
            let lastIndex = chunks.count - 1
            chunks[lastIndex] += " " + currentChunk
        } else if !currentChunk.isEmpty {
            chunks.append(currentChunk)
        }

        return chunks
    }

    private func runNotifyStage(document_id: String, source_type: String) async throws -> IngestionBranch {
        let handle = try await beginStage(document_id: document_id, stage: .notify, provider_id: nil)
        if source_type == WatchSourceType.initial_scan.rawValue {
            _ = try await persistence.updateParseJob(
                ParseJobUpdateInput(
                    job_id: handle.job_id,
                    status: .skipped,
                    finished_at: PipelineClock.nowString(),
                    duration_ms: PipelineClock.durationMs(since: handle.started_at),
                    error_code: nil,
                    error_message: "notification suppressed for initial scan"
                )
            )
            return .proceed
        }

        eventPublisher.publish(.notification_requested(document_id: document_id))
        try await completeStageSuccess(handle)
        return .proceed
    }

    private func beginStage(document_id: String, stage: DocumentStage, provider_id: String?) async throws -> StageHandle {
        try await ensureNotInterrupted(document_id: document_id, stage: stage)

        _ = try await persistence.updateDocument(
            document_id: document_id,
            update: DocumentPipelineUpdate(
                lifecycle_status: .processing,
                current_stage: stage,
                block_reason: BlockReason.none,
                last_error_code: nil,
                last_error_message: nil
            )
        )

        let now = PipelineClock.nowString()
        let created = try await persistence.createParseJob(
            ParseJobCreateInput(
                document_id: document_id,
                stage: stage,
                status: .queued,
                provider_id: provider_id,
                started_at: now
            )
        )

        _ = try await persistence.updateParseJob(
            ParseJobUpdateInput(
                job_id: created.id,
                status: .running
            )
        )

        return StageHandle(job_id: created.id, started_at: Date())
    }

    private func ensureNotInterrupted(document_id: String, stage: DocumentStage) async throws {
        guard interruptedDocumentIDs.contains(document_id) else {
            return
        }

        _ = try? await persistence.updateDocument(
            document_id: document_id,
            update: DocumentPipelineUpdate(
                lifecycle_status: .processing,
                current_stage: stage,
                last_error_code: .unknown,
                last_error_message: "interrupted"
            )
        )

        _ = try? await persistence.createParseJob(
            ParseJobCreateInput(
                document_id: document_id,
                stage: stage,
                status: .cancelled,
                provider_id: nil,
                started_at: PipelineClock.nowString(),
                finished_at: PipelineClock.nowString(),
                duration_ms: 0,
                error_code: .unknown,
                error_message: "interrupted"
            )
        )

        throw IngestionPipelineError.interrupted(document_id: document_id, stage: stage)
    }

    private func completeStageSuccess(
        _ handle: StageHandle,
        error_code: ErrorCode? = nil,
        message: String? = nil
    ) async throws {
        _ = try await persistence.updateParseJob(
            ParseJobUpdateInput(
                job_id: handle.job_id,
                status: .success,
                finished_at: PipelineClock.nowString(),
                duration_ms: PipelineClock.durationMs(since: handle.started_at),
                error_code: error_code,
                error_message: message
            )
        )
    }

    private func completeStageFailure(_ handle: StageHandle, error_code: ErrorCode, message: String) async throws {
        _ = try await persistence.updateParseJob(
            ParseJobUpdateInput(
                job_id: handle.job_id,
                status: .failed,
                finished_at: PipelineClock.nowString(),
                duration_ms: PipelineClock.durationMs(since: handle.started_at),
                error_code: error_code,
                error_message: message
            )
        )
    }

    private func markStagesSkipped(
        document_id: String,
        stages: [DocumentStage],
        error_code: ErrorCode,
        error_message: String
    ) async throws {
        for stage in stages {
            _ = try await persistence.createParseJob(
                ParseJobCreateInput(
                    document_id: document_id,
                    stage: stage,
                    status: .skipped,
                    provider_id: nil,
                    started_at: PipelineClock.nowString(),
                    finished_at: PipelineClock.nowString(),
                    duration_ms: 0,
                    error_code: error_code,
                    error_message: error_message
                )
            )
        }
    }

    private func mapParseErrorCode(file_url: URL, error: Error) -> ErrorCode {
        if let pipelineError = error as? IngestionPipelineError {
            switch pipelineError {
            case .parse_unsupported_type:
                return .parse_unsupported_type
            case .parse_failed(let message):
                if message.lowercased().contains("empty") {
                    return .parse_empty_text
                }
                if file_url.pathExtension.lowercased() == "pdf" {
                    return .parse_pdf_failed
                }
                if file_url.pathExtension.lowercased() == "docx" {
                    return .parse_docx_failed
                }
                return .parse_docx_failed
            default:
                break
            }
        }

        switch file_url.pathExtension.lowercased() {
        case "pdf":
            return .parse_pdf_failed
        case "docx":
            return .parse_docx_failed
        default:
            return .parse_docx_failed
        }
    }

    private func handleTopLevelPipelineError(_ error: IngestionPipelineError) async -> IngestionResult {
        switch error {
        case .interrupted(let documentID, _):
            return .failed(document_id: documentID, error_code: .unknown)
        case .file_missing:
            return .failed(document_id: nil, error_code: .import_file_missing_after_detected)
        case .file_not_stable:
            return .failed(document_id: nil, error_code: .import_file_changed_during_parse)
        case .parse_unsupported_type:
            return .failed(document_id: nil, error_code: .parse_unsupported_type)
        case .parse_failed:
            return .failed(document_id: nil, error_code: .parse_docx_failed)
        case .gate_confirmation_required:
            return .failed(document_id: nil, error_code: .gate_sensitive_confirmation_required)
        case .gate_policy_blocked:
            return .failed(document_id: nil, error_code: .gate_policy_blocked)
        case .quota_exceeded:
            return .failed(document_id: nil, error_code: .quota_parse_exceeded)
        case .provider_failed(let code, _):
            return .failed(document_id: nil, error_code: code)
        case .storage_failed:
            return .failed(document_id: nil, error_code: .db_write_failed)
        }
    }
}

private struct StageHandle: Sendable {
    let job_id: String
    let started_at: Date
}

private enum ParseStageOutcome: Sendable {
    case parsed(ParsedFileOutput)
    case terminal(IngestionResult)
}
