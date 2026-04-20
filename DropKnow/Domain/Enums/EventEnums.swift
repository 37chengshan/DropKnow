import Foundation

public enum EventDecisionStatus: String, UnknownCaseCodable {
    case suggested
    case accepted
    case dismissed
    case expired
    case unknown

    public static let unknownCase: Self = .unknown
}

public enum CalendarStatus: String, UnknownCaseCodable {
    case not_added
    case adding
    case added
    case failed
    case feature_locked
    case unknown

    public static let unknownCase: Self = .unknown
}
