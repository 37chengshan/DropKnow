import Foundation

public protocol DashboardServicing: Sendable {
    func fetchRecentFiles(limit: Int) async -> RepositoryResult<[RecentFileSnapshot]>
    func fetchImportantReminders(limit: Int) async -> RepositoryResult<[ImportantReminderSnapshot]>
}

public protocol DocumentDetailServicing: Sendable {
    func fetchDocumentDetail(document_id: String) async -> RepositoryResult<DocumentDetailSnapshot?>
    func retryParse(document_id: String, source_type: String) async -> RepositoryResult<IngestionResult>
    func markEventAddedToCalendar(event_id: String) async -> RepositoryResult<Bool>
    func ignoreEvent(event_id: String) async -> RepositoryResult<Bool>
}

public protocol SearchServicing: Sendable {
    func ask(question: String, mode: QuickMode) async -> SearchSnapshot
}

public actor DashboardService: DashboardServicing {
    private let documentRepository: DocumentRepository
    private let summaryRepository: SummaryRepository
    private let eventRepository: EventRepository

    public init(
        documentRepository: DocumentRepository,
        summaryRepository: SummaryRepository,
        eventRepository: EventRepository
    ) {
        self.documentRepository = documentRepository
        self.summaryRepository = summaryRepository
        self.eventRepository = eventRepository
    }

    public func fetchRecentFiles(limit: Int) async -> RepositoryResult<[RecentFileSnapshot]> {
        let docsResult = await documentRepository.listRecent(limit: limit)
        switch docsResult {
        case .failure(let failure):
            return .failure(failure)
        case .success(let documents):
            var snapshots: [RecentFileSnapshot] = []
            for document in documents {
                let summaryResult = await summaryRepository.get(document_id: document.id)
                let summary: DocumentSummaryDTO?
                switch summaryResult {
                case .success(let payload):
                    summary = payload
                case .failure:
                    summary = nil
                }

                snapshots.append(
                    RecentFileSnapshot(
                        document_id: document.id,
                        file_name: document.file_name,
                        lifecycle_status: document.lifecycle_status,
                        block_reason: document.block_reason,
                        summary_text: summary?.one_line_summary,
                        key_points: Self.decodeStringArray(summary?.key_points_json),
                        last_error_code: document.last_error_code,
                        imported_at: document.imported_at
                    )
                )
            }
            return .success(snapshots)
        }
    }

    public func fetchImportantReminders(limit: Int) async -> RepositoryResult<[ImportantReminderSnapshot]> {
        let docsResult = await documentRepository.listRecent(limit: limit)
        switch docsResult {
        case .failure(let failure):
            return .failure(failure)
        case .success(let documents):
            var reminders: [ImportantReminderSnapshot] = []

            for document in documents {
                guard document.event_status == .has_candidate
                    || document.event_status == .has_accepted_event
                    || document.event_status == .has_calendar_event else {
                    continue
                }

                let eventsResult = await eventRepository.get(document_id: document.id)
                guard case .success(let events) = eventsResult else {
                    continue
                }

                for event in events {
                    reminders.append(
                        ImportantReminderSnapshot(
                            event_id: event.id,
                            document_id: document.id,
                            file_name: document.file_name,
                            title: event.title,
                            raw_time_text: event.raw_time_text,
                            evidence_snippet: event.evidence_snippet,
                            event_status: document.event_status,
                            confidence: event.confidence
                        )
                    )
                }
            }

            let sorted = reminders.sorted {
                priority(for: $0) > priority(for: $1)
            }
            return .success(Array(sorted.prefix(max(limit, 0))))
        }
    }

    private func priority(for reminder: ImportantReminderSnapshot) -> Int {
        let statusScore: Int
        switch reminder.event_status {
        case .has_calendar_event:
            statusScore = 3
        case .has_accepted_event:
            statusScore = 2
        case .has_candidate:
            statusScore = 1
        default:
            statusScore = 0
        }

        let confidenceScore = reminder.confidence >= 0.8 ? 2 : (reminder.confidence >= 0.55 ? 1 : 0)
        let urgencyScore = urgencyScoreFromTimeText(reminder.raw_time_text, title: reminder.title)
        return statusScore * 100 + confidenceScore * 10 + urgencyScore
    }

    private func urgencyScoreFromTimeText(_ rawTimeText: String, title: String) -> Int {
        let haystack = "\(title.lowercased()) \(rawTimeText.lowercased())"
        let urgentTokens = ["今天", "明天", "今晚", "ddl", "截止", "考试", "面试", "缴费", "报名"]
        if urgentTokens.contains(where: { haystack.contains($0) }) {
            return 2
        }
        return rawTimeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 1
    }

    private static func decodeStringArray(_ json: String?) -> [String] {
        guard let json, let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }
}

