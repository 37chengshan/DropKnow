import XCTest
@testable import DropKnow

final class DocumentParserHeuristicsTests: XCTestCase {
    func testActionAndDateProduceHighConfidenceEvent() {
        let text = "高数考试时间为5月1日10:00，地点：A101，请准时参加。"

        let events = EventExtractor.extract(from: text, fileName: "考试通知.pdf")

        XCTAssertEqual(events.first?.eventType, .exam)
        XCTAssertTrue((events.first?.confidence ?? 0) >= 0.72)
        XCTAssertEqual(events.first?.location, "A101")
    }

    func testDateOnlyEvidenceDoesNotBecomeHighConfidence() {
        let text = "附件开放时间为5月1日，详见后续说明。"

        let events = EventExtractor.extract(from: text, fileName: "普通通知.pdf")

        XCTAssertTrue(events.allSatisfy { $0.confidence < 0.72 })
    }
}
