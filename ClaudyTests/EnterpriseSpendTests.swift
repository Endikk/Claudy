import XCTest
@testable import Claudy

/// Usage-billed plans (Enterprise) have no 5-hour or weekly window: the account reports a monthly
/// spend cap instead, and that cap is what the card must show.
final class EnterpriseSpendTests: XCTestCase {

    /// 2026-09-23 10:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_790_157_600)

    /// Shape captured from a Claude Enterprise account (Claude Code 2.1.261, September 2026),
    /// amounts unchanged: $46.31 spent of a $500.00 budget.
    private let enterprisePayload = """
    {
      "five_hour": null,
      "seven_day": null,
      "extra_usage": {
        "is_enabled": true, "monthly_limit": 50000, "used_credits": 4631,
        "utilization": 9.261999999999999, "currency": "USD", "decimal_places": 2,
        "disabled_reason": null, "user_disabled": false, "spend_limit_reached": false
      },
      "spend": {
        "used": {"amount_minor": 4631, "currency": "USD", "exponent": 2},
        "limit": {"amount_minor": 50000, "currency": "USD", "exponent": 2},
        "percent": 9, "severity": "normal", "enabled": true, "disabled_reason": null
      }
    }
    """

    // MARK: - Parsing

    func testSpendBlockBecomesTheMonthlyReading() throws {
        let reading = try XCTUnwrap(parse(enterprisePayload))
        let spend = try XCTUnwrap(reading.spend)

        XCTAssertNil(reading.session)
        XCTAssertNil(reading.weekly)
        XCTAssertEqual(spend.used, 46.31, accuracy: 0.0001)
        XCTAssertEqual(spend.limit, 500, accuracy: 0.0001)
        XCTAssertEqual(spend.currency, "USD")
        XCTAssertFalse(spend.isLimitReached)
        // Worked out from the amounts, not the rounded `percent: 9`.
        XCTAssertEqual(spend.percent, 0.09262, accuracy: 0.00001)
    }

    func testSpendResetsOnTheFirstOfNextMonthAtMidnightUTC() throws {
        let spend = try XCTUnwrap(parse(enterprisePayload)?.spend)

        XCTAssertEqual(spend.resetsAt, utc(2026, 10, 1))
        XCTAssertEqual(spend.startsAt, utc(2026, 9, 1))
    }

    func testDecemberRollsOverToJanuary() {
        let lateDecember = utc(2026, 12, 31, hour: 23)

        XCTAssertEqual(SpendReading.periodEnd(after: lateDecember), utc(2027, 1, 1))
    }

    func testExtraUsageIsTheFallbackWhenTheSpendBlockIsMissing() throws {
        let payload = """
        {
          "five_hour": null, "seven_day": null,
          "extra_usage": {
            "is_enabled": true, "monthly_limit": 100000, "used_credits": 25000,
            "utilization": 25, "currency": "EUR", "decimal_places": 2,
            "spend_limit_reached": false
          }
        }
        """
        let spend = try XCTUnwrap(parse(payload)?.spend)

        XCTAssertEqual(spend.used, 250, accuracy: 0.0001)
        XCTAssertEqual(spend.limit, 1000, accuracy: 0.0001)
        XCTAssertEqual(spend.currency, "EUR")
        XCTAssertEqual(spend.percent, 0.25, accuracy: 0.00001)
    }

    func testReachedCapIsReported() throws {
        let payload = """
        {
          "five_hour": null, "seven_day": null,
          "extra_usage": {"is_enabled": true, "monthly_limit": 40000, "used_credits": 40000,
                          "spend_limit_reached": true},
          "spend": {
            "used": {"amount_minor": 40000, "currency": "USD", "exponent": 2},
            "limit": {"amount_minor": 40000, "currency": "USD", "exponent": 2},
            "enabled": true
          }
        }
        """
        let spend = try XCTUnwrap(parse(payload)?.spend)

        XCTAssertTrue(spend.isLimitReached)
        XCTAssertEqual(spend.percent, 1)
    }

    /// Pro and Max carry a spend block too — their extra-usage cap. Their quota is the windows.
    func testWindowMeteredPlanIgnoresItsSpendBlock() throws {
        let payload = """
        {
          "five_hour": {"utilization": 30.0, "resets_at": "2026-09-23T14:00:00.000000+00:00"},
          "seven_day": {"utilization": 10.0, "resets_at": "2026-09-27T00:00:00.000000+00:00"},
          "spend": {
            "used": {"amount_minor": 1000, "currency": "USD", "exponent": 2},
            "limit": {"amount_minor": 50000, "currency": "USD", "exponent": 2},
            "enabled": true
          }
        }
        """
        let reading = try XCTUnwrap(parse(payload))

        XCTAssertNil(reading.spend)
        XCTAssertEqual(try XCTUnwrap(reading.session).percent, 0.30, accuracy: 0.0001)
    }

