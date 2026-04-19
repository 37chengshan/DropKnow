import Foundation

public enum PrivacyGateDecision: Sendable, Equatable {
    case allow
    case requires_confirmation
    case blocked_policy
    case blocked_quota
}

public protocol QuotaChecking: Sendable {
    func canUseParseQuota(reference_date: String) async -> Bool
}

public actor InMemoryQuotaChecker: QuotaChecking {
    private var usedPerDate: [String: Int] = [:]
    private let dailyLimit: Int

    public init(dailyLimit: Int) {
        self.dailyLimit = max(dailyLimit, 0)
    }

    public func canUseParseQuota(reference_date: String) async -> Bool {
        let used = usedPerDate[reference_date, default: 0]
        guard used < dailyLimit else {
            return false
        }
        usedPerDate[reference_date] = used + 1
        return true
    }
}

public protocol PrivacyGateChecking: Sendable {
    func evaluate(
        plain_text: String,
        reference_date: String,
        requires_manual_confirmation: Bool
    ) async -> PrivacyGateDecision
}

public struct DefaultPrivacyGateService: PrivacyGateChecking {
    private let quotaChecker: any QuotaChecking
    private let blockedKeywords: [String]
    private let confirmationKeywords: [String]

    public init(
        quotaChecker: any QuotaChecking,
        blockedKeywords: [String] = ["policy_block", "forbidden", "classified"],
        confirmationKeywords: [String] = ["身份证", "银行卡", "护照", "密码"]
    ) {
        self.quotaChecker = quotaChecker
        self.blockedKeywords = blockedKeywords
        self.confirmationKeywords = confirmationKeywords
    }

    public func evaluate(
        plain_text: String,
        reference_date: String,
        requires_manual_confirmation: Bool = false
    ) async -> PrivacyGateDecision {
        let lowered = plain_text.lowercased()

        if blockedKeywords.contains(where: { lowered.contains($0.lowercased()) }) {
            return .blocked_policy
        }

        if requires_manual_confirmation || confirmationKeywords.contains(where: { plain_text.contains($0) }) {
            return .requires_confirmation
        }

        let canProceed = await quotaChecker.canUseParseQuota(reference_date: reference_date)
        return canProceed ? .allow : .blocked_quota
    }
}
