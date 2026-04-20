import Foundation

public enum ParseJobStatus: String, UnknownCaseCodable {
    case queued
    case running
    case success
    case failed
    case skipped
    case cancelled
    case unknown

    public static let unknownCase: Self = .unknown
}
