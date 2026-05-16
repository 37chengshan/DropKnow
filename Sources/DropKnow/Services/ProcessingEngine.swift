import Foundation

enum ProcessingTrigger: String, Codable, CaseIterable, Hashable {
    case auto
    case manualReparse
    case manualBackfill
    case initialImport

    var label: String {
        switch self {
        case .auto: "自动监听"
        case .manualReparse: "手动重解析"
        case .manualBackfill: "补齐索引"
        case .initialImport: "首次导入"
        }
    }
}

enum ParseJobStatus: String, Codable, Hashable, CaseIterable {
    case queued
    case parsing
    case blockedSensitive
    case parsed
    case skippedUnchanged
    case failed
}

enum IndexJobStatus: String, Codable, Hashable, CaseIterable {
    case queued
    case refining
    case indexing
    case indexed
    case failed
}

struct ParseJob: Identifiable, Codable, Hashable {
    var id: UUID
    var fileID: UUID
    var fileName: String
    var filePath: String
    var trigger: ProcessingTrigger
    var status: ParseJobStatus
    var attemptCount: Int
    var maxAttempts: Int
    var lastError: String?
    var lastAttemptAt: Date?
    var nextRetryAt: Date?
    var forceAllowSensitive: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        fileID: UUID,
        fileName: String,
        filePath: String,
        trigger: ProcessingTrigger,
        status: ParseJobStatus = .queued,
        attemptCount: Int = 0,
        maxAttempts: Int = 3,
        lastError: String? = nil,
        lastAttemptAt: Date? = nil,
        nextRetryAt: Date? = nil,
        forceAllowSensitive: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.fileID = fileID
        self.fileName = fileName
        self.filePath = filePath
        self.trigger = trigger
        self.status = status
        self.attemptCount = attemptCount
        self.maxAttempts = maxAttempts
        self.lastError = lastError
        self.lastAttemptAt = lastAttemptAt
        self.nextRetryAt = nextRetryAt
        self.forceAllowSensitive = forceAllowSensitive
        self.createdAt = createdAt
    }
}

struct IndexJob: Identifiable, Codable, Hashable {
    var id: UUID
    var fileID: UUID
    var fileName: String
    var filePath: String
    var contentHash: String
    var trigger: ProcessingTrigger
    var status: IndexJobStatus
    var attemptCount: Int
    var maxAttempts: Int
    var lastError: String?
    var lastAttemptAt: Date?
    var nextRetryAt: Date?
    var requiresRefine: Bool
    var chunks: [String]
    var refineText: String
    var summary: FileSummary
    var priorityLevel: PriorityLevel
    var events: [EventCandidate]
    var revisionID: String
    var didRefine: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        fileID: UUID,
        fileName: String,
        filePath: String,
        contentHash: String,
        trigger: ProcessingTrigger,
        status: IndexJobStatus = .queued,
        attemptCount: Int = 0,
        maxAttempts: Int = 3,
        lastError: String? = nil,
        lastAttemptAt: Date? = nil,
        nextRetryAt: Date? = nil,
        requiresRefine: Bool,
        chunks: [String],
        refineText: String,
        summary: FileSummary,
        priorityLevel: PriorityLevel,
        events: [EventCandidate],
        revisionID: String,
        didRefine: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.fileID = fileID
        self.fileName = fileName
        self.filePath = filePath
        self.contentHash = contentHash
        self.trigger = trigger
        self.status = status
        self.attemptCount = attemptCount
        self.maxAttempts = maxAttempts
        self.lastError = lastError
        self.lastAttemptAt = lastAttemptAt
        self.nextRetryAt = nextRetryAt
        self.requiresRefine = requiresRefine
        self.chunks = chunks
        self.refineText = refineText
        self.summary = summary
        self.priorityLevel = priorityLevel
        self.events = events
        self.revisionID = revisionID
        self.didRefine = didRefine
        self.createdAt = createdAt
    }

    var totalCharacters: Int {
        chunks.reduce(0) { $0 + $1.count }
    }
}

struct DailyUsage: Codable, Hashable {
    var dayKey: String
    var parseUsed: Int
    var searchUsed: Int
    var chatUsed: Int
    var refineUsed: Int
    var embeddingFilesUsed: Int
    var embeddingChunksUsed: Int