    /// No cap means no quota: a percentage of nothing would be invented.
    func testSpendWithoutAUsableCapIsNotAQuota() {
        let uncapped = """
        {"five_hour": null, "seven_day": null,
         "spend": {"used": {"amount_minor": 4631, "exponent": 2}, "limit": null, "enabled": true}}
        """
        let zeroCap = """
        {"five_hour": null, "seven_day": null,
         "spend": {"used": {"amount_minor": 0, "exponent": 2},
                   "limit": {"amount_minor": 0, "exponent": 2}, "enabled": true}}
        """
        let disabled = """
        {"five_hour": null, "seven_day": null,
         "spend": {"used": {"amount_minor": 10, "exponent": 2},
                   "limit": {"amount_minor": 500, "exponent": 2}, "enabled": false},
         "extra_usage": {"is_enabled": false, "monthly_limit": 500, "used_credits": 10}}
        """

        XCTAssertNil(parse(uncapped))
        XCTAssertNil(parse(zeroCap))
        XCTAssertNil(parse(disabled))
    }

    /// Raw `/api/oauth/usage` answer of a Max account (September 2026, published anonymised by
    /// usage-monitor-for-claude). It carries a `spend` block with no cap next to live windows:
    /// the reading must be exactly what it was before spend caps existed.
    func testRealMaxPayloadKeepsItsWindowsAndIgnoresSpend() throws {
        let reading = try XCTUnwrap(parse(Self.realMaxPayload))

        XCTAssertNil(reading.spend)
        XCTAssertEqual(try XCTUnwrap(reading.session).percent, 0.48, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(reading.weekly).percent, 0.64, accuracy: 0.0001)
        XCTAssertEqual(reading.scoped?.label, "Sonnet")
        XCTAssertEqual(try XCTUnwrap(reading.scoped).percent, 0.02, accuracy: 0.0001)
    }

    func testRealMaxTierStillReadsMaxFiveTimes() {
        XCTAssertEqual(AccountLoader.planLabel(candidates: ["default_claude_max_5x", nil, "claude_max", "max"]),
                       "Max 5×")
    }

    private static let realMaxPayload = """
    {
      "five_hour": {
        "utilization": 48.0,
        "resets_at": "2026-09-05T12:59:59.966454+00:00",
        "limit_dollars": null,
        "used_dollars": null,
        "remaining_dollars": null,
        "locked_reason": null
      },
      "seven_day": {
        "utilization": 64.0,
        "resets_at": "2026-09-11T20:59:59.966479+00:00",
        "limit_dollars": null,
        "used_dollars": null,
        "remaining_dollars": null,
        "locked_reason": null
      },
      "seven_day_oauth_apps": null,
      "seven_day_opus": null,
      "seven_day_sonnet": {
        "utilization": 2.0,
        "resets_at": "2026-09-11T20:59:59.966479+00:00",
        "limit_dollars": null,
        "used_dollars": null,
        "remaining_dollars": null,
        "locked_reason": null
      },
      "seven_day_cowork": null,
      "seven_day_omelette": null,
      "tangelo": null,
      "iguana_necktie": null,
      "omelette_promotional": null,
      "nimbus_quill": {
        "utilization": 0.0,
        "resets_at": null,
        "limit_dollars": null,
        "used_dollars": null,
        "remaining_dollars": null,
        "locked_reason": null
      },
      "cinder_cove": null,
      "copper_kite": null,
      "amber_ladder": null,
      "juniper_tide": null,
      "extra_usage": {
        "is_enabled": true,
        "monthly_limit": null,
        "used_credits": 0.0,
        "utilization": null,
        "currency": "EUR",
        "decimal_places": 2,
        "disabled_reason": null,
        "user_disabled": false,
        "spend_limit_reached": false,
        "credits_ever_enabled": true,
        "daily": null,
        "weekly": null
      },
      "limits": [
        {
          "kind": "session",
          "group": "session",
          "percent": 48,
          "severity": "normal",
          "resets_at": "2026-09-05T12:59:59.966454+00:00",
          "scope": null,
          "is_active": true
        },
        {
          "kind": "weekly_all",
          "group": "weekly",
          "percent": 64,
          "severity": "normal",
          "resets_at": "2026-09-11T20:59:59.966479+00:00",
          "scope": null,
          "is_active": false
        }
      ],
      "spend": {
        "used": { "amount_minor": 0, "currency": "EUR", "exponent": 2 },
        "limit": null,
        "percent": 0,
        "severity": "normal",
        "enabled": true,
        "disabled_reason": null,
        "cap": null,
        "balance": null,
        "auto_reload": null,
        "disclaimer": "Usage credits cover you when you hit your plan limits. [Learn more](https://support.claude.com/articles/12429409)",
        "can_purchase_credits": false,
        "can_toggle": false
      },
      "member_dashboard_available": false
    }
    """

