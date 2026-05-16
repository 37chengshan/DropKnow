import Foundation

final class DirectoryMonitor {
    private var timer: Timer?
    private var seen: Set<String> = []
    var onTick: (() -> Void)?

    func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            self?.onTick?()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func markSeen(_ paths: [String]) {
        seen.formUnion(paths)
    }

    func newStableFiles(in directories: [String], modifiedAfter: Date? = nil, limit: Int? = nil) -> [URL] {
        var candidates: [(url: URL, modifiedAt: Date)] = []
        let manager = FileManager.default
        for directory in directories {
            guard let enumerator = manager.enumerator(
                at: URL(fileURLWithPath: directory, isDirectory: true),
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator {
                guard DocumentParser.kind(for: url) != .unsupported,
                      !seen.contains(url.path),
                      isStable(url: url) else { continue }
                let modifiedAt = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                if let modifiedAfter, modifiedAt < modifiedAfter {
                    continue
                }
                seen.insert(url.path)
                candidates.append((url: url, modifiedAt: modifiedAt))
            }
        }
        candidates.sort { $0.modifiedAt > $1.modifiedAt }
        if let limit {
            return Array(candidates.prefix(limit).map(\.url))
        }
        return candidates.map(\.url)
    }

    private func isStable(url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        if name.hasSuffix(".download") || name.hasSuffix(".crdownload") || name.hasSuffix(".tmp") || name.hasPrefix("~$") {
            return false
        }
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]),
              values.isRegularFile == true,
              let modified = values.contentModificationDate,
              let size = values.fileSize,
              size > 0 else {
            return false
        }
        return Date().timeIntervalSince(modified) > 2
    }
}
