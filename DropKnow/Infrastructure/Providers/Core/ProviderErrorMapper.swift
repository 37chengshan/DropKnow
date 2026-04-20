import Foundation

public enum ProviderErrorMapper {
    public static func toErrorCode(error: Error, task: ProviderTask) -> ErrorCode {
        if let providerError = error as? ProviderError {
            return providerError.toErrorCode(task: task)
        }
        return ProviderError.network(message: error.localizedDescription).toErrorCode(task: task)
    }
}
