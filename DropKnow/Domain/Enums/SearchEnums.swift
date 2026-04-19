import Foundation

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
