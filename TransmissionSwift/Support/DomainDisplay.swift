// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import TransmissionCore

/// Display-side extensions on the domain types. Kept in the app target so the
/// core stays presentation-free.
extension TorrentStatus {
    nonisolated var displayLabel: String {
        switch self {
        case .downloading: return L10n.text("Downloading")
        case .seeding: return L10n.text("Seeding")
        case .paused: return L10n.text("Paused")
        case .checking: return L10n.text("Checking")
        case .queued: return L10n.text("Queued")
        case .error: return L10n.text("Error")
        case .completed: return L10n.text("Completed")
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

extension Torrent {
    /// Progress-bar tint. A verify shows in the checking colour even when an
    /// error owns the status, since the bar then shows the verify's progress.
    /// A torrent waiting in the verify queue isn't being hashed yet, so it
    /// gets the idle grey.
    var progressNSColor: NSColor {
        switch activity {
        case .verifying: return TorrentStatus.checking.nsDisplayColor
        case .verifyQueued: return TorrentStatus.queued.nsDisplayColor
        default: return status.nsDisplayColor
        }
    }
}

extension TorrentPriority {
    nonisolated var displayLabel: String {
        switch self {
        case .low: return L10n.text("Low")
        case .normal: return L10n.text("Normal")
        case .high: return L10n.text("High")
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
    nonisolated var displayName: String {
        let separators = CharacterSet(charactersIn: "/\\")
        guard let firstSeparator = name.rangeOfCharacter(from: separators) else {
            return name
        }
        return String(name[firstSeparator.upperBound...])
    }
}

extension TrackerState {
    nonisolated var displayLabel: String {
        switch self {
        case .working: return L10n.text("Working")
        case .idle: return L10n.text("Idle")
        case .error: return L10n.text("Error")
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
    nonisolated var displayLabel: String {
        switch self {
        case .general: return L10n.text("General")
        case .files: return L10n.text("Files")
        case .peers: return L10n.text("Peers")
        case .trackers: return L10n.text("Trackers")
        }
    }
    var systemImage: String {
        switch self {
        case .general: return "info.circle"
        case .files: return "folder"
        case .peers: return "person.2"
        case .trackers: return "antenna.radiowaves.left.and.right"
        }
    }
}

extension TorrentStatusFilter {
    nonisolated var displayLabel: String {
        switch self {
        case .all: return L10n.text("All Torrents")
        case .downloading: return L10n.text("Downloading")
        case .seeding: return L10n.text("Seeding")
        case .active: return L10n.text("Active")
        case .paused: return L10n.text("Paused")
        case .checking: return L10n.text("Checking")
        case .queued: return L10n.text("Queued")
        case .error: return L10n.text("Error")
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

/// ISO-3166 alpha-2 country code → regional-indicator emoji flag, e.g. "NL" →
/// "🇳🇱". Returns nil unless the code is exactly two A–Z letters; macOS
/// renders the pair as the flag glyph.
nonisolated func countryFlagEmoji(for code: String) -> String? {
    let upper = Array(code.uppercased().unicodeScalars)
    guard code.unicodeScalars.count == 2, upper.count == 2,
        upper.allSatisfy({ (65...90).contains($0.value) })
    else { return nil }
    let scalars = upper.compactMap { Unicode.Scalar(0x1F1E6 + $0.value - 0x41) }
    return String(scalars.map(Character.init))
}

extension ActionError {
    nonisolated var displayTitle: String {
        switch self {
        case .failed: return L10n.text("Action Failed")
        case .torrentDuplicate: return L10n.text("Already in List")
        }
    }

    nonisolated var displayMessage: String {
        switch self {
        case .failed(let message): return message
        case .torrentDuplicate(let name):
            return L10n.format("“%@” is already in your list.", name)
        }
    }
}

extension GeoIPRefreshFrequency {
    nonisolated var displayLabel: String {
        switch self {
        case .onStartup: return L10n.text("On startup")
        case .daily: return L10n.text("Daily")
        case .weekly: return L10n.text("Weekly")
        case .monthly: return L10n.text("Monthly")
        }
    }
}
