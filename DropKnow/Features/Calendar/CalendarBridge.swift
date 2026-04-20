import Foundation

public struct CalendarAddRequest: Sendable, Equatable {
    public let title: String
    public let start_time: String?
    public let end_time: String?
    public let timezone: String?
    public let location: String?
    public let notes: String?

    public init(
        title: String,
        start_time: String?,
        end_time: String?,
        timezone: String?,
        location: String?,
        notes: String?
    ) {
        self.title = title
        self.start_time = start_time
        self.end_time = end_time
        self.timezone = timezone
        self.location = location
        self.notes = notes
    }
}

public enum CalendarAddResult: Sendable, Equatable {
    case added(eventIdentifier: String)
    case featureLocked
    case notEligible
    case permissionDenied
    case writeFailed
}

public protocol CalendarBridging: Sendable {
    func addEvent(_ request: CalendarAddRequest) async -> CalendarAddResult
}

public actor InMemoryCalendarBridge: CalendarBridging {
    public init() {}

    public func addEvent(_ request: CalendarAddRequest) async -> CalendarAddResult {
        if request.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .writeFailed
        }
        return .added(eventIdentifier: "cal_\(UUID().uuidString)")
    }
}

public protocol CalendarFeatureServicing: Sendable {
    func addEvent(from event: DocumentEventDTO) async -> CalendarAddResult
}

public actor CalendarFeatureService: CalendarFeatureServicing {
    private let bridge: any CalendarBridging
    private let subscriptionService: SubscriptionFeatureServicing

    public init(
        bridge: any CalendarBridging,
        subscriptionService: SubscriptionFeatureServicing
    ) {
        self.bridge = bridge
        self.subscriptionService = subscriptionService
    }

    public func addEvent(from event: DocumentEventDTO) async -> CalendarAddResult {
        if await !subscriptionService.canUseCalendarFeature() {
            return .featureLocked
        }
        if !event.calendar_eligible {
            return .notEligible
        }

        let request = CalendarAddRequest(
            title: event.title,
            start_time: event.start_time,
            end_time: event.end_time,
            timezone: event.timezone,
            location: event.location,
            notes: event.notes
        )
        return await bridge.addEvent(request)
    }
}
