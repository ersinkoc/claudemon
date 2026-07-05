import Foundation

/// A single usage metric parsed from the `/usage` output.
public struct UsageMetric: Identifiable, Equatable, Codable, Sendable {
    /// Stable identity derived from the kind so SwiftUI diffing is stable.
    public var id: Kind { kind }

    public enum Kind: String, CaseIterable, Codable, Sendable {
        case session
        case weekAll
        /// The per-model weekly limit. Which model this tracks (Sonnet, Fable,
        /// ...) is decided by Anthropic and shows up only in `rawLabel` — see
        /// `UsageMetric.modelName`. Do not hardcode a model name here.
        case weekModel

        public var displayName: String {
            switch self {
            case .session: return "Current Session (5h)"
            case .weekAll: return "Current Week (all models)"
            case .weekModel: return "Current Week (per model)"
            }
        }

        public var shortName: String {
            switch self {
            case .session: return "Session"
            case .weekAll: return "Week"
            case .weekModel: return "Model"
            }
        }
    }

    public let kind: Kind
    /// Raw label as it appeared in the source text (best-effort).
    public let rawLabel: String
    /// Percent used, 0...100 (clamped).
    public let percent: Int
    /// Absolute reset date in the metric's timezone, if it could be computed.
    public let resetDate: Date?
    /// IANA timezone identifier (e.g. "Europe/Istanbul"), if parsed.
    public let timezoneIdentifier: String?

    public init(kind: Kind, rawLabel: String, percent: Int, resetDate: Date?, timezoneIdentifier: String?) {
        self.kind = kind
        self.rawLabel = rawLabel
        self.percent = percent
        self.resetDate = resetDate
        self.timezoneIdentifier = timezoneIdentifier
    }

    public var timezone: TimeZone? {
        guard let timezoneIdentifier else { return nil }
        return TimeZone(identifier: timezoneIdentifier)
    }

    /// Best-effort model name for a `.weekModel` metric, extracted from the
    /// parenthesized part of `rawLabel` (e.g. "Current week (Fable)" →
    /// "Fable"). Falls back to the kind's generic short name if the label
    /// doesn't have the expected shape.
    public var modelName: String {
        guard kind == .weekModel,
              let open = rawLabel.firstIndex(of: "("),
              let close = rawLabel.firstIndex(of: ")"), open < close else {
            return kind.shortName
        }
        let inner = rawLabel[rawLabel.index(after: open)..<close]
            .trimmingCharacters(in: .whitespaces)
        return inner.isEmpty ? kind.shortName : inner
    }

    /// Full display label for headers/notifications/accessibility. Same as
    /// `kind.displayName`, except for `.weekModel`, where it substitutes the
    /// actual model name (e.g. "Current Week (Fable)") instead of the generic
    /// "Current Week (per model)" placeholder. Use this instead of
    /// `kind.displayName` anywhere a metric instance (not just its kind) is
    /// available, so the shown text tracks whatever model Anthropic is
    /// currently naming there.
    public var displayLabel: String {
        guard kind == .weekModel else { return kind.displayName }
        return "Current Week (\(modelName))"
    }
}

/// A complete usage report containing the three known metrics.
public struct UsageReport: Equatable, Codable, Sendable {
    public let metrics: [UsageMetric]
    /// When this report was produced (local device time).
    public let capturedAt: Date

    public init(metrics: [UsageMetric], capturedAt: Date) {
        self.metrics = metrics
        self.capturedAt = capturedAt
    }

    public func metric(_ kind: UsageMetric.Kind) -> UsageMetric? {
        metrics.first { $0.kind == kind }
    }

    public var session: UsageMetric? { metric(.session) }
    public var weekAll: UsageMetric? { metric(.weekAll) }
    public var weekModel: UsageMetric? { metric(.weekModel) }
}

// MARK: - Formatting helpers

public enum UsageFormatting {
    /// Returns a compact "Xh Ym" (or "Ym" / "now") countdown string from now
    /// until the supplied reset date. Returns nil if no date.
    public static func countdownString(to date: Date?, now: Date = Date()) -> String? {
        guard let date else { return nil }
        let interval = date.timeIntervalSince(now)
        if interval <= 0 { return "now" }

        let totalMinutes = Int(interval / 60.0)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    /// Absolute reset time formatted in the metric's own timezone, e.g.
    /// "Jun 24, 2:49 AM".
    public static func absoluteResetString(date: Date?, timezone: TimeZone?) -> String? {
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = timezone ?? TimeZone.current
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: date)
    }

    /// "HH:mm:ss" wall-clock string (local timezone) used for "last updated".
    public static func clockString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    /// "HH:mm" wall-clock string (local timezone) used for the widget's
    /// "as of" line.
    public static func shortClockString(_ date: Date) -> String {
        shortClockString(date, timeZone: nil)
    }

    /// "HH:mm" wall-clock string in the supplied timezone (falls back to the
    /// current timezone when nil). Used for the widget's "resets at" suffix so
    /// the time matches the panel's reset basis (the metric's own timezone).
    public static func shortClockString(_ date: Date, timeZone: TimeZone?) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = timeZone ?? TimeZone.current
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
