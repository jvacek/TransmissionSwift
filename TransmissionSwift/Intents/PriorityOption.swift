import AppIntents
import TransmissionCore

/// Bandwidth priority as a Shortcuts-pickable enum. Maps to the core
/// `TorrentPriority` (which can't conform to `AppEnum` without importing
/// AppIntents into `TransmissionCore`).
enum PriorityOption: String, AppEnum, CaseIterable, Sendable {
    case low
    case normal
    case high

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Priority")
    static let caseDisplayRepresentations: [PriorityOption: DisplayRepresentation] = [
        .low: "Low",
        .normal: "Normal",
        .high: "High",
    ]

    var domain: TorrentPriority {
        switch self {
        case .low: .low
        case .normal: .normal
        case .high: .high
        }
    }
}
