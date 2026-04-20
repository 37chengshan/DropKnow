import Foundation

#if canImport(PDFKit)
import PDFKit
#endif

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
            return try await parsePDF(file_url: file_url)
        case "docx":
            return try await parseDOCX(file_url: file_url)
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

    #if canImport(PDFKit)
    private func parsePDF(file_url: URL) async throws -> ParsedFileOutput {
        guard let document = PDFDocument(url: file_url) else {
            throw IngestionPipelineError.parse_failed(message: "unable to open pdf")
        }

        var pages: [String] = []
        pages.reserveCapacity(document.pageCount)
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index), let text = page.string else { continue }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                pages.append(trimmed)
            }
        }

        let plainText = pages.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !plainText.isEmpty else {
            throw IngestionPipelineError.parse_failed(message: "pdf text is empty")
        }

        return ParsedFileOutput(
            extracted_title: file_url.deletingPathExtension().lastPathComponent,
            plain_text: plainText,
            page_count: document.pageCount,
            parser_type: "pdfkit",
            language_hint: "zh-CN"
        )
    }
    #else
    private func parsePDF(file_url: URL) async throws -> ParsedFileOutput {
        throw IngestionPipelineError.parse_failed(message: "PDFKit unavailable")
    }
    #endif

    private func parseDOCX(file_url: URL) async throws -> ParsedFileOutput {
        let xmlData = try runUnzip(file_url: file_url, entry: "word/document.xml")
        let plainText = try extractText(fromDOCXXML: xmlData)

        guard !plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw IngestionPipelineError.parse_failed(message: "docx text is empty")
        }

        return ParsedFileOutput(
            extracted_title: file_url.deletingPathExtension().lastPathComponent,
            plain_text: plainText.trimmingCharacters(in: .whitespacesAndNewlines),
            page_count: nil,
            parser_type: "docx_xml",
            language_hint: "zh-CN"
        )
    }

    private func runUnzip(file_url: URL, entry: String) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", file_url.path, entry]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw IngestionPipelineError.parse_failed(message: "unable to extract docx xml")
        }

        return outputPipe.fileHandleForReading.readDataToEndOfFile()
    }

    private func extractText(fromDOCXXML data: Data) throws -> String {
        final class Delegate: NSObject, XMLParserDelegate {
            var result: String = ""

            func parser(_ parser: XMLParser, foundCharacters string: String) {
                result += string
            }

            func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String : String] = [:]) {
                if elementName == "tab" {
                    result += "\t"
                }
            }

            func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
                if elementName == "p" || elementName == "tr" || elementName == "br" {
                    result += "\n"
                }
            }
        }

        let parser = XMLParser(data: data)
        let delegate = Delegate()
        parser.delegate = delegate
        guard parser.parse() else {
            throw IngestionPipelineError.parse_failed(message: parser.parserError?.localizedDescription ?? "docx xml parse failed")
        }

        return delegate.result
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .replacingOccurrences(of: "[ \t]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
