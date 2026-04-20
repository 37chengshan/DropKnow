import Foundation

public enum PlanType: String, Codable, Sendable {
    case free
    case pro
}

public struct QuotaSnapshot: Sendable, Equatable {
    public let parse_used: Int
    public let parse_limit: Int
    public let qa_used: Int
    public let qa_limit: Int
    public let advanced_search_used: Int
    public let advanced_search_limit: Int

    public init(
        parse_used: Int,
        parse_limit: Int,
        qa_used: Int,
        qa_limit: Int,
        advanced_search_used: Int,
        advanced_search_limit: Int
    ) {
        self.parse_used = parse_used
        self.parse_limit = parse_limit
        self.qa_used = qa_used
        self.qa_limit = qa_limit
        self.advanced_search_used = advanced_search_used
        self.advanced_search_limit = advanced_search_limit
    }
}

public enum SearchGateResult: Sendable, Equatable {
    case allowed
    case blocked(reason: SearchBlockReason, message: String)
    case failed(message: String)
}

public protocol SubscriptionFeatureServicing: Sendable {
    func canUseCalendarFeature() async -> Bool
    func consumeSearchQuota(mode: QuickMode, reference_date: String) async -> SearchGateResult
    func fetchQuotaSnapshot(reference_date: String) async -> QuotaSnapshot
}

public actor SubscriptionFeatureService: SubscriptionFeatureServicing {
    private let quotaRepository: QuotaRepository
    private let planType: PlanType
    private let qaEnabledOnFree: Bool

    public init(
        quotaRepository: QuotaRepository,
        planType: PlanType = .free,
        qaEnabledOnFree: Bool = true
    ) {
        self.quotaRepository = quotaRepository
        self.planType = planType
        self.qaEnabledOnFree = qaEnabledOnFree
    }

    public func canUseCalendarFeature() async -> Bool {
        planType == .pro
    }

    public func consumeSearchQuota(mode: QuickMode, reference_date: String) async -> SearchGateResult {
        if mode == .qa && planType == .free && !qaEnabledOnFree {
            return .blocked(reason: .feature_locked, message: "当前套餐未开放问答能力。")
        }

        guard let quota = await ensureQuota(reference_date: reference_date) else {
            return .failed(message: "配额服务异常，请稍后重试。")
        }

        let nextQuota: QuotaRecord
        switch mode {
        case .search:
            if quota.advanced_search_used >= quota.advanced_search_limit {
                return .blocked(reason: .quota_exceeded, message: "今日高级搜索额度已用尽。")
            }
            nextQuota = QuotaRecord(
                quota_date: quota.quota_date,
                parse_used: quota.parse_used,
                parse_limit: quota.parse_limit,
                qa_used: quota.qa_used,
                qa_limit: quota.qa_limit,
                advanced_search_used: quota.advanced_search_used + 1,
                advanced_search_limit: quota.advanced_search_limit,
                updated_at: PipelineClock.nowString()
            )
        case .qa:
            if quota.qa_used >= quota.qa_limit {
                return .blocked(reason: .quota_exceeded, message: "今日问答额度已用尽。")
            }
            nextQuota = QuotaRecord(
                quota_date: quota.quota_date,
                parse_used: quota.parse_used,
                parse_limit: quota.parse_limit,
                qa_used: quota.qa_used + 1,
                qa_limit: quota.qa_limit,
                advanced_search_used: quota.advanced_search_used,
                advanced_search_limit: quota.advanced_search_limit,
                updated_at: PipelineClock.nowString()
            )
        }

        let updateResult = await quotaRepository.update(nextQuota)
        if case .failure = updateResult {
            return .failed(message: "配额更新失败，请稍后重试。")
        }

        return .allowed
    }

    public func fetchQuotaSnapshot(reference_date: String) async -> QuotaSnapshot {
        guard let quota = await ensureQuota(reference_date: reference_date) else {
            return QuotaSnapshot(
                parse_used: 0,
                parse_limit: defaultParseLimit,
                qa_used: 0,
                qa_limit: defaultQALimit,
                advanced_search_used: 0,
                advanced_search_limit: defaultAdvancedSearchLimit
            )
        }

        return QuotaSnapshot(
            parse_used: quota.parse_used,
            parse_limit: quota.parse_limit,
            qa_used: quota.qa_used,
            qa_limit: quota.qa_limit,
            advanced_search_used: quota.advanced_search_used,
            advanced_search_limit: quota.advanced_search_limit
        )
    }

    private var defaultParseLimit: Int {
        planType == .pro ? 200 : 5
    }

    private var defaultQALimit: Int {
        planType == .pro ? 100 : 5
    }

    private var defaultAdvancedSearchLimit: Int {
        planType == .pro ? 100 : 10
    }

    private func ensureQuota(reference_date: String) async -> QuotaRecord? {
        let getResult = await quotaRepository.get(quota_date: reference_date)
        switch getResult {
        case .failure:
            return nil
        case .success(let existing):
            if let existing {
                return existing
            }
            let created = QuotaRecord(
                quota_date: reference_date,
                parse_used: 0,
                parse_limit: defaultParseLimit,
                qa_used: 0,
                qa_limit: defaultQALimit,
                advanced_search_used: 0,
                advanced_search_limit: defaultAdvancedSearchLimit,
                updated_at: PipelineClock.nowString()
            )
            let createResult = await quotaRepository.create(created)
            switch createResult {
            case .success(let value):
                return value
            case .failure:
                return nil
            }
        }
    }
}
