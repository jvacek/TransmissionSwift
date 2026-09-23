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
    static let all: [TorrentTableColumnSpec] = [
        TorrentTableColumnSpec(
            column: .name, title: "Name", group: .general,
            minWidth: 240, idealWidth: 400, maxWidth: 800, hiddenByDefault: false),
        TorrentTableColumnSpec(
            column: .size, title: "Size", group: .general,
            minWidth: 54, idealWidth: 74, maxWidth: 120, hiddenByDefault: false),
        TorrentTableColumnSpec(
            column: .progress, title: "Progress", group: .general,
            minWidth: 80, idealWidth: 130, maxWidth: 200, hiddenByDefault: false),
        TorrentTableColumnSpec(
            column: .downloadSpeed, title: "\u{2193} Speed", group: .transfer,
            minWidth: 70, idealWidth: 95, maxWidth: 130, hiddenByDefault: false),
        TorrentTableColumnSpec(
            column: .uploadSpeed, title: "\u{2191} Speed", group: .transfer,
            minWidth: 70, idealWidth: 95, maxWidth: 130, hiddenByDefault: false),
        TorrentTableColumnSpec(
            column: .eta, title: "ETA", group: .transfer,
            minWidth: 52, idealWidth: 66, maxWidth: 100, hiddenByDefault: false),
        TorrentTableColumnSpec(
            column: .ratio, title: "Ratio", group: .transfer,
            minWidth: 50, idealWidth: 60, maxWidth: 90, hiddenByDefault: false),
        TorrentTableColumnSpec(
            column: .addedAt, title: "Added", group: .dates,
            minWidth: 72, idealWidth: 100, maxWidth: 150, hiddenByDefault: false),
        TorrentTableColumnSpec(
            column: .primaryTracker, title: "Tracker", group: .general,
            minWidth: 80, idealWidth: 120, maxWidth: 200, hiddenByDefault: false),
        TorrentTableColumnSpec(
            column: .connectedPeers, title: "Peers", group: .transfer,
            minWidth: 50, idealWidth: 65, maxWidth: 100, hiddenByDefault: true),
        TorrentTableColumnSpec(
            column: .availablePeers, title: "Available", group: .transfer,
            minWidth: 60, idealWidth: 80, maxWidth: 110, hiddenByDefault: true),
        TorrentTableColumnSpec(
            column: .seeds, title: "Seeds", group: .transfer,
            minWidth: 45, idealWidth: 60, maxWidth: 90, hiddenByDefault: true),
        TorrentTableColumnSpec(
            column: .status, title: "Status", group: .general,
            minWidth: 80, idealWidth: 100, maxWidth: 150, hiddenByDefault: true),
        TorrentTableColumnSpec(
            column: .label, title: "Labels", group: .general,
            minWidth: 80, idealWidth: 120, maxWidth: 200, hiddenByDefault: true),
        TorrentTableColumnSpec(
            column: .priority, title: "Priority", group: .general,
            minWidth: 70, idealWidth: 90, maxWidth: 130, hiddenByDefault: true),
        TorrentTableColumnSpec(
            column: .queuePosition, title: "Queue", group: .general,
            minWidth: 50, idealWidth: 65, maxWidth: 100, hiddenByDefault: true),
        TorrentTableColumnSpec(
            column: .errorMessage, title: "Error", group: .general,
            minWidth: 100, idealWidth: 200, maxWidth: 400, hiddenByDefault: true),
        TorrentTableColumnSpec(
            column: .pieces, title: "Pieces", group: .general,
            minWidth: 70, idealWidth: 90, maxWidth: 130, hiddenByDefault: true),
        TorrentTableColumnSpec(
            column: .downloadFolder, title: "Folder", group: .general,
            minWidth: 120, idealWidth: 200, maxWidth: 400, hiddenByDefault: true),
        TorrentTableColumnSpec(
            column: .hash, title: "Hash", group: .general,
            minWidth: 100, idealWidth: 200, maxWidth: 400, hiddenByDefault: true),
        TorrentTableColumnSpec(
            column: .completedAt, title: "Completed", group: .dates,
            minWidth: 72, idealWidth: 100, maxWidth: 150, hiddenByDefault: true),
        TorrentTableColumnSpec(
            column: .startedAt, title: "Started", group: .dates,
            minWidth: 72, idealWidth: 100, maxWidth: 150, hiddenByDefault: true),
        TorrentTableColumnSpec(
            column: .lastActivityAt, title: "Last Active", group: .dates,
            minWidth: 72, idealWidth: 100, maxWidth: 150, hiddenByDefault: true),
        TorrentTableColumnSpec(
            column: .downloadedEver, title: "Total DL", group: .totals,
            minWidth: 60, idealWidth: 80, maxWidth: 120, hiddenByDefault: true),
        TorrentTableColumnSpec(
            column: .uploadedEver, title: "Total UL", group: .totals,
            minWidth: 60, idealWidth: 80, maxWidth: 120, hiddenByDefault: true),
        TorrentTableColumnSpec(
            column: .leftUntilDone, title: "Remaining", group: .totals,
            minWidth: 60, idealWidth: 80, maxWidth: 120, hiddenByDefault: true),
        TorrentTableColumnSpec(
            column: .sizeWhenDone, title: "Size When Done", group: .totals,
            minWidth: 70, idealWidth: 95, maxWidth: 130, hiddenByDefault: true),
        TorrentTableColumnSpec(
            column: .secondsDownloading, title: "Download Time", group: .dates,
            minWidth: 70, idealWidth: 90, maxWidth: 120, hiddenByDefault: true),
        TorrentTableColumnSpec(
            column: .secondsSeeding, title: "Seeding Time", group: .dates,
            minWidth: 70, idealWidth: 90, maxWidth: 120, hiddenByDefault: true),
        TorrentTableColumnSpec(
            column: .downloadLimit, title: "DL Limit", group: .limits,
            minWidth: 60, idealWidth: 80, maxWidth: 110, hiddenByDefault: true),
        TorrentTableColumnSpec(
            column: .uploadLimit, title: "UL Limit", group: .limits,
            minWidth: 60, idealWidth: 80, maxWidth: 110, hiddenByDefault: true),
        TorrentTableColumnSpec(
            column: .seedRatioLimit, title: "Ratio Limit", group: .limits,
            minWidth: 60, idealWidth: 80, maxWidth: 110, hiddenByDefault: true),
        TorrentTableColumnSpec(
            column: .seedIdleLimit, title: "Idle Limit", group: .limits,
            minWidth: 60, idealWidth: 80, maxWidth: 110, hiddenByDefault: true),
        TorrentTableColumnSpec(
            column: .peerLimit, title: "Peer Limit", group: .limits,
            minWidth: 55, idealWidth: 70, maxWidth: 100, hiddenByDefault: true),
    ]

    static let cellReuseIdentifierPrefix = "torrentCell."
}
