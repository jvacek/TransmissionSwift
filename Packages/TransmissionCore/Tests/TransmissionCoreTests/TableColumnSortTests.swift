import Foundation
import Testing
import TransmissionCore

/// Correctness coverage for the table's sort comparator. Replaces the former
/// wall-clock "sorting performance" suite, which only timed the standard
/// library and guarded nothing here. For every column a low/high pair must order
/// ascending forward and descending in reverse; iterating `TableColumn.allCases`
/// means a new column whose key is not represented by a differing value fails
/// the test.
@Suite("TableColumn comparator")
struct TableColumnSortTests {
    /// A torrent whose key for every column is below `high`'s.
    private func low() -> Torrent {
        Torrent(
            id: 1,
            name: "A",
            hash: "a",
            size: 100,
            status: .downloading,
            progress: 0.1,
            downloadSpeed: 10,
            uploadSpeed: 10,
            connectedPeerCount: 1,
            availablePeerCount: 1,
            seedCount: 1,
            eta: 10,
            ratio: 0.1,
            primaryTracker: "a.example",
            downloadFolder: "/a",
            addedAt: Date(timeIntervalSince1970: 1_000),
            labels: ["a"],
            // Raw-string sort: "high" < "normal".
            priority: .high,
            pieces: 10,
            pieceSize: 1,
            havePieces: 1,
            queuePosition: 1,
            errorMessage: "a",
            options: TorrentOptions(
                downloadLimited: true, downloadLimitKBps: 100,
                uploadLimited: true, uploadLimitKBps: 100,
                seedRatioLimited: true, seedRatioLimit: 1,
                seedIdleLimited: true, seedIdleMinutes: 10, peerLimit: 10),
            completedAt: Date(timeIntervalSince1970: 1_000),
            startedAt: Date(timeIntervalSince1970: 1_000),
            secondsDownloading: 10,
            secondsSeeding: 10,
            leftUntilDone: 100,
            sizeWhenDone: 100,
            downloadedEver: 100,
            uploadedEver: 100,
            lastActivityAt: Date(timeIntervalSince1970: 1_000))
    }

    /// A torrent whose key for every column is above `low`'s. Limits are left
    /// off, so their sort keys read "unlimited" (`Int.max` / `.infinity`) and
    /// sort above the capped `low` torrent.
    private func high() -> Torrent {
        Torrent(
            id: 2,
            name: "Z",
            hash: "z",
            size: 900,
            status: .seeding,
            progress: 0.9,
            downloadSpeed: 90,
            uploadSpeed: 90,
            connectedPeerCount: 9,
            availablePeerCount: 9,
            seedCount: 9,
            eta: 90,
            ratio: 0.9,
            primaryTracker: "z.example",
            downloadFolder: "/z",
            addedAt: Date(timeIntervalSince1970: 9_000),
            labels: ["z"],
            priority: .normal,
            pieces: 90,
            pieceSize: 1,
            havePieces: 9,
            queuePosition: 9,
            errorMessage: "z",
            options: TorrentOptions(peerLimit: 90),
            completedAt: Date(timeIntervalSince1970: 9_000),
            startedAt: Date(timeIntervalSince1970: 9_000),
            secondsDownloading: 90,
            secondsSeeding: 90,
            leftUntilDone: 900,
            sizeWhenDone: 900,
            downloadedEver: 900,
            uploadedEver: 900,
            lastActivityAt: Date(timeIntervalSince1970: 9_000))
    }

    @Test("every column orders the pair ascending forward and descending in reverse")
    func comparatorOrdersBothDirections() {
        let low = low()
        let high = high()
        for column in TableColumn.allCases {
            let forward = column.comparator(order: .forward)
            let reverse = column.comparator(order: .reverse)
            #expect(
                forward.compare(low, high) == .orderedAscending,
                "\(column.rawValue) forward did not order low < high")
            #expect(
                reverse.compare(low, high) == .orderedDescending,
                "\(column.rawValue) reverse did not order high < low")
        }
    }

    @Test("a nil or infinite ETA sorts to the bottom")
    func etaSentinelsSortLast() {
        var missing = low()
        missing.eta = nil
        var infinite = low()
        infinite.eta = .infinity

        let comparator = TableColumn.eta.comparator(order: .forward)
        #expect(comparator.compare(low(), missing) == .orderedAscending)
        #expect(comparator.compare(low(), infinite) == .orderedAscending)
        #expect(comparator.compare(missing, infinite) == .orderedSame)
    }

    @Test("a missing queue position sorts to the bottom")
    func queuePositionSentinelSortsLast() {
        var missing = low()
        missing.queuePosition = nil

        let comparator = TableColumn.queuePosition.comparator(order: .forward)
        #expect(comparator.compare(low(), missing) == .orderedAscending)
    }
}
