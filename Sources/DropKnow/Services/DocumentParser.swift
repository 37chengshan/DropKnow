import Foundation
import PDFKit

struct ParsedDocument {
    var text: String
    var chunks: [String]
    var summary: FileSummary
    var events: [EventCandidate]
    var priority: PriorityLevel
    var sensitivity: SensitivityStatus
}

enum DocumentParser {
    static func kind(for url: URL) -> FileKind {
        switch url.pathExtension.lowercased() {
        case "pdf": .pdf
        case "docx": .docx
        case "txt", "md", "markdown": .text
        default: .unsupported
        }
    }

    static func parse(url: URL, trustedDirectories: [String]) async throws -> ParsedDocument {
        let kind = kind(for: url)
        return try await PerfTrace.measure(
            "parse.document",
            metadata: ["kind": kind.rawValue]
        ) {
            let text: String
            switch kind {
            case .pdf:
                text = try parsePDF(url)
            case .docx:
                text = try parseDOCX(url)
            case .text:
                text = try String(contentsOf: url, encoding: .utf8)
            case .unsupported:
                throw ParserError.unsupported
            }

            let normalized = normalize(text)
            let chunks = makeChunks(from: normalized)
            let trusted = trustedDirectories.contains { url.path.hasPrefix($0) }
            let sensitivity = trusted ? SensitivityStatus.trusted : SensitiveFileDetector.detect(fileName: url.lastPathComponent, text: normalized)
            let events = EventExtractor.extract(from: normalized, fileName: url.lastPathComponent)
            let priority = PriorityClassifier.classify(text: normalized, fileName: url.lastPathComponent, events: events)
            let summary = SummaryBuilder.build(fileName: url.lastPathComponent, text: normalized, chunks: chunks, events: events, priority: priority)

            return ParsedDocument(text: normalized, chunks: chunks, summary: summary, events: events, priority: priority, sensitivity: sensitivity)
        }
    }

    private static func parsePDF(_ url: URL) throws -> String {
        guard let document = PDFDocument(url: url) else {
            throw ParserError.unreadable
        }
        var pages: [String] = []
        for index in 0..<document.pageCount {
            if let text = document.page(at: index)?.string, !text.isEmpty {
                pages.append(text)
            }
        }
        return pages.joined(separator: "\n\n")
    }

    private static func parseDOCX(_ url: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", url.path, "word/document.xml"]

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        try process.run()
        let group = DispatchGroup()
        var outputData = Data()
        var errorData = Data()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            outputData = output.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            errorData = error.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        process.waitUntilExit()
        _ = group.wait(timeout: .now() + .seconds(2))

        guard process.terminationStatus == 0 else {
            let detail = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw ParserError.docxExtractionFailed(detail.isEmpty ? "DOCX 解析失败" : String(detail.prefix(240)))
        }

        guard let xml = String(data: outputData, encoding: .utf8), !xml.isEmpty else {
            throw ParserError.docxExtractionFailed("DOCX 内容为空或无法解码")
        }

        return xml
            .replacingOccurrences(of: "</w:p>", with: "\n")
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
    }

    private static func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "[\\t ]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func makeChunks(from text: String) -> [String] {
        let paragraphs = text
            .components(separatedBy: CharacterSet.newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var chunks: [String] = []
        var current = ""
        for paragraph in paragraphs {
            if current.count + paragraph.count > 900, !current.isEmpty {
                chunks.append(current)
                current = paragraph
            } else {
                current += current.isEmpty ? paragraph : "\n" + paragraph
            }
        }
        if !current.isEmpty {
            chunks.append(current)
        }
        return chunks.isEmpty && !text.isEmpty ? [String(text.prefix(900))] : chunks
    }
}

enum ParserError: LocalizedError {
    case unsupported
    case unreadable
    case docxExtractionFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupported: "暂不支持此文件类型"
        case .unreadable: "无法读取文件内容"
        case .docxExtractionFailed(let message): message
        }
    }
}

