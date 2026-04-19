import Foundation

public struct WatchDirectoryRecord: Equatable, Sendable {
    public let id: String
    public let display_name: String
    public let path_hint: String
    public let bookmark_data: Data?
    public let is_default_downloads: Bool
    public let is_active: Bool
    public let created_at: String
    public let updated_at: String

    public init(
        id: String,
        display_name: String,
        path_hint: String,
        bookmark_data: Data?,
        is_default_downloads: Bool,
        is_active: Bool,
        created_at: String,
        updated_at: String
    ) {
        self.id = id
        self.display_name = display_name
        self.path_hint = path_hint
        self.bookmark_data = bookmark_data
        self.is_default_downloads = is_default_downloads
        self.is_active = is_active
        self.created_at = created_at
        self.updated_at = updated_at
    }
}

public struct DocumentTextDTO: Sendable {
    public let document_id: String
    public let extracted_title: String?
    public let plain_text: String
    public let page_count: Int?
    public let parser_type: String
    public let language_hint: String?
    public let text_length: Int
    public let extracted_at: String

    public init(document_id: String, record: ParsedTextRecord) {
        self.document_id = document_id
        self.extracted_title = record.extracted_title
        self.plain_text = record.plain_text
        self.page_count = record.page_count
        self.parser_type = record.parser_type
        self.language_hint = record.language_hint
        self.text_length = record.text_length
        self.extracted_at = record.extracted_at
    }
}

public struct PrivacyDecisionRecord: Equatable, Sendable {
    public let id: String
    public let document_id: String
    public let risk_level: String
    public let rule_hits_json: String
    public let sampled_text: String?
    public let decision: String
    public let decided_at: String

    public init(
        id: String,
        document_id: String,
        risk_level: String,
        rule_hits_json: String,
        sampled_text: String?,
        decision: String,
        decided_at: String
    ) {
        self.id = id
        self.document_id = document_id
        self.risk_level = risk_level
        self.rule_hits_json = rule_hits_json
        self.sampled_text = sampled_text
        self.decision = decision
        self.decided_at = decided_at
    }
}

public struct NotificationRecord: Equatable, Sendable {
    public let id: String
    public let document_id: String?
    public let notification_type: String
    public let title: String
    public let body: String
    public let action_payload_json: String?
    public let shown_at: String?
    public let clicked_at: String?
    public let dismissed_at: String?

    public init(
        id: String,
        document_id: String?,
        notification_type: String,
        title: String,
        body: String,
        action_payload_json: String?,
        shown_at: String?,
        clicked_at: String?,
        dismissed_at: String?
    ) {
        self.id = id
        self.document_id = document_id
        self.notification_type = notification_type
        self.title = title
        self.body = body
        self.action_payload_json = action_payload_json
        self.shown_at = shown_at
        self.clicked_at = clicked_at
        self.dismissed_at = dismissed_at
    }
}

public struct QuotaRecord: Equatable, Sendable {
    public let quota_date: String
    public let parse_used: Int
    public let parse_limit: Int
    public let qa_used: Int
    public let qa_limit: Int
    public let advanced_search_used: Int
    public let advanced_search_limit: Int
    public let updated_at: String

    public init(
        quota_date: String,
        parse_used: Int,
        parse_limit: Int,
        qa_used: Int,
        qa_limit: Int,
        advanced_search_used: Int,
        advanced_search_limit: Int,
        updated_at: String
    ) {
        self.quota_date = quota_date
        self.parse_used = parse_used
        self.parse_limit = parse_limit
        self.qa_used = qa_used
        self.qa_limit = qa_limit
        self.advanced_search_used = advanced_search_used
        self.advanced_search_limit = advanced_search_limit
        self.updated_at = updated_at
    }
}

