import SwiftUI

/// A compact, geometry-driven usage bar shared by the floating mini-window and
/// the WidgetKit widget so both surfaces fill identically.
///
/// Unlike `ProgressView(.linear)`, this guarantees the fill width tracks the
/// percentage exactly (0–100, clamped) and keeps a small visible minimum so low
/// values like 2% are still clearly readable. The fill color uses the shared
/// `UsageColor` thresholds, matching the session ring.
public struct UsageBar: View {
    private let percent: Int
    private let height: CGFloat

    public init(percent: Int, height: CGFloat = 6) {
        self.percent = percent
        self.height = height
    }

    public var body: some View {
        let clamped = max(0, min(100, percent))
        GeometryReader { geo in
            let fullWidth = geo.size.width
            // Fraction of the track to fill. Keep a small visible sliver for
            // any non-zero value so e.g. 2% does not look empty.
            let fraction = CGFloat(clamped) / 100.0
            let minVisible: CGFloat = clamped > 0 ? height : 0
            let fillWidth = max(minVisible, fullWidth * fraction)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.15))
                Capsule()
                    .fill(UsageColor.color(for: clamped))
                    .frame(width: min(fullWidth, fillWidth))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}
