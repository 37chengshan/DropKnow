import Foundation

public final class DropKnowV1Container: @unchecked Sendable {
    public let bundle: MockPipelineBundle

    public let watchDirectoryRepository: WatchDirectoryRepository
    public let documentRepository: DocumentRepository
    public let documentTextRepository: DocumentTextRepository
    public let summaryRepository: SummaryRepository
    public let eventRepository: EventRepository
    public let parseJobRepository: ParseJobRepository
    public let privacyDecisionRepository: PrivacyDecisionRepository
    public let notificationRepository: NotificationRepository
    public let quotaRepository: QuotaRepository

    public let dashboardService: DashboardService
    public let detailService: DocumentDetailService
    public let searchService: SearchService

    public let coordinatorFacade: IngestionCoordinatorFacade

    public init(bundle: MockPipelineBundle = MockPipelineFactory.make()) {
        self.bundle = bundle

        let tx = InMemoryRepositoryTransactionManager()
        let aux = RepositoryAuxiliaryStore()

        self.watchDirectoryRepository = WatchDirectoryRepository(transaction: tx, store: aux)
        self.documentRepository = DocumentRepository(persistence: bundle.persistence, transaction: tx)
        self.documentTextRepository = DocumentTextRepository(persistence: bundle.persistence, transaction: tx)
        self.summaryRepository = SummaryRepository(persistence: bundle.persistence, transaction: tx)
        self.eventRepository = EventRepository(persistence: bundle.persistence, transaction: tx)
        self.parseJobRepository = ParseJobRepository(persistence: bundle.persistence, transaction: tx)
        self.privacyDecisionRepository = PrivacyDecisionRepository(transaction: tx, store: aux)
        self.notificationRepository = NotificationRepository(transaction: tx, store: aux)
        self.quotaRepository = QuotaRepository(transaction: tx, store: aux)

        self.coordinatorFacade = IngestionCoordinatorFacade(coordinator: bundle.coordinator)
        self.dashboardService = DashboardService(
            documentRepository: documentRepository,
            summaryRepository: summaryRepository,
            eventRepository: eventRepository
        )
        self.detailService = DocumentDetailService(
            documentRepository: documentRepository,
            summaryRepository: summaryRepository,
            eventRepository: eventRepository,
            coordinatorFacade: coordinatorFacade
        )
        self.searchService = SearchService()
    }

    public func makeRecentFilesViewModel() -> RecentFilesViewModel {
        RecentFilesViewModel(service: dashboardService)
    }

    public func makeImportantRemindersViewModel() -> ImportantRemindersViewModel {
        ImportantRemindersViewModel(service: dashboardService)
    }

    public func makeDocumentDetailViewModel() -> DocumentDetailViewModel {
        DocumentDetailViewModel(service: detailService)
    }

    public func makeSearchViewModel() -> SearchViewModel {
        SearchViewModel(service: searchService)
    }

    @discardableResult
    public func runDemoFlow(
        fileName: String = "dropknow_demo.txt",
        content: String = "明天下午三点在上海开会，请带身份证。",
        sourceType: WatchSourceType = .manual
    ) async -> IngestionResult {
        let tempDirectory = FileManager.default.temporaryDirectory
        let fileURL = tempDirectory.appendingPathComponent(fileName)

        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            return .failed(document_id: nil, error_code: .db_write_failed)
        }

        return await bundle.orchestrator.ingestNow(
            file_url: fileURL,
            source_type: sourceType.rawValue,
            watch_directory_id: nil
        )
    }
}