public actor RepositoryAuxiliaryStore {
    private var watchDirectories: [String: WatchDirectoryRecord] = [:]
    private var privacyDecisions: [String: PrivacyDecisionRecord] = [:]
    private var notifications: [String: NotificationRecord] = [:]
    private var quotas: [String: QuotaRecord] = [:]

    public init() {}

    public func upsertWatchDirectory(_ record: WatchDirectoryRecord) {
        watchDirectories[record.id] = record
    }

    public func fetchWatchDirectory(id: String) -> WatchDirectoryRecord? {
        watchDirectories[id]
    }

    public func deleteWatchDirectory(id: String) -> Bool {
        watchDirectories.removeValue(forKey: id) != nil
    }

    public func listRecentWatchDirectories(limit: Int) -> [WatchDirectoryRecord] {
        watchDirectories.values
            .sorted { $0.updated_at > $1.updated_at }
            .prefix(max(limit, 0))
            .map { $0 }
    }

    public func upsertPrivacyDecision(_ record: PrivacyDecisionRecord) {
        privacyDecisions[record.id] = record
    }

    public func fetchPrivacyDecision(id: String) -> PrivacyDecisionRecord? {
        privacyDecisions[id]
    }

    public func deletePrivacyDecision(id: String) -> Bool {
        privacyDecisions.removeValue(forKey: id) != nil
    }

    public func listRecentPrivacyDecisions(limit: Int) -> [PrivacyDecisionRecord] {
        privacyDecisions.values
            .sorted { $0.decided_at > $1.decided_at }
            .prefix(max(limit, 0))
            .map { $0 }
    }

    public func upsertNotification(_ record: NotificationRecord) {
        notifications[record.id] = record
    }

    public func fetchNotification(id: String) -> NotificationRecord? {
        notifications[id]
    }

    public func deleteNotification(id: String) -> Bool {
        notifications.removeValue(forKey: id) != nil
    }

    public func listRecentNotifications(limit: Int) -> [NotificationRecord] {
        notifications.values
            .sorted { ($0.shown_at ?? "") > ($1.shown_at ?? "") }
            .prefix(max(limit, 0))
            .map { $0 }
    }

    public func upsertQuota(_ record: QuotaRecord) {
        quotas[record.quota_date] = record
    }

    public func fetchQuota(quota_date: String) -> QuotaRecord? {
        quotas[quota_date]
    }

    public func deleteQuota(quota_date: String) -> Bool {
        quotas.removeValue(forKey: quota_date) != nil
    }

    public func listRecentQuotas(limit: Int) -> [QuotaRecord] {
        quotas.values
            .sorted { $0.updated_at > $1.updated_at }
            .prefix(max(limit, 0))
            .map { $0 }
    }
}

public actor WatchDirectoryRepository {
    private let transaction: any RepositoryTransactioning
    private let store: RepositoryAuxiliaryStore

    public init(
        transaction: any RepositoryTransactioning = InMemoryRepositoryTransactionManager(),
        store: RepositoryAuxiliaryStore = RepositoryAuxiliaryStore()
    ) {
        self.transaction = transaction
        self.store = store
    }

    public func create(_ record: WatchDirectoryRecord) async -> RepositoryResult<WatchDirectoryRecord> {
        await transaction.transaction {
            await self.store.upsertWatchDirectory(record)
            return .success(record)
        }
    }

    public func get(id: String) async -> RepositoryResult<WatchDirectoryRecord?> {
        let item = await store.fetchWatchDirectory(id: id)
        return .success(item)
    }

    public func update(_ record: WatchDirectoryRecord) async -> RepositoryResult<WatchDirectoryRecord> {
        await transaction.transaction {
            await self.store.upsertWatchDirectory(record)
            return .success(record)
        }
    }

    public func delete(id: String) async -> RepositoryResult<Bool> {
        await transaction.transaction {
            .success(await self.store.deleteWatchDirectory(id: id))
        }
    }

    public func listRecent(limit: Int) async -> RepositoryResult<[WatchDirectoryRecord]> {
        .success(await store.listRecentWatchDirectories(limit: limit))
    }
}