enum SensitiveFileDetector {
    static func detect(fileName: String, text: String) -> SensitivityStatus {
        let sample = (fileName + "\n" + String(text.prefix(2000))).lowercased()
        let keywords = [
            "成绩单", "成绩查询", "身份证", "护照", "简历", "个人信息", "银行", "发票", "体检", "医疗", "缴费",
            "accesskeyid", "accesskeysecret", "api key", "apikey", "secret key", "private key"
        ]
        if keywords.contains(where: { sample.contains($0.lowercased()) }) {
            return .suspected
        }
        let patterns = [
            #"\b1[3-9]\d{9}\b"#,
            #"\b\d{17}[\dXx]\b"#,
            #"\b\d{8,12}\b"#,
            #"\bsk-[A-Za-z0-9_-]{16,}\b"#,
            #"\bLTAI[A-Za-z0-9]{12,}\b"#,
            #"(?i)(accessKeySecret|api[_-]?key|secret|token)\s*[:=]\s*[A-Za-z0-9_./+=-]{12,}"#
        ]
        let hits = patterns.reduce(0) { count, pattern in
            count + ((try? NSRegularExpression(pattern: pattern)).map {
                $0.numberOfMatches(in: sample, range: NSRange(sample.startIndex..., in: sample))
            } ?? 0)
        }
        return hits >= 2 ? .suspected : .clear
    }
}

enum PriorityClassifier {
    static func classify(text: String, fileName: String, events: [EventCandidate]) -> PriorityLevel {
        let content = text.lowercased()
        if isLowValue(text: text, fileName: fileName) {
            return .low
        }
        let highKeywords = ["考试", "补考", "截止", "ddl", "deadline", "缴费", "报名", "面试", "答辩", "提交", "作品提交", "课堂作业"]
        if events.contains(where: { [.exam, .assignmentDeadline, .registrationDeadline, .paymentDeadline, .interview, .meeting].contains($0.eventType) && $0.confidence >= 0.72 }) ||
            highKeywords.contains(where: { content.contains($0) }) {
            return .high
        }
        let lowKeywords = ["参考资料", "阅读材料", "附件", "讲义"]
        if lowKeywords.contains(where: { content.contains($0) }) {
            return .low
        }
        return .normal
    }

    static func isLowValue(text: String, fileName: String) -> Bool {
        let sample = (fileName + "\n" + text.prefix(2500)).lowercased()
        let codeSignals = ["import ", "export ", "function ", "class ", "const ", "let ", "var ", "curl ", "localhost", "github.com", "package.json", "readme", "todo", "agents.md"]
        let devSignals = ["执行文档", "任务单", "重构", "架构文档", "打磨", "验收", "收尾计划", "benchmark", "codex", "开发计划", "迁移方案", "技术方案"]
        let lectureSignals = ["板书", "讲义", "lecture #", "print.pdf", "quartus", "安装教程", "破解教程", "基础班", "词根合集"]
        if codeSignals.contains(where: { sample.contains($0) }) ||
            devSignals.contains(where: { sample.contains($0.lowercased()) }) ||
            lectureSignals.contains(where: { sample.contains($0.lowercased()) }) {
            return true
        }
        let latinCount = sample.unicodeScalars.filter { CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz").contains($0) }.count
        let cjkCount = sample.unicodeScalars.filter { (0x4E00...0x9FFF).contains(Int($0.value)) }.count
        let thaiCount = sample.unicodeScalars.filter { (0x0E00...0x0E7F).contains(Int($0.value)) }.count
        let kanaCount = sample.unicodeScalars.filter { (0x3040...0x30FF).contains(Int($0.value)) }.count
        let devanagariCount = sample.unicodeScalars.filter { (0x0900...0x097F).contains(Int($0.value)) }.count
        return (thaiCount > 120 && cjkCount < 20 && latinCount < 80) ||
            kanaCount > 80 ||
            (devanagariCount > 120 && cjkCount < 20)
    }
}

enum SummaryBuilder {
    static func build(fileName: String, text: String, chunks: [String], events: [EventCandidate], priority: PriorityLevel) -> FileSummary {
        let firstChunk = chunks.first ?? text
        let candidates = meaningfulLines(from: firstChunk)
        let actionPoints = actionLines(from: candidates, events: events)
        let keyPoints = Array((actionPoints.isEmpty ? candidates : actionPoints).prefix(3)).map { String($0.prefix(80)) }
        let oneLine = oneLineSummary(fileName: fileName, points: keyPoints, events: events, priority: priority)
        let event = events.max(by: { $0.confidence < $1.confidence })
        let datedEvents = events.compactMap(\.startTime).sorted()
        let keyTime: String?
        if let first = datedEvents.first {
            let firstText = DateFormatter.dropShort.string(from: first)
            keyTime = datedEvents.count > 1 ? "\(firstText) 等 \(datedEvents.count) 个时间" : firstText
        } else {
            keyTime = nil
        }

        return FileSummary(
            fileTypeLabel: detectType(text: text, fileName: fileName),
            actionHint: actionHint(priority: priority, event: event),
            keyTime: keyTime,
            keyLocation: validLocation(event?.location),
            keyPoints: keyPoints.isEmpty ? ["已提取全文并建立语义索引", "可用自然语言搜索文件内容", "暂无明确行动项"] : keyPoints,
            oneLineSummary: String(oneLine.prefix(120))
        )
    }

