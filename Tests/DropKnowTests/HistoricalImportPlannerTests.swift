import XCTest
@testable import DropKnow

final class HistoricalImportPlannerTests: XCTestCase {
    func testPromptAppearsForMissingStateWhenHistoricalFilesExist() throws {
        let directory = try makeTempDirectory()
        let now = Date(timeIntervalSince1970: 10_000)
        let referenceDate = now
        try createFile(
            at: directory.appendingPathComponent("notice.pdf"),
            modifiedAt: now.addingTimeInterval(-3600)
        )
        try createFile(
            at: directory.appendingPathComponent("old.md"),
            modifiedAt: now.addingTimeInterval(-10 * 24 * 3600)
        )

        let prompt = HistoricalImportPlanner.promptState(
            for: .missingState,
            directories: [directory.path],
            recentDays: 7,
            referenceDate: referenceDate,
            now: now
        )

        XCTAssertNotNil(prompt)
        XCTAssertEqual(prompt?.totalHistoricalCount, 2)
        XCTAssertEqual(prompt?.recentCandidateCount, 1)
    }

    func testLoadedStateDoesNotPrompt() throws {
        let directory = try makeTempDirectory()
        let now = Date(timeIntervalSince1970: 10_000)
        try createFile(
            at: directory.appendingPathComponent("notice.pdf"),
            modifiedAt: now.addingTimeInterval(-3600)
        )

        let prompt = HistoricalImportPlanner.promptState(
            for: .loadedState,
            directories: [directory.path],
            recentDays: 7,
            referenceDate: now,
            now: now
        )

        XCTAssertNil(prompt)
    }

    func testSevenDayWindowExcludesOlderHistoricalFiles() throws {
        let directory = try makeTempDirectory()
        let now = Date(timeIntervalSince1970: 20_000)
        try createFile(
            at: directory.appendingPathComponent("recent.txt"),
            modifiedAt: now.addingTimeInterval(-2 * 24 * 3600)
        )
        try createFile(
            at: directory.appendingPathComponent("older.txt"),
            modifiedAt: now.addingTimeInterval(-9 * 24 * 3600)
        )

        let discovery = HistoricalImportPlanner.discover(
            in: [directory.path],
            recentDays: 7,
            referenceDate: now,
            now: now
        )

        XCTAssertEqual(discovery.totalHistoricalCount, 2)
        XCTAssertEqual(discovery.recentCandidateCount, 1)
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
