import Foundation

public enum ProviderError: Error, Sendable, Equatable {
    case auth
    case rate_limited
    case timeout
    case service_unavailable
    case invalid_json(message: String)
    case schema_validation_failed(message: String)
    case offline
    case network(message: String)
    case malformed_response
    case unsupported_transport
}

public extension ProviderError {
    var category: String {
        switch self {
        case .auth:
            return "auth"
        case .rate_limited:
            return "rate_limited"
        case .timeout:
            return "timeout"
        case .service_unavailable:
            return "service_unavailable"
        case .invalid_json:
            return "invalid_json"
        case .schema_validation_failed:
            return "schema_validation"
        case .offline, .network:
            return "network"
        case .malformed_response:
            return "malformed_response"
        case .unsupported_transport:
            return "unsupported_transport"
        }
    }

    var shouldRetry: Bool {
        switch self {
        case .rate_limited, .timeout, .service_unavailable, .offline, .network:
            return true
        case .invalid_json, .schema_validation_failed, .auth, .malformed_response, .unsupported_transport:
            return false
        }
    }

    func toErrorCode(task: ProviderTask) -> ErrorCode {
        switch self {
        case .auth:
            switch task {
            case .summary:
                return .summary_provider_auth_failed
            case .event_candidates, .qa_with_citations:
                return .provider_auth_failed
            }
        case .rate_limited:
            switch task {
            case .summary:
                return .summary_provider_rate_limited
            case .event_candidates, .qa_with_citations:
                return .provider_rate_limited
            }
        case .timeout:
            if task == .qa_with_citations {
                return .qa_provider_timeout
            }
            return .summary_provider_timeout
        case .service_unavailable, .malformed_response:
            switch task {
            case .summary:
                return .summary_provider_service_unavailable
            case .event_candidates, .qa_with_citations:
                return .provider_service_unavailable
            }
        case .invalid_json, .schema_validation_failed:
            switch task {
            case .summary:
                return .summary_invalid_json
            case .event_candidates:
                return .event_invalid_json
            case .qa_with_citations:
                return .qa_invalid_json
            }
        case .offline, .network:
            return .network_offline
        case .unsupported_transport:
            return .provider_service_unavailable
        }
    }
}