    private static func meaningfulLines(from text: String) -> [String] {
        var seen = Set<String>()
        return text
            .components(separatedBy: CharacterSet(charactersIn: "。！？!?;\n"))
            .map(cleanLine)
            .filter { isMeaningful($0) }
            .filter { line in
                if seen.contains(line) { return false }
                seen.insert(line)
                return true
            }
    }

    private static func actionLines(from lines: [String], events: [EventCandidate]) -> [String] {
        let actionWords = ["考试", "补考", "截止", "报名", "缴费", "提交", "作品", "时间", "日期", "安排", "地点", "要求", "答辩", "面试", "会议", "参赛", "需完成", "请于", "完成", "参加"]
        let eventEvidence = events.map(\.evidence).flatMap { meaningfulLines(from: $0) }
        let combined = eventEvidence + lines
        return combined.filter { line in
            actionWords.contains { line.localizedCaseInsensitiveContains($0) }
        }
    }

    private static func oneLineSummary(fileName: String, points: [String], events: [EventCandidate], priority: PriorityLevel) -> String {
        if let firstEvent = events
            .filter({ $0.confidence >= 0.72 })
            .sorted(by: { $0.confidence > $1.confidence })
            .first {
            let timeText = firstEvent.startTime.map(DateFormatter.dropShort.string(from:)) ?? "待确认时间"
            switch firstEvent.eventType {
            case .exam:
                return "考试安排：\(timeText)"
            case .assignmentDeadline:
                return "作业截止：\(timeText)"
            case .registrationDeadline:
                return "报名节点：\(timeText)"
            case .paymentDeadline:
                return "缴费截止：\(timeText)"
            case .interview:
                return "面试/宣讲：\(timeText)"
            case .meeting:
                return "会议安排：\(timeText)"
            case .campusActivity:
                return "活动安排：\(timeText)"
            case .classSchedule:
                return "课程安排：\(timeText)"
            }
        }
        if let first = points.first {
            return first
        }
        switch priority {
        case .high:
            return "\(fileName) 包含需要处理的通知事项。"
        case .normal:
            return "\(fileName) 已完成解析，可在问答中检索。"
        case .low:
            return "\(fileName) 更像资料或参考内容，暂无明确待办。"
        }
    }

