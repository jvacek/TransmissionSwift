import Foundation
import Testing
import TransmissionCore

@testable import TransmissionSwift

/// The row-level poll guard: which `Torrent` fields flip `TorrentRowDisplay`
/// equality (and therefore repaint a cell).
@Suite("TorrentRowDisplay")
struct TorrentRowDisplayTests {
    @Test func displayEquality_tracksRenderedFields() {
        let base = makeTableTorrent()
        #expect(TorrentRowDisplay(base) == TorrentRowDisplay(base))
        // A field the table renders must flip equality so the cell refreshes.
        #expect(TorrentRowDisplay(makeTableTorrent(size: 2_000_000)) != TorrentRowDisplay(base))
        #expect(TorrentRowDisplay(makeTableTorrent(downloadSpeed: 1_024)) != TorrentRowDisplay(base))
        #expect(TorrentRowDisplay(makeTableTorrent(name: "Renamed")) != TorrentRowDisplay(base))
    }

    @Test func displayEquality_ignoresNonRenderedFields() {
        let base = makeTableTorrent()
        // Fields the table never renders must NOT flip the poll guard — otherwise
        // a poll that only changed, say, a file list would refresh every row.
        #expect(TorrentRowDisplay(makeTableTorrent(pieceSize: 99)) == TorrentRowDisplay(base))
        #expect(
            TorrentRowDisplay(
                makeTableTorrent(files: [TorrentFile(id: 1, name: "f.bin", size: 1, progress: 0)]))
                == TorrentRowDisplay(base))
    }

    @Test func displayEquality_tracksRenderedOptionFields() {
        // Per-torrent limits render in the Limits column group, so an options
        // change must flip the poll guard.
        let base = makeTableTorrent()
        #expect(
            TorrentRowDisplay(makeTableTorrent(options: TorrentOptions(peerLimit: 999)))
                != TorrentRowDisplay(base))
    }

    /// Drift guard: every column renders at least one `Torrent` field, and each
    /// of those fields must participate in `TorrentRowDisplay` equality or the
    /// cell would never repaint. The `switch` is exhaustive over `TableColumn`,
    /// so adding a column forces this test to cover it.
    @Test func displayEquality_coversEveryRenderedColumn() {
        let base = makeTableTorrent()
        for column in TableColumn.allCases {
            var changed = base
            switch column {
            case .name: changed.name += " x"
            case .size: changed.size += 1
            case .progress: changed.progress = 0.9
            case .downloadSpeed: changed.downloadSpeed += 1
            case .uploadSpeed: changed.uploadSpeed += 1
            case .eta: changed.eta = 60
            case .ratio: changed.ratio += 0.5
            case .addedAt: changed.addedAt = changed.addedAt.addingTimeInterval(60)
            case .completedAt: changed.completedAt = Date(timeIntervalSince1970: 1)
            case .startedAt: changed.startedAt = Date(timeIntervalSince1970: 1)
            case .lastActivityAt: changed.lastActivityAt = Date(timeIntervalSince1970: 1)
            case .primaryTracker: changed.primaryTracker = "other"
            case .connectedPeers: changed.connectedPeerCount += 1
            case .availablePeers: changed.availablePeerCount += 1
            case .seeds: changed.seedCount += 1
            case .queuePosition: changed.queuePosition = 3
            case .label: changed.labels = ["x"]
            case .priority: changed.priority = .high
            case .status: changed.status = .seeding
            case .errorMessage: changed.errorMessage = "boom"
            case .pieces: changed.pieces += 1
            case .downloadFolder: changed.downloadFolder = "/other"
            case .hash: changed.hash = "other"
            case .downloadedEver: changed.downloadedEver += 1
            case .uploadedEver: changed.uploadedEver += 1
            case .leftUntilDone: changed.leftUntilDone += 1
            case .sizeWhenDone: changed.sizeWhenDone += 1
            case .secondsDownloading: changed.secondsDownloading += 1
            case .secondsSeeding: changed.secondsSeeding += 1
            case .downloadLimit: changed.options.downloadLimitKBps += 1
            case .uploadLimit: changed.options.uploadLimitKBps += 1
            case .seedRatioLimit: changed.options.seedRatioLimit += 1
            case .seedIdleLimit: changed.options.seedIdleMinutes += 1
            case .peerLimit: changed.options.peerLimit += 1
            }
            #expect(
                TorrentRowDisplay(changed) != TorrentRowDisplay(base),
                "\(column.rawValue) renders a field missing from TorrentRowDisplay.==")
        }
    }
}