    // MARK: - Plan label

    func testEnterpriseTierReadsAsEnterprise() {
        XCTAssertEqual(AccountLoader.planLabel(candidates: ["default_claude_zero", "claude_enterprise"]),
                       "Enterprise")
        XCTAssertEqual(AccountLoader.planLabel(candidates: ["default_raven_enterprise"]), "Enterprise")
        XCTAssertEqual(AccountLoader.planLabel(candidates: ["", "default_claude_zero", nil, "enterprise"]),
                       "Enterprise")
    }

    func testOtherPlansKeepTheirTier() {
        XCTAssertEqual(AccountLoader.planLabel(candidates: ["default_claude_max_20x", "claude_max"]), "Max 20×")
        XCTAssertEqual(AccountLoader.planLabel(candidates: [nil, "", "claude_pro"]), "Pro")
        XCTAssertEqual(AccountLoader.planLabel(candidates: [nil, ""]), "")
    }

    // MARK: - Snapshot

    func testSpendLeadsTheCardOnAUsageBilledPlan() throws {
        let snapshot = UsageAggregator.snapshot(from: [], account: AccountLoader.fallback(),
                                                reading: try XCTUnwrap(parse(enterprisePayload)),
                                                now: now)
        let spend = try XCTUnwrap(snapshot.spend)

        XCTAssertEqual(snapshot.primary.title, "Spend")
        XCTAssertEqual(snapshot.primary.window, "month")
        XCTAssertTrue(spend.isMeasured)
        XCTAssertEqual(spend.percent, 0.09262, accuracy: 0.00001)
        XCTAssertEqual(spend.windowStart, utc(2026, 9, 1))
        XCTAssertEqual(spend.resetDate, utc(2026, 10, 1))
        XCTAssertEqual(spend.amount?.used ?? 0, 46.31, accuracy: 0.0001)
        XCTAssertFalse(snapshot.weekly.isMeasured)
        XCTAssertFalse(snapshot.isOverloaded)
        XCTAssertEqual(snapshot.strain, 0)
    }

    func testReachedSpendCapOverloadsTheCard() {
        let spend = SpendReading(used: 400, limit: 400, currency: "USD", isLimitReached: true,
                                 resetsAt: utc(2026, 10, 1))
        let reading = QuotaReading(session: nil, weekly: nil, scoped: nil, spend: spend, source: .api)
        let snapshot = UsageAggregator.snapshot(from: [], account: AccountLoader.fallback(),
                                                reading: reading, now: now)

        XCTAssertTrue(snapshot.isOverloaded)
        XCTAssertEqual(snapshot.strain, 1)
    }

    func testWindowMeteredPlanStillLeadsWithTheSession() {
        let reading = QuotaReading(
            session: QuotaWindow(percent: 0.4, resetsAt: now.addingTimeInterval(3600)),
            weekly: nil, scoped: nil, source: .api
        )
        let snapshot = UsageAggregator.snapshot(from: [], account: AccountLoader.fallback(),
                                                reading: reading, now: now)

        XCTAssertNil(snapshot.spend)
        XCTAssertEqual(snapshot.primary.title, "Session")
    }

    @MainActor
    func testAmountsFormatInTheirCurrency() {
        let spend = SpendReading(used: 46.31, limit: 500, currency: "USD", isLimitReached: false,
                                 resetsAt: utc(2026, 10, 1))

        XCTAssertEqual(UsageViewModel.spent(spend, locale: Locale(identifier: "en_US")),
                       "$46.31 of $500.00")
    }

    // MARK: - Helpers

    private func parse(_ json: String) -> QuotaReading? {
        ClaudeAccountClient.parseUsage(Data(json.utf8), now: now)
    }

    private func utc(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
}
