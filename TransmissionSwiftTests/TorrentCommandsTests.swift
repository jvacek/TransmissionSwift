import Testing
import TransmissionCore

@testable import TransmissionSwift

/// The start/stop split behind ⌘S and ⇧⌘S.
@Suite("Torrent commands")
struct TorrentCommandsTests {
    @Test func toggleStartsStoppedTorrentsAndStopsTheRest() {
        let torrents = [
            makeTableTorrent(id: 1, status: .paused, isStopped: true),
            makeTableTorrent(id: 2, status: .downloading),
            makeTableTorrent(id: 3, status: .completed, isStopped: true),
            makeTableTorrent(id: 4, status: .completed),
        ]

        let targets = torrentToggleTargets(ids: [1, 2, 3, 4], torrents: torrents)

        #expect(targets.start == [1, 3])
        #expect(targets.stop == [2, 4])
    }

    @Test func toggleOnlyConsidersSelectedTorrentsInTableOrder() {
        let torrents = [
            makeTableTorrent(id: 1),
            makeTableTorrent(id: 2, status: .paused, isStopped: true),
            makeTableTorrent(id: 3),
        ]

        let targets = torrentToggleTargets(ids: [3, 2], torrents: torrents)

        #expect(targets.start == [2])
        #expect(targets.stop == [3])
    }

    @Test func toggleIgnoresIDsTheListNoLongerHas() {
        let targets = torrentToggleTargets(ids: [7], torrents: [makeTableTorrent(id: 1)])
        #expect(targets.start.isEmpty)
        #expect(targets.stop.isEmpty)
    }

    @Test func magnetCopyFollowsTheDisplayedRows() {
        let first = makeTableTorrent(id: 2, name: "Second")
        let second = makeTableTorrent(id: 1, name: "First")

        // The table's order, not the daemon's, and only rows it still shows.
        #expect(
            selectedMagnetLinksText(from: [first, second], ids: [1, 2])
                == first.magnetURI + "\n" + second.magnetURI)
        #expect(selectedMagnetLinksText(from: [second], ids: [1, 2]) == second.magnetURI)
        #expect(selectedMagnetLinksText(from: [], ids: []) == nil)
    }
}