public actor DocumentRepository {
    private let transaction: any RepositoryTransactioning
    private let persistence: InMemoryIngestionPersistence

    public init(
        persistence: InMemoryIngestionPersistence,
        transaction: any RepositoryTransactioning = InMemoryRepositoryTransactionManager()
    ) {
        self.persistence = persistence
        self.transaction = transaction
    }

    public func create(_ input: NewDocumentInput) async -> RepositoryResult<DocumentDTO> {
        await transaction.transaction {
            do {
                let created = try await self.persistence.createDocument(input)
                return .success(created)
            } catch {
                return .dbWriteFailure("create document failed: \(error.localizedDescription)")
            }
        }
    }

    public func get(id: String) async -> RepositoryResult<DocumentDTO?> {
        do {
            return .success(try await persistence.fetchDocument(document_id: id))
        } catch {
            return .dbReadFailure("get document failed: \(error.localizedDescription)")
        }
    }

    public func update(document_id: String, update: DocumentPipelineUpdate) async -> RepositoryResult<DocumentDTO?> {
        await transaction.transaction {
            do {
                let updated = try await self.persistence.updateDocument(document_id: document_id, update: update)
                return .success(updated)
            } catch {
                return .dbWriteFailure("update document failed: \(error.localizedDescription)")
            }
        }
    }

    public func delete(id: String) async -> RepositoryResult<Bool> {
        await transaction.transaction {
            .success(await self.persistence.deleteDocument(document_id: id))
        }
    }

    public func listRecent(limit: Int) async -> RepositoryResult<[DocumentDTO]> {
        .success(await persistence.listRecentDocuments(limit: limit))
    }
}

public actor DocumentTextRepository {
    private let transaction: any RepositoryTransactioning
    private let persistence: InMemoryIngestionPersistence

    public init(
        persistence: InMemoryIngestionPersistence,
        transaction: any RepositoryTransactioning = InMemoryRepositoryTransactionManager()
    ) {
        self.persistence = persistence
        self.transaction = transaction
    }

    public func create(document_id: String, record: ParsedTextRecord) async -> RepositoryResult<DocumentTextDTO> {
        await transaction.transaction {
            do {
                try await self.persistence.saveDocumentText(document_id: document_id, record: record)
                return .success(DocumentTextDTO(document_id: document_id, record: record))
            } catch {
                return .dbWriteFailure("create document_text failed: \(error.localizedDescription)")
            }
        }
    }

    public func get(document_id: String) async -> RepositoryResult<DocumentTextDTO?> {
        guard let item = await persistence.fetchDocumentText(document_id: document_id) else {
            return .success(nil)
        }
        return .success(DocumentTextDTO(document_id: document_id, record: item))
    }

    public func update(document_id: String, record: ParsedTextRecord) async -> RepositoryResult<DocumentTextDTO> {
        await create(document_id: document_id, record: record)
    }

    public func delete(document_id: String) async -> RepositoryResult<Bool> {
        await transaction.transaction {
            .success(await self.persistence.deleteDocumentText(document_id: document_id))
        }
    }

    public func listRecent(limit: Int) async -> RepositoryResult<[DocumentTextDTO]> {
        let all = await self.persistence.allDocumentTexts().map { key, value in
            DocumentTextDTO(document_id: key, record: value)
        }
        let sorted = all.sorted { $0.extracted_at > $1.extracted_at }
        return .success(Array(sorted.prefix(max(limit, 0))))
    }
}

