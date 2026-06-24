import WidgetKit
import SwiftUI
import ClaudemonCore

/// Widget body: switches layout by family. Reuses ClaudemonCore color/format.
struct ClaudemonWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry

    var body: some View {
        if let report = entry.report {
            switch family {
            case .systemSmall:
                SmallUsageView(report: report, capturedAt: entry.capturedAt, isStale: entry.isStale)
            default:
                MediumUsageView(report: report, capturedAt: entry.capturedAt, isStale: entry.isStale)
            }
        } else {
            EmptyUsageView()
        }
    }
}

// MARK: - Small: session ring + weekly percent

struct SmallUsageView: View {
    let report: UsageReport
    let capturedAt: Date?
    let isStale: Bool

    private var session: Int { report.session?.percent ?? 0 }
    private var week: Int { report.weekAll?.percent ?? 0 }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.12), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: CGFloat(min(session, 100)) / 100.0)
                    .stroke(UsageColor.color(for: session),
                            style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 1) {
                    Text("\(session)%")
                        .font(.system(size: 18, weight: .bold).monospacedDigit())
                    Text("session")
                        .font(.system(size: 9, weight: .medium))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 66, height: 66)

            HStack(spacing: 4) {
                Text("Week")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(week)%")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(UsageColor.color(for: week))
            }

            footerLine
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Session \(session) percent, Week \(week) percent")
    }

    @ViewBuilder private var footerLine: some View {
        if let capturedAt {
            Text("\(isStale ? "stale · " : "")as of \(UsageFormatting.shortClockString(capturedAt))")
                .font(.system(size: 8))
                .foregroundStyle(isStale ? .orange : .secondary)
        }
    }
}

// MARK: - Medium: all three metrics as labeled bars

struct MediumUsageView: View {
    let report: UsageReport
    let capturedAt: Date?
    let isStale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "gauge.with.dots.needle.50percent")
                    .foregroundStyle(.tint)
                Text("Claude Usage")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let capturedAt {
                    Text("\(isStale ? "stale · " : "")as of \(UsageFormatting.shortClockString(capturedAt))")
                        .font(.caption2)
                        .foregroundStyle(isStale ? .orange : .secondary)
                }
            }

            ForEach(report.metrics) { metric in
                bar(for: metric)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func bar(for metric: UsageMetric) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(metric.kind.shortName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(metric.percent)%")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(UsageColor.color(for: metric.percent))
            }
            UsageBar(percent: metric.percent, height: 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(metric.kind.displayName), \(metric.percent) percent")
    }
}

// MARK: - Empty / no-cache state

struct EmptyUsageView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "gauge.with.dots.needle.0percent")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
            Text("Open Claudemon")
                .font(.subheadline.weight(.medium))
            Text("to load your usage")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No data. Open Claudemon to load your usage.")
    }
}
