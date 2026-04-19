import Foundation

public struct EventExtractionProvider: EventExtractionProviding {
    public let config: ProviderConfig

    private let client: any ProviderClient
    private let repairService: any JSONRepairing

    public init(
        config: ProviderConfig,
        client: (any ProviderClient)? = nil,
        repairService: any JSONRepairing = DefaultJSONRepairService()
    ) {
        self.config = config
        self.client = client ?? ProviderClientFactory.makeClient(config: config)
        self.repairService = repairService
    }

    public func generate(request: EventExtractionProviderRequest) async throws -> EventExtractionProviderResponse {
        let inputJSON = try ProviderExecutionSupport.encodeRequest(request)

        let rawResponse = try await ProviderExecutionSupport.executeWithRetry(policy: config.retry_policy) { _ in
            let clientRequest = ProviderClientRequest(task: .event_candidates, input_json: inputJSON)
            do {
                return try await ProviderExecutionSupport.withTimeout(timeoutMs: config.timeout_ms) {
                    try await client.send(clientRequest, config: config)
                }
            } catch let providerError as ProviderError {
                throw providerError
            } catch {
                throw ProviderError.network(message: error.localizedDescription)
            }
        }

        return try ProviderExecutionSupport.decodeValidated(
            rawText: rawResponse.raw_text,
            repairService: repairService,
            validate: EventExtractionSchemaValidator.validate
        )
    }
}