public actor SummaryRepository {
    private let transaction: any RepositoryTransactioning
    private let persistence: InMemoryIngestionPersistence

    public init(
        persistence: InMemoryIngestionPersistence,
        transaction: any RepositoryTransactioning = InMemoryRepositoryTransactionManager()
    ) {
        self.persistence = persistence
        self.transaction = transaction
    }

    public func create(document_id: String, summary: SummaryProviderResponse, provider: ProviderConfig) async -> RepositoryResult<DocumentSummaryDTO?> {
        await transaction.transaction {
            do {
                try await self.persistence.saveSummary(document_id: document_id, summary: summary, provider: provider)
                return .success(await self.persistence.fetchSummary(document_id: document_id))
            } catch {
                return .dbWriteFailure("create summary failed: \(error.localizedDescription)")
            }
        }
    }

    public func get(document_id: String) async -> RepositoryResult<DocumentSummaryDTO?> {
        .success(await persistence.fetchSummary(document_id: document_id))
    }

    public func update(document_id: String, summary: SummaryProviderResponse, provider: ProviderConfig) async -> RepositoryResult<DocumentSummaryDTO?> {
        await create(document_id: document_id, summary: summary, provider: provider)
    }

    public func delete(document_id: String) async -> RepositoryResult<Bool> {
        await transaction.transaction {
            .success(await self.persistence.deleteSummary(document_id: document_id))
        }
    }

    public func listRecent(limit: Int) async -> RepositoryResult<[DocumentSummaryDTO]> {
        .success(await self.persistence.listRecentSummaries(limit: limit))
    }
}

public actor EventRepository {
    private let transaction: any RepositoryTransactioning
    private let persistence: InMemoryIngestionPersistence

    public init(
        persistence: InMemoryIngestionPersistence,
        transaction: any RepositoryTransactioning = InMemoryRepositoryTransactionManager()
    ) {
        self.persistence = persistence
        self.transaction = transaction
    }

    public func create(document_id: String, events: [EventCandidateResponse]) async -> RepositoryResult<[DocumentEventDTO]> {
        await transaction.transaction {
            do {
                try await self.persistence.saveEvents(document_id: document_id, events: events)
                return .success(await self.persistence.fetchEvents(document_id: document_id))
            } catch {
                return .dbWriteFailure("create events failed: \(error.localizedDescription)")
            }
        }
    }

    public func get(document_id: String) async -> RepositoryResult<[DocumentEventDTO]> {
        .success(await persistence.fetchEvents(document_id: document_id))
    }

    public func update(_ event: DocumentEventDTO) async -> RepositoryResult<DocumentEventDTO> {
        await transaction.transaction {
            await self.persistence.upsertEvent(event)
            return .success(event)
        }
    }

    public func delete(event_id: String) async -> RepositoryResult<Bool> {
        await transaction.transaction {
            .success(await self.persistence.deleteEvent(event_id: event_id))
        }
    }

    public func listRecent(limit: Int) async -> RepositoryResult<[DocumentEventDTO]> {
        .success(await self.persistence.listRecentEvents(limit: limit))
    }
}

public actor ParseJobRepository {
    private let transaction: any RepositoryTransactioning
    private let persistence: InMemoryIngestionPersistence

    public init(
        persistence: InMemoryIngestionPersistence,
        transaction: any RepositoryTransactioning = InMemoryRepositoryTransactionManager()
    ) {
        self.persistence = persistence
        self.transaction = transaction
    }

    public func create(_ input: ParseJobCreateInput) async -> RepositoryResult<ParseJobDTO> {
        await transaction.transaction {
            do {
                return .success(try await self.persistence.createParseJob(input))
            } catch {
                return .dbWriteFailure("create parse_job failed: \(error.localizedDescription)")
            }
        }
    }

    public func get(id: String) async -> RepositoryResult<ParseJobDTO?> {
        .success(await persistence.fetchParseJob(job_id: id))
    }

    public func update(_ input: ParseJobUpdateInput) async -> RepositoryResult<ParseJobDTO?> {
        await transaction.transaction {
            do {
                return .success(try await self.persistence.updateParseJob(input))
            } catch {
                return .dbWriteFailure("update parse_job failed: \(error.localizedDescription)")
            }
        }
    }

    public func delete(id: String) async -> RepositoryResult<Bool> {
        await transaction.transaction {
            .success(await self.persistence.deleteParseJob(job_id: id))
        }
    }

    public func listRecent(limit: Int) async -> RepositoryResult<[ParseJobDTO]> {
        .success(await self.persistence.listRecentParseJobs(limit: limit))
    }
}

