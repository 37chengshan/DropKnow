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

        let readyExpectation = expectation(description: "ready file emitted")
        let scanReadyExpectation = expectation(description: "initial scan completed")
        Task {
            for await event in stream {
                switch event {
                case .initial_scan_completed:
                    scanReadyExpectation.fulfill()
                case .file_ready(let ready) where ready.file_url.lastPathComponent == "final-note.txt":
                    readyExpectation.fulfill()
                    return
                default:
                    continue
                }
            }
        }

        await fulfillment(of: [scanReadyExpectation], timeout: 4)

        let tempDownload = root.appendingPathComponent("final-note.txt.crdownload")
        let finalFile = root.appendingPathComponent("final-note.txt")

        try "demo".write(to: tempDownload, atomically: true, encoding: .utf8)
        try FileManager.default.moveItem(at: tempDownload, to: finalFile)

        await fulfillment(of: [readyExpectation], timeout: 10)
    }
}
#endif
