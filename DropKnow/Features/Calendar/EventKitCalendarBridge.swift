import Foundation
import EventKit

public actor EventKitCalendarBridge: CalendarBridging {
    private let eventStore: EKEventStore

    public init() {
        self.eventStore = EKEventStore()
    }

    public func addEvent(_ request: CalendarAddRequest) async -> CalendarAddResult {
        if request.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .writeFailed
        }

        let granted = await requestAccessIfNeeded()
        guard granted else {
            return .permissionDenied
        }

        let event = EKEvent(eventStore: eventStore)
        event.title = request.title

        if let startStr = request.start_time {
            event.startDate = parseDate(startStr)
        } else {
            event.startDate = Date()
        }

        if let endStr = request.end_time {
            event.endDate = parseDate(endStr)
        } else {
            event.endDate = event.startDate.addingTimeInterval(3600)
        }

        if let tz = request.timezone, let timezone = TimeZone(identifier: tz) {
            event.timeZone = timezone
        }

        event.location = request.location
        event.notes = request.notes
        event.calendar = eventStore.defaultCalendarForNewEvents

        do {
            try eventStore.save(event, span: .thisEvent)
            guard let identifier = event.eventIdentifier else {
                return .writeFailed
            }
            return .added(eventIdentifier: identifier)
        } catch {
            return .writeFailed
        }
    }

    private func requestAccessIfNeeded() async -> Bool {
        if #available(macOS 14.0, *) {
            let status = EKEventStore.authorizationStatus(for: .event)
            switch status {
            case .fullAccess, .writeOnly:
                return true
            case .notDetermined:
                return await withCheckedContinuation { continuation in
                    eventStore.requestWriteOnlyAccessToEvents { granted, _ in
                        continuation.resume(returning: granted)
                    }
                }
            case .denied, .restricted:
                return false
            @unknown default:
                return false
            }
        } else {
            let status = EKEventStore.authorizationStatus(for: .event)
            switch status {
            case .authorized:
                return true
            case .notDetermined:
                return await withCheckedContinuation { continuation in
                    eventStore.requestAccess(to: .event) { granted, _ in
                        continuation.resume(returning: granted)
                    }
                }
            case .denied, .restricted, .fullAccess, .writeOnly:
                return false
            @unknown default:
                return false
            }
        }
    }

    private func parseDate(_ string: String) -> Date? {
        let formatters: [any DateFormatterProtocol] = [
            ISO8601DateFormatter(),
            {
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
                return f
            }(),
            {
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd HH:mm:ss"
                return f
            }()
        ]
        for formatter in formatters {
            if let iso = formatter as? ISO8601DateFormatter, let date = iso.date(from: string) {
                return date
            }
            if let df = formatter as? DateFormatter, let date = df.date(from: string) {
                return date
            }
        }
        return nil
    }
}

private protocol DateFormatterProtocol {}

extension ISO8601DateFormatter: DateFormatterProtocol {}
extension DateFormatter: DateFormatterProtocol {}
