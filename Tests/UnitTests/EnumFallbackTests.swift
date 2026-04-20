import Foundation
#if canImport(XCTest)
import XCTest
#if canImport(DropKnow)
@testable import DropKnow
#endif

final class EnumFallbackTests: XCTestCase {
    private struct LifecycleHolder: Codable, Equatable {
        let lifecycle_status: DocumentLifecycleStatus
    }

    func testDocumentLifecycleStatusDecodeKnownValue() throws {
        let data = #"{"lifecycle_status":"processing"}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(LifecycleHolder.self, from: data)
        XCTAssertEqual(decoded.lifecycle_status, .processing)
    }

    func testDocumentLifecycleStatusDecodeUnknownFallsBack() throws {
        let data = #"{"lifecycle_status":"future_state"}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(LifecycleHolder.self, from: data)
        XCTAssertEqual(decoded.lifecycle_status, .unknown)
    }

    func testDatabaseMapperUsesUnknownFallbackForDirtyStates() {
        let dto = DatabaseRowMapper.toDTO(Self.makeDirtyRow())
        XCTAssertEqual(dto.lifecycle_status, .unknown)
        XCTAssertEqual(dto.current_stage, .unknown)
        XCTAssertEqual(dto.block_reason, .unknown)
        XCTAssertEqual(dto.event_status, .unknown)
    }

    private static func makeDirtyRow() -> DocumentRow {
        DocumentRow(
            id: "doc_1",
            watch_directory_id: nil,
            file_name: "file.pdf",
            file_extension: "pdf",
            absolute_path: "/tmp/file.pdf",
            file_hash: "hash",
            file_size: 128,
            imported_at: "2026-04-18 10:00:00",
            lifecycle_status: "bad_status",
            current_stage: "bad_stage",
            block_reason: "bad_reason",
            event_status: "bad_event_status",
            parse_status: nil,
            summary_status: nil,
            privacy_status: nil,
            readiness_flags_json: "{}",
            importance_score: 0,
            last_error_code: nil,
            last_error_message: nil
        )
    }
}
#else
struct EnumFallbackSmokeTests {
    static func run() {
        struct LifecycleHolder: Codable {
            let lifecycle_status: DocumentLifecycleStatus
        }
        let data = #"{"lifecycle_status":"future_state"}"#.data(using: .utf8)!
        let decoded = try! JSONDecoder().decode(LifecycleHolder.self, from: data)
        assert(decoded.lifecycle_status == .unknown)
        let dto = DatabaseRowMapper.toDTO(
            DocumentRow(
                id: "doc_1",
                watch_directory_id: nil,
                file_name: "file.pdf",
                file_extension: "pdf",
                absolute_path: "/tmp/file.pdf",
                file_hash: "hash",
                file_size: 128,
                imported_at: "2026-04-18 10:00:00",
                lifecycle_status: "bad_status",
                current_stage: "bad_stage",
                block_reason: "bad_reason",
                event_status: "bad_event_status",
                parse_status: nil,
                summary_status: nil,
                privacy_status: nil,
                readiness_flags_json: "{}",
                importance_score: 0,
                last_error_code: nil,
                last_error_message: nil
            )
        )
        assert(dto.lifecycle_status == .unknown)
    }
}
#endif
