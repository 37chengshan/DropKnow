import Foundation

public struct HTTPProviderClient: ProviderClient {
    public init() {}

    public func send(
        _ request: ProviderClientRequest,
        config: ProviderConfig
    ) async throws -> ProviderClientResponse {
        try await ProviderExecutionSupport.withTimeout(timeoutMs: config.timeout_ms) {
            try await performRequest(request, config: config)
        }
    }

    private func performRequest(
        _ request: ProviderClientRequest,
        config: ProviderConfig
    ) async throws -> ProviderClientResponse {
        let url = try buildURL(baseURL: config.base_url)
        let body = try ProviderExecutionSupport.encodeRequest(request)

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderError.malformed_response
        }

        try mapHTTPStatus(httpResponse.statusCode)

        let clientResponse = try parseResponse(data: data)
        return clientResponse
    }

    private func buildURL(baseURL: String) throws -> URL {
        guard var components = URLComponents(string: baseURL) else {
            throw ProviderError.network(message: "Invalid base URL: \(baseURL)")
        }

        if components.scheme == nil {
            components.scheme = "https"
        }

        guard let url = components.url else {
            throw ProviderError.network(message: "Failed to construct URL from: \(baseURL)")
        }

        return url
    }

    private func mapHTTPStatus(_ statusCode: Int) throws {
        switch statusCode {
        case 200...299:
            return
        case 400...499:
            throw ProviderError.bad_request
        case 500...599:
            throw ProviderError.upstream_error
        default:
            throw ProviderError.malformed_response
        }
    }

    private func parseResponse(data: Data) throws -> ProviderClientResponse {
        do {
            return try ProviderExecutionSupport.decoder.decode(ProviderClientResponse.self, from: data)
        } catch {
            throw ProviderError.malformed_response
        }
    }
}
