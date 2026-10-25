import Foundation
import Testing
import TransmissionTestSupport

@testable import TransmissionCore

/// The two-cadence poll: the full list once per base interval, the active subset
/// in between. The schedule and the merge are pure, so no clock is involved.
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
            RPCTorrentService.plan(cache: [], lastFullPoll: nil, base: 5, now: now)
                == RPCTorrentService.PollPlan(ids: nil, isFull: true))
        #expect(
            RPCTorrentService.plan(
                cache: [fixture(id: 1, active: true)], lastFullPoll: now, base: 5,
                now: now.addingTimeInterval(5))
                == RPCTorrentService.PollPlan(ids: nil, isFull: true))
    }

    @Test("between full polls only the active torrents are fetched")
    func partialPollSchedule() {
        let now = Date()
        let cache = [fixture(id: 1, active: true), fixture(id: 2, active: false)]
        #expect(
            RPCTorrentService.plan(
                cache: cache, lastFullPoll: now, base: 5, now: now.addingTimeInterval(1))
                == RPCTorrentService.PollPlan(ids: [1], isFull: false))
    }

    @Test("with nothing transferring the tick waits for the next full poll")
    func idleSchedule() {
        let now = Date()
        #expect(
            RPCTorrentService.plan(
                cache: [fixture(id: 1, active: false)], lastFullPoll: now, base: 5,
                now: now.addingTimeInterval(1)) == nil)
    }

    @Test("a partial response replaces matching entries and keeps the rest")
    func mergePartial() {
        var updated = fixture(id: 2, active: true)
        updated.name = "renamed"
        let cache = [fixture(id: 1, active: false), fixture(id: 2, active: false)]

        let merged = RPCTorrentService.merging([updated, fixture(id: 3, active: true)], into: cache)

        #expect(merged.map(\.id) == [1, 2])
        #expect(merged[1].name == "renamed")
        #expect(merged[1].isActive)
        #expect(merged[0].name == cache[0].name)
        // An id the cache doesn't know is ignored, not appended or resurrected.
        #expect(!merged.contains { $0.id == 3 })
    }
}
