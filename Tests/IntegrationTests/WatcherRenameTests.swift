import Foundation
#if canImport(XCTest)
import XCTest
#if canImport(DropKnow)
@testable import DropKnow
#endif

final class WatcherRenameTests: XCTestCase {
    func testRenameFromDownloadTempToFinalFileEmitsReadyEvent() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dropknow_watcher_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let registration = WatchDirectoryRegistration(
            id: "watch_test",
            display_name: "test",
            path_hint: root.path,
            bookmark_data: nil,
            is_default_downloads: false,
            is_active: true
        )

        let watcher = DirectoryWatcherService(
            registrations: [registration],
            poll_interval_ms: 100,
            debounce_ms: 80,
            initial_scan_days: 0
        )

        let stream = await watcher.makeEventStream()

        let expectation = expectation(description: "ready file emitted")
        Task {
            for await event in stream {
                if case .file_ready(let ready) = event, ready.file_url.lastPathComponent == "final-note.txt" {
                    expectation.fulfill()
                    break
                }
            }
        }

        let tempDownload = root.appendingPathComponent("final-note.txt.crdownload")
        let finalFile = root.appendingPathComponent("final-note.txt")

        try "demo".write(to: tempDownload, atomically: true, encoding: .utf8)
        try FileManager.default.moveItem(at: tempDownload, to: finalFile)

        wait(for: [expectation], timeout: 8)
    }
}
#endif