    static func empty(dayKey: String) -> DailyUsage {
        DailyUsage(
            dayKey: dayKey,
            parseUsed: 0,
            searchUsed: 0,
            chatUsed: 0,
            refineUsed: 0,
            embeddingFilesUsed: 0,
            embeddingChunksUsed: 0
        )
    }
}

struct QuotaCounter: Codable, Hashable {
    var used: Int
    var limit: Int

    var remaining: Int {
        max(0, limit - used)
    }
}

struct QuotaSnapshot: Codable, Hashable {
    var parse: QuotaCounter
    var search: QuotaCounter
    var chat: QuotaCounter
    var refineUsed: Int
    var embeddingFilesUsed: Int
    var embeddingChunksUsed: Int
}

struct RuntimeState: Codable, Hashable {
    var parseJobs: [ParseJob]
    var indexJobs: [IndexJob]
    var dailyUsage: DailyUsage
    var lastRecoveredAt: Date?

    static var empty: RuntimeState {
        RuntimeState(
            parseJobs: [],
            indexJobs: [],
            dailyUsage: .empty(dayKey: QuotaService.dayKey(for: Date())),
            lastRecoveredAt: nil
        )
    }
}

struct ProcessingQueueSummary: Codable, Hashable {
    var queued: Int
    var running: Int
    var failed: Int
}

enum QueueItemKind: String, Hashable {
    case parse
    case index

    var label: String {
        switch self {
        case .parse: "解析"
        case .index: "索引"
        }
    }
}

enum QueueDisplayStatus: String, Hashable, CaseIterable {
    case queued
    case running
    case failed
    case blocked
    case skipped
    case completed

    var label: String {
        switch self {
        case .queued: "排队中"
        case .running: "运行中"
        case .failed: "已失败"
        case .blocked: "已阻塞"
        case .skipped: "已跳过"
        case .completed: "已完成"
        }
    }
}

struct QueueDisplayItem: Identifiable, Hashable {
    var id: UUID { jobID }
    var jobID: UUID
    var fileID: UUID
    var fileName: String
    var filePath: String
    var kind: QueueItemKind
    var trigger: ProcessingTrigger
    var status: QueueDisplayStatus
    var statusText: String
    var attemptCount: Int
    var maxAttempts: Int
    var lastError: String?
    var lastAttemptAt: Date?
    var nextRetryAt: Date?
}

enum UserQuotaKind {
    case parse
    case search
    case chat
}

enum QuotaMetric {
    case parse
    case search
    case chat
    case refine
    case embeddingFiles
    case embeddingChunks
}

struct QuotaDecision: Hashable {
    var allowed: Bool
    var message: String?
}

enum QuotaService {
    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let start = calendar.startOfDay(for: date)
        let components = calendar.dateComponents([.year, .month, .day], from: start)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    static func normalizedUsage(_ usage: DailyUsage, now: Date, calendar: Calendar = .current) -> DailyUsage {
        let currentDayKey = dayKey(for: now, calendar: calendar)
        guard usage.dayKey != currentDayKey else { return usage }
        return .empty(dayKey: currentDayKey)
    }

    static func snapshot(
        settings: DropSettings,
        usage: DailyUsage,
        now: Date,
        calendar: Calendar = .current
    ) -> QuotaSnapshot {
        let normalized = normalizedUsage(usage, now: now, calendar: calendar)
        return QuotaSnapshot(
            parse: QuotaCounter(used: normalized.parseUsed, limit: settings.dailyParseLimit),
            search: QuotaCounter(used: normalized.searchUsed, limit: settings.dailySearchLimit),
            chat: QuotaCounter(used: normalized.chatUsed, limit: settings.dailyChatLimit),
            refineUsed: normalized.refineUsed,
            embeddingFilesUsed: normalized.embeddingFilesUsed,
            embeddingChunksUsed: normalized.embeddingChunksUsed
        )
    }

