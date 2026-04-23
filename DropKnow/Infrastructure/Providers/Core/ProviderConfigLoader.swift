import Foundation

public enum ProviderConfigSource: Sendable {
    case file(URL)
    case environment
}

/// Loads provider configurations from a JSON file.
///
/// File format (`~/Library/Application Support/DropKnow/providers.json`):
/// ```json
/// [
///   {
///     "provider_id": "provider_summary",
///     "base_url": "https://api.example.com/v1/summary",
///     "model_name": "qwen-plus",
///     "timeout_ms": 8000
///   }
/// ]
/// ```
///
/// If the file does not exist, returns an empty array.
/// Callers should treat an empty array as "unconfigured" and fall back to
/// safe defaults (empty base_url + mock transport) rather than crashing.
public enum ProviderConfigLoader {
    private static let configFileName = "providers.json"

    /// Returns the default provider config file URL:
    /// `~/Library/Application Support/DropKnow/providers.json`
    public static func defaultConfigURL() -> URL? {
        try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        .appendingPathComponent("DropKnow", isDirectory: true)
        .appendingPathComponent(configFileName)
    }

    /// Loads all provider configurations from the given source.
    /// - Parameter source: `.file(URL)` to load from a specific file, or `.environment` to use
    ///   `~/Library/Application Support/DropKnow/providers.json`.
    /// - Returns: An array of `ProviderConfig` entries found in the file, or an empty array if
    ///   the file does not exist or cannot be decoded. Never throws.
    public static func load(source: ProviderConfigSource) -> [ProviderConfig] {
        let url: URL?
        switch source {
        case .file(let fileURL):
            url = fileURL
        case .environment:
            url = defaultConfigURL()
        }

        guard let targetURL = url else { return [] }

        guard FileManager.default.fileExists(atPath: targetURL.path) else { return [] }

        do {
            let data = try Data(contentsOf: targetURL)
            let decoder = JSONDecoder()
            return try decoder.decode([ProviderConfig].self, from: data)
        } catch {
            // File exists but malformed — treat as unconfigured.
            return []
        }
    }

    /// Loads from the environment path (`~/Library/Application Support/DropKnow/providers.json`).
    public static func load() -> [ProviderConfig] {
        load(source: .environment)
    }
}
