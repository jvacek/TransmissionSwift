import TransmissionCore

/// Projection of a `Torrent` onto exactly the fields the table renders. Single
/// source of truth for what a row "displays": the row-level poll guard compares
/// `[TorrentRowDisplay]`, and `TorrentCellContent.make` reads from it — so the
/// guarded fields and the rendered fields can never drift apart.
nonisolated struct TorrentRowDisplay: Equatable {
    let torrent: Torrent

    var id: Torrent.ID { torrent.id }

    init(_ torrent: Torrent) {
        self.torrent = torrent
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        // Only the fields the table renders participate in the poll guard; a
        // full `Torrent` equality would deep-compare files/peers/trackers on
        // every tick. Keep this list in sync with `TorrentCellContent.make`:
        // a renderable field must be added to both.
        lhs.torrent.id == rhs.torrent.id
            && lhs.torrent.name == rhs.torrent.name
            && lhs.torrent.hash == rhs.torrent.hash
            && lhs.torrent.size == rhs.torrent.size
            && lhs.torrent.progress == rhs.torrent.progress
            && lhs.torrent.status == rhs.torrent.status
            && lhs.torrent.downloadSpeed == rhs.torrent.downloadSpeed
            && lhs.torrent.uploadSpeed == rhs.torrent.uploadSpeed
            && lhs.torrent.connectedPeerCount == rhs.torrent.connectedPeerCount
            && lhs.torrent.availablePeerCount == rhs.torrent.availablePeerCount
            && lhs.torrent.seedCount == rhs.torrent.seedCount
            && lhs.torrent.eta == rhs.torrent.eta
            && lhs.torrent.ratio == rhs.torrent.ratio
            && lhs.torrent.primaryTracker == rhs.torrent.primaryTracker
            && lhs.torrent.downloadFolder == rhs.torrent.downloadFolder
            && lhs.torrent.addedAt == rhs.torrent.addedAt
            && lhs.torrent.completedAt == rhs.torrent.completedAt
            && lhs.torrent.startedAt == rhs.torrent.startedAt
            && lhs.torrent.lastActivityAt == rhs.torrent.lastActivityAt
            && lhs.torrent.downloadedEver == rhs.torrent.downloadedEver
            && lhs.torrent.uploadedEver == rhs.torrent.uploadedEver
            && lhs.torrent.leftUntilDone == rhs.torrent.leftUntilDone
            && lhs.torrent.sizeWhenDone == rhs.torrent.sizeWhenDone
            && lhs.torrent.secondsDownloading == rhs.torrent.secondsDownloading
            && lhs.torrent.secondsSeeding == rhs.torrent.secondsSeeding
            && lhs.torrent.options == rhs.torrent.options
            && lhs.torrent.labels == rhs.torrent.labels
            && lhs.torrent.priority == rhs.torrent.priority
            && lhs.torrent.pieces == rhs.torrent.pieces
            && lhs.torrent.havePieces == rhs.torrent.havePieces
            && lhs.torrent.queuePosition == rhs.torrent.queuePosition
            && lhs.torrent.errorMessage == rhs.torrent.errorMessage
    }
}
