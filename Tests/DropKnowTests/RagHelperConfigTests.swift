import XCTest

final class RagHelperConfigTests: XCTestCase {
    func testInvalidProvidersConfigReturnsConfigInvalidErrorCode() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true, attributes: nil)
        defer { try? FileManager.default.removeItem(at: base) }

        let store = base.appendingPathComponent("rag_store")
        let config = base.appendingPathComponent("providers.local.json")
        try Data("{ bad json".utf8).write(to: config)

        let object = try runHelper(
            script: try ragHelperScriptURL(),
            mode: "chat",
            store: store,
            payload: #"{"query":"hello"}"#
        )

        XCTAssertEqual(object["ok"] as? Bool, false)
        XCTAssertEqual(object["errorCode"] as? String, "CONFIG_INVALID")
    }

    func testRagHelperDiagnosticsModeReturnsMetadataCounts() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true, attributes: nil)
        defer { try? FileManager.default.removeItem(at: base) }

        let object = try runHelper(
            script: try ragHelperScriptURL(),
            mode: "diagnostics",
            store: base.appendingPathComponent("rag_store"),
            payload: "{}"
        )

        let diagnostics = object["diagnostics"] as? [String: Any]
        XCTAssertEqual(object["ok"] as? Bool, true)
        XCTAssertEqual(diagnostics?["indexedFileCount"] as? Int, 0)
        XCTAssertEqual(diagnostics?["chunkCount"] as? Int, 0)
        XCTAssertEqual(diagnostics?["activeRevisionCount"] as? Int, 0)
        XCTAssertEqual(diagnostics?["emptyIndex"] as? Bool, true)
    }

    private func ragHelperScriptURL() throws -> URL {
        let fileURL = URL(fileURLWithPath: #file)
        let root = fileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let script = root
            .appendingPathComponent("Sources")
            .appendingPathComponent("DropKnow")
            .appendingPathComponent("Scripts")
            .appendingPathComponent("rag_helper.py")
        XCTAssertTrue(FileManager.default.fileExists(atPath: script.path))
        return script
    }

    private func runHelper(script: URL, mode: String, store: URL, payload: String) throws -> [String: Any] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [script.path, mode, "--store", store.path]

        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = Pipe()

        let expectation = expectation(description: "rag_helper terminates")
        process.terminationHandler = { _ in
            expectation.fulfill()
        }

        try process.run()
        input.fileHandleForWriting.write(payload.data(using: .utf8) ?? Data())
        input.fileHandleForWriting.closeFile()

        wait(for: [expectation], timeout: 3)
        if process.isRunning {
            process.terminate()
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return object ?? [:]
    }
}
