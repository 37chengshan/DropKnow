import Foundation

public struct DefaultJSONRepairService: JSONRepairing {
    public init() {}

    public func repair(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var candidate = stripMarkdownFence(from: trimmed)
        candidate = replaceSmartQuotes(candidate)

        if let extracted = extractJSONObjectOrArray(from: candidate) {
            candidate = extracted
        }

        candidate = removeTrailingCommas(candidate)
        candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)

        return candidate.isEmpty ? nil : candidate
    }

    private func stripMarkdownFence(from text: String) -> String {
        if text.hasPrefix("```") {
            let lines = text.components(separatedBy: .newlines)
            let contentLines = lines.filter { !$0.hasPrefix("```") }
            return contentLines.joined(separator: "\n")
        }
        return text
    }

    private func replaceSmartQuotes(_ text: String) -> String {
        text
            .replacingOccurrences(of: "“", with: "\"")
            .replacingOccurrences(of: "”", with: "\"")
            .replacingOccurrences(of: "‘", with: "'")
            .replacingOccurrences(of: "’", with: "'")
    }

    private func extractJSONObjectOrArray(from text: String) -> String? {
        let objectRange = extractBalancedSegment(in: text, opening: "{", closing: "}")
        let arrayRange = extractBalancedSegment(in: text, opening: "[", closing: "]")

        if let objectRange, let arrayRange {
            let objectLength = text.distance(from: objectRange.lowerBound, to: objectRange.upperBound)
            let arrayLength = text.distance(from: arrayRange.lowerBound, to: arrayRange.upperBound)
            return objectLength >= arrayLength ? String(text[objectRange]) : String(text[arrayRange])
        }
        if let objectRange {
            return String(text[objectRange])
        }
        if let arrayRange {
            return String(text[arrayRange])
        }
        return nil
    }

    private func extractBalancedSegment(in text: String, opening: Character, closing: Character) -> Range<String.Index>? {
        guard let start = text.firstIndex(of: opening) else { return nil }
        var depth = 0
        var cursor = start

        while cursor < text.endIndex {
            let char = text[cursor]
            if char == opening {
                depth += 1
            } else if char == closing {
                depth -= 1
                if depth == 0 {
                    return start..<text.index(after: cursor)
                }
            }
            cursor = text.index(after: cursor)
        }

        return nil
    }

    private func removeTrailingCommas(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #",\s*([}\]])"#, options: []) else {
            return text
        }
        let range = NSRange(location: 0, length: text.utf16.count)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "$1")
    }
}
