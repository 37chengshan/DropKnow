import Foundation

public struct WatchDedupeSignature: Hashable, Sendable {
    public let file_hash: String
    public let file_size: Int64
    public let modified_at_fs: String?

    public init(file_hash: String, file_size: Int64, modified_at_fs: String?) {
        self.file_hash = file_hash
        self.file_size = file_size
        self.modified_at_fs = modified_at_fs
    }
}

public actor WatchEventDeduper {
    private var seen: [WatchDedupeSignature: Date] = [:]
    private let ttl_seconds: TimeInterval

    public init(ttl_seconds: TimeInterval = 24 * 60 * 60) {
        self.ttl_seconds = ttl_seconds
    }

    public func insertIfNew(_ signature: WatchDedupeSignature) -> Bool {
        cleanupIfNeeded()
        if seen[signature] != nil {
            return false
        }
        seen[signature] = Date()
        return true
    }

    public func seed(_ signatures: [WatchDedupeSignature]) {
        let now = Date()
        for signature in signatures {
            seen[signature] = now
        }
    }

    private func cleanupIfNeeded() {
        let deadline = Date().addingTimeInterval(-ttl_seconds)
        seen = seen.filter { $0.value >= deadline }
    }
}
