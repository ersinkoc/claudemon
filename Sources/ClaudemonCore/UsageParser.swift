import Foundation

/// Outcomes of parsing the `/usage` payload.
public enum UsageParseError: Error, LocalizedError {
    /// The `.result` body was empty — a genuine failure (no usable output).
    case emptyResult
    /// The `.result` body was a real, non-empty usage report, but it did NOT
    /// contain the three "Current session/week" limit lines. This is NOT a
    /// failure: the `claude` CLI only refreshes those lines on its own ~1-minute
    /// internal cadence and returns a fast local-only body in between. The
    /// app should keep showing last-good data ("stale render"), not an error.
    case noMetricsFound

    /// True when this outcome means "no new limit data this tick" rather than a
    /// real failure — i.e. last-good data is still valid and should be kept.
    public var isStaleRender: Bool {
        if case .noMetricsFound = self { return true }
        return false
    }

    public var errorDescription: String? {
        switch self {
        case .emptyResult: return "The usage output was empty."
        case .noMetricsFound: return "No new usage data this cycle."
        }
    }
}

/// Tolerant parser turning the human-readable `.result` text into a `UsageReport`.
///
/// Expected lines (order tolerant, wording tolerant):
///   Current session: 28% used · resets Jun 24 at 2:49am (Europe/Istanbul)
///   Current week (all models): 29% used · resets Jun 26 at 9:59am (Europe/Istanbul)
///   Current week (Sonnet only): 2% used · resets Jun 26 at 10am (Europe/Istanbul)
///
/// Times may be "2:49am", "9:59am", or "10am" (no minutes). The year is not in
/// the text and is inferred as the nearest future occurrence.
public enum UsageParser {

    /// Parse the outer subprocess JSON, extract `.result`, then parse metrics.
    public static func parse(jsonData: Data, now: Date = Date()) throws -> UsageReport {
        guard let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let result = obj["result"] as? String else {
            throw UsageParseError.emptyResult
        }
        return try parse(resultText: result, now: now)
    }

    /// Parse the `.result` free-text string directly.
    public static func parse(resultText: String, now: Date = Date()) throws -> UsageReport {
        let trimmed = resultText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw UsageParseError.emptyResult }

        var metrics: [UsageMetric] = []
        let lines = trimmed.components(separatedBy: "\n")

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let kind = classify(line: line) else { continue }
            // Avoid duplicate kinds (first match wins).
            if metrics.contains(where: { $0.kind == kind }) { continue }
            if let metric = parseMetric(line: line, kind: kind, now: now) {
                metrics.append(metric)
            }
        }

        guard !metrics.isEmpty else { throw UsageParseError.noMetricsFound }

        // Keep a stable, expected ordering.
        let order: [UsageMetric.Kind] = [.session, .weekAll, .weekSonnet]
        metrics.sort { a, b in
            (order.firstIndex(of: a.kind) ?? 99) < (order.firstIndex(of: b.kind) ?? 99)
        }

        return UsageReport(metrics: metrics, capturedAt: now)
    }

    // MARK: - Line classification

    private static func classify(line: String) -> UsageMetric.Kind? {
        let lower = line.lowercased()
        // Must look like a usage line at all.
        guard lower.contains("used") || lower.contains("resets") else { return nil }

        if lower.contains("session") {
            return .session
        }
        if lower.contains("week") {
            if lower.contains("sonnet") {
                return .weekSonnet
            }
            // "all models" or anything else weekly that is not sonnet.
            return .weekAll
        }
        return nil
    }

    // MARK: - Metric line parsing

    /// Matches: "<percent>% used" and the reset clause.
    /// Tolerant: separators, spacing, optional minutes, optional timezone.
    private static func parseMetric(line: String, kind: UsageMetric.Kind, now: Date) -> UsageMetric? {
        guard let percent = parsePercent(in: line) else { return nil }

        let label = parseLabel(in: line) ?? kind.shortName
        let (resetDate, tzIdentifier) = parseReset(in: line, now: now)

        return UsageMetric(
            kind: kind,
            rawLabel: label,
            percent: max(0, min(100, percent)),
            resetDate: resetDate,
            timezoneIdentifier: tzIdentifier
        )
    }

    private static func parseLabel(in line: String) -> String? {
        // Label is everything before the first ":".
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let label = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces)
        return label.isEmpty ? nil : label
    }

    private static func parsePercent(in line: String) -> Int? {
        // Find "<digits>%". Use a tolerant regex.
        guard let regex = try? NSRegularExpression(pattern: #"(\d{1,3})\s*%"#) else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range),
              let r = Range(match.range(at: 1), in: line),
              let value = Int(line[r]) else { return nil }
        return value
    }

    /// Parses "resets Jun 24 at 2:49am (Europe/Istanbul)" → (Date?, tzId?).
    private static func parseReset(in line: String, now: Date) -> (Date?, String?) {
        // Pattern groups:
        //  1: month abbreviation (3+ letters)
        //  2: day (1-2 digits)
        //  3: hour (1-2 digits)
        //  4: minutes (optional, ":mm")
        //  5: am/pm
        //  6: timezone (optional, inside parentheses)
        let pattern = #"resets\s+([A-Za-z]{3,})\s+(\d{1,2})\s+at\s+(\d{1,2})(?::(\d{2}))?\s*([ap]m)(?:\s*\(([^)]+)\))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return (nil, nil)
        }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range) else {
            return (nil, nil)
        }

        func group(_ i: Int) -> String? {
            guard let r = Range(match.range(at: i), in: line) else { return nil }
            return String(line[r])
        }

        guard let monthStr = group(1),
              let dayStr = group(2), let day = Int(dayStr),
              let hourStr = group(3), var hour = Int(hourStr),
              let ampm = group(5)?.lowercased() else {
            return (nil, nil)
        }
        let minute = group(4).flatMap { Int($0) } ?? 0
        let tzId = group(6)

        // A timezone without a usable date is meaningless, so return (nil, nil).
        guard let month = monthNumber(from: monthStr) else { return (nil, nil) }

        // 12-hour → 24-hour conversion.
        if ampm == "pm" && hour != 12 { hour += 12 }
        if ampm == "am" && hour == 12 { hour = 0 }

        let timezone = tzId.flatMap { TimeZone(identifier: $0) } ?? TimeZone.current

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone

        // Infer year: start with the current year (in the target tz), then roll
        // forward if the resulting date is in the past.
        let nowComponents = calendar.dateComponents([.year], from: now)
        let baseYear = nowComponents.year ?? Calendar.current.component(.year, from: now)

        var components = DateComponents()
        components.timeZone = timezone
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = 0
        components.year = baseYear

        guard var date = calendar.date(from: components) else { return (nil, nil) }

        // If the computed date is already in the past, roll to next year.
        if date < now {
            components.year = baseYear + 1
            if let next = calendar.date(from: components) {
                date = next
            }
        }

        return (date, tzId)
    }

    private static func monthNumber(from raw: String) -> Int? {
        let key = raw.prefix(3).lowercased()
        let months = ["jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
                      "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12]
        return months[String(key)]
    }
}
