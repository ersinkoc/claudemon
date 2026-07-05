import XCTest
@testable import ClaudemonCore

final class SharedUsageCacheTests: XCTestCase {

    // MARK: - Helpers

    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudemon-cache-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir, FileManager.default.fileExists(atPath: tempDir.path) {
            try FileManager.default.removeItem(at: tempDir)
        }
        tempDir = nil
        try super.tearDownWithError()
    }

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

    /// A full report with all three metrics, dates, and distinct timezones.
    private func sampleReport() -> UsageReport {
        let session = UsageMetric(
            kind: .session,
            rawLabel: "Current session",
            percent: 27,
            resetDate: date(2026, 6, 24, 2, 49, tz: "Europe/Istanbul"),
            timezoneIdentifier: "Europe/Istanbul"
        )
        let weekAll = UsageMetric(
            kind: .weekAll,
            rawLabel: "Current week (all models)",
            percent: 29,
            resetDate: date(2026, 6, 26, 9, 59, tz: "America/New_York"),
            timezoneIdentifier: "America/New_York"
        )
        let weekModel = UsageMetric(
            kind: .weekModel,
            rawLabel: "Current week (Fable)",
            percent: 2,
            resetDate: date(2026, 6, 26, 10, 0, tz: "Asia/Tokyo"),
            timezoneIdentifier: "Asia/Tokyo"
        )
        return UsageReport(
            metrics: [session, weekAll, weekModel],
            capturedAt: date(2026, 6, 23, 12, 0, tz: "Europe/Istanbul")
        )
    }

    // MARK: - Round-trip (write → read)

    func testWriteSuccessRoundTripPreservesAllFields() throws {
        let cache = SharedUsageCache(baseDirectory: tempDir)
        let report = sampleReport()

        cache.writeSuccess(report)
        let cached = try XCTUnwrap(cache.read(), "Reading back a freshly-written cache must succeed")

        XCTAssertEqual(cached.state, .ok)
        XCTAssertNil(cached.errorMessage)

        let readReport = try XCTUnwrap(cached.report)
        XCTAssertEqual(readReport.metrics.count, 3)
        XCTAssertEqual(readReport.metrics.map { $0.kind }, [.session, .weekAll, .weekModel])

        // Percents
        XCTAssertEqual(readReport.session?.percent, 27)
        XCTAssertEqual(readReport.weekAll?.percent, 29)
        XCTAssertEqual(readReport.weekModel?.percent, 2)

        // Reset dates (compared against the original report's dates)
        XCTAssertEqual(readReport.session?.resetDate, report.session?.resetDate)
        XCTAssertEqual(readReport.weekAll?.resetDate, report.weekAll?.resetDate)
        XCTAssertEqual(readReport.weekModel?.resetDate, report.weekModel?.resetDate)

        // Timezone identifiers
        XCTAssertEqual(readReport.session?.timezoneIdentifier, "Europe/Istanbul")
        XCTAssertEqual(readReport.weekAll?.timezoneIdentifier, "America/New_York")
        XCTAssertEqual(readReport.weekModel?.timezoneIdentifier, "Asia/Tokyo")

        // Whole-report equality (covers rawLabel + capturedAt too)
        XCTAssertEqual(readReport, report)
    }

    func testWriteStatePreservedAcrossRoundTrip() throws {
        let cache = SharedUsageCache(baseDirectory: tempDir)
        let report = sampleReport()

        cache.writeStale(report, error: "poll failed")
        let cached = try XCTUnwrap(cache.read())

        XCTAssertEqual(cached.state, .stale, "State flag must survive the round-trip")
        XCTAssertEqual(cached.errorMessage, "poll failed")
        XCTAssertEqual(cached.report, report)
    }

    func testWriteErrorHasNilReportAndErrorState() throws {
        let cache = SharedUsageCache(baseDirectory: tempDir)

        cache.writeError("boom")
        let cached = try XCTUnwrap(cache.read())

        XCTAssertEqual(cached.state, .error)
        XCTAssertEqual(cached.errorMessage, "boom")
        XCTAssertNil(cached.report, "An error write should carry no report")
    }

    func testWrittenAtSurvivesRoundTrip() throws {
        let cache = SharedUsageCache(baseDirectory: tempDir)
        let writtenAt = date(2026, 6, 23, 22, 30, 15, tz: "Europe/Istanbul")
        let payload = CachedUsage(report: sampleReport(), state: .ok, errorMessage: nil, writtenAt: writtenAt)

        cache.write(payload)
        let cached = try XCTUnwrap(cache.read())
        XCTAssertEqual(cached.writtenAt, writtenAt)
    }

    func testWriteOverwritesPreviousPayload() throws {
        let cache = SharedUsageCache(baseDirectory: tempDir)

        cache.writeError("first")
        cache.writeSuccess(sampleReport())

        let cached = try XCTUnwrap(cache.read())
        XCTAssertEqual(cached.state, .ok, "Latest atomic write should win")
        XCTAssertNil(cached.errorMessage)
        XCTAssertNotNil(cached.report)
    }

    // MARK: - Empty / missing cache

    func testReadOnMissingCacheReturnsNilWithoutCrashing() {
        // Fresh temp dir, nothing written yet.
        let cache = SharedUsageCache(baseDirectory: tempDir)
        XCTAssertNil(cache.read(), "Missing cache file must return nil, not crash")
    }

    func testReadAfterFileRemovedReturnsNil() throws {
        let cache = SharedUsageCache(baseDirectory: tempDir)
        cache.writeSuccess(sampleReport())
        XCTAssertNotNil(cache.read())

        // Remove everything in the temp dir, then read again.
        for url in try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil) {
            try FileManager.default.removeItem(at: url)
        }
        XCTAssertNil(cache.read(), "Reading after the file is gone must return nil")
    }

    // MARK: - Malformed JSON

    func testMalformedJSONReturnsNilWithoutCrashing() throws {
        let cache = SharedUsageCache(baseDirectory: tempDir)
        let fileURL = tempDir.appendingPathComponent("usage-cache.json", conformingTo: .json)
        try Data("{ this is not valid json ]".utf8).write(to: fileURL)

        XCTAssertNil(cache.read(), "Malformed JSON must decode to nil, not crash")
    }

    func testValidJSONWrongShapeReturnsNil() throws {
        let cache = SharedUsageCache(baseDirectory: tempDir)
        let fileURL = tempDir.appendingPathComponent("usage-cache.json", conformingTo: .json)
        // Syntactically valid JSON, but not a CachedUsage.
        try Data(#"{"unexpected":"shape"}"#.utf8).write(to: fileURL)

        XCTAssertNil(cache.read(), "Valid-but-wrong-shape JSON must decode to nil, not crash")
    }

    func testEmptyFileReturnsNil() throws {
        let cache = SharedUsageCache(baseDirectory: tempDir)
        let fileURL = tempDir.appendingPathComponent("usage-cache.json", conformingTo: .json)
        try Data().write(to: fileURL)

        XCTAssertNil(cache.read(), "An empty cache file must return nil, not crash")
    }
}
