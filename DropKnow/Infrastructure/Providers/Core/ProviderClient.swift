import Foundation

public struct ProviderClientRequest: Codable, Equatable, Sendable {
    public let task: ProviderTask
    public let input_json: String

    public init(task: ProviderTask, input_json: String) {
        self.task = task
        self.input_json = input_json
    }
}

public struct ProviderClientResponse: Codable, Equatable, Sendable {
    public let raw_text: String
    public let response_id: String?
    public let model_name: String?

    public init(raw_text: String, response_id: String? = nil, model_name: String? = nil) {
        self.raw_text = raw_text
        self.response_id = response_id
        self.model_name = model_name
    }
}

public protocol ProviderClient: Sendable {
    func send(_ request: ProviderClientRequest, config: ProviderConfig) async throws -> ProviderClientResponse
}

public protocol JSONRepairing: Sendable {
    func repair(_ raw: String) -> String?
}

public protocol SchemaValidating: Sendable {
    associatedtype Output
    static func validate(_ output: Output) throws
}
