import XCTest
@testable import DropKnow

final class QuotaServiceTests: XCTestCase {
    func testSnapshotResetsUsageAcrossDayBoundary() {
        let calendar = Calendar(identifier: .gregorian)
        let settings = DropSettings.defaults()
        let yesterday = Date(timeIntervalSince1970: 86_400)
        let today = Date(timeIntervalSince1970: 172_800)
        let usage = DailyUsage(
            dayKey: QuotaService.dayKey(for: yesterday, calendar: calendar),
            parseUsed: 3,
            searchUsed: 2,
            chatUsed: 1,
            refineUsed: 1,
            embeddingFilesUsed: 1,
            embeddingChunksUsed: 10
        )

        let snapshot = QuotaService.snapshot(
            settings: settings,
            usage: usage,
            now: today,
            calendar: calendar
        )

        XCTAssertEqual(snapshot.parse.used, 0)
        XCTAssertEqual(snapshot.search.used, 0)
        XCTAssertEqual(snapshot.chat.used, 0)
    }

    func testConsumeParseUsageIncrementsSameDay() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 200_000)
        var usage = DailyUsage.empty(dayKey: QuotaService.dayKey(for: now, calendar: calendar))

        QuotaService.consume(.parse, usage: &usage, amount: 1, now: now, calendar: calendar)
        QuotaService.consume(.parse, usage: &usage, amount: 1, now: now, calendar: calendar)

        XCTAssertEqual(usage.parseUsed, 2)
    }

    func testCanConsumeParseQuotaBlocksWhenLimitReached() {
        let calendar = Calendar(identifier: .gregorian)
        let settings = DropSettings.defaults()
        let now = Date(timeIntervalSince1970: 200_000)
        let usage = DailyUsage(
            dayKey: QuotaService.dayKey(for: now, calendar: calendar),
            parseUsed: settings.dailyParseLimit,
            searchUsed: 0,
            chatUsed: 0,
            refineUsed: 0,
            embeddingFilesUsed: 0,
            embeddingChunksUsed: 0
        )

        let decision = QuotaService.canConsumeUserQuota(
            .parse,
            settings: settings,
            usage: usage,
            now: now,
            calendar: calendar
        )

        XCTAssertFalse(decision.allowed)
        XCTAssertNotNil(decision.message)
    }

    func testManualBackfillUsesParseQuotaPool() {
        let calendar = Calendar(identifier: .gregorian)
        let settings = DropSettings.defaults()
        let now = Date(timeIntervalSince1970: 200_000)
        var usage = DailyUsage.empty(dayKey: QuotaService.dayKey(for: now, calendar: calendar))

        QuotaService.consume(.parse, usage: &usage, amount: 1, now: now, calendar: calendar)
        let decision = QuotaService.canConsumeUserQuota(
            .parse,
            settings: settings,
            usage: usage,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(usage.parseUsed, 1)
        XCTAssertTrue(decision.allowed)
    }

    func testSearchQuotaCheckDoesNotConsumeUsage() {
        let calendar = Calendar(identifier: .gregorian)
        let settings = DropSettings.defaults()
        let now = Date(timeIntervalSince1970: 200_000)
        let usage = DailyUsage.empty(dayKey: QuotaService.dayKey(for: now, calendar: calendar))

        let decision = QuotaService.canConsumeUserQuota(
            .search,
            settings: settings,
            usage: usage,
            now: now,
            calendar: calendar
        )

        XCTAssertTrue(decision.allowed)
        XCTAssertEqual(usage.searchUsed, 0)
    }
}
