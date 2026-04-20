import Foundation

public enum ProviderClientFactory {
    public static func makeClient(
        config: ProviderConfig,
        mockHandler: MockProviderClient.Handler? = nil
    ) -> any ProviderClient {
        switch config.transport {
        case .mock:
            return MockProviderClient(handler: mockHandler)
        case .http_placeholder:
            return HTTPProviderClientPlaceholder()
        }
    }
}

public struct HTTPProviderClientPlaceholder: ProviderClient {
    public init() {}

    public func send(_ request: ProviderClientRequest, config: ProviderConfig) async throws -> ProviderClientResponse {
        _ = request
        _ = config
        throw ProviderError.unsupported_transport
    }
}
