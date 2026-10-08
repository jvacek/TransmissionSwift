import Testing
import TransmissionCore

@testable import TransmissionSwift

/// The pure state machine behind the table's row updates: what an incoming
/// poll snapshot requires (nothing, a visible-cell refresh, or a reload).
@Suite("TorrentTableRowStore")
struct TorrentTableRowStoreTests {
    @Test func classifyChange_none_whenIdentical() {
        #expect(classify(from: [1, 2], to: [1, 2]) == .none)
    }

    @Test func classifyChange_values_whenOnlyContentMoved() {
        let old = [TorrentRowDisplay(makeTableTorrent(id: 1, downloadSpeed: 0))]
        let new = [TorrentRowDisplay(makeTableTorrent(id: 1, downloadSpeed: 5_000))]
        #expect(TorrentTableRowStore.classifyChange(from: old, to: new) == .values)
    }

    @Test func classifyChange_structural_onIdOrCountChange() {
        #expect(classify(from: [1], to: [1, 2]) == .structural)
        #expect(classify(from: [1, 2], to: [2, 1]) == .structural)
        #expect(classify(from: [1, 2], to: [2, 3]) == .structural)
    }

    private func classify(from old: [Int], to new: [Int]) -> TorrentTableRowStore.ChangeKind {
        TorrentTableRowStore.classifyChange(
            from: old.map { TorrentRowDisplay(makeTableTorrent(id: $0)) },
            to: new.map { TorrentRowDisplay(makeTableTorrent(id: $0)) })
    }

    @Test func rowStore_none_whenSnapshotUnchanged() {
        var store = TorrentTableRowStore()
        let rows = [makeTableTorrent(id: 1), makeTableTorrent(id: 2)]
        // First apply goes from empty to two rows (structural); the identical
        // second one is a no-op.
        #expect(store.apply(rows: rows, downloadDirectoryBase: nil, tagColors: [:]) == .reload)
        #expect(store.apply(rows: rows, downloadDirectoryBase: nil, tagColors: [:]) == .none)
    }

    @Test func rowStore_refreshVisible_whenOnlyContentMoved() {
        var store = TorrentTableRowStore()
        _ = store.apply(
            rows: [makeTableTorrent(id: 1, downloadSpeed: 0)], downloadDirectoryBase: nil,
            tagColors: [:])
        let update = store.apply(
            rows: [makeTableTorrent(id: 1, downloadSpeed: 5_000)], downloadDirectoryBase: nil,
            tagColors: [:])
        #expect(update == .refreshVisible)
    }

    @Test func rowStore_reload_whenOrderOrSetChanges() {
        var store = TorrentTableRowStore()
        _ = store.apply(
            rows: [makeTableTorrent(id: 1), makeTableTorrent(id: 2)], downloadDirectoryBase: nil,
            tagColors: [:])
        #expect(
            store.apply(
                rows: [makeTableTorrent(id: 2), makeTableTorrent(id: 1)], downloadDirectoryBase: nil,
                tagColors: [:]) == .reload)
        #expect(
            store.apply(rows: [makeTableTorrent(id: 1)], downloadDirectoryBase: nil, tagColors: [:])
                == .reload)
    }

    @Test func rowStore_refreshVisible_whenTagColorsChange() {
        var store = TorrentTableRowStore()
        let rows = [makeTableTorrent(id: 1, labels: ["A"])]
        _ = store.apply(rows: rows, downloadDirectoryBase: nil, tagColors: [:])
        #expect(
            store.apply(rows: rows, downloadDirectoryBase: nil, tagColors: ["A": .red])
                == .refreshVisible)
    }

    @Test func rowStore_refreshVisible_whenBaseDirectoryChanges() {
        var store = TorrentTableRowStore()
        let rows = [makeTableTorrent(id: 1)]
        _ = store.apply(rows: rows, downloadDirectoryBase: "/a", tagColors: [:])
        #expect(
            store.apply(rows: rows, downloadDirectoryBase: "/b", tagColors: [:]) == .refreshVisible)
    }
}
