import Foundation

public struct RepositoryFailure: Error, Equatable, Sendable {
    public let error_code: ErrorCode
    public let message: String

    public init(error_code: ErrorCode, message: String) {
        self.error_code = error_code
        self.message = message
    }
}

public enum RepositoryResult<Value: Sendable>: Sendable {
    case success(Value)
    case failure(RepositoryFailure)

    public func map<T: Sendable>(_ transform: (Value) -> T) -> RepositoryResult<T> {
        switch self {
        case .success(let value):
            return .success(transform(value))
        case .failure(let failure):
            return .failure(failure)
        }
    }
}

public protocol RepositoryTransactioning: Sendable {
    func transaction<T: Sendable>(
        _ operation: @escaping @Sendable () async -> RepositoryResult<T>
    ) async -> RepositoryResult<T>
}

public actor InMemoryRepositoryTransactionManager: RepositoryTransactioning {
    public init() {}

    public func transaction<T: Sendable>(
        _ operation: @escaping @Sendable () async -> RepositoryResult<T>
    ) async -> RepositoryResult<T> {
        await operation()
    }
}

public extension RepositoryResult {
    static func dbReadFailure(_ message: String) -> RepositoryResult<Value> {
        .failure(RepositoryFailure(error_code: .db_read_failed, message: message))
    }

    static func dbWriteFailure(_ message: String) -> RepositoryResult<Value> {
        .failure(RepositoryFailure(error_code: .db_write_failed, message: message))
    }
}
