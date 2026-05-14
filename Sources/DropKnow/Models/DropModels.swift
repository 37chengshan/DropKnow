import Foundation

enum FileKind: String, Codable, CaseIterable {
    case pdf = "PDF"
    case docx = "DOCX"
    case text = "TXT/MD"
    case unsupported = "不支持"

    var systemImage: String {
        switch self {
        case .pdf: "doc.richtext"
        case .docx: "doc.text"
        case .text: "text.alignleft"
        case .unsupported: "exclamationmark.triangle"
        }
    }
}

enum ParseStatus: String, Codable {
    case queued = "等待解析"
    case parsing = "解析中"
    case sensitiveGate = "等待确认"
    case parsed = "已索引"
    case failed = "解析失败"
    case ignored = "已忽略"
}

enum PriorityLevel: String, Codable, CaseIterable {
    case high = "重要"
    case normal = "普通"
    case low = "可忽略"

    var systemImage: String {
        switch self {
        case .high: "exclamationmark.circle.fill"
        case .normal: "circle.fill"
        case .low: "minus.circle"
        }
    }
}

enum SensitivityStatus: String, Codable {
    case clear = "非敏感"
    case suspected = "疑似敏感"
    case approvedOnce = "单次允许"
    case trusted = "信任目录"
}

enum CalendarStatus: String, Codable {
    case none = "无"
    case candidate = "候选"
    case added = "已加入"
}

enum EventType: String, Codable, CaseIterable {
    case exam = "考试"
    case assignmentDeadline = "作业截止"
    case registrationDeadline = "报名截止"
    case interview = "面试/宣讲"
    case classSchedule = "课程安排"
    case meeting = "会议通知"
    case paymentDeadline = "缴费截止"
    case campusActivity = "校园活动"
}

struct FileSummary: Codable, Hashable {
    var fileTypeLabel: String
    var actionHint: String
    var keyTime: String?
    var keyLocation: String?
    var keyPoints: [String]
    var oneLineSummary: String
}

struct EventCandidate: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var eventType: EventType
    var title: String
    var startTime: Date?
    var endTime: Date?
    var location: String?
    var note: String
    var evidence: String
    var confidence: Double
    var calendarStatus: CalendarStatus

    var canAddToCalendar: Bool {
        startTime != nil && calendarStatus != .added && confidence >= 0.72
    }

    var hasClockTime: Bool {
        evidence.range(of: #"(\d{1,2}[:：]\d{1,2}|\d{1,2}\s*点)"#, options: .regularExpression) != nil
    }
}

struct DropFile: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var fileName: String
    var filePath: String
    var sourceDirectory: String
    var fileKind: FileKind
    var importedAt: Date
    var modifiedAt: Date
    var fileSize: Int64
    var textLength: Int
    var parsedStatus: ParseStatus
    var sensitivityStatus: SensitivityStatus
    var priorityLevel: PriorityLevel
    var summary: FileSummary?
    var events: [EventCandidate]
    var snippets: [String]
    var errorMessage: String?
    var contentHash: String? = nil
    var fingerprintComputedAt: Date? = nil
    var parserVersion: String? = nil
    var summaryVersion: String? = nil
    var refineModel: String? = nil
    var embeddingProvider: String? = nil
    var embeddingModel: String? = nil
    var embeddingDimension: Int? = nil
    var indexedContentHash: String? = nil
    var indexedAt: Date? = nil
    var refinedContentHash: String? = nil
    var refinedAt: Date? = nil
    var activeIndexRevision: String? = nil

    var hasHighConfidenceEvent: Bool {
        events.contains { $0.confidence >= 0.72 }
    }
}

extension DropFile {
    var ragIndexState: RAGIndexState {
        if parsedStatus == .sensitiveGate || parsedStatus == .ignored {
            return .blocked
        }
        if parsedStatus == .failed {
            return .failed
        }
        if parsedStatus == .parsing {
            return contentHash == nil ? .notIndexed : .indexing
        }
        guard parsedStatus == .parsed else {
            return .notIndexed
        }
        guard let contentHash, let indexedContentHash, indexedAt != nil else {
            return .notIndexed
        }
        if contentHash != indexedContentHash {
            return .stale
        }
        return .indexed
    }
}

