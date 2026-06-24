import SwiftUI

/// Threshold-based color for a usage percentage, shared by the app UI and the
/// widget so both surfaces use identical green/yellow/red bands.
public enum UsageColor {
    public static func color(for percent: Int) -> Color {
        switch percent {
        case ..<60: return .green
        case 60..<86: return .yellow
        default: return .red
        }
    }
}
