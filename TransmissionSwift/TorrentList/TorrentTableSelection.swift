import Foundation
import TransmissionCore

/// Pure mapping between the table's row indexes and torrent IDs. Kept separate
/// from `NSTableView` so the selection rules are testable headlessly.
nonisolated enum TorrentTableSelection {
    /// Clicked rows ∪ selection, matching the old SwiftUI context-menu
    /// semantics: a right-click inside the selection acts on all of it, outside
    /// it acts on just the clicked rows, and a blank-area click falls back to
    /// the whole selection.
    static func affectedIDs(
        rows: IndexSet,
        displayedRows: [TorrentRowDisplay],
        selection: Set<Torrent.ID>
    ) -> Set<Torrent.ID> {
        guard !rows.isEmpty else { return selection }
        let rowIDs = ids(at: rows, displayedRows: displayedRows)
        let clickInsideSelection = rows.allSatisfy { row in
            displayedRows.indices.contains(row) && selection.contains(displayedRows[row].id)
        }
        return clickInsideSelection ? selection : rowIDs
    }

    /// IDs for a set of row indexes, skipping any index the current projection
    /// doesn't cover.
    static func ids(at rows: IndexSet, displayedRows: [TorrentRowDisplay]) -> Set<Torrent.ID> {
        Set(
            rows.compactMap { row in
                displayedRows.indices.contains(row) ? displayedRows[row].id : nil
            })
    }

    /// Row indexes for a set of IDs, in table order.
    static func rowIndexes(
        for ids: Set<Torrent.ID>, displayedRows: [TorrentRowDisplay]
    ) -> IndexSet {
        IndexSet(
            displayedRows.enumerated().compactMap { row, display in
                ids.contains(display.id) ? row : nil
            })
    }
}
