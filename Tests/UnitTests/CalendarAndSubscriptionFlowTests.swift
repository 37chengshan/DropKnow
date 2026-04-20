import Foundation
#if canImport(XCTest)
import XCTest
#if canImport(DropKnow)
@testable import DropKnow
#endif

final class CalendarAndSubscriptionFlowTests: XCTestCase {
    func testImportantRemindersIncludesAcceptedEvents() async {
        let persistence = InMemoryIngestionPersistence()
        let documentRepository = DocumentRepository(persistence: persistence)
        let summaryRepository = SummaryRepository(persistence: persistence)
        let eventRepository = EventRepository(persistence: persistence)
        let dashboardService = DashboardService(
            documentRepository: documentRepository,
            summaryRepository: summaryRepository,
            eventRepository: eventRepository
        )

        let statuses: [DocumentEventStatus] = [.has_candidate, .has_accepted_event, .has_calendar_event]
        for (index, status) in statuses.enumerated() {
            let createResult = await documentRepository.create(
                NewDocumentInput(
                    watch_directory_id: nil,
                    file_name: "event-\(index).txt",
                    file_extension: "txt",
                    absolute_path: "/tmp/event-\(index).txt",
                    file_hash: UUID().uuidString,
                    file_size: 16,
                    created_at_fs: nil,
                    modified_at_fs: nil,
                    imported_at: PipelineClock.nowString(),
                    source_type: WatchSourceType.manual.rawValue
                )
            )

            guard case .success(let document) = createResult else {
                XCTFail("create document failed")
                return
            }

            _ = await documentRepository.update(
                document_id: document.id,
                update: DocumentPipelineUpdate(lifecycle_status: .ready, current_stage: .done, event_status: status)
            )
            _ = await eventRepository.create(
                document_id: document.id,
                events: [
                    EventCandidateResponse(
                        event_type: "exam",
                        title: "事件\(index)",
                        start_time: nil,
                        end_time: nil,
                        raw_time_text: "明天",
                        location: nil,
                        notes: nil,
                        evidence_snippet: "证据\(index)",
                        confidence: 0.8,
                        calendar_eligible: true
                    )
                ]
            )
        }

        let result = await dashboardService.fetchImportantReminders(limit: 10)
        guard case .success(let reminders) = result else {
            XCTFail("fetch reminders failed")
            return
        }

        XCTAssertEqual(reminders.count, 3)
    }

    func testCalendarFeatureLockedForFreePlan() async {
        let context = await makeContext(planType: .free, bridgeResult: .added(eventIdentifier: "evt_1"))

        let result = await context.detailService.markEventAddedToCalendar(event_id: context.eventID)
        guard case .success(let changed) = result else {
            XCTFail("expected success result")
            return
        }

        XCTAssertFalse(changed)

        let eventsResult = await context.eventRepository.get(document_id: context.documentID)
        guard case .success(let events) = eventsResult, let event = events.first else {
            XCTFail("expected event")
            return
        }

        XCTAssertEqual(event.calendar_status, .feature_locked)
    }

    func testCalendarAddedForProPlan() async {
        let context = await makeContext(planType: .pro, bridgeResult: .added(eventIdentifier: "evt_42"))

        let result = await context.detailService.markEventAddedToCalendar(event_id: context.eventID)
        guard case .success(let changed) = result else {
            XCTFail("expected success result")
            return
        }

        XCTAssertTrue(changed)

        let eventsResult = await context.eventRepository.get(document_id: context.documentID)
        guard case .success(let events) = eventsResult, let event = events.first else {
            XCTFail("expected event")
            return
        }

        XCTAssertEqual(event.calendar_status, .added)
        XCTAssertEqual(event.calendar_event_identifier, "evt_42")
    }

