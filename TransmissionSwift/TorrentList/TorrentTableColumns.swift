import AppKit
import TransmissionCore

struct TorrentTableColumnSpec {
    let column: TableColumn
    let title: String
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
            column: .name, title: "Name",
            minWidth: 240, idealWidth: 400, maxWidth: 800, hiddenByDefault: false),
        TorrentTableColumnSpec(
            column: .size, title: "Size",
            minWidth: 54, idealWidth: 74, maxWidth: 120, hiddenByDefault: false),
        TorrentTableColumnSpec(
            column: .progress, title: "Progress",
            minWidth: 80, idealWidth: 130, maxWidth: 200, hiddenByDefault: false),
        TorrentTableColumnSpec(
            column: .downloadSpeed, title: "\u{2193} Speed",
            minWidth: 70, idealWidth: 95, maxWidth: 130, hiddenByDefault: false),
        TorrentTableColumnSpec(
            column: .uploadSpeed, title: "\u{2191} Speed",
            minWidth: 70, idealWidth: 95, maxWidth: 130, hiddenByDefault: false),
        TorrentTableColumnSpec(
            column: .eta, title: "ETA",
            minWidth: 52, idealWidth: 66, maxWidth: 100, hiddenByDefault: false),
        TorrentTableColumnSpec(
            column: .ratio, title: "Ratio",
            minWidth: 50, idealWidth: 60, maxWidth: 90, hiddenByDefault: false),
        TorrentTableColumnSpec(
            column: .addedAt, title: "Added",
            minWidth: 72, idealWidth: 100, maxWidth: 150, hiddenByDefault: false),
        TorrentTableColumnSpec(
            column: .primaryTracker, title: "Tracker",
            minWidth: 80, idealWidth: 120, maxWidth: 200, hiddenByDefault: false),
        TorrentTableColumnSpec(
            column: .connectedPeers, title: "Peers",
            minWidth: 50, idealWidth: 65, maxWidth: 100, hiddenByDefault: true),
        TorrentTableColumnSpec(
            column: .availablePeers, title: "Available",
            minWidth: 60, idealWidth: 80, maxWidth: 110, hiddenByDefault: true),
        TorrentTableColumnSpec(
            column: .seeds, title: "Seeds",
            minWidth: 45, idealWidth: 60, maxWidth: 90, hiddenByDefault: true),
        TorrentTableColumnSpec(
            column: .status, title: "Status",
            minWidth: 80, idealWidth: 100, maxWidth: 150, hiddenByDefault: true),
        TorrentTableColumnSpec(
            column: .label, title: "Labels",
            minWidth: 80, idealWidth: 120, maxWidth: 200, hiddenByDefault: true),
        TorrentTableColumnSpec(
            column: .priority, title: "Priority",
            minWidth: 70, idealWidth: 90, maxWidth: 130, hiddenByDefault: true),
        TorrentTableColumnSpec(
            column: .queuePosition, title: "Queue",
            minWidth: 50, idealWidth: 65, maxWidth: 100, hiddenByDefault: true),
        TorrentTableColumnSpec(
            column: .errorMessage, title: "Error",
            minWidth: 100, idealWidth: 200, maxWidth: 400, hiddenByDefault: true),
        TorrentTableColumnSpec(
            column: .pieces, title: "Pieces",
            minWidth: 70, idealWidth: 90, maxWidth: 130, hiddenByDefault: true),
        TorrentTableColumnSpec(
            column: .downloadFolder, title: "Folder",
            minWidth: 120, idealWidth: 200, maxWidth: 400, hiddenByDefault: true),
        TorrentTableColumnSpec(
            column: .hash, title: "Hash",
            minWidth: 100, idealWidth: 200, maxWidth: 400, hiddenByDefault: true),
    ]

    static let cellReuseIdentifierPrefix = "torrentCell."
}
