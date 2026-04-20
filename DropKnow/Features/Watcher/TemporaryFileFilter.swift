import Foundation

enum TemporaryFileFilter {
    private static let temporaryExtensions: Set<String> = [
        "crdownload", "download", "part", "partial", "tmp", "temp", "ds_store"
    ]

    private static let temporaryPrefixes: [String] = [
        ".", "~$", "._"
    ]

    static func shouldSkip(_ url: URL) -> Bool {
        let fileName = url.lastPathComponent.lowercased()
        let ext = url.pathExtension.lowercased()

        if temporaryExtensions.contains(ext) {
            return true
        }

        return temporaryPrefixes.contains { fileName.hasPrefix($0) }
    }
}
