import Foundation
import Testing
import TransmissionTestSupport

@testable import TransmissionCore

/// The two-cadence poll: the full list once per base interval, the daemon's
/// recently-active set in between. The schedule, the interval clamp and the
/// merge are pure, so no clock is involved.
@Suite("RPCTorrentService — poll cadence")
struct RPCPollCadenceTests {
    private func fixture(id: Int, active: Bool) -> Torrent {
        var torrent = MockFixtures.torrents()[0]
        torrent.id = id
        torrent.status = .downloading
        torrent.peersSendingToUs = active ? 1 : 0
        torrent.peersGettingFromUs = 0
        torrent.webseedsSendingToUs = 0
        return torrent
    }

    @Test("the first tick and every base interval fetch the full list")
    func fullPollSchedule() {
        let now = Date()
        #expect(
            RPCTorrentService.plan(cache: [], lastFullPoll: nil, base: 5, now: now) == .full)
        #expect(
            RPCTorrentService.plan(
                cache: [fixture(id: 1, active: true)], lastFullPoll: now, base: 5,
                now: now.addingTimeInterval(5)) == .full)
    }

    @Test("between full polls the changed set is fetched while something transfers")
    func incrementalSchedule() {
        let now = Date()
        let cache = [fixture(id: 1, active: true), fixture(id: 2, active: false)]
        #expect(
            RPCTorrentService.plan(
                cache: cache, lastFullPoll: now, base: 5, now: now.addingTimeInterval(1))
                == .recentlyActive)
    }

    @Test("with nothing transferring the tick waits for the next full poll")
    func idleSchedule() {
        let now = Date()
        #expect(
            RPCTorrentService.plan(
                cache: [fixture(id: 1, active: false)], lastFullPoll: now, base: 5,
                now: now.addingTimeInterval(1)) == nil)
    }

    @Test("the incremental interval is clamped to the full interval and the change window")
    func intervalClamp() {
        #expect(RPCTorrentService.incrementalInterval(active: 1, base: 5) == 1)
        #expect(RPCTorrentService.incrementalInterval(active: 0, base: 5) == 1)
        #expect(RPCTorrentService.incrementalInterval(active: 0.5, base: 5) == 1)
        #expect(RPCTorrentService.incrementalInterval(active: 45, base: 300) == 45)
        #expect(RPCTorrentService.incrementalInterval(active: 60, base: 300) == 45)
        #expect(RPCTorrentService.incrementalInterval(active: 120, base: 10) == 10)
    }

    @Test("a recently-active response replaces, appends and removes entries")
    func mergeIncremental() {
        var renamed = fixture(id: 2, active: true)
        renamed.name = "renamed"
        let cache = [
            fixture(id: 1, active: false), fixture(id: 2, active: false),
            fixture(id: 4, active: false),
        ]

        let merged = RPCTorrentService.merging(
            [renamed, fixture(id: 3, active: true), fixture(id: 4, active: true)],
            removing: [1],
            into: cache)

        // 1 removed, 2 and 4 replaced in place, 3 appended because it is new.
        #expect(merged.map(\.id) == [2, 4, 3])
        #expect(merged[0].name == "renamed")
        #expect(merged[1].isActive)
    }

    @Test("an id both returned and removed stays removed")
    func removalWins() {
        let merged = RPCTorrentService.merging(
            [fixture(id: 2, active: true)], removing: [2], into: [fixture(id: 2, active: false)])
        #expect(merged.isEmpty)
    }
}
