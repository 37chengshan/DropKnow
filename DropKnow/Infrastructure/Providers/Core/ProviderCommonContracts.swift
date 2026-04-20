import Foundation

public struct ProviderDocumentContextRequest: Codable, Equatable, Sendable {
    public let document_id: String
    public let file_name: String
    public let file_extension: String
    public let reference_date: String
    public let user_timezone: String
    public let plain_text: String
    public let language_hint: String?

    public init(
        document_id: String,
        file_name: String,
        file_extension: String,
        reference_date: String,
        user_timezone: String,
        plain_text: String,
        language_hint: String?
    ) {
        self.document_id = document_id
        self.file_name = file_name
        self.file_extension = file_extension
        self.reference_date = reference_date
        self.user_timezone = user_timezone
        self.plain_text = plain_text
        self.language_hint = language_hint
    }
}