public actor PrivacyDecisionRepository {
    private let transaction: any RepositoryTransactioning
    private let store: RepositoryAuxiliaryStore

    public init(
        transaction: any RepositoryTransactioning = InMemoryRepositoryTransactionManager(),
        store: RepositoryAuxiliaryStore = RepositoryAuxiliaryStore()
    ) {
        self.transaction = transaction
        self.store = store
    }

    public func create(_ record: PrivacyDecisionRecord) async -> RepositoryResult<PrivacyDecisionRecord> {
        await transaction.transaction {
            await self.store.upsertPrivacyDecision(record)
            return .success(record)
        }
    }

    public func get(id: String) async -> RepositoryResult<PrivacyDecisionRecord?> {
        .success(await store.fetchPrivacyDecision(id: id))
    }

    public func update(_ record: PrivacyDecisionRecord) async -> RepositoryResult<PrivacyDecisionRecord> {
        await create(record)
    }

    public func delete(id: String) async -> RepositoryResult<Bool> {
        await transaction.transaction {
            .success(await self.store.deletePrivacyDecision(id: id))
        }
    }

    public func listRecent(limit: Int) async -> RepositoryResult<[PrivacyDecisionRecord]> {
        .success(await self.store.listRecentPrivacyDecisions(limit: limit))
    }
}

public actor NotificationRepository {
    private let transaction: any RepositoryTransactioning
    private let store: RepositoryAuxiliaryStore

    public init(
        transaction: any RepositoryTransactioning = InMemoryRepositoryTransactionManager(),
        store: RepositoryAuxiliaryStore = RepositoryAuxiliaryStore()
    ) {
        self.transaction = transaction
        self.store = store
    }

    public func create(_ record: NotificationRecord) async -> RepositoryResult<NotificationRecord> {
        await transaction.transaction {
            await self.store.upsertNotification(record)
            return .success(record)
        }
    }

    public func get(id: String) async -> RepositoryResult<NotificationRecord?> {
        .success(await store.fetchNotification(id: id))
    }

    public func update(_ record: NotificationRecord) async -> RepositoryResult<NotificationRecord> {
        await create(record)
    }

    public func delete(id: String) async -> RepositoryResult<Bool> {
        await transaction.transaction {
            .success(await self.store.deleteNotification(id: id))
        }
    }

    public func listRecent(limit: Int) async -> RepositoryResult<[NotificationRecord]> {
        .success(await self.store.listRecentNotifications(limit: limit))
    }
}

public actor QuotaRepository {
    private let transaction: any RepositoryTransactioning
    private let store: RepositoryAuxiliaryStore

    public init(
        transaction: any RepositoryTransactioning = InMemoryRepositoryTransactionManager(),
        store: RepositoryAuxiliaryStore = RepositoryAuxiliaryStore()
    ) {
        self.transaction = transaction
        self.store = store
    }

    public func create(_ record: QuotaRecord) async -> RepositoryResult<QuotaRecord> {
        await transaction.transaction {
            await self.store.upsertQuota(record)
            return .success(record)
        }
    }

    public func get(quota_date: String) async -> RepositoryResult<QuotaRecord?> {
        .success(await store.fetchQuota(quota_date: quota_date))
    }

    public func update(_ record: QuotaRecord) async -> RepositoryResult<QuotaRecord> {
        await create(record)
    }

    public func delete(quota_date: String) async -> RepositoryResult<Bool> {
        await transaction.transaction {
            .success(await self.store.deleteQuota(quota_date: quota_date))
        }
    }

    public func listRecent(limit: Int) async -> RepositoryResult<[QuotaRecord]> {
        .success(await self.store.listRecentQuotas(limit: limit))
    }
}
