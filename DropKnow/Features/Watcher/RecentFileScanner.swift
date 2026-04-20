import Foundation

public struct RecentFileCandidate: Sendable, Hashable {
    public let file_url: URL
    public let file_size: Int64
    public let modified_at_fs: String?
    public let modified_at: Date?

    public init(file_url: URL, file_size: Int64, modified_at_fs: String?, modified_at: Date?) {
        self.file_url = file_url
        self.file_size = file_size
        self.modified_at_fs = modified_at_fs
        self.modified_at = modified_at
    }
}

public protocol RecentFileScanning: Sendable {
    func enumerateRecentFiles(directory: AuthorizedWatchDirectory, days: Int) throws -> [RecentFileCandidate]
    func snapshot(directory: AuthorizedWatchDirectory) throws -> [String: RecentFileCandidate]
}

public struct DefaultRecentFileScanner: RecentFileScanning {
    public init() {}

    public func enumerateRecentFiles(directory: AuthorizedWatchDirectory, days: Int = 7) throws -> [RecentFileCandidate] {
        let cutoff = Calendar(identifier: .gregorian).date(byAdding: .day, value: -max(days, 0), to: Date())
        let all = try scanFiles(directory: directory)
        return all
            .filter { candidate in
                guard let cutoff else { return true }
                guard let modified = candidate.modified_at else { return false }
                return modified >= cutoff
            }
            .sorted { lhs, rhs in
                (lhs.modified_at ?? .distantPast) > (rhs.modified_at ?? .distantPast)
            }
    }

    public func snapshot(directory: AuthorizedWatchDirectory) throws -> [String: RecentFileCandidate] {
        let list = try scanFiles(directory: directory)
        var map: [String: RecentFileCandidate] = [:]
        for item in list {
            map[item.file_url.path] = item
        }
        return map
    }

    private func scanFiles(directory: AuthorizedWatchDirectory) throws -> [RecentFileCandidate] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]

        guard let enumerator = FileManager.default.enumerator(
            at: directory.directory_url,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else {
            throw DirectoryAuthorizationError.permission_denied(path: directory.directory_url.path)
        }

        var candidates: [RecentFileCandidate] = []
        for case let fileURL as URL in enumerator {
            if TemporaryFileFilter.shouldSkip(fileURL) {
                continue
            }

            let values = try fileURL.resourceValues(forKeys: keys)
            guard values.isRegularFile == true else {
                continue
            }

            let size = Int64(values.fileSize ?? 0)
            let modified = values.contentModificationDate
            candidates.append(
                RecentFileCandidate(
                    file_url: fileURL,
                    file_size: size,
                    modified_at_fs: modified.map { PipelineClock.format($0) },
                    modified_at: modified
                )
            )
        }

        return candidates
    }
}
