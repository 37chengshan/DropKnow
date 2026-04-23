import Foundation
import os.log

public final class DropKnowV1Container: @unchecked Sendable {
    public enum RuntimeMode: Sendable {
        case sqlite(
            databaseURL: URL? = nil,
            sqlDirectoryURL: URL? = nil
        )
        case inMemory(bundle: MockPipelineBundle)
    }

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
    public let subscriptionService: SubscriptionFeatureService
    public let calendarService: CalendarFeatureService
    public let searchQAProvider: SearchQAProvider

    public let dashboardService: DashboardService
    public let detailService: DocumentDetailService
    public let searchService: SearchService

    public let coordinatorFacade: IngestionCoordinatorFacade
    private let orchestrator: WatchOrchestrator

    public init(
        mode: RuntimeMode = .sqlite(databaseURL: nil, sqlDirectoryURL: nil)
    ) {
        let runtime = Self.buildRuntime(mode: mode)
        let persistence = runtime.persistence
        let coordinator = runtime.coordinator
        self.orchestrator = runtime.orchestrator
        self.bundle = runtime.bundle

        let tx = InMemoryRepositoryTransactionManager()
        let aux = RepositoryAuxiliaryStore()

        self.watchDirectoryRepository = WatchDirectoryRepository(transaction: tx, store: aux)
        self.documentRepository = DocumentRepository(persistence: persistence, transaction: tx)
        self.documentTextRepository = DocumentTextRepository(persistence: persistence, transaction: tx)
        self.summaryRepository = SummaryRepository(persistence: persistence, transaction: tx)
        self.eventRepository = EventRepository(persistence: persistence, transaction: tx)
        self.parseJobRepository = ParseJobRepository(persistence: persistence, transaction: tx)
        self.privacyDecisionRepository = PrivacyDecisionRepository(transaction: tx, store: aux)
        self.notificationRepository = NotificationRepository(transaction: tx, store: aux)
        self.quotaRepository = QuotaRepository(transaction: tx, store: aux)

        self.subscriptionService = SubscriptionFeatureService(quotaRepository: quotaRepository, planType: .free)
        self.calendarService = CalendarFeatureService(
            bridge: EventKitCalendarBridge(),
            subscriptionService: subscriptionService
        )

        self.searchQAProvider = SearchQAProvider(config: Self.makeQAConfig())
        self.coordinatorFacade = IngestionCoordinatorFacade(coordinator: coordinator)
        self.dashboardService = DashboardService(
            documentRepository: documentRepository,
            summaryRepository: summaryRepository,
            eventRepository: eventRepository
        )
        self.detailService = DocumentDetailService(
            documentRepository: documentRepository,
            summaryRepository: summaryRepository,
            eventRepository: eventRepository,
            coordinatorFacade: coordinatorFacade,
            calendarService: calendarService
        )
        self.searchService = SearchService(
            documentRepository: documentRepository,
            summaryRepository: summaryRepository,
            eventRepository: eventRepository,
            subscriptionService: subscriptionService,
            qaProvider: searchQAProvider
        )
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

        return await orchestrator.ingestNow(
            file_url: fileURL,
            source_type: sourceType.rawValue,
            watch_directory_id: nil
        )
    }

    private static let cachedProviderConfigs: [ProviderConfig] = ProviderConfigLoader.load()

    private static func makeSafeFallbackConfig(providerID: String, task: ProviderTask) -> ProviderConfig {
        ProviderConfig(
            provider_id: providerID,
            provider_type: task == .summary ? .qwen : .zhipu,
            model_name: "unknown",
            base_url: "",
            timeout_ms: 8_000,
            retry_policy: RetryPolicy(max_attempts: 3, initial_delay_ms: 100, max_delay_ms: 1_000),
            transport: .mock
        )
    }

    private static func resolveProviderConfig(
        from loaded: [ProviderConfig],
        providerID: String,
        task: ProviderTask
    ) -> ProviderConfig {
        guard let found = loaded.first(where: { $0.provider_id == providerID }) else {
            return makeSafeFallbackConfig(providerID: providerID, task: task)
        }
        return ProviderConfig(
            provider_id: found.provider_id,
            provider_type: found.provider_type,
            model_name: found.model_name,
            base_url: found.base_url,
            timeout_ms: found.timeout_ms,
            retry_policy: found.retry_policy,
            transport: .http_placeholder
        )
    }