    func testQuotaSnapshotUsesRepositoryValues() async {
        let quotaRepository = QuotaRepository(store: RepositoryAuxiliaryStore())
        let today = Self.referenceDateString()

        _ = await quotaRepository.create(
            QuotaRecord(
                quota_date: today,
                parse_used: 2,
                parse_limit: 5,
                qa_used: 1,
                qa_limit: 5,
                advanced_search_used: 3,
                advanced_search_limit: 10,
                updated_at: PipelineClock.nowString()
            )
        )

        let subscriptionService = SubscriptionFeatureService(
            quotaRepository: quotaRepository,
            planType: .free,
            qaEnabledOnFree: true
        )

        let snapshot = await subscriptionService.fetchQuotaSnapshot(reference_date: today)
        XCTAssertEqual(snapshot.parse_used, 2)
        XCTAssertEqual(snapshot.qa_used, 1)
        XCTAssertEqual(snapshot.advanced_search_used, 3)
    }

    private struct Context {
        let detailService: DocumentDetailService
        let eventRepository: EventRepository
        let documentID: String
        let eventID: String
    }

    private func makeContext(planType: PlanType, bridgeResult: CalendarAddResult) async -> Context {
        let persistence = InMemoryIngestionPersistence()
        let documentRepository = DocumentRepository(persistence: persistence)
        let summaryRepository = SummaryRepository(persistence: persistence)
        let eventRepository = EventRepository(persistence: persistence)
        let quotaRepository = QuotaRepository(store: RepositoryAuxiliaryStore())

        let subscriptionService = SubscriptionFeatureService(
            quotaRepository: quotaRepository,
            planType: planType,
            qaEnabledOnFree: true
        )
        let calendarService = CalendarFeatureService(
            bridge: TestCalendarBridge(result: bridgeResult),
            subscriptionService: subscriptionService
        )

        let bundle = MockPipelineFactory.make()
        let detailService = DocumentDetailService(
            documentRepository: documentRepository,
            summaryRepository: summaryRepository,
            eventRepository: eventRepository,
            coordinatorFacade: IngestionCoordinatorFacade(coordinator: bundle.coordinator),
            calendarService: calendarService
        )

        let createResult = await documentRepository.create(
            NewDocumentInput(
                watch_directory_id: nil,
                file_name: "calendar-target.txt",
                file_extension: "txt",
                absolute_path: "/tmp/calendar-target.txt",
                file_hash: UUID().uuidString,
                file_size: 42,
                created_at_fs: nil,
                modified_at_fs: nil,
                imported_at: PipelineClock.nowString(),
                source_type: WatchSourceType.manual.rawValue
            )
        )

        guard case .success(let document) = createResult else {
            XCTFail("failed to create document")
            return Context(
                detailService: detailService,
                eventRepository: eventRepository,
                documentID: "",
                eventID: ""
            )
        }

        _ = await documentRepository.update(
            document_id: document.id,
            update: DocumentPipelineUpdate(lifecycle_status: .ready, current_stage: .done, event_status: .has_candidate)
        )

        let eventsResult = await eventRepository.create(
            document_id: document.id,
            events: [
                EventCandidateResponse(
                    event_type: "exam",
                    title: "高数期中考试",
                    start_time: nil,
                    end_time: nil,
                    raw_time_text: "明天 10:00",
                    location: "教学楼 A101",
                    notes: "闭卷",
                    evidence_snippet: "高数期中考试安排在明天上午 10 点",
                    confidence: 0.95,
                    calendar_eligible: true
                )
            ]
        )

        guard case .success(let events) = eventsResult, let event = events.first else {
            XCTFail("failed to create event")
            return Context(
                detailService: detailService,
                eventRepository: eventRepository,
                documentID: document.id,
                eventID: ""
            )
        }

        return Context(
            detailService: detailService,
            eventRepository: eventRepository,
            documentID: document.id,
            eventID: event.id
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

private actor TestCalendarBridge: CalendarBridging {
    private let result: CalendarAddResult

    init(result: CalendarAddResult) {
        self.result = result
    }

    func addEvent(_ request: CalendarAddRequest) async -> CalendarAddResult {
        _ = request
        return result
    }
}
#endif
