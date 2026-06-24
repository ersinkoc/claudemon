import Foundation

/// The shared App Group identifier used by both the app and the widget.
public let claudemonAppGroupID = "group.com.claudemon.app"

/// The widget kind string, shared so the app can request reloads by name.
public let claudemonWidgetKind = "ClaudemonWidget"

/// High-level freshness flag persisted alongside the cached report.
public enum CachedUsageState: String, Codable, Sendable {
    case ok       // last write was a successful fresh poll
    case stale    // app is showing last-good data but the latest poll failed
    case error    // no data and an error
}

/// The full payload written to the App Group container.
public struct CachedUsage: Codable, Sendable {
    public let report: UsageReport?
    public let state: CachedUsageState
    public let errorMessage: String?
    /// When the cache file was last written (device local time).
    public let writtenAt: Date

    public init(report: UsageReport?, state: CachedUsageState, errorMessage: String?, writtenAt: Date) {
        self.report = report
        self.state = state
        self.errorMessage = errorMessage
        self.writtenAt = writtenAt
    }
}

/// Reads/writes the latest `UsageReport` (as JSON) into the App Group container
/// so the network-free widget can read it. The app writes; the widget reads.
public struct SharedUsageCache {

    public static let shared = SharedUsageCache()

    private let groupID: String
    private let fileName = "usage-cache.json"

    /// Optional explicit base directory. When set (tests/CLI), the cache reads
    /// and writes directly under this directory instead of resolving the App
    /// Group container. Production always leaves this nil so the real App Group
    /// container path is used.
    private let baseDirectory: URL?

    public init(groupID: String = claudemonAppGroupID) {
        self.groupID = groupID
        self.baseDirectory = nil
    }

    /// Testable initializer that injects an explicit base directory (e.g. a temp
    /// dir) so round-trips can be verified without the App Group entitlement.
    /// Not used by production code paths.
    init(baseDirectory: URL, groupID: String = claudemonAppGroupID) {
        self.groupID = groupID
        self.baseDirectory = baseDirectory
    }

    /// URL of the cache file inside the App Group container (or the injected
    /// base directory in tests), if available.
    private var fileURL: URL? {
        if let baseDirectory {
            return baseDirectory.appendingPathComponent(fileName, conformingTo: .json)
        }
        return FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appendingPathComponent(fileName, conformingTo: .json)
    }

    // MARK: - Write (app side)

    /// Persist a cache payload. Silently no-ops if the container is unavailable
    /// (e.g. running unsandboxed without the entitlement).
    public func write(_ cached: CachedUsage) {
        guard let url = fileURL else { return }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(cached)
            try data.write(to: url, options: .atomic)
        } catch {
            // Non-fatal: the live surfaces are unaffected by a cache write miss.
        }
    }

    /// Convenience for a successful poll.
    public func writeSuccess(_ report: UsageReport) {
        write(CachedUsage(report: report, state: .ok, errorMessage: nil, writtenAt: Date()))
    }

    /// Convenience for a stale state (keep last-good data + note the error).
    public func writeStale(_ report: UsageReport, error: String) {
        write(CachedUsage(report: report, state: .stale, errorMessage: error, writtenAt: Date()))
    }

    /// Convenience for an error with no data.
    public func writeError(_ error: String) {
        write(CachedUsage(report: nil, state: .error, errorMessage: error, writtenAt: Date()))
    }

    // MARK: - Read (widget side)

    /// Read the most recent cache payload, or nil if none exists / unreadable.
    public func read() -> CachedUsage? {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CachedUsage.self, from: data)
    }
}
