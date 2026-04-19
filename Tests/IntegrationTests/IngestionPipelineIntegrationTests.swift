import Foundation
#if canImport(XCTest)
import XCTest
#if canImport(DropKnow)
@testable import DropKnow
#endif

final class IngestionPipelineIntegrationTests: XCTestCase {
    func testPipelineSmokeRunWritesDocumentAndJobs() async {
        let runner = EndToEndSmokeRunner()
        let report = await runner.runSingleDocument(
            fileName: "integration_pipeline.txt",
            content: "明天下午四点去体检中心复查。"
        )

        XCTAssertFalse(report.recent_documents.isEmpty)

        guard let document = report.recent_documents.first else {
            XCTFail("expected a document")
            return
        }

        XCTAssertEqual(document.current_stage, .done)
        XCTAssertEqual(document.lifecycle_status, .ready)
        XCTAssertTrue(document.event_status == .has_candidate || document.event_status == .has_calendar_event)

        let stages = Set(report.parse_jobs.map { $0.stage })
        XCTAssertTrue(stages.contains(.import))
        XCTAssertTrue(stages.contains(.parse))
        XCTAssertTrue(stages.contains(.gate))
        XCTAssertTrue(stages.contains(.summary))
        XCTAssertTrue(stages.contains(.event_extract))
        XCTAssertTrue(stages.contains(.index))
        XCTAssertTrue(stages.contains(.notify))
        XCTAssertFalse(report.events.isEmpty)
    }
}
#endif
