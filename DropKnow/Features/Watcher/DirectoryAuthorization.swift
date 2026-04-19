import Foundation

public struct WatchDirectoryRegistration: Sendable, Equatable {
    public let id: String
    public let display_name: String
    public let path_hint: String
    public let bookmark_data: Data?
    public let is_default_downloads: Bool
    public let is_active: Bool

    public init(
        id: String,
        display_name: String,
        path_hint: String,
        bookmark_data: Data?,
        is_default_downloads: Bool,
        is_active: Bool
    ) {
        self.id = id
        self.display_name = display_name
        self.path_hint = path_hint
        self.bookmark_data = bookmark_data
        self.is_default_downloads = is_default_downloads
        self.is_active = is_active
    }
}

public struct AuthorizedWatchDirectory: Sendable, Equatable {
    public let id: String
    public let display_name: String
    public let directory_url: URL
    public let is_default_downloads: Bool

    public init(id: String, display_name: String, directory_url: URL, is_default_downloads: Bool) {
        self.id = id
        self.display_name = display_name
        self.directory_url = directory_url
        self.is_default_downloads = is_default_downloads
    }
}

public enum DirectoryAuthorizationError: Error, Sendable, Equatable {
    case permission_denied(path: String)
    case bookmark_access_failed(path: String)
    case invalid_path(path: String)
    case not_directory(path: String)
}

public protocol DirectoryAuthorizing: Sendable {
    func defaultDownloadsRegistration() -> WatchDirectoryRegistration
    func normalizeForV1(_ registrations: [WatchDirectoryRegistration]) -> [WatchDirectoryRegistration]
    func authorize(_ registration: WatchDirectoryRegistration) throws -> AuthorizedWatchDirectory
}

public struct DefaultDirectoryAuthorizer: DirectoryAuthorizing {
    public init() {}

    public func defaultDownloadsRegistration() -> WatchDirectoryRegistration {
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)

        return WatchDirectoryRegistration(
            id: "watch_default_downloads",
            display_name: "Downloads",
            path_hint: downloadsURL.path,
            bookmark_data: nil,
            is_default_downloads: true,
            is_active: true
        )
    }

    public func normalizeForV1(_ registrations: [WatchDirectoryRegistration]) -> [WatchDirectoryRegistration] {
        let active = registrations.filter { $0.is_active }
        if active.isEmpty {
            return [defaultDownloadsRegistration()]
        }

        let downloads = active.first { $0.is_default_downloads }
        let custom = active.first { !$0.is_default_downloads }

        var result: [WatchDirectoryRegistration] = []
        if let downloads {
            result.append(downloads)
        }
        if let custom {
            result.append(custom)
        }

        return result
    }

    public func authorize(_ registration: WatchDirectoryRegistration) throws -> AuthorizedWatchDirectory {
        let url = try resolveURL(for: registration)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw DirectoryAuthorizationError.invalid_path(path: url.path)
        }
        guard isDirectory.boolValue else {
            throw DirectoryAuthorizationError.not_directory(path: url.path)
        }
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            if registration.bookmark_data != nil {
                throw DirectoryAuthorizationError.bookmark_access_failed(path: url.path)
            }
            throw DirectoryAuthorizationError.permission_denied(path: url.path)
        }

        return AuthorizedWatchDirectory(
            id: registration.id,
            display_name: registration.display_name,
            directory_url: url,
            is_default_downloads: registration.is_default_downloads
        )
    }

    private func resolveURL(for registration: WatchDirectoryRegistration) throws -> URL {
        if let bookmarkData = registration.bookmark_data {
            var isStale = false
            do {
                let resolved = try URL(
                    resolvingBookmarkData: bookmarkData,
                    options: [.withoutUI, .withoutMounting],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                if isStale {
                    throw DirectoryAuthorizationError.bookmark_access_failed(path: registration.path_hint)
                }
                return resolved
            } catch {
                throw DirectoryAuthorizationError.bookmark_access_failed(path: registration.path_hint)
            }
        }

        return URL(fileURLWithPath: registration.path_hint, isDirectory: true)
    }
}

extension DirectoryAuthorizationError {
    var errorCode: ErrorCode {
        switch self {
        case .permission_denied:
            return .watch_permission_denied
        case .bookmark_access_failed:
            return .watch_bookmark_access_failed
        case .invalid_path, .not_directory:
            return .watch_permission_denied
        }
    }
}
