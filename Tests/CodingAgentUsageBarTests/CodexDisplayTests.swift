import XCTest
@testable import CodingAgentUsageBar

final class CodexDisplayTests: XCTestCase {
    // 調査時と同じ、支出上限がなく残高 0 の応答。個人情報・認証情報は含めない。
    private func rateUsage(plan: String = "plus", session: Int = 76, weekly: Int = 26) throws -> CodexUsage {
        try CodexUsageAPI.parse(Data("""
        {
          "plan_type": "\(plan)",
          "rate_limit": {
            "primary_window": {"used_percent": \(session), "limit_window_seconds": 18000},
            "secondary_window": {"used_percent": \(weekly), "limit_window_seconds": 604800}
          },
          "spend_control": {"individual_limit": null},
          "credits": {"has_credits": false, "unlimited": false, "balance": "0"}
        }
        """.utf8))
    }

    func testPlusAndProExposeRateMetricsWithoutCreditSettings() throws {
        for plan in ["plus", "pro", "future_plan"] {
            let usage = try rateUsage(plan: plan)
            let display = CodexDisplay(limits: usage.limits)
            XCTAssertEqual(usage.planType, plan)
            XCTAssertEqual(display.availableMetrics, [.automatic, .session, .weekly, .max])
            XCTAssertEqual(display.percent(for: .automatic), 76)
            XCTAssertEqual(display.percent(for: .session), 76)
            XCTAssertEqual(display.percent(for: .weekly), 26)
            XCTAssertFalse(display.supportsCreditTier)
            XCTAssertNil(usage.spend)
            XCTAssertFalse(usage.limits.contains { $0.group == "credits" })
        }
    }

    func testExistingCreditAndPacePreferencesStillShowRateUsage() throws {
        let display = CodexDisplay(limits: try rateUsage().limits)
        for metric in [CodexMetric.dailyPace, .weeklyPace, .credits, .creditTier] {
            XCTAssertEqual(display.effectiveMetric(metric), .automatic)
            XCTAssertEqual(display.percent(for: metric), 76)
        }
    }

    func testAutomaticShowsWeeklyWhenItIsCloserToTheLimit() throws {
        let display = CodexDisplay(limits: try rateUsage(session: 20, weekly: 95).limits)
        XCTAssertEqual(display.percent(for: .automatic), 95)
        XCTAssertEqual(display.automaticLimit?.kind, "weekly_all")
    }

    func testZeroUsageIsAvailableRatherThanMissing() throws {
        let display = CodexDisplay(limits: try rateUsage(session: 0, weekly: 0).limits)
        XCTAssertEqual(display.availableMetrics, [.automatic, .session, .weekly, .max])
        XCTAssertEqual(display.percent(for: .dailyPace), 0)
    }

    func testCreditPlansKeepTheirCreditAndPaceMetrics() throws {
        let usage = try CodexUsageAPI.parse(Data("""
        {
          "plan_type": "business",
          "rate_limit": null,
          "spend_control": {"individual_limit": {"used": 500, "limit": 20000, "remaining": 19500}}
        }
        """.utf8))
        let pace = [
            UsageLimit(provider: .codex, kind: "pace_daily", group: "pace", percent: 45),
            UsageLimit(provider: .codex, kind: "pace_weekly", group: "pace", percent: 35),
        ]
        let display = CodexDisplay(limits: usage.limits + pace)
        XCTAssertEqual(display.availableMetrics, [.automatic, .dailyPace, .weeklyPace, .credits, .creditTier, .max])
        XCTAssertEqual(display.percent(for: .automatic), 2.5)
        XCTAssertEqual(display.percent(for: .dailyPace), 45)
        XCTAssertEqual(display.percent(for: .weeklyPace), 35)
        XCTAssertEqual(display.percent(for: .creditTier), 50)
        XCTAssertTrue(display.supportsCreditTier)
        XCTAssertEqual(usage.spend?.limit, 20000)

        // 目安 OFF や、クレジット制へのプラン変更でも使用率を表示する。
        let withoutPace = CodexDisplay(limits: usage.limits)
        XCTAssertFalse(withoutPace.availableMetrics.contains(.dailyPace))
        XCTAssertEqual(withoutPace.percent(for: .dailyPace), 2.5)
        XCTAssertEqual(withoutPace.percent(for: .session), 2.5)
    }

    func testModelSpecificLimitsAreIncluded() throws {
        let usage = try CodexUsageAPI.parse(Data("""
        {
          "rate_limit": {"primary_window": {"used_percent": 20}},
          "additional_rate_limits": [{
            "limit_name": "Preview", "metered_feature": "preview",
            "rate_limit": {"primary_window": {"used_percent": 90}}
          }]
        }
        """.utf8))
        let display = CodexDisplay(limits: usage.limits)
        XCTAssertEqual(display.percent(for: .automatic), 90)
        XCTAssertEqual(display.percent(for: .session), 90)
        XCTAssertEqual(display.automaticLimit?.modelName, "Preview")
        XCTAssertFalse(display.availableMetrics.contains(.weekly))
    }

    func testCreditBalanceDoesNotMaskAnAvailablePercentage() {
        let display = CodexDisplay(limits: [
            UsageLimit(provider: .codex, kind: "credit_balance", group: "credits", details: ["残高 0"]),
            UsageLimit(provider: .codex, kind: "credits", group: "credits", percent: 12),
            UsageLimit(provider: .codex, kind: "session", group: "session", percent: 80),
        ])
        XCTAssertEqual(display.percent(for: .automatic), 12)
        XCTAssertEqual(display.percent(for: .credits), 12)
        XCTAssertEqual(display.percent(for: .max), 80)
    }

    func testBalanceOnlyDoesNotInventAPercentage() throws {
        let usage = try CodexUsageAPI.parse(Data("""
        {"credits": {"balance": "100", "unlimited": false}}
        """.utf8))
        let display = CodexDisplay(limits: usage.limits)
        XCTAssertEqual(display.availableMetrics, [.automatic])
        XCTAssertNil(display.percent(for: .automatic))
        XCTAssertEqual(usage.limits.first?.details, ["残高 100"])
    }

    func testEmptyResponseReportsAnErrorInsteadOfLoadingForever() {
        XCTAssertThrowsError(try CodexUsageAPI.parse(Data("{}".utf8))) { error in
            guard case UsageError.noUsageData = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    @MainActor
    func testNewSettingsDefaultToAutomaticAndPreserveExistingPreference() {
        let suite = "CodexDisplayTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(UsageSettings(defaults: defaults).codexMetric, .automatic)
        defaults.set("dailyPace", forKey: "codexMetric")
        XCTAssertEqual(UsageSettings(defaults: defaults).codexMetric, .dailyPace)
    }
}
