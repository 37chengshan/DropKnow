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
    func ask(question: String) async -> SearchSnapshot
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
                guard document.event_status == .has_candidate || document.event_status == .has_calendar_event else {
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
                priority(for: $0.event_status) > priority(for: $1.event_status)
            }
            return .success(Array(sorted.prefix(max(limit, 0))))
        }
    }

    private func priority(for status: DocumentEventStatus) -> Int {
        switch status {
        case .has_calendar_event:
            return 2
        case .has_candidate:
            return 1
        default:
            return 0
        }
    }
}

public actor DocumentDetailService: DocumentDetailServicing {
    private let documentRepository: DocumentRepository
    private let summaryRepository: SummaryRepository
    private let eventRepository: EventRepository
    private let coordinatorFacade: IngestionCoordinatorFacade

    public init(
        documentRepository: DocumentRepository,
        summaryRepository: SummaryRepository,
        eventRepository: EventRepository,
        coordinatorFacade: IngestionCoordinatorFacade
    ) {
        self.documentRepository = documentRepository
        self.summaryRepository = summaryRepository
        self.eventRepository = eventRepository
        self.coordinatorFacade = coordinatorFacade
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
            calendar_status: .added,
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

public struct SearchService: SearchServicing {
    public init() {}

    public func ask(question: String) async -> SearchSnapshot {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return SearchSnapshot(status: .idle, answer: "", citations: [])
        }

        return SearchSnapshot(
            status: .no_result,
            answer: "V1 最小搜索尚未接入检索索引。",
            citations: []
        )
    }
}
