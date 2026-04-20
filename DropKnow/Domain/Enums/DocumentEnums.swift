import Foundation

public enum DocumentLifecycleStatus: String, UnknownCaseCodable {
    case detected
    case processing
    case waiting_user_confirmation
    case ready
    case blocked
    case failed
    case unknown

    public static let unknownCase: Self = .unknown
}

public enum DocumentStage: String, UnknownCaseCodable {
    case `import`
    case parse
    case gate
    case summary
    case event_extract
    case index
    case notify
    case done
    case unknown

    public static let unknownCase: Self = .unknown
}

public enum BlockReason: String, UnknownCaseCodable {
    case none
    case privacy_confirmation_required
    case quota_exceeded
    case feature_locked
    case unsupported_type
    case permission_denied
    case policy_blocked
    case unknown

    public static let unknownCase: Self = .unknown
}

public enum DocumentEventStatus: String, UnknownCaseCodable {
    case none
    case has_candidate
    case has_accepted_event
    case has_calendar_event
    case all_dismissed
    case unknown

    public static let unknownCase: Self = .unknown
}
