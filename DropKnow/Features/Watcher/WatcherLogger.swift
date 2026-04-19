import Foundation

enum WatcherLogger {
    enum Level: String {
        case debug = "DEBUG"
        case info = "INFO"
        case warn = "WARN"
        case error = "ERROR"
    }

    static func log(_ level: Level, _ message: String, context: [String: String] = [:]) {
        let contextText: String
        if context.isEmpty {
            contextText = ""
        } else {
            let pairs = context.keys.sorted().map { "\($0)=\(context[$0] ?? "")" }
            contextText = " | " + pairs.joined(separator: " ")
        }
        print("[Watcher][\(level.rawValue)] \(message)\(contextText)")
    }
}
