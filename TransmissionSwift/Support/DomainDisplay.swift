import AppKit
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
        Color(nsColor: nsDisplayColor)
    }

    /// AppKit colour for the native table cells, mirrors `displayColor`.
    var nsDisplayColor: NSColor {
        switch self {
        case .downloading: return .systemBlue
        case .seeding, .completed: return .systemGreen
        case .paused, .queued: return .secondaryLabelColor
        case .checking: return .systemOrange
        case .error: return .systemRed
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

    /// Priority glyph, shared by the table column, the context-menu submenu,
    /// the file-inspector dropdown, and the General-tab picker. High/low are
    /// directional chevrons; normal is a neutral ring (not a dash).
    var systemImage: String {
        switch self {
        case .high: return "chevron.up"
        case .normal: return "circle"
        case .low: return "chevron.down"
        }
    }

    var displayColor: Color {
        switch self {
        case .high: return .orange
        case .normal: return .gray
        case .low: return .blue
        }
    }

    /// AppKit colour for the native table cells, mirrors `displayColor`.
    var nsDisplayColor: NSColor {
        switch self {
        case .high: return .systemOrange
        case .normal: return .systemGray
        case .low: return .systemBlue
        }
    }
}

extension TorrentFile {
    /// For multi-file torrents Transmission reports each file's path relative to
    /// the download directory, so the first component is the torrent's base
    /// directory. Stripping it shows the file as it appears inside the torrent.
    /// Single-file torrents have no separator and are returned unchanged.
    var displayName: String {
        let separators = CharacterSet(charactersIn: "/\\")
        guard let firstSeparator = name.rangeOfCharacter(from: separators) else {
            return name
        }
        return String(name[firstSeparator.upperBound...])
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
