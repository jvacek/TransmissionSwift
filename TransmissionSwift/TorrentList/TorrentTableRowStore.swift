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
        /// The row set or id order changed — reload the whole table.
        case reload
    }

    enum ChangeKind: Equatable {
        case none, values, structural
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
        return change == .structural ? .reload : .refreshVisible
    }

    /// One pass over both arrays, folding the old "id sequence" and "field
    /// equality" guards into a single comparison so the poll never pays for two
    /// full scans. `.structural` when the row set or id order changed (reload),
    /// `.values` when only cell content changed (refresh visible cells in
    /// place), `.none` when nothing moved.
    static func classifyChange(
        from old: [TorrentRowDisplay], to new: [TorrentRowDisplay]
    ) -> ChangeKind {
        guard old.count == new.count else { return .structural }
        var valuesChanged = false
        for (lhs, rhs) in zip(old, new) {
            if lhs.id != rhs.id { return .structural }
            if lhs != rhs { valuesChanged = true }
        }
        return valuesChanged ? .values : .none
    }
}
