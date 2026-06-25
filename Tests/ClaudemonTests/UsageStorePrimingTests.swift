import XCTest
@testable import Claudemon
@testable import ClaudemonCore

/// Verifies that `UsageStore` seeds last-good data from the App Group cache on
/// launch, so the menu bar shows instantly and a first-fetch stale-render does
/// not drop the store back to the blank `.loading` placeholder.
@MainActor
final class UsageStorePrimingTests: XCTestCase {

    // MARK: - Helpers

    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudemon-store-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir, FileManager.default.fileExists(atPath: tempDir.path) {
            try FileManager.default.removeItem(at: tempDir)
        }
        tempDir = nil
        try super.tearDownWithError()
    }

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

    private func sampleReport() -> UsageReport {
        let session = UsageMetric(
            kind: .session, rawLabel: "Current session", percent: 27,
            resetDate: date(2026, 6, 24, 2, 49), timezoneIdentifier: "Europe/Istanbul"
        )
        let weekAll = UsageMetric(
            kind: .weekAll, rawLabel: "Current week (all models)", percent: 29,
            resetDate: date(2026, 6, 26, 9, 59, tz: "America/New_York"),
            timezoneIdentifier: "America/New_York"
        )
        return UsageReport(metrics: [session, weekAll], capturedAt: date(2026, 6, 23, 12, 0))
    }

    // MARK: - Priming

    /// With a valid cached report, a freshly-started store exposes that report
    /// as last-good (and a calm stale-render state) BEFORE any live fetch runs.
    func testPrimeFromCacheSeedsLastGoodReport() throws {
        let writtenAt = date(2026, 6, 23, 12, 1, 30)
        let cache = SharedUsageCache(baseDirectory: tempDir)
        let report = sampleReport()
        cache.write(CachedUsage(report: report, state: .ok, errorMessage: nil, writtenAt: writtenAt))

        let store = UsageStore(cache: cache)
        // Sanity: nothing seeded yet.
        XCTAssertNil(store.lastGoodReport)
        XCTAssertEqual(store.state, .loading)

        // Prime only (no refresh) — never spawns the real `claude` subprocess.
        store.primeFromCache()

        XCTAssertEqual(store.lastGoodReport, report, "Cached report must be exposed as last-good")
        XCTAssertEqual(store.state, .staleRender(report), "Primed state must be a calm stale-render")
        XCTAssertEqual(store.lastUpdated, report.capturedAt,
                       "lastUpdated must reflect the report's own capture time, not the cache write time")
        XCTAssertNotEqual(store.lastUpdated, writtenAt,
                          "lastUpdated must NOT be the cache write timestamp (which is the last failure time for stale caches)")
        XCTAssertNil(store.errorMessage, "Priming must never look like an error")
        XCTAssertFalse(store.hasNoData)
    }

    /// Priming from a stale cache whose report was captured long ago must surface
    /// the OLD capture time as `lastUpdated`, so the existing stale-detection
    /// (`dataAge` > 10 min, driving the "· stale" footer hint) correctly fires.
    /// The cache's `writtenAt` here is "now" (it is stamped at the last failure),
    /// which must NOT be mistaken for a fresh update.
    func testPrimeFromStaleCacheReflectsOldCaptureTime() throws {
        // Floor to whole seconds so the dates survive the cache's `.iso8601`
        // round-trip (which truncates sub-second precision) and compare exactly.
        let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        // Report captured 30 minutes ago, but the stale cache was written "now"
        // (writeStale stamps writtenAt: Date() on the last failure).
        let oldCapture = now.addingTimeInterval(-30 * 60)
        let session = UsageMetric(
            kind: .session, rawLabel: "Current session", percent: 27,
            resetDate: nil, timezoneIdentifier: "Europe/Istanbul"
        )
        let report = UsageReport(metrics: [session], capturedAt: oldCapture)

        let cache = SharedUsageCache(baseDirectory: tempDir)
        cache.write(CachedUsage(report: report, state: .stale,
                                errorMessage: "Couldn't read usage", writtenAt: now))

        let store = UsageStore(cache: cache)
        store.primeFromCache()

        XCTAssertEqual(store.lastUpdated, oldCapture,
                       "lastUpdated must be the report's old capture time, not the failure write time")
        let age = try XCTUnwrap(store.dataAge)
        XCTAssertGreaterThan(age, 10 * 60,
                             "Old primed data must be detected as stale (> 10 min)")
        XCTAssertEqual(store.calmFooterText(now: now), "updated \(UsageFormatting.shortClockString(oldCapture)) · stale",
                       "The stale footer hint must fire for genuinely old primed data")
    }

    /// With no cache present, priming is a no-op and the store stays loading.
    func testPrimeFromCacheNoOpWhenCacheEmpty() {
        let cache = SharedUsageCache(baseDirectory: tempDir) // nothing written
        let store = UsageStore(cache: cache)

        store.primeFromCache()

        XCTAssertEqual(store.state, .loading)
        XCTAssertNil(store.lastGoodReport)
        XCTAssertNil(store.lastUpdated)
    }

    /// Once primed, a first-fetch stale-render (`noMetricsFound`) must KEEP the
    /// primed data rather than dropping back to `.loading`. The non-nil
    /// `lastGoodReport` after priming is exactly what makes that branch hold.
    func testPrimedReportSurvivesStaleRenderBranch() {
        let cache = SharedUsageCache(baseDirectory: tempDir)
        let report = sampleReport()
        cache.write(CachedUsage(report: report, state: .ok, errorMessage: nil, writtenAt: Date()))

        let store = UsageStore(cache: cache)
        store.primeFromCache()

        // The stale-render branch keeps last-good iff lastGoodReport != nil.
        XCTAssertNotNil(store.lastGoodReport, "Primed last-good guards against a drop to .loading")
    }
}
