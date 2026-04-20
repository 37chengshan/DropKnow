import Foundation
import Observation

@Observable
public final class ImportantRemindersViewModel {
    public enum State: Equatable {
        case loading
        case empty
        case loaded
        case error(message: String)
    }

    public struct ReminderItem: Equatable, Sendable {
        public let event_id: String
        public let document_id: String
        public let file_name: String
        public let title: String
        public let time_text: String
        public let evidence_snippet: String
        public let is_high_priority: Bool

        public init(
            event_id: String,
            document_id: String,
            file_name: String,
            title: String,
            time_text: String,
            evidence_snippet: String,
            is_high_priority: Bool
        ) {
            self.event_id = event_id
            self.document_id = document_id
            self.file_name = file_name
            self.title = title
            self.time_text = time_text
            self.evidence_snippet = evidence_snippet
            self.is_high_priority = is_high_priority
        }
    }

    public private(set) var state: State = .loading
    public private(set) var items: [ReminderItem] = []

    private let service: any DashboardServicing

    public init(service: any DashboardServicing) {
        self.service = service
    }

    public func load(limit: Int = 30) async {
        state = .loading
        let result = await service.fetchImportantReminders(limit: limit)

        switch result {
        case .failure(let failure):
            items = []
            state = .error(message: failure.message)
        case .success(let reminders):
            items = reminders.map {
                ReminderItem(
                    event_id: $0.event_id,
                    document_id: $0.document_id,
                    file_name: $0.file_name,
                    title: $0.title,
                    time_text: $0.raw_time_text,
                    evidence_snippet: $0.evidence_snippet,
                    is_high_priority: $0.event_status == .has_calendar_event
                )
            }
            state = items.isEmpty ? .empty : .loaded
        }
    }
}
