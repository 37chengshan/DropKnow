import Foundation

private enum TimeoutSignal: Error {
    case timeout
}

enum ProviderExecutionSupport {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        JSONDecoder()
    }()

    static func encodeRequest<T: Encodable>(_ request: T) throws -> String {
        let data = try encoder.encode(request)
        guard let text = String(data: data, encoding: .utf8) else {
            throw ProviderError.malformed_response
        }
        return text
    }

    static func executeWithRetry(
        policy: RetryPolicy,
        operation: @escaping @Sendable (_ attempt: Int) async throws -> ProviderClientResponse
    ) async throws -> ProviderClientResponse {
        var lastError: ProviderError?

        for attempt in 1...policy.max_attempts {
            do {
                if attempt > 1 {
                    let delay = policy.delayForAttempt(attempt - 1)
                    try await Task.sleep(nanoseconds: delay * 1_000_000)
                }
                return try await operation(attempt)
            } catch let providerError as ProviderError {
                lastError = providerError
                if !providerError.shouldRetry || attempt == policy.max_attempts {
                    throw providerError
                }
            } catch {
                let wrapped = ProviderError.network(message: error.localizedDescription)
                lastError = wrapped
                if attempt == policy.max_attempts {
                    throw wrapped
                }
            }
        }

        throw lastError ?? .service_unavailable
    }

    static func withTimeout<T: Sendable>(
        timeoutMs: UInt64,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutMs * 1_000_000)
                throw TimeoutSignal.timeout
            }

            defer { group.cancelAll() }

            do {
                guard let result = try await group.next() else {
                    throw ProviderError.timeout
                }
                return result
            } catch TimeoutSignal.timeout {
                throw ProviderError.timeout
            } catch {
                throw error
            }
        }
    }

    static func decodeValidated<T: Decodable>(
        rawText: String,
        repairService: any JSONRepairing,
        validate: (T) throws -> Void
    ) throws -> T {
        do {
            let decoded: T = try decode(text: rawText)
            try validate(decoded)
            return decoded
        } catch let providerError as ProviderError {
            throw providerError
        } catch {
            guard let repaired = repairService.repair(rawText), repaired != rawText else {
                throw ProviderError.invalid_json(message: error.localizedDescription)
            }

            do {
                let repairedDecoded: T = try decode(text: repaired)
                try validate(repairedDecoded)
                return repairedDecoded
            } catch let providerError as ProviderError {
                throw providerError
            } catch {
                throw ProviderError.invalid_json(message: error.localizedDescription)
            }
        }
    }

    private static func decode<T: Decodable>(text: String) throws -> T {
        guard let data = text.data(using: .utf8) else {
            throw ProviderError.invalid_json(message: "UTF-8 decoding failed")
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw ProviderError.invalid_json(message: error.localizedDescription)
        }
    }
}
