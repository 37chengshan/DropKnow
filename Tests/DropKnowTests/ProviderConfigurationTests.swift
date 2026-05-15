import XCTest
@testable import DropKnow

final class ProviderConfigurationTests: XCTestCase {
    func testEnvKeyOverridesLocalFile() throws {
        let workspace = try makeTempDirectory()
        let configURL = workspace.appendingPathComponent("providers.local.json")
        try Data(#"{"api_key":"file-key"}"#.utf8).write(to: configURL)

        let config = ProviderConfiguration.load(
            environment: ["DASHSCOPE_API_KEY": "env-key"],
            configURL: configURL
        )

        XCTAssertEqual(config.apiKey, "env-key")
        XCTAssertTrue(config.hasAPIKey)
        XCTAssertEqual(config.source, .environment)
    }

    func testLoadsKeyFromLocalFileWhenEnvMissing() throws {
        let workspace = try makeTempDirectory()
        let configURL = workspace.appendingPathComponent("providers.local.json")
        try Data(#"{"api_key":"file-key"}"#.utf8).write(to: configURL)

        let config = ProviderConfiguration.load(environment: [:], configURL: configURL)

        XCTAssertEqual(config.apiKey, "file-key")
        XCTAssertTrue(config.hasAPIKey)
        XCTAssertEqual(config.source, .file)
    }

    func testNoKeyReturnsEmpty() throws {
        let workspace = try makeTempDirectory()
        let configURL = workspace.appendingPathComponent("providers.local.json")

        let config = ProviderConfiguration.load(environment: [:], configURL: configURL)

        XCTAssertEqual(config.apiKey, "")
        XCTAssertFalse(config.hasAPIKey)
        XCTAssertEqual(config.source, .missing)
    }

    private func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
