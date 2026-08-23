import Foundation

/// A Finder-style tag colour. Finder supports exactly seven colours plus
/// "none"; we model "none" as an absent entry in `TagColorStore` rather than a
/// case, so the palette here is the full seven.
public enum TagColor: String, CaseIterable, Codable, Sendable, Hashable {
    case red
    case orange
    case yellow
    case green
    case blue
    case purple
    case gray

    /// Human-readable colour name, matching Finder's default tag labels.
    public var displayName: String {
        switch self {
        case .red: return "Red"
        case .orange: return "Orange"
        case .yellow: return "Yellow"
        case .green: return "Green"
        case .blue: return "Blue"
        case .purple: return "Purple"
        case .gray: return "Gray"
        }
    }
}
