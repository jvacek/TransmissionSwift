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
}