public actor DocumentDetailService: DocumentDetailServicing {
    private let documentRepository: DocumentRepository
    private let summaryRepository: SummaryRepository
    private let eventRepository: EventRepository
    private let coordinatorFacade: IngestionCoordinatorFacade
    private let calendarService: (any CalendarFeatureServicing)?

    public init(
        documentRepository: DocumentRepository,
        summaryRepository: SummaryRepository,
        eventRepository: EventRepository,
        coordinatorFacade: IngestionCoordinatorFacade,
        calendarService: (any CalendarFeatureServicing)? = nil
    ) {
        self.documentRepository = documentRepository
        self.summaryRepository = summaryRepository
        self.eventRepository = eventRepository
        self.coordinatorFacade = coordinatorFacade
        self.calendarService = calendarService
    }

    public func fetchDocumentDetail(document_id: String) async -> RepositoryResult<DocumentDetailSnapshot?> {
        let documentResult = await documentRepository.get(id: document_id)
        let summaryResult = await summaryRepository.get(document_id: document_id)
        let eventsResult = await eventRepository.get(document_id: document_id)

        guard case .success(let maybeDocument) = documentResult else {
            if case .failure(let failure) = documentResult {
                return .failure(failure)
            }
            return .dbReadFailure("read document detail failed")
        }

        guard let document = maybeDocument else {
            return .success(nil)
        }

        let summary: DocumentSummaryDTO?
        switch summaryResult {
        case .success(let value):
            summary = value
        case .failure:
            summary = nil
        }

        let events: [DocumentEventDTO]
        switch eventsResult {
        case .success(let value):
            events = value
        case .failure:
            events = []
        }

        return .success(DocumentDetailSnapshot(document: document, summary: summary, events: events))
    }

    public func retryParse(document_id: String, source_type: String = WatchSourceType.manual.rawValue) async -> RepositoryResult<IngestionResult> {
        let documentResult = await documentRepository.get(id: document_id)
        guard case .success(let maybeDocument) = documentResult else {
            if case .failure(let failure) = documentResult {
                return .failure(failure)
            }
            return .dbReadFailure("retry parse failed when reading document")
        }

        guard let document = maybeDocument else {
            return .dbReadFailure("retry parse failed: missing document")
        }

        let request = IngestionRequest(
            file_url: URL(fileURLWithPath: document.absolute_path),
            source_type: source_type,
            watch_directory_id: document.watch_directory_id,
            reference_date: Self.referenceDateString(),
            user_timezone: TimeZone.current.identifier
        )
        let result = await coordinatorFacade.recover(document_id: document_id, request: request)
        return .success(result)
    }

    public func markEventAddedToCalendar(event_id: String) async -> RepositoryResult<Bool> {
        let recentResult = await eventRepository.listRecent(limit: 200)
        guard case .success(let allEvents) = recentResult else {
            if case .failure(let failure) = recentResult {
                return .failure(failure)
            }
            return .dbReadFailure("list events failed")
        }

        guard let target = allEvents.first(where: { $0.id == event_id }) else {
            return .success(false)
        }

        guard let calendarService else {
            return .failure(RepositoryFailure(error_code: .calendar_write_failed, message: "calendar service unavailable"))
        }

        let addResult = await calendarService.addEvent(from: target)

        let nextStatus: CalendarStatus
        let nextIdentifier: String?
        switch addResult {
        case .added(let eventIdentifier):
            nextStatus = .added
            nextIdentifier = eventIdentifier
        case .featureLocked:
            nextStatus = .feature_locked
            nextIdentifier = target.calendar_event_identifier
        case .notEligible:
            nextStatus = .failed
            nextIdentifier = target.calendar_event_identifier
        case .permissionDenied, .writeFailed:
            nextStatus = .failed
            nextIdentifier = target.calendar_event_identifier
        }

        let updated = DocumentEventDTO(
            id: target.id,
            document_id: target.document_id,
            event_type: target.event_type,
            title: target.title,
            start_time: target.start_time,
            end_time: target.end_time,
            raw_time_text: target.raw_time_text,
            timezone: target.timezone,
            location: target.location,
            notes: target.notes,
            evidence_snippet: target.evidence_snippet,
            confidence: target.confidence,
            calendar_eligible: target.calendar_eligible,
            decision_status: .accepted,
            calendar_status: nextStatus,
            calendar_event_identifier: nextIdentifier,
            created_at: target.created_at,
            updated_at: PipelineClock.nowString()
        )

        let updateResult = await eventRepository.update(updated)
        switch updateResult {
        case .success(let saved):
            return .success(saved.calendar_status == .added)
        case .failure(let failure):
            return .failure(failure)
        }
    }

    public func ignoreEvent(event_id: String) async -> RepositoryResult<Bool> {
        let recentResult = await eventRepository.listRecent(limit: 200)
        guard case .success(let allEvents) = recentResult else {
            if case .failure(let failure) = recentResult {
                return .failure(failure)
            }
            return .dbReadFailure("list events failed")
        }

        guard let target = allEvents.first(where: { $0.id == event_id }) else {
            return .success(false)
        }

        let updated = DocumentEventDTO(
            id: target.id,
            document_id: target.document_id,
            event_type: target.event_type,
            title: target.title,
            start_time: target.start_time,
            end_time: target.end_time,
            raw_time_text: target.raw_time_text,
            timezone: target.timezone,
            location: target.location,
            notes: target.notes,
            evidence_snippet: target.evidence_snippet,
            confidence: target.confidence,
            calendar_eligible: target.calendar_eligible,
            decision_status: .dismissed,
            calendar_status: .not_added,
            calendar_event_identifier: target.calendar_event_identifier,
            created_at: target.created_at,
            updated_at: PipelineClock.nowString()
        )

        let updateResult = await eventRepository.update(updated)
        switch updateResult {
        case .success:
            return .success(true)
        case .failure(let failure):
            return .failure(failure)
        }
    }

    private static func referenceDateString() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}

