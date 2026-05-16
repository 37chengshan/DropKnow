import Foundation
import os

enum PerfTrace {
    private static let logger = Logger(subsystem: "DropKnow", category: "perf")
    private static let clock = ContinuousClock()

    static func measure<T>(_ name: String, metadata: [String: String] = [:], work: () throws -> T) rethrows -> T {
        let start = clock.now
        do {
            let value = try work()
            log(name: name, start: start, success: true, metadata: metadata)
            return value
        } catch {
            log(name: name, start: start, success: false, metadata: metadata)
            throw error
        }
    }

    static func measure<T>(_ name: String, metadata: [String: String] = [:], work: () async throws -> T) async rethrows -> T {
        let start = clock.now
        do {
            let value = try await work()
            log(name: name, start: start, success: true, metadata: metadata)
            return value
        } catch {
            log(name: name, start: start, success: false, metadata: metadata)
            throw error
        }
    }

    static func log(name: String, start: ContinuousClock.Instant, success: Bool, metadata: [String: String] = [:]) {
        let duration = clock.now - start
        let ms = milliseconds(duration)
        let tail = format(metadata)
        logger.info("name=\(name, privacy: .public) ok=\(success ? 1 : 0, privacy: .public) ms=\(ms, format: .fixed(precision: 2), privacy: .public)\(tail, privacy: .public)")
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1000 + Double(components.attoseconds) / 1_000_000_000_000_000
    }

    private static func format(_ metadata: [String: String]) -> String {
        guard !metadata.isEmpty else { return "" }
        let text = metadata
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        return " " + text
    }
}
