import SwiftUI
import TransmissionCore

/// Display-side extensions on the domain types. Kept in the app target so the
/// core stays presentation-free.
extension TorrentStatus {
    var displayLabel: String {
        switch self {
        case .downloading: return "Downloading"
        case .seeding: return "Seeding"
        case .paused: return "Paused"
        case .checking: return "Checking"
        case .queued: return "Queued"
        case .error: return "Error"
        case .completed: return "Completed"
        }
    }

    /// Semantic status colour. Matches the Liquid Glass guidance: colour is
    /// reserved for status indicators, the rest of the chrome stays mono.
    var displayColor: Color {
        switch self {
        case .downloading: return .blue
        case .seeding, .completed: return .green
        case .paused, .queued: return .secondary
        case .checking: return .orange
        case .error: return .red
        }
    }
}

extension TorrentPriority {
    var displayLabel: String {
        switch self {
        case .low: return "Low"
        case .normal: return "Normal"
        case .high: return "High"
        }
    }
}

extension TrackerState {
    var displayLabel: String {
        switch self {
        case .working: return "Working"
        case .idle: return "Idle"
        case .error: return "Error"
        }
    }

    var displayColor: Color {
        switch self {
        case .working: return .green
        case .idle: return .secondary
        case .error: return .red
        }
    }
}

extension InspectorTab {
    var displayLabel: String {
        switch self {
        case .general: return "General"
        case .files: return "Files"
        case .peers: return "Peers"
        case .trackers: return "Trackers"
        case .options: return "Options"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "info.circle"
        case .files: return "folder"
        case .peers: return "person.2"
        case .trackers: return "antenna.radiowaves.left.and.right"
        case .options: return "slider.horizontal.3"
        }
    }
}

extension TorrentStatusFilter {
    var displayLabel: String {
        switch self {
        case .all: return "All Torrents"
        case .downloading: return "Downloading"
        case .seeding: return "Seeding"
        case .active: return "Active"
        case .paused: return "Paused"
        case .checking: return "Checking"
        case .queued: return "Queued"
        case .error: return "Error"
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "tray.full"
        case .downloading: return "arrow.down.circle"
        case .seeding: return "arrow.up.circle"
        case .active: return "bolt"
        case .paused: return "pause"
        case .checking: return "arrow.clockwise.circle"
        case .queued: return "clock"
        case .error: return "exclamationmark.triangle"
        }
    }
}
