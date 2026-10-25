import Foundation
import Testing
import TransmissionTestSupport

@testable import TransmissionCore

/// The two-cadence poll: the full list once per refresh interval, the daemon's
/// changed set on every tick in between. The schedule bounds and the merge are
/// pure, so no clock is involved.
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

    @Test("the full list is due on the first tick and once per refresh interval")
    func fullPollSchedule() {
        let now = Date()
        #expect(RPCTorrentService.isFullPollDue(lastFullPoll: nil, base: 15, now: now))
        #expect(
            !RPCTorrentService.isFullPollDue(
                lastFullPoll: now, base: 15, now: now.addingTimeInterval(1)))
        #expect(
            !RPCTorrentService.isFullPollDue(
                lastFullPoll: now, base: 15, now: now.addingTimeInterval(14.9)))
        #expect(
            RPCTorrentService.isFullPollDue(
                lastFullPoll: now, base: 15, now: now.addingTimeInterval(15)))
    }

    @Test("the incremental interval is capped at 45 seconds and at the refresh interval")
    func intervalClamp() {
        #expect(PollingIntervals.clampedIncremental(1, refresh: 5) == 1)
        #expect(PollingIntervals.clampedIncremental(0, refresh: 5) == 1)
        #expect(PollingIntervals.clampedIncremental(0.4, refresh: 5) == 1)
        #expect(PollingIntervals.clampedIncremental(45, refresh: 300) == 45)
        #expect(PollingIntervals.clampedIncremental(60, refresh: 300) == 45)
        #expect(PollingIntervals.clampedIncremental(120, refresh: 10) == 10)
    }

    @Test("interval values are whole seconds inside their bounds")
    func intervalNormalization() {
        #expect(PollingIntervals.normalized(0, to: PollingIntervals.refresh) == 1)
        #expect(PollingIntervals.normalized(0.5, to: PollingIntervals.refresh) == 1)
        #expect(PollingIntervals.normalized(2.6, to: PollingIntervals.refresh) == 3)
        #expect(PollingIntervals.normalized(600, to: PollingIntervals.refresh) == 300)
        #expect(PollingIntervals.normalized(2, to: PollingIntervals.freeSpace) == 5)
        #expect(PollingIntervals.normalized(7200, to: PollingIntervals.freeSpace) == 3600)
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