enum SearchQueryMode: String, Codable, Hashable {
    case fileSearch
    case generalChat
    case localFallback
    case quotaBlocked
    case errorFallback
}

struct SearchDiagnostics: Codable, Hashable {
    var embeddingEngine: String?
    var embeddingModel: String?
    var chatModel: String?
    var topK: Int
    var chatUsed: Bool
    var fallbackReason: String?
    var indexedFileCount: Int
    var chunkCount: Int
    var activeRevisionCount: Int
    var emptyIndex: Bool
    var providerConfigured: Bool

    static let empty = SearchDiagnostics(
        embeddingEngine: nil,
        embeddingModel: nil,
        chatModel: nil,
        topK: 0,
        chatUsed: false,
        fallbackReason: nil,
        indexedFileCount: 0,
        chunkCount: 0,
        activeRevisionCount: 0,
        emptyIndex: false,
        providerConfigured: false
    )
}

enum RAGIndexState: String, Codable, Hashable {
    case notIndexed = "未索引"
    case indexing = "索引中"
    case indexed = "可问"
    case stale = "索引过期"
    case failed = "索引失败"
    case blocked = "不可索引"
}

struct SearchHit: Identifiable, Codable, Hashable {
    var id: String
    var fileID: UUID?
    var fileName: String
    var filePath: String
    var snippet: String
    var score: Double
    var chunkIndex: Int?
    var revisionID: String?
    var matchReason: String?

    init(
        id: String,
        fileID: UUID?,
        fileName: String,
        filePath: String,
        snippet: String,
        score: Double,
        chunkIndex: Int? = nil,
        revisionID: String? = nil,
        matchReason: String? = nil
    ) {
        self.id = id
        self.fileID = fileID
        self.fileName = fileName
        self.filePath = filePath
        self.snippet = snippet
        self.score = score
        self.chunkIndex = chunkIndex
        self.revisionID = revisionID
        self.matchReason = matchReason
    }
}

struct SearchResult: Codable, Hashable {
    var answer: String
    var hits: [SearchHit]
    var engine: String
    var warning: String?
    var queryMode: SearchQueryMode
    var diagnostics: SearchDiagnostics

    init(
        answer: String,
        hits: [SearchHit],
        engine: String,
        warning: String?,
        queryMode: SearchQueryMode = .fileSearch,
        diagnostics: SearchDiagnostics = .empty
    ) {
        self.answer = answer
        self.hits = hits
        self.engine = engine
        self.warning = warning
        self.queryMode = queryMode
        self.diagnostics = diagnostics
    }

    enum CodingKeys: String, CodingKey {
        case answer
        case hits
        case engine
        case warning
        case queryMode
        case diagnostics
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        answer = try container.decode(String.self, forKey: .answer)
        hits = try container.decode([SearchHit].self, forKey: .hits)
        engine = try container.decode(String.self, forKey: .engine)
        warning = try container.decodeIfPresent(String.self, forKey: .warning)
        queryMode = try container.decodeIfPresent(SearchQueryMode.self, forKey: .queryMode) ?? .fileSearch
        diagnostics = try container.decodeIfPresent(SearchDiagnostics.self, forKey: .diagnostics) ?? .empty
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(answer, forKey: .answer)
        try container.encode(hits, forKey: .hits)
        try container.encode(engine, forKey: .engine)
        try container.encodeIfPresent(warning, forKey: .warning)
        try container.encode(queryMode, forKey: .queryMode)
        try container.encode(diagnostics, forKey: .diagnostics)
    }
}

enum FileDetailSectionAnchor: String, Hashable, Codable {
    case summary
    case importance
    case events
    case calendarReason
    case snippets
}

struct ExplanationSignal: Codable, Hashable {
    var title: String
    var detail: String
    var prominent: Bool = false
}

struct FileExplanation: Codable, Hashable {
    var headline: String
    var summary: String
    var signals: [ExplanationSignal]
}

enum UpgradeTrigger: String, Codable, Hashable {
    case settings
    case directoryLimit
    case calendar
    case parseQuota
    case searchQuota
    case chatQuota

