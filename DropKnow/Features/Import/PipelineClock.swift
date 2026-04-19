import Foundation

enum PipelineClock {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    static func nowString() -> String {
        formatter.string(from: Date())
    }

    static func format(_ date: Date) -> String {
        formatter.string(from: date)
    }

    static func durationMs(since start: Date) -> Int {
        Int(Date().timeIntervalSince(start) * 1000)
    }
}
