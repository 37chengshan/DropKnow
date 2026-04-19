import Foundation

public protocol DocumentParsing: Sendable {
    func parse(file_url: URL) async throws -> ParsedFileOutput
}

public struct DefaultDocumentParsingService: DocumentParsing {
    public init() {}

    public func parse(file_url: URL) async throws -> ParsedFileOutput {
        let fileExtension = file_url.pathExtension.lowercased()

        switch fileExtension {
        case "txt", "md", "csv", "json", "log", "text":
            return try await parseTextLikeFile(file_url: file_url, parserType: "text_native")
        case "pdf":
            return ParsedFileOutput(
                extracted_title: file_url.lastPathComponent,
                plain_text: "[mock-pdf-parser] \(file_url.lastPathComponent)",
                page_count: nil,
                parser_type: "pdfkit_mock",
                language_hint: "zh-CN"
            )
        case "docx":
            return ParsedFileOutput(
                extracted_title: file_url.lastPathComponent,
                plain_text: "[mock-docx-parser] \(file_url.lastPathComponent)",
                page_count: nil,
                parser_type: "docx_mock",
                language_hint: "zh-CN"
            )
        default:
            throw IngestionPipelineError.parse_unsupported_type
        }
    }

    private func parseTextLikeFile(file_url: URL, parserType: String) async throws -> ParsedFileOutput {
        let text = try await Task.detached(priority: .utility) {
            try String(contentsOf: file_url, encoding: .utf8)
        }.value

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw IngestionPipelineError.parse_failed(message: "empty text")
        }

        return ParsedFileOutput(
            extracted_title: file_url.deletingPathExtension().lastPathComponent,
            plain_text: trimmed,
            page_count: nil,
            parser_type: parserType,
            language_hint: nil
        )
    }
}
