import Foundation
#if canImport(XCTest)
import XCTest
#if canImport(DropKnow)
@testable import DropKnow
#endif

final class SearchServiceQATests: XCTestCase {
    func testEmptyIndexDoesNotConsumeQuota() async {
        let quotaRepository = QuotaRepository(store: RepositoryAuxiliaryStore())
        let subscriptionService = SubscriptionFeatureService(
            quotaRepository: quotaRepository,
            planType: .free,
            qaEnabledOnFree: true
        )

        let persistence = InMemoryIngestionPersistence()
        let service = SearchService(
            documentRepository: DocumentRepository(persistence: persistence),
            summaryRepository: SummaryRepository(persistence: persistence),
            eventRepository: EventRepository(persistence: persistence),
            subscriptionService: subscriptionService,
            qaProvider: nil
        )

        let snapshot = await service.ask(question: "有没有考试安排", mode: .search)
        XCTAssertEqual(snapshot.status, .blocked)
        XCTAssertEqual(snapshot.block_reason, .empty_index)

        let quota = await subscriptionService.fetchQuotaSnapshot(reference_date: Self.referenceDateString())
        XCTAssertEqual(quota.advanced_search_used, 0)
    }

    func testQAModeUsesProviderAndReturnsCitations() async {
        let context = await makeSearchContext(planType: .free, qaEnabledOnFree: true)
        let provider = TestQAProvider { request in
            SearchQAProviderResponse(
                answer: "报名截止时间是 2026-05-01。",
                answer_type: .direct_answer,
                confidence: 0.92,
                citations: [
                    CitationResponse(
                        document_id: request.retrieved_items.first?.document_id ?? "",
                        chunk_id: "c1",
                        file_name: request.retrieved_items.first?.file_name ?? "",
                        evidence_snippet: "报名截止：2026-05-01"
                    )
                ]
            )
        }

        let service = SearchService(
            documentRepository: context.documentRepository,
            summaryRepository: context.summaryRepository,
            eventRepository: context.eventRepository,
            subscriptionService: context.subscriptionService,
            qaProvider: provider
        )

        let snapshot = await service.ask(question: "报名截止 2026-05-01", mode: .qa)

        XCTAssertEqual(snapshot.status, .success)
        XCTAssertEqual(snapshot.mode, .qa)
        XCTAssertTrue(snapshot.answer.contains("2026-05-01"))
        XCTAssertEqual(snapshot.citations.count, 1)
    }

    func testQAModeBlockedWhenFeatureLocked() async {
        let context = await makeSearchContext(planType: .free, qaEnabledOnFree: false)
        let service = SearchService(
            documentRepository: context.documentRepository,
            summaryRepository: context.summaryRepository,
            eventRepository: context.eventRepository,
            subscriptionService: context.subscriptionService,
            qaProvider: nil
        )

        let snapshot = await service.ask(question: "这周有什么考试", mode: .qa)

        XCTAssertEqual(snapshot.status, .blocked)
        XCTAssertEqual(snapshot.block_reason, .feature_locked)
    }

    func testQAModeBlockedWhenQuotaExceeded() async {
        let store = RepositoryAuxiliaryStore()
        let quotaRepository = QuotaRepository(store: store)
        let today = Self.referenceDateString()
        _ = await quotaRepository.create(
            QuotaRecord(
                quota_date: today,
                parse_used: 0,
                parse_limit: 5,
                qa_used: 5,
                qa_limit: 5,
                advanced_search_used: 0,
                advanced_search_limit: 10,
                updated_at: PipelineClock.nowString()
            )
        )

        let context = await makeSearchContext(
            quotaRepository: quotaRepository,
            planType: .free,
            qaEnabledOnFree: true
        )
        let service = SearchService(
            documentRepository: context.documentRepository,
            summaryRepository: context.summaryRepository,
            eventRepository: context.eventRepository,
            subscriptionService: context.subscriptionService,
            qaProvider: nil
        )

        let snapshot = await service.ask(question: "补考通知说了什么", mode: .qa)

        XCTAssertEqual(snapshot.status, .blocked)
        XCTAssertEqual(snapshot.block_reason, .quota_exceeded)
    }

    private struct SearchContext {
        let documentRepository: DocumentRepository
        let summaryRepository: SummaryRepository
        let eventRepository: EventRepository
        let subscriptionService: SubscriptionFeatureService
    }

    private func makeSearchContext(
        quotaRepository: QuotaRepository? = nil,
        planType: PlanType,
        qaEnabledOnFree: Bool
    ) async -> SearchContext {
        let persistence = InMemoryIngestionPersistence()
        let documentRepository = DocumentRepository(persistence: persistence)
        let summaryRepository = SummaryRepository(persistence: persistence)
        let eventRepository = EventRepository(persistence: persistence)
        let effectiveQuotaRepository = quotaRepository ?? QuotaRepository(store: RepositoryAuxiliaryStore())

        let subscriptionService = SubscriptionFeatureService(
            quotaRepository: effectiveQuotaRepository,
            planType: planType,
            qaEnabledOnFree: qaEnabledOnFree
        )

        let createResult = await documentRepository.create(
            NewDocumentInput(
                watch_directory_id: nil,
                file_name: "search-source.txt",
                file_extension: "txt",
                absolute_path: "/tmp/search-source.txt",
                file_hash: UUID().uuidString,
                file_size: 64,
                created_at_fs: nil,
                modified_at_fs: nil,
                imported_at: PipelineClock.nowString(),
                source_type: WatchSourceType.manual.rawValue
            )
        )

        guard case .success(let document) = createResult else {
            XCTFail("failed to create document")
            return SearchContext(
                documentRepository: documentRepository,
                summaryRepository: summaryRepository,
                eventRepository: eventRepository,
                subscriptionService: subscriptionService
            )
        }

        _ = await documentRepository.update(
            document_id: document.id,
            update: DocumentPipelineUpdate(
                lifecycle_status: .ready,
                current_stage: .done,
                event_status: .has_candidate
            )
        )

        _ = await eventRepository.create(
            document_id: document.id,
            events: [
                EventCandidateResponse(
                    event_type: "registration_deadline",
                    title: "课程报名截止",
                    start_time: nil,
                    end_time: nil,
                    raw_time_text: "报名截止 2026-05-01",
                    location: nil,
                    notes: nil,
                    evidence_snippet: "请在 2026-05-01 前完成报名",
                    confidence: 0.91,
                    calendar_eligible: true
                )
            ]
        )

        return SearchContext(
            documentRepository: documentRepository,
            summaryRepository: summaryRepository,
            eventRepository: eventRepository,
            subscriptionService: subscriptionService
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
}

private actor TestQAProvider: SearchQAProviding {
    typealias Handler = @Sendable (SearchQAProviderRequest) async throws -> SearchQAProviderResponse

    private let handler: Handler

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func generate(request: SearchQAProviderRequest) async throws -> SearchQAProviderResponse {
        try await handler(request)
    }
}
#endif
