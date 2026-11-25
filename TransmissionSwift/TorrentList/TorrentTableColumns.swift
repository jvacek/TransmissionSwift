// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import TransmissionCore

/// Grouping for the header's column-visibility menu. The native AppKit header
/// menu is a flat list — with 30+ columns that's unfindable, so the table
/// installs a custom grouped menu (see the coordinator's header menu) with one
/// submenu per group.
enum TorrentTableColumnGroup: String, CaseIterable {
    case general = "General"
    case transfer = "Transfer"
    case dates = "Dates & Time"
    case totals = "Totals"
    case limits = "Limits"

    var displayLabel: String {
        L10n.text(rawValue)
    }
}

struct TorrentTableColumnSpec {
    let column: TableColumn
    let title: String
    let group: TorrentTableColumnGroup
    let minWidth: CGFloat
    let idealWidth: CGFloat
    let maxWidth: CGFloat
    let hiddenByDefault: Bool

    var identifier: NSUserInterfaceItemIdentifier {
        NSUserInterfaceItemIdentifier(column.rawValue)
    }
}

enum TorrentTableColumns {
    static var all: [TorrentTableColumnSpec] {
        [
            TorrentTableColumnSpec(
                column: .name, title: L10n.text("Name"), group: .general,
                minWidth: 240, idealWidth: 400, maxWidth: 800, hiddenByDefault: false),
            TorrentTableColumnSpec(
                column: .size, title: L10n.text("Size"), group: .general,
                minWidth: 54, idealWidth: 74, maxWidth: 120, hiddenByDefault: false),
            TorrentTableColumnSpec(
                column: .progress, title: L10n.text("Progress"), group: .general,
                minWidth: 80, idealWidth: 130, maxWidth: 200, hiddenByDefault: false),
            TorrentTableColumnSpec(
                column: .downloadSpeed, title: L10n.text("\u{2193} Speed"), group: .transfer,
                minWidth: 70, idealWidth: 95, maxWidth: 130, hiddenByDefault: false),
            TorrentTableColumnSpec(
                column: .uploadSpeed, title: L10n.text("\u{2191} Speed"), group: .transfer,
                minWidth: 70, idealWidth: 95, maxWidth: 130, hiddenByDefault: false),
            TorrentTableColumnSpec(
                column: .eta, title: L10n.text("ETA"), group: .transfer,
                minWidth: 52, idealWidth: 66, maxWidth: 100, hiddenByDefault: false),
            TorrentTableColumnSpec(
                column: .ratio, title: L10n.text("Ratio"), group: .transfer,
                minWidth: 50, idealWidth: 60, maxWidth: 90, hiddenByDefault: false),
            TorrentTableColumnSpec(
                column: .addedAt, title: L10n.text("Added"), group: .dates,
                minWidth: 72, idealWidth: 100, maxWidth: 150, hiddenByDefault: false),
            TorrentTableColumnSpec(
                column: .primaryTracker, title: L10n.text("Tracker"), group: .general,
                minWidth: 80, idealWidth: 120, maxWidth: 200, hiddenByDefault: false),
            TorrentTableColumnSpec(
                column: .connectedPeers, title: L10n.text("Peers"), group: .transfer,
                minWidth: 50, idealWidth: 65, maxWidth: 100, hiddenByDefault: true),
            TorrentTableColumnSpec(
                column: .availablePeers, title: L10n.text("Available"), group: .transfer,
                minWidth: 60, idealWidth: 80, maxWidth: 110, hiddenByDefault: true),
            TorrentTableColumnSpec(
                column: .seeds, title: L10n.text("Seeds"), group: .transfer,
                minWidth: 45, idealWidth: 60, maxWidth: 90, hiddenByDefault: true),
            TorrentTableColumnSpec(
                column: .status, title: L10n.text("Status"), group: .general,
                minWidth: 80, idealWidth: 100, maxWidth: 150, hiddenByDefault: true),
            TorrentTableColumnSpec(
                column: .label, title: L10n.text("Labels"), group: .general,
                minWidth: 80, idealWidth: 120, maxWidth: 200, hiddenByDefault: true),
            TorrentTableColumnSpec(
                column: .priority, title: L10n.text("Priority"), group: .general,
                minWidth: 70, idealWidth: 90, maxWidth: 130, hiddenByDefault: true),
            TorrentTableColumnSpec(
                column: .queuePosition, title: L10n.text("Queue"), group: .general,
                minWidth: 50, idealWidth: 65, maxWidth: 100, hiddenByDefault: true),
            TorrentTableColumnSpec(
                column: .errorMessage, title: L10n.text("Error"), group: .general,
                minWidth: 100, idealWidth: 200, maxWidth: 400, hiddenByDefault: true),
            TorrentTableColumnSpec(
                column: .pieces, title: L10n.text("Pieces"), group: .general,
                minWidth: 70, idealWidth: 90, maxWidth: 130, hiddenByDefault: true),
            TorrentTableColumnSpec(
                column: .downloadFolder, title: L10n.text("Folder"), group: .general,
                minWidth: 120, idealWidth: 200, maxWidth: 400, hiddenByDefault: true),
            TorrentTableColumnSpec(
                column: .hash, title: L10n.text("Hash"), group: .general,
                minWidth: 100, idealWidth: 200, maxWidth: 400, hiddenByDefault: true),
            TorrentTableColumnSpec(
                column: .completedAt, title: L10n.text("Completed"), group: .dates,
                minWidth: 72, idealWidth: 100, maxWidth: 150, hiddenByDefault: true),
            TorrentTableColumnSpec(
                column: .startedAt, title: L10n.text("Started"), group: .dates,
                minWidth: 72, idealWidth: 100, maxWidth: 150, hiddenByDefault: true),
            TorrentTableColumnSpec(
                column: .lastActivityAt, title: L10n.text("Last Active"), group: .dates,
                minWidth: 72, idealWidth: 100, maxWidth: 150, hiddenByDefault: true),
            TorrentTableColumnSpec(
                column: .downloadedEver, title: L10n.text("Total DL"), group: .totals,
                minWidth: 60, idealWidth: 80, maxWidth: 120, hiddenByDefault: true),
            TorrentTableColumnSpec(
                column: .uploadedEver, title: L10n.text("Total UL"), group: .totals,
                minWidth: 60, idealWidth: 80, maxWidth: 120, hiddenByDefault: true),
            TorrentTableColumnSpec(
                column: .leftUntilDone, title: L10n.text("Remaining"), group: .totals,
                minWidth: 60, idealWidth: 80, maxWidth: 120, hiddenByDefault: true),
            TorrentTableColumnSpec(
                column: .sizeWhenDone, title: L10n.text("Size When Done"), group: .totals,
                minWidth: 70, idealWidth: 95, maxWidth: 130, hiddenByDefault: true),
            TorrentTableColumnSpec(
                column: .secondsDownloading, title: L10n.text("Download Time"), group: .dates,
                minWidth: 70, idealWidth: 90, maxWidth: 120, hiddenByDefault: true),
            TorrentTableColumnSpec(
                column: .secondsSeeding, title: L10n.text("Seeding Time"), group: .dates,
                minWidth: 70, idealWidth: 90, maxWidth: 120, hiddenByDefault: true),
            TorrentTableColumnSpec(
                column: .downloadLimit, title: L10n.text("DL Limit"), group: .limits,
                minWidth: 60, idealWidth: 80, maxWidth: 110, hiddenByDefault: true),
            TorrentTableColumnSpec(
                column: .uploadLimit, title: L10n.text("UL Limit"), group: .limits,
                minWidth: 60, idealWidth: 80, maxWidth: 110, hiddenByDefault: true),
            TorrentTableColumnSpec(
                column: .seedRatioLimit, title: L10n.text("Ratio Limit"), group: .limits,
                minWidth: 60, idealWidth: 80, maxWidth: 110, hiddenByDefault: true),
            TorrentTableColumnSpec(
                column: .seedIdleLimit, title: L10n.text("Idle Limit"), group: .limits,
                minWidth: 60, idealWidth: 80, maxWidth: 110, hiddenByDefault: true),
            TorrentTableColumnSpec(
                column: .peerLimit, title: L10n.text("Peer Limit"), group: .limits,
                minWidth: 55, idealWidth: 70, maxWidth: 100, hiddenByDefault: true),
        ]
    }

    static let cellReuseIdentifierPrefix = "torrentCell."
}
