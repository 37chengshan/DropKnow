import Foundation

enum ProviderConfigurationSource: String, Hashable {
    case environment = "环境变量"
    case file = "配置文件"
    case missing = "未配置"
}

struct ProviderConfiguration: Hashable {
    var apiKey: String
    var configURL: URL
    var source: ProviderConfigurationSource = .missing

    var hasAPIKey: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func load(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default,
        configURL: URL = AppPaths.providerConfigURL
    ) -> ProviderConfiguration {
        let envKey = (environment["DASHSCOPE_API_KEY"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var fileKey = ""
        if fileManager.fileExists(atPath: configURL.path),
           let data = try? Data(contentsOf: configURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let raw = json["api_key"] as? String {
            fileKey = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let resolved = envKey.isEmpty ? fileKey : envKey
        let source: ProviderConfigurationSource
        if !envKey.isEmpty {
            source = .environment
        } else if !fileKey.isEmpty {
            source = .file
        } else {
            source = .missing
        }
        return ProviderConfiguration(apiKey: resolved, configURL: configURL, source: source)
    }
}
