import Foundation

public struct MockPipelineBundle {
    public let watcher: MockFileWatcher
    public let orchestrator: WatchOrchestrator
    public let coordinator: IngestionCoordinator
    public let persistence: InMemoryIngestionPersistence
    public let event_bus: InMemoryPipelineEventBus

    public init(
        watcher: MockFileWatcher,
        orchestrator: WatchOrchestrator,
        coordinator: IngestionCoordinator,
        persistence: InMemoryIngestionPersistence,
        event_bus: InMemoryPipelineEventBus
    ) {
        self.watcher = watcher
        self.orchestrator = orchestrator
        self.coordinator = coordinator
        self.persistence = persistence
        self.event_bus = event_bus
    }
}

public enum MockPipelineFactory {
    public static func make(dailyParseLimit: Int = 100) -> MockPipelineBundle {
        let summaryConfig = ProviderConfig(
            provider_id: "provider_summary_mock",
            provider_type: .qwen,
            model_name: "qwen-plus",
            base_url: "mock://summary",
            timeout_ms: 8_000,
            retry_policy: RetryPolicy(max_attempts: 3, initial_delay_ms: 100, max_delay_ms: 1_000),
            transport: .mock
        )

        let eventConfig = ProviderConfig(
            provider_id: "provider_event_mock",
            provider_type: .zhipu,
            model_name: "glm-4",
            base_url: "mock://events",
            timeout_ms: 8_000,
            retry_policy: RetryPolicy(max_attempts: 3, initial_delay_ms: 100, max_delay_ms: 1_000),
            transport: .mock
        )

        let summaryProvider = SummaryProvider(config: summaryConfig)
        let eventProvider = EventExtractionProvider(config: eventConfig)

        let persistence = InMemoryIngestionPersistence()
        let eventBus = InMemoryPipelineEventBus()
        let quotaChecker = InMemoryQuotaChecker(dailyLimit: dailyParseLimit)

        let coordinator = IngestionCoordinator(
            persistence: persistence,
            stabilityDetector: FileStabilityDetector(),
            fingerprintService: SHA256FileFingerprintService(),
            parsingService: DefaultDocumentParsingService(),
            privacyGate: DefaultPrivacyGateService(quotaChecker: quotaChecker),
            summarizationService: DocumentSummarizationService(provider: summaryProvider),
            eventExtractionService: DocumentEventExtractionService(provider: eventProvider),
            eventPublisher: eventBus,
            summaryProviderID: summaryConfig.provider_id,
            eventProviderID: eventConfig.provider_id
        )

        let watcher = MockFileWatcher()
        let orchestrator = WatchOrchestrator(watcher: watcher, coordinator: coordinator)

        return MockPipelineBundle(
            watcher: watcher,
            orchestrator: orchestrator,
            coordinator: coordinator,
            persistence: persistence,
            event_bus: eventBus
        )
    }
}
