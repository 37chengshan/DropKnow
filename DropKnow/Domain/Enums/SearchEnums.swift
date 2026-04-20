import Foundation

public enum QuickMode: String, Codable, Sendable {
    case search
    case qa
}

public enum SearchBlockReason: String, Codable, Sendable {
    case none
    case quota_exceeded
    case feature_locked
    case empty_index
}

public enum SearchStatus: String, UnknownCaseCodable {
    case idle
    case retrieving
    case assembling
    case answering
    case success
    case no_result
    case blocked
    case failed
    case unknown

    public static let unknownCase: Self = .unknown
}