    private static func cleanLine(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isMeaningful(_ line: String) -> Bool {
        guard line.count >= 8 else { return false }
        if line.range(of: #"^[—\-_=·\s]+$"#, options: .regularExpression) != nil { return false }
        if line.range(of: #"^[\d\s\-/年月日:：.]+$"#, options: .regularExpression) != nil { return false }
        if line.contains("公众号") || line.contains("页码") || line.lowercased().contains("http") { return false }
        if line.hasSuffix("函件") && line.count < 24 { return false }
        if line.contains("如下") && line.count < 16 { return false }
        if line.range(of: #"^[\u4e00-\u9fffA-Za-z]+函\[\d{4}\]\d+号$"#, options: .regularExpression) != nil { return false }
        return true
    }

    private static func validLocation(_ location: String?) -> String? {
        guard let location = location?.trimmingCharacters(in: .whitespacesAndNewlines),
              !location.isEmpty else {
            return nil
        }
        let badFragments = ["如下", "时间安排", "安排如下", "详见", "通知"]
        if badFragments.contains(where: { location.contains($0) }) {
            return nil
        }
        return location
    }

    private static func detectType(text: String, fileName: String) -> String {
        let combined = fileName + text.prefix(1000)
        if PriorityClassifier.isLowValue(text: text, fileName: fileName) {
            if combined.lowercased().contains("readme") || combined.lowercased().contains("import ") || combined.lowercased().contains("function ") {
                return "代码/配置"
            }
            if combined.contains("板书") || combined.lowercased().contains("lecture") || combined.lowercased().contains("quartus") {
                return "课程资料"
            }
            return "阅读材料"
        }
        if combined.contains("考试") || combined.contains("补考") { return "考试安排" }
        if combined.contains("作业") || combined.contains("提交") { return "作业说明" }
        if combined.contains("报名") { return "报名通知" }
        if combined.contains("活动") || combined.contains("讲座") { return "活动通知" }
        return "课程/校园通知"
    }

    private static func actionHint(priority: PriorityLevel, event: EventCandidate?) -> String {
        if let event, event.confidence >= 0.72 {
            switch event.eventType {
            case .assignmentDeadline, .registrationDeadline, .paymentDeadline:
                return "记下截止时间，建议尽快处理"
            case .exam, .interview, .meeting:
                return "记下时间地点，可加入日历"
            case .campusActivity, .classSchedule:
                return "确认时间安排，可加入日历"
            }
        }
        switch priority {
        case .high: return "现在阅读"
        case .normal: return "稍后回看"
        case .low: return "可忽略"
        }
    }
}

enum EventExtractor {
    static func extract(from text: String, fileName: String) -> [EventCandidate] {
        let sample = String(text.prefix(6000))
        let type = inferType(text: fileName + sample)
        guard shouldExtractEvents(from: fileName + "\n" + sample, type: type) else {
            return []
        }
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        let range = NSRange(sample.startIndex..., in: sample)
        let matches = detector?.matches(in: sample, range: range) ?? []

        var events: [EventCandidate] = matches.prefix(3).compactMap { match in
            guard let date = match.date else { return nil }
            let evidence = snippet(around: match.range, in: sample)
            return EventCandidate(
                eventType: type,
                title: eventTitle(type: type, fileName: fileName),
                startTime: date,
                endTime: nil,
                location: extractLocation(from: evidence + "\n" + sample),
                note: "由文件内容自动识别，请确认后再加入日历。",
                evidence: evidence,
                confidence: confidence(type: type, evidence: evidence),
                calendarStatus: .candidate
            )
        }

        let chineseEvents = chineseDateEvents(in: sample, type: type, fileName: fileName)
            .filter { candidate in
                guard let candidateDate = candidate.startTime else { return false }
                return !events.contains { existing in
                    guard let existingDate = existing.startTime else { return false }
                    return abs(existingDate.timeIntervalSince(candidateDate)) < 3600
                }
            }
        events.append(contentsOf: chineseEvents.prefix(max(0, 3 - events.count)))

        if events.isEmpty, let fallback = fallbackDateEvidence(in: sample) {
            events.append(EventCandidate(
                eventType: type,
                title: eventTitle(type: type, fileName: fileName),
                startTime: nil,
                endTime: nil,
                location: extractLocation(from: fallback + "\n" + sample),
                note: "识别到日期文本，但需要人工确认具体时间。",
                evidence: fallback,
                confidence: 0.58,
                calendarStatus: .candidate
            ))
        }
        return events
    }

    private static func chineseDateEvents(in text: String, type: EventType, fileName: String) -> [EventCandidate] {
        let pattern = #"(?:(\d{4})\s*[年/-])?(\d{1,2})\s*[月/-](\d{1,2})\s*日?(?:\s*(上午|下午|晚上|中午|早上)?\s*(\d{1,2})(?:\s*[:：点]\s*(\d{1,2})?)?)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        return matches.compactMap { match in
            guard let date = date(from: match, in: text) else { return nil }
            let evidence = snippet(around: match.range, in: text)
            return EventCandidate(
                eventType: type,
                title: eventTitle(type: type, fileName: fileName),
                startTime: date,
                endTime: nil,
                location: extractLocation(from: evidence + "\n" + text),
                note: "由文件内容自动识别，请确认后再加入日历。",
                evidence: evidence,
                confidence: confidence(type: type, evidence: evidence),
                calendarStatus: .candidate
            )
        }
    }

    private static func date(from match: NSTextCheckingResult, in text: String) -> Date? {
        func capture(_ index: Int) -> String? {
            guard index < match.numberOfRanges,
                  match.range(at: index).location != NSNotFound,
                  let range = Range(match.range(at: index), in: text) else {
                return nil
            }
            let value = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }

        let now = Date()
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: now)
        guard let month = Int(capture(2) ?? ""),
              let day = Int(capture(3) ?? "") else {
            return nil
        }

        var year = Int(capture(1) ?? "") ?? currentYear
        var hour = Int(capture(5) ?? "") ?? 0
        let minute = Int(capture(6) ?? "") ?? 0
        let marker = capture(4) ?? ""

        if (marker.contains("下午") || marker.contains("晚上")) && hour > 0 && hour < 12 {
            hour += 12
        } else if marker.contains("中午") && hour > 0 && hour < 11 {
            hour += 12
        }

        var components = DateComponents()
        components.calendar = calendar
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute

        guard let date = calendar.date(from: components) else { return nil }
        if capture(1) == nil,
           let nextYear = calendar.date(byAdding: .year, value: 1, to: date),
           date.timeIntervalSince(now) < -15552000 {
            year += 1
            components.year = year
            return nextYear
        }
        return date
    }

    private static func inferType(text: String) -> EventType {
        if text.contains("考试") || text.contains("补考") { return .exam }
        if text.contains("大赛") || text.contains("竞赛") || text.contains("决赛") || text.contains("比赛") { return .campusActivity }
        if text.contains("作业") || text.contains("提交") || text.lowercased().contains("ddl") { return .assignmentDeadline }
        if text.contains("报名") { return .registrationDeadline }
        if text.contains("面试") || text.contains("宣讲") { return .interview }
        if text.contains("缴费") { return .paymentDeadline }
        if text.contains("会议") { return .meeting }
        if text.contains("课程") || text.contains("上课") { return .classSchedule }
        return .campusActivity
    }

    private static func shouldExtractEvents(from text: String, type: EventType) -> Bool {
        if PriorityClassifier.isLowValue(text: text, fileName: "") {
            return false
        }
        let content = text.lowercased()
        let actionWords = ["考试", "补考", "截止", "ddl", "deadline", "提交", "报名", "缴费", "面试", "宣讲", "会议", "活动", "安排", "通知", "课堂作业", "作品提交", "参赛", "答辩"]
        let dateWords = ["月", "日", "周", "星期", "上午", "下午", "晚上", "点", ":"]
        let hasActionWord = actionWords.contains(where: { content.contains($0.lowercased()) })
        let hasDateWord = dateWords.contains(where: { content.contains($0.lowercased()) })
        if hasActionWord && hasDateWord {
            return true
        }
        return hasDateWord && [.exam, .assignmentDeadline, .registrationDeadline, .paymentDeadline, .interview, .meeting].contains(type)
    }

    private static func eventTitle(type: EventType, fileName: String) -> String {
        if type == .campusActivity, fileName.contains("大赛") || fileName.contains("竞赛") || fileName.contains("比赛") {
            return "大赛日程：\(fileName.replacingOccurrences(of: ".pdf", with: ""))"
        }
        return "\(type.rawValue)：\(fileName.replacingOccurrences(of: ".pdf", with: ""))"
    }

    private static func confidence(type: EventType, evidence: String) -> Double {
        let content = evidence.lowercased()
        let actionWords = ["考试", "补考", "截止", "ddl", "deadline", "提交", "报名", "缴费", "面试", "宣讲", "会议", "答辩", "参赛"]
        let timeWords = ["上午", "下午", "晚上", "中午", "点", ":", "："]
        let locationWords = ["地点", "教室", "会场", "线上", "腾讯会议", "zoom"]

        var score = 0.48
        if content.contains(type.rawValue.prefix(2).lowercased()) { score += 0.12 }
        if actionWords.contains(where: { content.contains($0.lowercased()) }) { score += 0.16 }
        if timeWords.contains(where: { content.contains($0.lowercased()) }) { score += 0.08 }
        if locationWords.contains(where: { content.contains($0.lowercased()) }) { score += 0.08 }
        if content.range(of: #"\d{1,2}\s*[月/-]\s*\d{1,2}"#, options: .regularExpression) != nil { score += 0.08 }
        if content.range(of: #"\d{1,2}\s*[:：点]\s*\d{0,2}"#, options: .regularExpression) != nil { score += 0.06 }
        if !actionWords.contains(where: { content.contains($0.lowercased()) }) {
            score -= 0.1
        }
        return min(max(score, 0.4), 0.94)
    }

    private static func snippet(around range: NSRange, in text: String) -> String {
        guard let swiftRange = Range(range, in: text) else { return String(text.prefix(180)) }
        let lower = text.index(swiftRange.lowerBound, offsetBy: -80, limitedBy: text.startIndex) ?? text.startIndex
        let upper = text.index(swiftRange.upperBound, offsetBy: 120, limitedBy: text.endIndex) ?? text.endIndex
        return text[lower..<upper]
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func fallbackDateEvidence(in text: String) -> String? {
        let pattern = #"\d{4}[年/-]\d{1,2}[月/-]\d{1,2}日?|\d{1,2}月\d{1,2}日"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            return nil
        }
        return snippet(around: match.range, in: text)
    }

    private static func extractLocation(from text: String) -> String? {
        let pattern = #"(地点|地址|教室|会场)[:：]?\s*([^\n，。；;]{2,40})"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 2), in: text) else {
            return nil
        }
        let value = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        let badFragments = ["如下", "时间安排", "安排如下", "详见", "通知"]
        if badFragments.contains(where: { value.contains($0) }) {
            return nil
        }
        return value
    }
}
