import Foundation

enum AppPaths {
    static var appSupportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = base.appendingPathComponent("DropKnow", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static var providerConfigURL: URL {
        appSupportDirectory.appendingPathComponent("providers.local.json")
    }

    static var databaseURL: URL {
        appSupportDirectory.appendingPathComponent("dropknow_state.json")
    }

    static var ragStoreURL: URL {
        let directory = appSupportDirectory.appendingPathComponent("RAG", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static var settingsURL: URL {
        appSupportDirectory.appendingPathComponent("settings.json")
    }

    static var runtimeURL: URL {
        appSupportDirectory.appendingPathComponent("dropknow_runtime.json")
    }
}

extension DateFormatter {
    static let dropShort: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

extension ByteCountFormatter {
    static let dropFileSize: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()
}
