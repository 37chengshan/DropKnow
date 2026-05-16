import XCTest
@testable import DropKnow

final class StoredFileStateStoreTests: XCTestCase {
    func testMissingStateFileReturnsMissingStatus() throws {
        let directory = try makeTempDirectory()
        let fileURL = directory.appendingPathComponent("state.json")

        let result = StoredFileStateStore.load(from: fileURL)

        XCTAssertEqual(result.status, .missingState)
        XCTAssertTrue(result.files.isEmpty)
        XCTAssertNil(result.backupURL)
    }

    func testCorruptedStateFileIsBackedUpAndReported() throws {
        let directory = try makeTempDirectory()
        let fileURL = directory.appendingPathComponent("state.json")
        try Data("not-json".utf8).write(to: fileURL)

        let result = StoredFileStateStore.load(from: fileURL)

        XCTAssertEqual(result.status, .corruptedState)
        XCTAssertTrue(result.files.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertNotNil(result.backupURL)
        if let backupURL = result.backupURL {
            XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path))
        }
    }

    private func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
