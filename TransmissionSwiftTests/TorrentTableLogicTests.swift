import Foundation
import Testing
import TransmissionCore

@testable import TransmissionSwift

/// Unit coverage for the raw NSTableView migration's pure logic: the row-level
/// poll guard (`TorrentRowDisplay` equality + `classifyChange`) and the
/// formatter that feeds the two-part speed cell. These are the pieces the
/// snapshot UI test can't reach — no daemon, no AppKit window.
struct TorrentTableLogicTests {
    // MARK: - Fixture

    private func makeTorrent(
        id: Int = 1,
        name: String = "Torrent A",
        size: Int64 = 1_000_000,
        progress: Double = 0.5,
        downloadSpeed: Int64 = 0,
        pieceSize: Int64 = 1,
        options: TorrentOptions = TorrentOptions(),
        files: [TorrentFile] = []
    ) -> Torrent {
        Torrent(
            id: id,
            name: name,
            hash: "hash-\(id)",
            size: size,
            status: .downloading,
            progress: progress,
            downloadSpeed: downloadSpeed,
            primaryTracker: "tracker",
            downloadFolder: "/downloads",
            addedAt: Date(timeIntervalSince1970: 1_700_000_000),
            pieces: 10,
            pieceSize: pieceSize,
            havePieces: 5,
            options: options,
            files: files)
    }

    // MARK: - TorrentRowDisplay poll guard

    @Test func displayEquality_tracksRenderedFields() {
        let base = makeTorrent()
        #expect(TorrentRowDisplay(base) == TorrentRowDisplay(base))
        // A field the table renders must flip equality so the cell refreshes.
        #expect(TorrentRowDisplay(makeTorrent(size: 2_000_000)) != TorrentRowDisplay(base))
        #expect(TorrentRowDisplay(makeTorrent(downloadSpeed: 1_024)) != TorrentRowDisplay(base))
        #expect(TorrentRowDisplay(makeTorrent(name: "Renamed")) != TorrentRowDisplay(base))
    }

    @Test func displayEquality_ignoresNonRenderedFields() {
        let base = makeTorrent()
        // Fields the table never renders must NOT flip the poll guard — otherwise
        // a poll that only changed, say, a file list would refresh every row.
        #expect(TorrentRowDisplay(makeTorrent(pieceSize: 99)) == TorrentRowDisplay(base))
        #expect(
            TorrentRowDisplay(makeTorrent(options: TorrentOptions(peerLimit: 999)))
                == TorrentRowDisplay(base))
        #expect(
            TorrentRowDisplay(
                makeTorrent(files: [TorrentFile(id: 1, name: "f.bin", size: 1, progress: 0)]))
                == TorrentRowDisplay(base))
    }

    // MARK: - classifyChange

    @MainActor
    @Test func classifyChange_none_whenIdentical() {
        #expect(classify(from: [1, 2], to: [1, 2]) == .none)
    }

    @MainActor
    @Test func classifyChange_values_whenOnlyContentMoved() {
        let old = [TorrentRowDisplay(makeTorrent(id: 1, downloadSpeed: 0))]
        let new = [TorrentRowDisplay(makeTorrent(id: 1, downloadSpeed: 5_000))]
        #expect(
            TorrentTableRepresentable.Coordinator.classifyChange(from: old, to: new) == .values)
    }

    @MainActor
    @Test func classifyChange_structural_onIdOrCountChange() {
        #expect(classify(from: [1], to: [1, 2]) == .structural)
        #expect(classify(from: [1, 2], to: [2, 1]) == .structural)
        #expect(classify(from: [1, 2], to: [2, 3]) == .structural)
    }

    @MainActor
    private func classify(
        from old: [Int], to new: [Int]
    ) -> TorrentTableRepresentable.Coordinator.ChangeKind {
        TorrentTableRepresentable.Coordinator.classifyChange(
            from: old.map { TorrentRowDisplay(makeTorrent(id: $0)) },
            to: new.map { TorrentRowDisplay(makeTorrent(id: $0)) })
    }

    // MARK: - ColumnFormatters.speedParts

    @Test func speedParts_splitsValueAndUnit() {
        #expect(ColumnFormatters.speedParts(1024) == ("1.0", "KB/s"))
        #expect(ColumnFormatters.speedParts(2_300_000) == ("2.2", "MB/s"))
        #expect(ColumnFormatters.speedParts(500) == ("500.0", "B/s"))
    }

    @Test func speedParts_zeroIsEmDash() {
        // Zero renders as a dash with no unit; the split must not invent one.
        #expect(ColumnFormatters.speedParts(0) == ("\u{2014}", ""))
    }
}