    static func canConsumeUserQuota(
        _ kind: UserQuotaKind,
        settings: DropSettings,
        usage: DailyUsage,
        now: Date,
        calendar: Calendar = .current
    ) -> QuotaDecision {
        let snapshot = snapshot(settings: settings, usage: usage, now: now, calendar: calendar)
        switch kind {
        case .parse:
            return snapshot.parse.remaining > 0
                ? QuotaDecision(allowed: true, message: nil)
                : QuotaDecision(allowed: false, message: "今日解析额度已用尽")
        case .search:
            return snapshot.search.remaining > 0
                ? QuotaDecision(allowed: true, message: nil)
                : QuotaDecision(allowed: false, message: "今日高级搜索额度已用尽")
        case .chat:
            return snapshot.chat.remaining > 0
                ? QuotaDecision(allowed: true, message: nil)
                : QuotaDecision(allowed: false, message: "今日问答额度已用尽")
        }
    }

    static func consume(
        _ metric: QuotaMetric,
        usage: inout DailyUsage,
        amount: Int = 1,
        now: Date,
        calendar: Calendar = .current
    ) {
        usage = normalizedUsage(usage, now: now, calendar: calendar)
        switch metric {
        case .parse:
            usage.parseUsed += amount
        case .search:
            usage.searchUsed += amount
        case .chat:
            usage.chatUsed += amount
        case .refine:
            usage.refineUsed += amount
        case .embeddingFiles:
            usage.embeddingFilesUsed += amount
        case .embeddingChunks:
            usage.embeddingChunksUsed += amount
        }
    }
}

struct ProcessingIndexSeed: Hashable {
    var fileID: UUID
    var fileName: String
    var filePath: String
    var contentHash: String
    var requiresRefine: Bool
    var chunks: [String]
    var refineText: String
    var summary: FileSummary
    var priorityLevel: PriorityLevel
    var events: [EventCandidate]
}

enum ProcessingWorkItem: Hashable {
    case parse(ParseJob)
    case refine(IndexJob)
    case indexBatch([IndexJob])
}

struct QueueIndexCompletion: Hashable {
    var jobID: UUID
    var revisionID: String
}

struct RuntimeStateLoadResult {
    var state: RuntimeState
    var backupURL: URL?
    var errorMessage: String?
}