    var title: String {
        switch self {
        case .settings: "查看订阅版"
        case .directoryLimit: "解锁多目录监听"
        case .calendar: "解锁日历能力"
        case .parseQuota: "提升解析额度"
        case .searchQuota: "提升搜索额度"
        case .chatQuota: "提升问答额度"
        }
    }

    var summary: String {
        switch self {
        case .settings:
            return "查看免费版与订阅版的完整权益对比。"
        case .directoryLimit:
            return "订阅版支持 Downloads + 自定义目录等更多监听能力。"
        case .calendar:
            return "订阅版可把高置信度 DDL、考试和报名时间加入系统日历。"
        case .parseQuota:
            return "订阅版提供更高的每日解析额度。"
        case .searchQuota:
            return "订阅版提供更高的高级搜索额度。"
        case .chatQuota:
            return "订阅版提供更高的问答额度。"
        }
    }
}

struct SectionNavigationRequest: Identifiable, Hashable {
    var id: UUID = UUID()
    var section: AppSection
}

struct DetailFocusRequest: Identifiable, Hashable {
    var id: UUID = UUID()
    var fileID: UUID
    var anchor: FileDetailSectionAnchor
}

struct ParsedFileNotificationDescriptor: Hashable {
    var fileID: UUID
    var title: String
    var subtitle: String
    var body: String
    var anchor: FileDetailSectionAnchor
}

struct ChatMessage: Identifiable, Hashable {
    enum Role: Hashable {
        case user
        case assistant
    }

    var id = UUID()
    var role: Role
    var text: String
    var result: SearchResult?
    var createdAt = Date()
}

struct DropSettings: Codable, Hashable {
    var watchDirectories: [String]
    var autoParseNewFiles: Bool
    var importRecentDays: Int
    var sensitiveAlwaysAsk: Bool
    var trustedDirectories: [String]
    var dailyParseLimit: Int
    var dailyChatLimit: Int
    var dailySearchLimit: Int
    var currentPlan: String

    static func defaults() -> DropSettings {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path
            ?? NSHomeDirectory() + "/Downloads"
        return DropSettings(
            watchDirectories: [downloads],
            autoParseNewFiles: true,
            importRecentDays: 7,
            sensitiveAlwaysAsk: true,
            trustedDirectories: [],
            dailyParseLimit: 5,
            dailyChatLimit: 5,
            dailySearchLimit: 5,
            currentPlan: "Free"
        )
    }
}

enum SubscriptionPlan: String, Codable, Hashable {
    case free = "Free"
    case pro = "Pro"

    init(storageValue: String) {
        switch storageValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "pro":
            self = .pro
        default:
            self = .free
        }
    }

    var capabilities: PlanCapabilities {
        switch self {
        case .free:
            return PlanCapabilities(
                maxWatchDirectories: 1,
                canUseCalendarWrite: false,
                allowedInitialImportWindowDays: 7,
                canCustomizeInitialImportWindow: false
            )
        case .pro:
            return PlanCapabilities(
                maxWatchDirectories: Int.max,
                canUseCalendarWrite: true,
                allowedInitialImportWindowDays: 30,
                canCustomizeInitialImportWindow: true
            )
        }
    }
}

struct PlanCapabilities: Hashable {
    var maxWatchDirectories: Int
    var canUseCalendarWrite: Bool
    var allowedInitialImportWindowDays: Int
    var canCustomizeInitialImportWindow: Bool

    var canManageMultipleWatchDirectories: Bool {
        maxWatchDirectories > 1
    }
}

enum WatchDirectoryAddResult: Equatable {
    case added
    case duplicate
    case blocked(message: String)
}

enum SensitiveAuthorizationKind: Equatable {
    case clear
    case trustedDirectory
    case oneTimeApproval
}

enum SensitiveRemoteDecision: Equatable {
    case allow(SensitiveAuthorizationKind)
    case block(message: String)
}

extension DropSettings {
    var subscriptionPlan: SubscriptionPlan {
        SubscriptionPlan(storageValue: currentPlan)
    }
}
