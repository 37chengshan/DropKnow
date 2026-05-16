import EventKit
import Foundation
import AppKit

final class CalendarService {
    private let eventStore = EKEventStore()

    func add(event: EventCandidate, file: DropFile) async throws {
        guard let startDate = event.startTime else {
            throw CalendarError.missingDate
        }

        let granted: Bool
        if #available(macOS 14.0, *) {
            granted = try await eventStore.requestFullAccessToEvents()
        } else {
            granted = try await withCheckedThrowingContinuation { continuation in
                eventStore.requestAccess(to: .event) { allowed, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: allowed)
                    }
                }
            }
        }

        guard granted else {
            throw CalendarError.denied
        }

        guard let targetCalendar = writableCalendar() else {
            throw CalendarError.noWritableCalendar
        }

        let calendarEvent = EKEvent(eventStore: eventStore)
        calendarEvent.title = event.title
        calendarEvent.startDate = startDate
        calendarEvent.isAllDay = !event.hasClockTime
        calendarEvent.endDate = event.endTime ?? Calendar.current.date(
            byAdding: calendarEvent.isAllDay ? .day : .hour,
            value: 1,
            to: startDate
        )
        calendarEvent.location = event.location
        calendarEvent.notes = """
        \(event.note)

        来源文件：\(file.fileName)
        路径：\(file.filePath)

        证据：\(event.evidence)
        """
        calendarEvent.calendar = targetCalendar
        try eventStore.save(calendarEvent, span: .thisEvent, commit: true)
    }

    func openCalendarPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    private func writableCalendar() -> EKCalendar? {
        if let calendar = eventStore.defaultCalendarForNewEvents, calendar.allowsContentModifications {
            return calendar
        }
        return eventStore.calendars(for: .event).first { $0.allowsContentModifications }
    }
}

enum CalendarError: LocalizedError {
    case missingDate
    case denied
    case noWritableCalendar

    var errorDescription: String? {
        switch self {
        case .missingDate: "该候选事件缺少可写入日历的具体时间"
        case .denied: "未获得日历访问权限，请在系统设置中允许落知访问日历"
        case .noWritableCalendar: "没有可写入的日历，请先在系统日历中启用一个可编辑日历"
        }
    }
}
