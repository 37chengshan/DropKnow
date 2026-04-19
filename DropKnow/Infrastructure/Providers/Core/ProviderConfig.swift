import Foundation

public enum ProviderTask: String, Codable, Equatable, Sendable {
    case summary
    case event_candidates
    case qa_with_citations
}

public enum ControlledProvider: String, Codable, Equatable, Sendable {
    case qwen
    case zhipu
}

public enum ProviderTransport: String, Codable, Equatable, Sendable {
    case mock
    case http_placeholder
}

public struct RetryPolicy: Codable, Equatable, Sendable {
    public let max_attempts: Int
    public let initial_delay_ms: UInt64
    public let max_delay_ms: UInt64

    public init(
        max_attempts: Int = 3,
        initial_delay_ms: UInt64 = 250,
        max_delay_ms: UInt64 = 2_000
    ) {
        self.max_attempts = max(max_attempts, 1)
        self.initial_delay_ms = max(initial_delay_ms, 10)
        self.max_delay_ms = max(max_delay_ms, initial_delay_ms)
    }

    func delayForAttempt(_ attemptIndex: Int) -> UInt64 {
        guard attemptIndex > 0 else { return 0 }
        let factor = UInt64(1 << min(attemptIndex - 1, 8))
        return min(initial_delay_ms * factor, max_delay_ms)
    }
}

public struct ProviderConfig: Codable, Equatable, Sendable {
    public let provider_id: String
    public let provider_type: ControlledProvider
    public let model_name: String
    public let base_url: String
    public let timeout_ms: UInt64
    public let retry_policy: RetryPolicy
    public let transport: ProviderTransport

    public init(
        provider_id: String,
        provider_type: ControlledProvider,
        model_name: String,
        base_url: String,
        timeout_ms: UInt64 = 15_000,
        retry_policy: RetryPolicy = RetryPolicy(),
        transport: ProviderTransport = .mock
    ) {
        self.provider_id = provider_id
        self.provider_type = provider_type
        self.model_name = model_name
        self.base_url = base_url
        self.timeout_ms = max(timeout_ms, 100)
        self.retry_policy = retry_policy
        self.transport = transport
    }
}
