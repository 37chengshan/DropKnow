import Foundation

public protocol UnknownCaseCodable: RawRepresentable, Codable, Equatable, Sendable where RawValue == String {
    static var unknownCase: Self { get }
}

public extension UnknownCaseCodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = Self(rawValue: rawValue) ?? Self.unknownCase
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    init(databaseValue: String?) {
        guard let databaseValue, !databaseValue.isEmpty else {
            self = Self.unknownCase
            return
        }
        self = Self(rawValue: databaseValue) ?? Self.unknownCase
    }

    var isUnknownCase: Bool {
        self == Self.unknownCase
    }
}