enum RuntimeStateStore {
    static func load(from url: URL) -> RuntimeStateLoadResult {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return RuntimeStateLoadResult(state: .empty, backupURL: nil, errorMessage: nil)
        }
        do {
            let data = try Data(contentsOf: url)
            let state = try decoder.decode(RuntimeState.self, from: data)
            return RuntimeStateLoadResult(state: state, backupURL: nil, errorMessage: nil)
        } catch {
            let backupURL = backupCorruptedState(at: url)
            return RuntimeStateLoadResult(state: .empty, backupURL: backupURL, errorMessage: error.localizedDescription)
        }
    }

    static func save(_ state: RuntimeState, to url: URL) throws {
        let data = try encoder.encode(state)
        try data.write(to: url, options: .atomic)
    }

    private static func backupCorruptedState(at url: URL) -> URL? {
        let backupURL = url.deletingPathExtension().appendingPathExtension("corrupted.json")
        do {
            if FileManager.default.fileExists(atPath: backupURL.path) {
                try FileManager.default.removeItem(at: backupURL)
            }
            try FileManager.default.moveItem(at: url, to: backupURL)
            return backupURL
        } catch {
            return nil
        }
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

actor ProcessingEngine {
    private var state: RuntimeState
    private let runtimeURL: URL

    init(initialState: RuntimeState, runtimeURL: URL = AppPaths.runtimeURL, recoveredAt: Date = Date()) {
        self.runtimeURL = runtimeURL
        self.state = Self.recoveredState(from: initialState, recoveredAt: recoveredAt)
        try? RuntimeStateStore.save(self.state, to: runtimeURL)
    }

    func snapshot() -> RuntimeState {
        state
    }

    @discardableResult
    func enqueueParse(_ job: ParseJob, now: Date = Date()) -> Bool {
        refreshUsageDay(now: now)
        let isDuplicate = state.parseJobs.contains {
            $0.filePath == job.filePath && [.queued, .parsing].contains($0.status)
        }
        guard !isDuplicate else { return false }
        state.parseJobs.append(job)
        persist()
        return true
    }

    func canEnqueueParse(settings: DropSettings, now: Date = Date()) -> QuotaDecision {
        refreshUsageDay(now: now)
        let baseDecision = QuotaService.canConsumeUserQuota(.parse, settings: settings, usage: state.dailyUsage, now: now)
        guard baseDecision.allowed else { return baseDecision }
        let reserved = state.parseJobs.filter { [.queued, .parsing].contains($0.status) }.count
        let limit = settings.dailyParseLimit
        if state.dailyUsage.parseUsed + reserved >= limit {
            return QuotaDecision(allowed: false, message: "今日解析额度已排满")
        }
        return QuotaDecision(allowed: true, message: nil)
    }

    func canConsumeUserQuota(_ kind: UserQuotaKind, settings: DropSettings, now: Date = Date()) -> QuotaDecision {
        refreshUsageDay(now: now)
        return QuotaService.canConsumeUserQuota(kind, settings: settings, usage: state.dailyUsage, now: now)
    }

    @discardableResult
    func consumeUserQuota(_ kind: UserQuotaKind, settings: DropSettings, now: Date = Date()) -> QuotaDecision {
        refreshUsageDay(now: now)
        let decision = QuotaService.canConsumeUserQuota(kind, settings: settings, usage: state.dailyUsage, now: now)
        guard decision.allowed else { return decision }
        switch kind {
        case .parse:
            QuotaService.consume(.parse, usage: &state.dailyUsage, now: now)
        case .search:
            QuotaService.consume(.search, usage: &state.dailyUsage, now: now)
        case .chat:
            QuotaService.consume(.chat, usage: &state.dailyUsage, now: now)
        }
        persist()
        return decision
    }

    func earliestRetryDate(now: Date = Date()) -> Date? {
        refreshUsageDay(now: now)
        let parseDates = state.parseJobs.compactMap { job -> Date? in
            guard job.status == .queued, let nextRetryAt = job.nextRetryAt, nextRetryAt > now else { return nil }
            return nextRetryAt
        }
        let indexDates = state.indexJobs.compactMap { job -> Date? in
            guard job.status == .queued, let nextRetryAt = job.nextRetryAt, nextRetryAt > now else { return nil }
            return nextRetryAt
        }
        return (parseDates + indexDates).min()
    }

    func recordInternalUsage(_ metric: QuotaMetric, amount: Int = 1, now: Date = Date()) {
        refreshUsageDay(now: now)
        QuotaService.consume(metric, usage: &state.dailyUsage, amount: amount, now: now)
        persist()
    }

    @discardableResult
    func retryFailedJobs(now: Date = Date()) -> Int {
        refreshUsageDay(now: now)
        var retried = 0
        for index in state.parseJobs.indices where state.parseJobs[index].status == .failed {
            state.parseJobs[index].status = .queued
            state.parseJobs[index].lastError = nil
            state.parseJobs[index].nextRetryAt = nil
            retried += 1
        }
        for index in state.indexJobs.indices where state.indexJobs[index].status == .failed {
            state.indexJobs[index].status = .queued
            state.indexJobs[index].lastError = nil
            state.indexJobs[index].nextRetryAt = nil
            retried += 1
        }
        if retried > 0 {
            persist()
        }
        return retried
    }

    @discardableResult
    func retryJob(id: UUID, now: Date = Date()) -> Bool {
        refreshUsageDay(now: now)
        if let index = state.parseJobs.firstIndex(where: { $0.id == id && $0.status == .failed }) {
            state.parseJobs[index].status = .queued
            state.parseJobs[index].lastError = nil
            state.parseJobs[index].nextRetryAt = nil
            persist()
            return true
        }
        if let index = state.indexJobs.firstIndex(where: { $0.id == id && $0.status == .failed }) {
            state.indexJobs[index].status = .queued
            state.indexJobs[index].lastError = nil
            state.indexJobs[index].nextRetryAt = nil
            persist()
            return true
        }
        return false
    }

    func nextWorkItem(
        now: Date = Date(),
        maxBatchFiles: Int = 8,
        maxBatchChunks: Int = 64,
        maxBatchCharacters: Int = 60_000
    ) -> ProcessingWorkItem? {
        refreshUsageDay(now: now)

        if let index = state.parseJobs.indices.first(where: { isRunnable($0, now: now) }) {
            state.parseJobs[index].status = .parsing
            state.parseJobs[index].attemptCount += 1
            state.parseJobs[index].lastAttemptAt = now
            state.parseJobs[index].nextRetryAt = nil
            let job = state.parseJobs[index]
            persist()
            return .parse(job)
        }

        if let index = state.indexJobs.indices.first(where: { isRunnableRefine($0, now: now) }) {
            state.indexJobs[index].status = .refining
            state.indexJobs[index].attemptCount += 1
            state.indexJobs[index].lastAttemptAt = now
            state.indexJobs[index].nextRetryAt = nil
            let job = state.indexJobs[index]
            persist()
            return .refine(job)
        }

        let candidateIndices = state.indexJobs.indices.filter { isRunnableIndex($0, now: now) }
        guard !candidateIndices.isEmpty else { return nil }

        var selected: [Int] = []
        var chunkCount = 0
        var characterCount = 0
        for index in candidateIndices {
            let job = state.indexJobs[index]
            let nextChunkCount = chunkCount + job.chunks.count
            let nextCharacterCount = characterCount + job.totalCharacters
            if !selected.isEmpty && (selected.count >= maxBatchFiles || nextChunkCount > maxBatchChunks || nextCharacterCount > maxBatchCharacters) {
                break
            }
            selected.append(index)
            chunkCount = nextChunkCount
            characterCount = nextCharacterCount
        }
        guard !selected.isEmpty else { return nil }
        for index in selected {
            state.indexJobs[index].status = .indexing
            state.indexJobs[index].attemptCount += 1
            state.indexJobs[index].lastAttemptAt = now
            state.indexJobs[index].nextRetryAt = nil
        }
        let jobs = selected.map { state.indexJobs[$0] }
        persist()
        return .indexBatch(jobs)
    }

    func completeParseSkipped(jobID: UUID, now: Date = Date()) {
        refreshUsageDay(now: now)
        guard let index = state.parseJobs.firstIndex(where: { $0.id == jobID }) else { return }
        state.parseJobs[index].status = .skippedUnchanged
        state.parseJobs[index].lastError = nil
        state.parseJobs[index].nextRetryAt = nil
        persist()
    }

    func completeParseBlocked(jobID: UUID, now: Date = Date()) {
        refreshUsageDay(now: now)
        guard let index = state.parseJobs.firstIndex(where: { $0.id == jobID }) else { return }
        state.parseJobs[index].status = .blockedSensitive
        state.parseJobs[index].lastError = nil
        state.parseJobs[index].nextRetryAt = nil
        persist()
    }

    func discardJobs(for fileID: UUID, now: Date = Date()) {
        refreshUsageDay(now: now)
        state.parseJobs.removeAll { $0.fileID == fileID }
        state.indexJobs.removeAll { $0.fileID == fileID }
        persist()
    }

    func completeParseParsed(jobID: UUID, indexSeed: ProcessingIndexSeed, now: Date = Date()) {
        refreshUsageDay(now: now)
        guard let index = state.parseJobs.firstIndex(where: { $0.id == jobID }) else { return }
        state.parseJobs[index].status = .parsed
        state.parseJobs[index].lastError = nil
        state.parseJobs[index].nextRetryAt = nil
        QuotaService.consume(.parse, usage: &state.dailyUsage, now: now)
        state.indexJobs.append(
            IndexJob(
                fileID: indexSeed.fileID,
                fileName: indexSeed.fileName,
                filePath: indexSeed.filePath,
                contentHash: indexSeed.contentHash,
                trigger: state.parseJobs[index].trigger,
                requiresRefine: indexSeed.requiresRefine,
                chunks: indexSeed.chunks,
                refineText: indexSeed.refineText,
                summary: indexSeed.summary,
                priorityLevel: indexSeed.priorityLevel,
                events: indexSeed.events,
                revisionID: UUID().uuidString
            )
        )
        persist()
    }

    func failParse(jobID: UUID, error: String, now: Date = Date()) {
        refreshUsageDay(now: now)
        guard let index = state.parseJobs.firstIndex(where: { $0.id == jobID }) else { return }
        state.parseJobs[index].lastError = error
        if state.parseJobs[index].attemptCount >= state.parseJobs[index].maxAttempts {
            state.parseJobs[index].status = .failed
            state.parseJobs[index].nextRetryAt = nil
        } else {
            state.parseJobs[index].status = .queued
            state.parseJobs[index].nextRetryAt = retryDate(forAttempt: state.parseJobs[index].attemptCount, now: now)
        }
        persist()
    }

    func completeRefine(jobID: UUID, summary: FileSummary, priorityLevel: PriorityLevel, events: [EventCandidate], now: Date = Date()) {
        refreshUsageDay(now: now)
        guard let index = state.indexJobs.firstIndex(where: { $0.id == jobID }) else { return }
        state.indexJobs[index].summary = summary
        state.indexJobs[index].priorityLevel = priorityLevel
        state.indexJobs[index].events = events
        state.indexJobs[index].requiresRefine = false
        state.indexJobs[index].didRefine = true
        state.indexJobs[index].status = .queued
        state.indexJobs[index].lastError = nil
        state.indexJobs[index].nextRetryAt = nil
        persist()
    }

    func failIndex(jobID: UUID, error: String, now: Date = Date()) {
        refreshUsageDay(now: now)
        guard let index = state.indexJobs.firstIndex(where: { $0.id == jobID }) else { return }
        state.indexJobs[index].lastError = error
        if state.indexJobs[index].attemptCount >= state.indexJobs[index].maxAttempts {
            state.indexJobs[index].status = .failed
            state.indexJobs[index].nextRetryAt = nil
        } else {
            state.indexJobs[index].status = .queued
            state.indexJobs[index].nextRetryAt = retryDate(forAttempt: state.indexJobs[index].attemptCount, now: now)
        }
        persist()
    }

    func completeIndexBatch(_ completions: [QueueIndexCompletion], totalChunkCount: Int, now: Date = Date()) {
        refreshUsageDay(now: now)
        let ids = Set(completions.map(\.jobID))
        for completion in completions {
            guard let index = state.indexJobs.firstIndex(where: { $0.id == completion.jobID }) else { continue }
            state.indexJobs[index].status = .indexed
            state.indexJobs[index].revisionID = completion.revisionID
            state.indexJobs[index].lastError = nil
            state.indexJobs[index].nextRetryAt = nil
        }
        QuotaService.consume(.embeddingFiles, usage: &state.dailyUsage, amount: ids.count, now: now)
        QuotaService.consume(.embeddingChunks, usage: &state.dailyUsage, amount: totalChunkCount, now: now)
        persist()
    }

    private func refreshUsageDay(now: Date) {
        state.dailyUsage = QuotaService.normalizedUsage(state.dailyUsage, now: now)
    }

    private func persist() {
        try? RuntimeStateStore.save(state, to: runtimeURL)
    }

    private func isRunnable(_ index: Array<ParseJob>.Index, now: Date) -> Bool {
        let job = state.parseJobs[index]
        guard job.status == .queued else { return false }
        if let nextRetryAt = job.nextRetryAt, nextRetryAt > now {
            return false
        }
        return true
    }

    private func isRunnableRefine(_ index: Array<IndexJob>.Index, now: Date) -> Bool {
        let job = state.indexJobs[index]
        guard job.status == .queued, job.requiresRefine else { return false }
        if let nextRetryAt = job.nextRetryAt, nextRetryAt > now {
            return false
        }
        return true
    }

    private func isRunnableIndex(_ index: Array<IndexJob>.Index, now: Date) -> Bool {
        let job = state.indexJobs[index]
        guard job.status == .queued, !job.requiresRefine else { return false }
        if let nextRetryAt = job.nextRetryAt, nextRetryAt > now {
            return false
        }
        return true
    }

    private func retryDate(forAttempt attempt: Int, now: Date) -> Date {
        switch attempt {
        case 1:
            return now.addingTimeInterval(30)
        case 2:
            return now.addingTimeInterval(300)
        default:
            return now
        }
    }

    private static func recoveredState(from initialState: RuntimeState, recoveredAt: Date) -> RuntimeState {
        var state = initialState
        for index in state.parseJobs.indices {
            if state.parseJobs[index].status == .parsing {
                state.parseJobs[index].status = state.parseJobs[index].attemptCount >= state.parseJobs[index].maxAttempts ? .failed : .queued
            }
        }
        for index in state.indexJobs.indices {
            if state.indexJobs[index].status == .refining || state.indexJobs[index].status == .indexing {
                state.indexJobs[index].status = state.indexJobs[index].attemptCount >= state.indexJobs[index].maxAttempts ? .failed : .queued
            }
        }
        state.lastRecoveredAt = recoveredAt
        state.dailyUsage = QuotaService.normalizedUsage(state.dailyUsage, now: recoveredAt)
        return state
    }
}
