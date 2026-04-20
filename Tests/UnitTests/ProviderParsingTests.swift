import Foundation
#if canImport(XCTest)
import XCTest
#if canImport(DropKnow)
@testable import DropKnow
#endif

final class ProviderParsingTests: XCTestCase {
    func testSummaryProviderRejectsNoneRiskFlag() async {
        let config = ProviderConfig(
            provider_id: "summary_test",
            provider_type: .qwen,
            model_name: "mock",
            base_url: "mock://summary"
        )

        let client = MockProviderClient { _, _ in
            ProviderClientResponse(
                raw_text: """
                {
                  \"document_type\": \"notice\",
                  \"one_line_summary\": \"test\",
                  \"action_required\": \"read\",
                  \"key_points\": [\"a\"],
                  \"time_signals\": [{\"raw_time_text\": \"tomorrow\", \"normalized_time\": null, \"signal_type\": \"relative\"}],
                  \"location_signals\": [],
                  \"supporting_snippets\": [\"snippet\"],
                  \"risk_flags\": [\"none\"],
                  \"confidence\": 0.7
                }
                """
            )
        }

        let provider = SummaryProvider(config: config, client: client)
        let request = ProviderDocumentContextRequest(
            document_id: "doc_1",
            file_name: "a.txt",
            file_extension: "txt",
            reference_date: "2026-04-18",
            user_timezone: "Asia/Shanghai",
            plain_text: "hello",
            language_hint: "zh-CN"
        )

        do {
            _ = try await provider.generate(request: request)
            XCTFail("should fail schema validation")
        } catch let error as ProviderError {
            XCTAssertEqual(error.category, "schema_validation")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testSearchQACitationFieldsRequired() async {
        let config = ProviderConfig(
            provider_id: "qa_test",
            provider_type: .zhipu,
            model_name: "mock",
            base_url: "mock://qa"
        )

        let client = MockProviderClient { _, _ in
            ProviderClientResponse(
                raw_text: """
                {
                  \"answer\": \"ok\",
                  \"answer_type\": \"direct_answer\",
                  \"confidence\": 0.9,
                  \"citations\": [
                    {
                      \"document_id\": \"\",
                      \"chunk_id\": \"c1\",
                      \"file_name\": \"x.txt\",
                      \"evidence_snippet\": \"e\"
                    }
                  ]
                }
                """
            )
        }

        let provider = SearchQAProvider(config: config, client: client)
        let request = SearchQAProviderRequest(
            question: "Q",
            reference_date: "2026-04-18",
            user_timezone: "Asia/Shanghai",
            retrieved_items: [
                SearchQARetrievedItem(document_id: "d1", chunk_id: "c1", file_name: "x.txt", snippet: "e")
            ]
        )

        do {
            _ = try await provider.generate(request: request)
            XCTFail("should fail when citation fields are empty")
        } catch let error as ProviderError {
            XCTAssertEqual(error.category, "schema_validation")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
#endif
