import Foundation

public actor MockProviderClient: ProviderClient {
    public typealias Handler = @Sendable (ProviderClientRequest, ProviderConfig) async throws -> ProviderClientResponse

    private let handler: Handler?

    public init(handler: Handler? = nil) {
        self.handler = handler
    }

    public func send(_ request: ProviderClientRequest, config: ProviderConfig) async throws -> ProviderClientResponse {
        if let handler {
            return try await handler(request, config)
        }
        return try await defaultResponse(for: request, config: config)
    }

    private func defaultResponse(for request: ProviderClientRequest, config: ProviderConfig) async throws -> ProviderClientResponse {
        if request.input_json.contains("SIMULATE_AUTH") {
            throw ProviderError.auth
        }
        if request.input_json.contains("SIMULATE_RATE_LIMIT") {
            throw ProviderError.rate_limited
        }
        if request.input_json.contains("SIMULATE_TIMEOUT") {
            throw ProviderError.timeout
        }
        if request.input_json.contains("SIMULATE_SERVICE_UNAVAILABLE") {
            throw ProviderError.service_unavailable
        }
        if request.input_json.contains("SIMULATE_OFFLINE") {
            throw ProviderError.offline
        }

        switch request.task {
        case .summary:
            if request.input_json.contains("SIMULATE_INVALID_JSON") {
                return ProviderClientResponse(raw_text: "{\"document_type\":\"unknown\",")
            }
            return ProviderClientResponse(
                raw_text: """
                {
                  "document_type": "general_notice",
                  "one_line_summary": "这是一份需要用户尽快处理的通知类文件。",
                  "action_required": "请确认时间、地点和需要准备的事项。",
                  "key_points": ["重点1：确认文件内容", "重点2：核对时间地点", "重点3：按要求完成后续动作"],
                  "time_signals": [{"raw_time_text": "明天", "normalized_time": null, "signal_type": "relative"}],
                  "location_signals": ["上海"],
                  "supporting_snippets": ["文档里明确提到了时间与地点信息。"],
                  "risk_flags": [],
                  "confidence": 0.82
                }
                """,
                response_id: UUID().uuidString,
                model_name: config.model_name
            )
        case .event_candidates:
            if request.input_json.contains("SIMULATE_INVALID_JSON") {
                return ProviderClientResponse(raw_text: "```json\n{\"event_candidates\":[}\n```")
            }
            return ProviderClientResponse(
                raw_text: """
                {
                                    "event_candidates": [
                                        {
                                            "event_type": "reminder",
                                            "title": "文档中提到待办事项",
                                            "start_time": null,
                                            "end_time": null,
                                            "raw_time_text": "尽快处理",
                                            "location": null,
                                            "notes": "由 mock provider 生成",
                                            "evidence_snippet": "文档中包含需要安排的事项",
                                            "confidence": 0.78,
                                            "calendar_eligible": true
                                        }
                                    ]
                }
                """,
                response_id: UUID().uuidString,
                model_name: config.model_name
            )
        case .qa_with_citations:
            if request.input_json.contains("SIMULATE_INVALID_JSON") {
                return ProviderClientResponse(raw_text: "{\"answer\":\"broken\",\"citations\":}")
            }
            return ProviderClientResponse(
                raw_text: """
                {
                  "answer": "根据检索结果，暂无明确答案。",
                  "answer_type": "not_found",
                  "confidence": 0.35,
                  "citations": []
                }
                """,
                response_id: UUID().uuidString,
                model_name: config.model_name
            )
        }
    }
}
