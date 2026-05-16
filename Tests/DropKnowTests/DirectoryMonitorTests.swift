import XCTest
@testable import DropKnow

final class DirectoryMonitorTests: XCTestCase {
    func testOlderFileCanBeDiscoveredAfterLaterModification() throws {
        let workspace = try makeTempDirectory()
        let fileURL = workspace.appendingPathComponent("notice.md")
        try createFile(at: fileURL, modifiedAt: Date(timeIntervalSince1970: 100))

        let monitor = DirectoryMonitor()
        let sessionStartedAt = Date(timeIntervalSince1970: 200)

        XCTAssertTrue(
            monitor.newStableFiles(
                in: [workspace.path],
                modifiedAfter: sessionStartedAt
            ).isEmpty
        )

        try createFile(at: fileURL, modifiedAt: Date(timeIntervalSince1970: 300))

        let discovered = monitor.newStableFiles(
            in: [workspace.path],
            modifiedAfter: sessionStartedAt
        )

        XCTAssertEqual(discovered.map { $0.standardizedFileURL.path }, [fileURL.standardizedFileURL.path])
    }

    private func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func createFile(at url: URL, modifiedAt: Date) throws {
        try Data("test".utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: url.path)
    }
}
