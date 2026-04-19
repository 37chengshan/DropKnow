import Foundation
#if canImport(XCTest)
import XCTest
#if canImport(DropKnow)
@testable import DropKnow
#endif

final class ErrorCodeRetryPolicyTests: XCTestCase {
    private struct ErrorHolder: Codable, Equatable {
        let error_code: ErrorCode
    }

    func testErrorCodeDecodeUnknownFallsBack() throws {
        let data = #"{"error_code":"new_unexpected_code"}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ErrorHolder.self, from: data)
        XCTAssertEqual(decoded.error_code, .unknown)
    }

    func testRetryDispositionForAutoRetryCode() {
        XCTAssertEqual(ErrorCode.summary_provider_timeout.retryDisposition, .auto_retry)
    }

    func testRetryDispositionForRepairThenRetryOnceCode() {
        XCTAssertEqual(ErrorCode.summary_invalid_json.retryDisposition, .repair_then_retry_once)
    }

    func testRetryDispositionForNonRetryableCode() {
        XCTAssertEqual(ErrorCode.calendar_permission_denied.retryDisposition, .no_auto_retry)
    }
}
#else
struct ErrorCodeRetryPolicySmokeTests {
    static func run() {
        struct ErrorHolder: Codable {
            let error_code: ErrorCode
        }
        let data = #"{"error_code":"new_unexpected_code"}"#.data(using: .utf8)!
        let decoded = try! JSONDecoder().decode(ErrorHolder.self, from: data)
        assert(decoded.error_code == .unknown)
        assert(ErrorCode.summary_provider_timeout.retryDisposition == .auto_retry)
        assert(ErrorCode.summary_invalid_json.retryDisposition == .repair_then_retry_once)
        assert(ErrorCode.calendar_permission_denied.retryDisposition == .no_auto_retry)
    }
}
#endif
