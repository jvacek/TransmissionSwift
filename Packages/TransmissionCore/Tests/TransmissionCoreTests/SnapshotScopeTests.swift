import Foundation
import Testing

@testable import TransmissionCore
@testable import TransmissionRPC

private func makeWire(id: Int) -> WireTorrent {
    WireTorrent(
        id: id,
        name: "T\(id)",
        hashString: "hash\(id)",
        totalSize: 1,
        status: 4,
        error: 0,
        errorString: "",
        isFinished: false,
        percentDone: 0,
        rateDownload: 0,
        rateUpload: 0,
        peersConnected: 0,
        peersSendingToUs: 0,
        peersGettingFromUs: 0,
        peersFrom: WirePeersFrom(
            fromCache: 0, fromDht: 0, fromIncoming: 0,
            fromLpd: 0, fromLtep: 0, fromPex: 0, fromTracker: 0
        ),
        eta: -1,
        uploadRatio: 0,
        downloadDir: "/x",
        addedDate: 0,
        labels: nil,
        bandwidthPriority: 0,
        pieceCount: 1,
        pieceSize: 1024,
        haveValid: 0,
        queuePosition: 0,
        trackers: nil
    )
}

@Suite("SnapshotScope")
struct SnapshotScopeTests {
    @Test("no scope → everything in daemon order")
    func noScope() {
        let wires = [makeWire(id: 1), makeWire(id: 2), makeWire(id: 3)]
        let result = SnapshotScope.apply(to: wires, visibleOrder: nil, maxTorrents: nil)
        #expect(result.map(\.id) == [1, 2, 3])
    }

    @Test("visible order filters down and preserves that order")
    func visibleOrder() {
        let wires = [makeWire(id: 1), makeWire(id: 2), makeWire(id: 3)]
        let result = SnapshotScope.apply(to: wires, visibleOrder: [3, 1], maxTorrents: nil)
        #expect(result.map(\.id) == [3, 1])
    }

    @Test("limit caps at the front of the scoped set")
    func limit() {
        let wires = [makeWire(id: 1), makeWire(id: 2), makeWire(id: 3)]
        let result = SnapshotScope.apply(to: wires, visibleOrder: nil, maxTorrents: 2)
        #expect(result.map(\.id) == [1, 2])
    }

    @Test("visible order + limit: the top N you're looking at")
    func visibleOrderThenLimit() {
        let wires = [makeWire(id: 1), makeWire(id: 2), makeWire(id: 3), makeWire(id: 4)]
        let result = SnapshotScope.apply(to: wires, visibleOrder: [4, 2, 1], maxTorrents: 2)
        #expect(result.map(\.id) == [4, 2])
    }

    @Test("ids in the visible order that aren't in the snapshot are ignored")
    func unknownIDs() {
        let wires = [makeWire(id: 1), makeWire(id: 2)]
        let result = SnapshotScope.apply(to: wires, visibleOrder: [99, 1], maxTorrents: nil)
        #expect(result.map(\.id) == [1])
    }
}