    private static func makeSummaryConfig() -> ProviderConfig {
        resolveProviderConfig(from: cachedProviderConfigs, providerID: "provider_summary_mock", task: .summary)
    }

    private static func makeEventConfig() -> ProviderConfig {
        resolveProviderConfig(from: cachedProviderConfigs, providerID: "provider_event_mock", task: .event_candidates)
    }

    private static func makeQAConfig() -> ProviderConfig {
        resolveProviderConfig(from: cachedProviderConfigs, providerID: "provider_search_qa_mock", task: .qa_with_citations)
    }

    private static func buildRuntime(mode: RuntimeMode) -> (
        bundle: MockPipelineBundle,
        persistence: any RepositoryPersistenceBacking,
        coordinator: IngestionCoordinator,
        orchestrator: WatchOrchestrator
    ) {
        switch mode {
        case .inMemory(let inMemoryBundle):
            return (
                bundle: inMemoryBundle,
                persistence: inMemoryBundle.persistence,
                coordinator: inMemoryBundle.coordinator,
                orchestrator: inMemoryBundle.orchestrator
            )

        case .sqlite(let databaseURL, let sqlDirectoryURL):
            let fallback = MockPipelineFactory.make()
            let sqlDirectory = sqlDirectoryURL ?? DatabaseInitializer.Configuration.defaultSQLDirectory()

            let databaseDirectory: URL
            if let databaseURL {
                databaseDirectory = databaseURL.deletingLastPathComponent()
            } else {
                databaseDirectory = (try? DatabaseInitializer.Configuration.defaultApplicationSupportDirectory())
                    ?? FileManager.default.temporaryDirectory.appendingPathComponent("DropKnow", isDirectory: true)
            }

            let databaseFile = databaseURL ?? databaseDirectory.appendingPathComponent("dropknow.sqlite3")
            let config = DatabaseInitializer.Configuration(
                databaseURL: databaseFile,
                schemaSQLURL: sqlDirectory.appendingPathComponent("schema.sql"),
                migrationV1SQLURL: sqlDirectory.appendingPathComponent("migration_v1.sql")
            )

            guard let sqlitePersistence = try? SQLiteIngestionPersistence(configuration: config) else {
                return (
                    bundle: fallback,
                    persistence: fallback.persistence,
                    coordinator: fallback.coordinator,
                    orchestrator: fallback.orchestrator
                )
            }

            if cachedProviderConfigs.isEmpty {
                let logger = Logger(subsystem: "com.dropknow.DropKnow", category: "ProviderConfig")
                let configPath = ProviderConfigLoader.defaultConfigURL()?.path ?? "unknown"
                logger.warning("No provider configuration found at \(configPath) — using safe mock defaults")
            }

            let summaryConfig = makeSummaryConfig()
            let eventConfig = makeEventConfig()
            let eventBus = InMemoryPipelineEventBus()
            let quotaChecker = InMemoryQuotaChecker(dailyLimit: 100)

            let coordinator = IngestionCoordinator(
                persistence: sqlitePersistence,
                stabilityDetector: FileStabilityDetector(),
                fingerprintService: SHA256FileFingerprintService(),
                parsingService: DefaultDocumentParsingService(),
                privacyGate: DefaultPrivacyGateService(quotaChecker: quotaChecker),
                summarizationService: DocumentSummarizationService(provider: SummaryProvider(config: summaryConfig)),
                eventExtractionService: DocumentEventExtractionService(provider: EventExtractionProvider(config: eventConfig)),
                eventPublisher: eventBus,
                summaryProviderID: summaryConfig.provider_id,
                eventProviderID: eventConfig.provider_id
            )

            let watcher = MockFileWatcher()
            let orchestrator = WatchOrchestrator(watcher: watcher, coordinator: coordinator)

            let syntheticBundle = MockPipelineBundle(
                watcher: watcher,
                orchestrator: orchestrator,
                coordinator: coordinator,
                persistence: InMemoryIngestionPersistence(),
                event_bus: eventBus
            )

            return (
                bundle: syntheticBundle,
                persistence: sqlitePersistence,
                coordinator: coordinator,
                orchestrator: orchestrator
            )
        }
    }
}
