import Foundation
import Testing
import TransmissionTestSupport

@testable import TransmissionCore

/// The snapshot the poll loop keeps between ticks: full replacements, the
/// recently-active merge and the full-poll schedule.
@Suite("TorrentSnapshot")
struct TorrentSnapshotTests {
    private func fixture(id: Int, active: Bool) -> Torrent {
        var torrent = MockFixtures.torrents()[0]
        torrent.id = id
        torrent.status = .downloading
        torrent.peersSendingToUs = active ? 1 : 0
        torrent.peersGettingFromUs = 0
        torrent.webseedsSendingToUs = 0
        return torrent
    }

    @Test("the first tick and once per refresh interval are full polls")
    func fullPollSchedule() {
        var snapshot = TorrentSnapshot()
        let now = Date()

        #expect(snapshot.isFullPollDue(base: 15, now: now))

        snapshot.applyFull([fixture(id: 1, active: true)], at: now)
        #expect(!snapshot.isFullPollDue(base: 15, now: now.addingTimeInterval(1)))
        #expect(!snapshot.isFullPollDue(base: 15, now: now.addingTimeInterval(14.9)))
        #expect(snapshot.isFullPollDue(base: 15, now: now.addingTimeInterval(15)))
    }

    @Test("a full poll replaces the list and restarts the interval")
    func fullPollReplaces() {
        var snapshot = TorrentSnapshot()
        let now = Date()
        snapshot.applyFull([fixture(id: 1, active: false)], at: now.addingTimeInterval(-30))
        snapshot.applyChanges([fixture(id: 2, active: true)], removed: [])

        let refreshed = now.addingTimeInterval(-1)
        snapshot.applyFull([fixture(id: 3, active: false)], at: refreshed)

        #expect(snapshot.torrents.map(\.id) == [3])
        #expect(!snapshot.isFullPollDue(base: 15, now: now))
    }

    @Test("a reset makes the next tick a full poll")
    func resetStartsOver() {
        var snapshot = TorrentSnapshot()
        let now = Date()
        snapshot.applyFull([fixture(id: 1, active: true)], at: now)
        snapshot.reset()

        #expect(snapshot.torrents.isEmpty)
        #expect(snapshot.isFullPollDue(base: 15, now: now))
    }

    @Test("changes replace, append and remove entries")
    func applyChanges() {
        var snapshot = TorrentSnapshot()
        let now = Date()
        snapshot.applyFull(
            [
                fixture(id: 1, active: false), fixture(id: 2, active: false),
                fixture(id: 4, active: false),
            ], at: now)

        var renamed = fixture(id: 2, active: true)
        renamed.name = "renamed"
        snapshot.applyChanges(
            [renamed, fixture(id: 3, active: true), fixture(id: 4, active: true)], removed: [1])

        // 1 removed, 2 and 4 replaced in place, 3 appended because it is new.
        #expect(snapshot.torrents.map(\.id) == [2, 4, 3])
        #expect(snapshot.torrents[0].name == "renamed")
        #expect(snapshot.torrents[1].isActive)
    }

    @Test("an id both returned and removed stays removed")
    func removalWins() {
        var snapshot = TorrentSnapshot()
        snapshot.applyFull([fixture(id: 2, active: false)], at: Date())
        snapshot.applyChanges([fixture(id: 2, active: true)], removed: [2])

        #expect(snapshot.torrents.isEmpty)
    }

    @Test("a duplicate id in one response keeps the first and does not trap")
    func duplicateIDsInChanges() {
        var snapshot = TorrentSnapshot()
        var existing = fixture(id: 1, active: false)
        existing.name = "existing"
        snapshot.applyFull([existing], at: Date())

        var first = fixture(id: 1, active: true)
        first.name = "first"
        var duplicate = fixture(id: 1, active: true)
        duplicate.name = "duplicate"

        snapshot.applyChanges([first, duplicate], removed: [])

        #expect(snapshot.torrents.count == 1)
        #expect(snapshot.torrents[0].name == "first")
    }
}
