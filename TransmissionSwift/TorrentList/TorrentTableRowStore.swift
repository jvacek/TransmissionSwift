// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import TransmissionCore

/// Pure state machine behind the table's row updates. Owns the displayed
/// projection, the base directory and the tag-colour snapshot it was last
/// rendered against, and decides whether an incoming snapshot needs no work, a
/// visible-cell refresh, or a full reload. Kept free of AppKit so the poll guard
/// is unit-testable without a window.
nonisolated struct TorrentTableRowStore {
    enum Update: Equatable {
        case none
        /// Cell content moved but the row set/order did not — repaint visible
        /// cells in place.
        case refreshVisible
        /// The same rows are present in a different order (a speed/ETA sort
        /// moved them) — repaint only the visible rows instead of tearing down
        /// every cell view.
        case reordered
        /// The row set changed — reload the whole table.
        case reload
    }

    enum ChangeKind: Equatable {
        case none, values, reordered, structural
    }

    private(set) var displayedRows: [TorrentRowDisplay] = []
    private var lastDownloadDirectoryBase: String?
    private var lastTagColors: [String: TagColor] = [:]

    /// Folds an incoming poll snapshot in and reports the cheapest update the
    /// table needs. Mirrors the former `Coordinator.apply` gating exactly: on a
    /// no-op the stored projections are left untouched (they are equal on the
    /// rendered fields but may carry newer non-rendered ones), and the tag-colour
    /// snapshot is still advanced so a later change is detected.
    mutating func apply(
        rows: [Torrent],
        downloadDirectoryBase: String?,
        tagColors: [String: TagColor]
    ) -> Update {
        let newDisplays = rows.map(TorrentRowDisplay.init)
        let change = Self.classifyChange(from: displayedRows, to: newDisplays)
        let baseChanged = downloadDirectoryBase != lastDownloadDirectoryBase
        let colorsChanged = tagColors != lastTagColors
        if colorsChanged { lastTagColors = tagColors }
        guard change != .none || baseChanged || colorsChanged else { return .none }
        displayedRows = newDisplays
        lastDownloadDirectoryBase = downloadDirectoryBase
        switch change {
        case .structural: return .reload
        case .reordered: return .reordered
        case .values, .none: return .refreshVisible
        }
    }

    /// One pass over both arrays. `.structural` when the row set changed,
    /// `.reordered` when the same ids moved position, `.values` when only cell
    /// content changed, `.none` when nothing moved. The set comparison only
    /// runs on the mismatch path.
    static func classifyChange(
        from old: [TorrentRowDisplay], to new: [TorrentRowDisplay]
    ) -> ChangeKind {
        guard old.count == new.count else { return .structural }
        var orderChanged = false
        var valuesChanged = false
        for (lhs, rhs) in zip(old, new) {
            if lhs.id != rhs.id { orderChanged = true }
            if lhs != rhs { valuesChanged = true }
        }
        guard orderChanged else { return valuesChanged ? .values : .none }
        return Set(old.map(\.id)) == Set(new.map(\.id)) ? .reordered : .structural
    }
}
