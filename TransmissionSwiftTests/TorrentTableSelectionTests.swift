import Foundation
import Testing
import TransmissionCore

@testable import TransmissionSwift

/// Pure mapping between the table's row indexes and torrent IDs.
@Suite("TorrentTableSelection")
struct TorrentTableSelectionTests {
    @Test func selection_blankRowsFallBackToWholeSelection() {
        let rows = [
            TorrentRowDisplay(makeTableTorrent(id: 1)), TorrentRowDisplay(makeTableTorrent(id: 2)),
        ]
        #expect(
            TorrentTableSelection.affectedIDs(
                rows: IndexSet(), displayedRows: rows, selection: [1, 2]) == [1, 2])
    }

    @Test func selection_clickInsideKeepsSelection() {
        let rows = [
            TorrentRowDisplay(makeTableTorrent(id: 1)), TorrentRowDisplay(makeTableTorrent(id: 2)),
        ]
        #expect(
            TorrentTableSelection.affectedIDs(
                rows: IndexSet(integer: 0), displayedRows: rows, selection: [1, 2]) == [1, 2])
    }

    @Test func selection_clickOutsideReplacesWithClickedRow() {
        let rows = [
            TorrentRowDisplay(makeTableTorrent(id: 1)), TorrentRowDisplay(makeTableTorrent(id: 2)),
        ]
        #expect(
            TorrentTableSelection.affectedIDs(
                rows: IndexSet(integer: 1), displayedRows: rows, selection: [1]) == [2])
    }

    @Test func selection_rowIndexesAreInTableOrder() {
        let rows = [
            TorrentRowDisplay(makeTableTorrent(id: 2)), TorrentRowDisplay(makeTableTorrent(id: 1)),
        ]
        #expect(
            TorrentTableSelection.rowIndexes(for: [1, 2], displayedRows: rows) == IndexSet([0, 1]))
        #expect(
            TorrentTableSelection.rowIndexes(for: [1], displayedRows: rows) == IndexSet(integer: 1))
    }

    @Test func selection_idsSkipsOutOfRangeRows() {
        let rows = [TorrentRowDisplay(makeTableTorrent(id: 1))]
        #expect(TorrentTableSelection.ids(at: IndexSet([0, 5]), displayedRows: rows) == [1])
    }
}
