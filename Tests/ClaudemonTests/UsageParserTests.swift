import XCTest
@testable import ClaudemonCore

final class UsageParserTests: XCTestCase {

    // MARK: - Helpers

    /// Build a deterministic Date from components in a given timezone.
    private func date(
        _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0,
        tz: String = "Europe/Istanbul"
    ) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: tz)!
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day
        c.hour = hour; c.minute = minute; c.second = second
        return cal.date(from: c)!
    }

    /// Extract wall-clock components of a Date in a specific timezone.
    private func components(of date: Date, tz: String) -> DateComponents {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: tz)!
        return cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    }

    // The real verified /usage result block (post Fable rollout — Anthropic
    // renamed the per-model line from "(Sonnet only)" to "(Fable)").
    private let realResult = """
    Current session: 27% used · resets Jun 24 at 2:49am (Europe/Istanbul)
    Current week (all models): 29% used · resets Jun 26 at 9:59am (Europe/Istanbul)
    Current week (Fable): 2% used · resets Jun 26 at 10am (Europe/Istanbul)
    """

    // MARK: - Real verified block

    func testRealResultBlockParsesThreeMetrics() throws {
        // "now" earlier than all resets so years stay in 2026.
        let now = date(2026, 6, 23, 12, 0, tz: "Europe/Istanbul")
        let report = try UsageParser.parse(resultText: realResult, now: now)

        XCTAssertEqual(report.metrics.count, 3, "Expected exactly 3 metrics")

        // Ordering: session, weekAll, weekModel
        XCTAssertEqual(report.metrics.map { $0.kind }, [.session, .weekAll, .weekModel])

        let session = try XCTUnwrap(report.session)
        let weekAll = try XCTUnwrap(report.weekAll)
        let weekModel = try XCTUnwrap(report.weekModel)

        XCTAssertEqual(session.percent, 27)
        XCTAssertEqual(weekAll.percent, 29)
        XCTAssertEqual(weekModel.percent, 2)
        XCTAssertEqual(weekModel.modelName, "Fable", "Model name should be read from the label, not hardcoded")

        XCTAssertEqual(session.timezoneIdentifier, "Europe/Istanbul")
        XCTAssertEqual(weekAll.timezoneIdentifier, "Europe/Istanbul")
        XCTAssertEqual(weekModel.timezoneIdentifier, "Europe/Istanbul")

        // Session: Jun 24 2:49am Europe/Istanbul
        let sc = components(of: try XCTUnwrap(session.resetDate), tz: "Europe/Istanbul")
        XCTAssertEqual(sc.year, 2026)
        XCTAssertEqual(sc.month, 6)
        XCTAssertEqual(sc.day, 24)
        XCTAssertEqual(sc.hour, 2)
        XCTAssertEqual(sc.minute, 49)

        // Week all: Jun 26 9:59am
        let wc = components(of: try XCTUnwrap(weekAll.resetDate), tz: "Europe/Istanbul")
        XCTAssertEqual(wc.month, 6)
        XCTAssertEqual(wc.day, 26)
        XCTAssertEqual(wc.hour, 9)
        XCTAssertEqual(wc.minute, 59)

        // Week model: Jun 26 10am (no minutes → 00)
        let mc = components(of: try XCTUnwrap(weekModel.resetDate), tz: "Europe/Istanbul")
        XCTAssertEqual(mc.month, 6)
        XCTAssertEqual(mc.day, 26)
        XCTAssertEqual(mc.hour, 10)
        XCTAssertEqual(mc.minute, 0)
    }

    /// The classifier must not hardcode any specific model name — it should
    /// treat ANY "Current week (<model>)" line (that isn't "all models") as
    /// the per-model kind. This is a regression test for the bug where the
    /// old parser only recognized lines containing the literal word "sonnet"
    /// and silently dropped the line once Anthropic renamed it to "(Fable)".
    func testPerModelLineIsGenericNotHardcodedToSonnet() throws {
        for modelName in ["Sonnet only", "Fable", "Opus", "Haiku 4.5", "SomeFutureModelXYZ"] {
            let text = "Current week (\(modelName)): 12% used · resets Jul 1 at 10am (Europe/Istanbul)"
            let now = date(2026, 6, 23, 12, 0)
            let report = try UsageParser.parse(resultText: text, now: now)
            let m = try XCTUnwrap(report.weekModel, "Model line '\(modelName)' should classify as weekModel")
            XCTAssertEqual(m.percent, 12)
            XCTAssertEqual(m.modelName, modelName)
        }
    }

    func testParsesViaOuterJSON() throws {
        let json = try JSONSerialization.data(withJSONObject: ["result": realResult])
        let now = date(2026, 6, 23, 12, 0)
        let report = try UsageParser.parse(jsonData: json, now: now)
        XCTAssertEqual(report.metrics.count, 3)
        XCTAssertEqual(report.session?.percent, 27)
    }

    // MARK: - Time format: no minutes (10am)

    func testNoMinutesVariantParses() throws {
        let text = "Current week (Fable): 5% used · resets Jul 1 at 10am (Europe/Istanbul)"
        let now = date(2026, 6, 23, 12, 0)
        let report = try UsageParser.parse(resultText: text, now: now)
        let m = try XCTUnwrap(report.weekModel)
        let c = components(of: try XCTUnwrap(m.resetDate), tz: "Europe/Istanbul")
        XCTAssertEqual(c.hour, 10)
        XCTAssertEqual(c.minute, 0)
    }

    // MARK: - 12am / 12pm boundaries

    func test12amBoundaryMapsToMidnight() throws {
        let text = "Current session: 10% used · resets Jun 24 at 12am (Europe/Istanbul)"
        let now = date(2026, 6, 23, 12, 0)
        let report = try UsageParser.parse(resultText: text, now: now)
        let c = components(of: try XCTUnwrap(report.session?.resetDate), tz: "Europe/Istanbul")
        XCTAssertEqual(c.hour, 0, "12am must map to 00:00")
        XCTAssertEqual(c.day, 24)
    }

    func test12pmBoundaryMapsToNoon() throws {
        let text = "Current session: 10% used · resets Jun 24 at 12pm (Europe/Istanbul)"
        let now = date(2026, 6, 23, 12, 0)
        let report = try UsageParser.parse(resultText: text, now: now)
        let c = components(of: try XCTUnwrap(report.session?.resetDate), tz: "Europe/Istanbul")
        XCTAssertEqual(c.hour, 12, "12pm must map to 12:00")
    }

    func test1pmMapsTo13() throws {
        let text = "Current session: 10% used · resets Jun 24 at 1:30pm (Europe/Istanbul)"
        let now = date(2026, 6, 23, 12, 0)
        let report = try UsageParser.parse(resultText: text, now: now)
        let c = components(of: try XCTUnwrap(report.session?.resetDate), tz: "Europe/Istanbul")
        XCTAssertEqual(c.hour, 13)
        XCTAssertEqual(c.minute, 30)
    }

    // MARK: - Year inference

    func testPastMonthDayRollsToNextYear() throws {
        // now = mid-December 2026. Reset "Jan 5" is earlier in the calendar →
        // should roll to 2027.
        let now = date(2026, 12, 15, 12, 0)
        let text = "Current session: 10% used · resets Jan 5 at 9am (Europe/Istanbul)"
        let report = try UsageParser.parse(resultText: text, now: now)
        let c = components(of: try XCTUnwrap(report.session?.resetDate), tz: "Europe/Istanbul")
        XCTAssertEqual(c.year, 2027, "A reset earlier in the calendar than now should roll to next year")
        XCTAssertEqual(c.month, 1)
        XCTAssertEqual(c.day, 5)
    }

    func testFutureMonthDayStaysThisYear() throws {
        // now = Jan 2026. Reset "Dec 31" is later this year → stays 2026.
        let now = date(2026, 1, 10, 12, 0)
        let text = "Current session: 10% used · resets Dec 31 at 9am (Europe/Istanbul)"
        let report = try UsageParser.parse(resultText: text, now: now)
        let c = components(of: try XCTUnwrap(report.session?.resetDate), tz: "Europe/Istanbul")
        XCTAssertEqual(c.year, 2026, "A future reset within the year should stay this year")
        XCTAssertEqual(c.month, 12)
        XCTAssertEqual(c.day, 31)
    }

    // MARK: - Alternate timezone

    func testAlternateTimezoneResolves() throws {
        let text = "Current session: 10% used · resets Jun 24 at 2:49am (America/New_York)"
        let now = date(2026, 6, 23, 12, 0)
        let report = try UsageParser.parse(resultText: text, now: now)
        let m = try XCTUnwrap(report.session)
        XCTAssertEqual(m.timezoneIdentifier, "America/New_York")
        XCTAssertEqual(m.timezone, TimeZone(identifier: "America/New_York"))
        // Verify the date carries the correct wall-clock in New York.
        let c = components(of: try XCTUnwrap(m.resetDate), tz: "America/New_York")
        XCTAssertEqual(c.hour, 2)
        XCTAssertEqual(c.minute, 49)
        XCTAssertEqual(c.day, 24)
    }

    // MARK: - Malformed / missing input (no crash)

    func testEmptyStringThrowsEmptyResult() {
        XCTAssertThrowsError(try UsageParser.parse(resultText: "")) { error in
            XCTAssertEqual(error as? UsageParseError, UsageParseError.emptyResult)
        }
    }

    func testWhitespaceOnlyThrowsEmptyResult() {
        XCTAssertThrowsError(try UsageParser.parse(resultText: "   \n  \t ")) { error in
            XCTAssertEqual(error as? UsageParseError, UsageParseError.emptyResult)
        }
    }

    func testGarbageTextThrowsNoMetrics() {
        XCTAssertThrowsError(try UsageParser.parse(resultText: "hello world\nnothing here")) { error in
            XCTAssertEqual(error as? UsageParseError, UsageParseError.noMetricsFound)
        }
    }

    /// The REAL local-only body the `claude` CLI returns between its ~1-minute
    /// limit-line refreshes: a successful, non-empty `.result` that simply omits
    /// the three "Current session/week" lines. This must map to a STALE-RENDER
    /// signal (keep last-good data), NOT a hard error.
    func testSuccessBodyWithoutLimitLinesIsStaleRenderNotError() {
        let localOnlyBody = """
        You are currently using your subscription to power your Claude Code usage

        What's contributing to your limits usage?
        Approximate, based on local sessions on this machine.

        Last 24h · 1691 requests · 11 sessions
        Last 7d · 4199 requests · 22 sessions
        """
        XCTAssertThrowsError(try UsageParser.parse(resultText: localOnlyBody)) { error in
            let parseError = error as? UsageParseError
            XCTAssertEqual(parseError, UsageParseError.noMetricsFound)
            XCTAssertEqual(parseError?.isStaleRender, true,
                           "A success body without limit lines is a stale render, not a failure")
        }
    }

    /// An empty `.result` is a genuine failure, NOT a stale render.
    func testEmptyResultIsNotStaleRender() {
        XCTAssertThrowsError(try UsageParser.parse(resultText: "")) { error in
            let parseError = error as? UsageParseError
            XCTAssertEqual(parseError, UsageParseError.emptyResult)
            XCTAssertEqual(parseError?.isStaleRender, false,
                           "An empty body is a real failure, not a stale render")
        }
    }

    func testNonUsageJSONThrowsEmptyResult() {
        let json = try! JSONSerialization.data(withJSONObject: ["error": "boom"])
        XCTAssertThrowsError(try UsageParser.parse(jsonData: json)) { error in
            XCTAssertEqual(error as? UsageParseError, UsageParseError.emptyResult)
        }
    }

    func testInvalidJSONDataThrowsEmptyResult() {
        let data = Data("not json".utf8)
        XCTAssertThrowsError(try UsageParser.parse(jsonData: data)) { error in
            XCTAssertEqual(error as? UsageParseError, UsageParseError.emptyResult)
        }
    }

    func testLineWithPercentButNoResetDoesNotCrash() throws {
        // Has a recognizable usage line (percent) but no valid reset clause.
        let text = "Current session: 42% used"
        let now = date(2026, 6, 23, 12, 0)
        let report = try UsageParser.parse(resultText: text, now: now)
        let m = try XCTUnwrap(report.session)
        XCTAssertEqual(m.percent, 42)
        XCTAssertNil(m.resetDate, "Missing reset clause should yield nil date, not a crash")
        XCTAssertNil(m.timezoneIdentifier)
    }

    func testResetWithoutTimezoneFallsBackToCurrent() throws {
        let text = "Current session: 42% used · resets Jun 24 at 2:49am"
        let now = date(2026, 6, 23, 12, 0)
        let report = try UsageParser.parse(resultText: text, now: now)
        let m = try XCTUnwrap(report.session)
        XCTAssertNil(m.timezoneIdentifier, "No tz in text → identifier should be nil")
        XCTAssertNotNil(m.resetDate, "Date should still resolve using current tz")
    }

    func testPercentClampedAndDuplicateKindsIgnored() throws {
        // Two session lines: first wins. Also an over-100 percent gets clamped.
        let text = """
        Current session: 27% used · resets Jun 24 at 2:49am (Europe/Istanbul)
        Current session: 150% used · resets Jun 25 at 2:49am (Europe/Istanbul)
        """
        let now = date(2026, 6, 23, 12, 0)
        let report = try UsageParser.parse(resultText: text, now: now)
        XCTAssertEqual(report.metrics.count, 1)
        XCTAssertEqual(report.session?.percent, 27, "First matching line wins")
    }

    func testOrderToleranceAndExtraNoise() throws {
        // Lines out of order, with leading garbage lines.
        let text = """
        Some banner text
        Current week (Fable): 2% used · resets Jun 26 at 10am (Europe/Istanbul)
        Current session: 27% used · resets Jun 24 at 2:49am (Europe/Istanbul)
        Current week (all models): 29% used · resets Jun 26 at 9:59am (Europe/Istanbul)
        """
        let now = date(2026, 6, 23, 12, 0)
        let report = try UsageParser.parse(resultText: text, now: now)
        XCTAssertEqual(report.metrics.map { $0.kind }, [.session, .weekAll, .weekModel],
                       "Output ordering must be stable regardless of input order")
    }
}