public actor SearchService: SearchServicing {
    private let documentRepository: DocumentRepository
    private let summaryRepository: SummaryRepository
    private let eventRepository: EventRepository
    private let subscriptionService: SubscriptionFeatureServicing
    private let qaProvider: (any SearchQAProviding)?

    public init(
        documentRepository: DocumentRepository,
        summaryRepository: SummaryRepository,
        eventRepository: EventRepository,
        subscriptionService: SubscriptionFeatureServicing,
        qaProvider: (any SearchQAProviding)? = nil
    ) {
        self.documentRepository = documentRepository
        self.summaryRepository = summaryRepository
        self.eventRepository = eventRepository
        self.subscriptionService = subscriptionService
        self.qaProvider = qaProvider
    }

    public func ask(question: String, mode: QuickMode) async -> SearchSnapshot {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return SearchSnapshot(status: .idle, mode: mode, answer: "", citations: [], results: [])
        }

        let documentsResult = await documentRepository.listRecent(limit: 120)
        guard case .success(let documents) = documentsResult else {
            return SearchSnapshot(status: .failed, mode: mode, answer: "读取本地索引失败，请稍后重试。", citations: [], results: [])
        }

        let readyDocuments = documents.filter { $0.lifecycle_status == .ready }
        guard !readyDocuments.isEmpty else {
            return SearchSnapshot(
                status: .blocked,
                mode: mode,
                answer: "尚无可检索内容，请先导入并完成解析。",
                citations: [],
                results: [],
                block_reason: .empty_index
            )
        }

        let gateResult = await subscriptionService.consumeSearchQuota(mode: mode, reference_date: Self.referenceDateString())
        switch gateResult {
        case .allowed:
            break
        case .blocked(let reason, let message):
            return SearchSnapshot(
                status: .blocked,
                mode: mode,
                answer: message,
                citations: [],
                results: [],
                block_reason: reason
            )
        case .failed(let message):
            return SearchSnapshot(
                status: .failed,
                mode: mode,
                answer: message,
                citations: [],
                results: []
            )
        }

        let keywords = tokenizedKeywords(from: trimmed)
        let ftsQuery = buildFTSQuery(from: keywords)

        let chunksResult = await documentRepository.searchChunks(query: ftsQuery, limit: 20)
        let chunks: [ChunkSearchResult]
        switch chunksResult {
        case .success(let results):
            chunks = results
        case .failure:
            return SearchSnapshot(status: .failed, mode: mode, answer: "检索服务暂时不可用，请稍后重试。", citations: [], results: [])
        }

        guard !chunks.isEmpty else {
            if mode == .qa {
                let eventFallback = await buildEventFallbackSnapshot(question: trimmed, mode: mode)
                if !eventFallback.citations.isEmpty {
                    return eventFallback
                }
            }
            return SearchSnapshot(
                status: .no_result,
                mode: mode,
                answer: "未检索到匹配内容，请尝试更具体的关键词。",
                citations: [],
                results: []
            )
        }

        let ranked = Array(chunks.prefix(8))
        switch mode {
        case .search:
            var results: [SearchSnapshot.SearchResultItem] = []
            for chunk in ranked {
                let docsResult = await documentRepository.get(id: chunk.document_id)
                let fileName: String
                if case .success(let doc) = docsResult, let doc {
                    fileName = doc.file_name
                } else {
                    fileName = "未知文件"
                }
                results.append(
                    SearchSnapshot.SearchResultItem(
                        document_id: chunk.document_id,
                        file_name: fileName,
                        title: fileName,
                        subtitle: chunk.content_preview,
                        evidence: chunk.content_preview
                    )
                )
            }
            return SearchSnapshot(status: .success, mode: mode, answer: "", citations: [], results: results)

        case .qa:
            guard let qaProvider else {
                return fallbackQASnapshotFromChunks(from: Array(chunks.prefix(3)), mode: mode)
            }

            let retrievedItems = chunks.prefix(3).map { chunk in
                SearchQARetrievedItem(
                    document_id: chunk.document_id,
                    chunk_id: chunk.chunk_id,
                    file_name: "",
                    snippet: chunk.content_preview
                )
            }

            do {
                let response = try await qaProvider.generate(
                    request: SearchQAProviderRequest(
                        question: trimmed,
                        reference_date: Self.referenceDateString(),
                        user_timezone: TimeZone.current.identifier,
                        retrieved_items: Array(retrievedItems)
                    )
                )

                if response.answer_type == .not_found {
                    return SearchSnapshot(
                        status: .no_result,
                        mode: mode,
                        answer: response.answer,
                        citations: [],
                        results: []
                    )
                }

                return SearchSnapshot(
                    status: .success,
                    mode: mode,
                    answer: response.answer,
                    citations: response.citations,
                    results: []
                )
            } catch {
                return SearchSnapshot(
                    status: .failed,
                    mode: mode,
                    answer: "问答服务暂时不可用，请稍后重试。",
                    citations: [],
                    results: []
                )
            }
        }
    }

    private func buildFTSQuery(from keywords: [String]) -> String {
        let escaped = keywords.map { keyword in
            let escaped = keyword.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return escaped.joined(separator: " ")
    }

    private func fallbackQASnapshotFromChunks(from chunks: [ChunkSearchResult], mode: QuickMode) -> SearchSnapshot {
        let citations = chunks.map { chunk in
            CitationResponse(
                document_id: chunk.document_id,
                chunk_id: chunk.chunk_id,
                file_name: "",
                evidence_snippet: chunk.content_preview
            )
        }
        let answerLines = citations.enumerated().map { index, citation in
            "\(index + 1). [文档片段] \(citation.evidence_snippet)"
        }
        return SearchSnapshot(
            status: .success,
            mode: mode,
            answer: "根据本地证据，与你的问题最相关的信息如下：\n\n\(answerLines.joined(separator: "\n"))",
            citations: citations,
            results: []
        )
    }

    private func buildEventFallbackSnapshot(question: String, mode: QuickMode) async -> SearchSnapshot {
        let eventsResult = await eventRepository.listRecent(limit: 50)
        guard case .success(let events) = eventsResult else {
            return SearchSnapshot(status: .no_result, mode: mode, answer: "", citations: [], results: [])
        }

        let keywords = tokenizedKeywords(from: question)
        let matching = events.filter { event in
            keywords.contains { keyword in
                event.title.lowercased().contains(keyword.lowercased()) ||
                event.raw_time_text.lowercased().contains(keyword.lowercased()) ||
                event.evidence_snippet.lowercased().contains(keyword.lowercased())
            }
        }

        guard !matching.isEmpty else {
            return SearchSnapshot(status: .no_result, mode: mode, answer: "", citations: [], results: [])
        }

        let citations = matching.prefix(5).map { event in
            CitationResponse(
                document_id: event.document_id,
                chunk_id: event.id,
                file_name: "",
                evidence_snippet: event.evidence_snippet
            )
        }

        let answerLines: [String] = matching.prefix(5).enumerated().map { index, event in
            let dateInfo = event.raw_time_text.isEmpty ? "" : "（\(event.raw_time_text)）"
            return "\(index + 1). [事件] \(event.title)\(dateInfo)"
        }

        return SearchSnapshot(
            status: .success,
            mode: mode,
            answer: "根据事件记录，与你的问题最相关的信息如下：\n\n\(answerLines.joined(separator: "\n"))",
            citations: Array(citations),
            results: []
        )
    }

    private static func referenceDateString() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private func tokenizedKeywords(from question: String) -> [String] {
        let lowered = question.lowercased()
        let separators = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        var words = lowered.components(separatedBy: separators).filter { !$0.isEmpty }

        if words.count == 1, let token = words.first, containsCJK(token), token.count >= 4 {
            words = cjkNGrams(token, n: 2)
        }

        if words.isEmpty {
            return [lowered]
        }

        return words
    }

    private func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)
        }
    }

    private func cjkNGrams(_ text: String, n: Int) -> [String] {
        let characters = Array(text)
        guard characters.count >= n else { return [text] }
        return (0...(characters.count - n)).map { index in
            String(characters[index..<(index + n)])
        }
    }
}
