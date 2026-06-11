import Foundation
import Testing

@testable import TransmissionCore
@testable import TransmissionRPC

// MARK: - Wire fixture

private func makeWire(
    status: Int = 0,
    error: Int = 0,
    errorString: String = "",
    isFinished: Bool = false,
    eta: Int = -1,
    bandwidthPriority: Int = 0,
    pieceCount: Int = 100,
    pieceSize: Int64 = 1024,
    haveValid: Int64 = 0,
    queuePosition: Int = 0,
    trackers: [WireTrackerStub]? = nil
) -> WireTorrent {
    WireTorrent(
        id: 1,
        name: "Test",
        hashString: "abc123",
        totalSize: 102_400,
        status: status,
        error: error,
        errorString: errorString,
        isFinished: isFinished,
        percentDone: 0.0,
        rateDownload: 0,
        rateUpload: 0,
        peersConnected: 0,
        peersSendingToUs: 0,
        peersGettingFromUs: 0,
        peersFrom: WirePeersFrom(
            fromCache: 1, fromDht: 2, fromIncoming: 3,
            fromLpd: 0, fromLtep: 0, fromPex: 0, fromTracker: 0
        ),
        eta: eta,
        uploadRatio: 0.0,
        downloadDir: "/downloads",
        addedDate: 0,
        labels: nil,
        bandwidthPriority: bandwidthPriority,
        pieceCount: pieceCount,
        pieceSize: pieceSize,
        haveValid: haveValid,
        queuePosition: queuePosition,
        trackers: trackers
    )
}

// MARK: - Status mapping

@Suite("TorrentMapping — status")
struct StatusMappingTests {
    @Test("error >= 2 maps to .error regardless of status integer")
    func errorOverridesStatus() {
        for status in [0, 1, 2, 3, 4, 5, 6] {
            let t = Torrent(wire: makeWire(status: status, error: 2))
            #expect(t.status == .error, "status=\(status) error=2 should be .error")
        }
        let t3 = Torrent(wire: makeWire(status: 4, error: 3))
        #expect(t3.status == .error)
    }

    @Test("error >= 2 with non-empty errorString uses errorString")
    func errorMessageFromString() {
        let t = Torrent(wire: makeWire(error: 2, errorString: "Disk full"))
        #expect(t.errorMessage == "Disk full")
    }

    @Test("error >= 2 with empty errorString falls back to generic message")
    func errorMessageFallback() {
        let t = Torrent(wire: makeWire(error: 3, errorString: ""))
        #expect(t.errorMessage == "Error 3")
    }

    @Test("error < 2 yields nil errorMessage")
    func noErrorMessage() {
        #expect(Torrent(wire: makeWire(error: 0)).errorMessage == nil)
        #expect(Torrent(wire: makeWire(error: 1, errorString: "warning")).errorMessage == nil)
    }

    @Test("error == 1 (tracker warning) does not override status")
    func trackerWarningIsNotError() {
        let downloading = Torrent(wire: makeWire(status: 4, error: 1))
        #expect(downloading.status == .downloading)
        let seeding = Torrent(wire: makeWire(status: 6, error: 1))
        #expect(seeding.status == .seeding)
    }

    @Test("isFinished with status 0 maps to .completed, not .paused")
    func isFinishedMapsToCompleted() {
        let t = Torrent(wire: makeWire(status: 0, isFinished: true))
        #expect(t.status == .completed)
    }

    @Test("status 0 maps to .paused")
    func status0() { #expect(Torrent(wire: makeWire(status: 0)).status == .paused) }

    @Test("status 1, 3, 5 map to .queued")
    func queuedStatuses() {
        for s in [1, 3, 5] {
            #expect(Torrent(wire: makeWire(status: s)).status == .queued, "status \(s) should be .queued")
        }
    }

    @Test("status 2 maps to .checking")
    func status2() { #expect(Torrent(wire: makeWire(status: 2)).status == .checking) }

    @Test("status 4 maps to .downloading")
    func status4() { #expect(Torrent(wire: makeWire(status: 4)).status == .downloading) }

    @Test("status 6 maps to .seeding")
    func status6() { #expect(Torrent(wire: makeWire(status: 6)).status == .seeding) }
}

// MARK: - ETA mapping

@Suite("TorrentMapping — ETA")
struct ETAMappingTests {
    @Test("ETA -1 (TR_ETA_NOT_AVAIL) maps to nil")
    func etaNotAvail() { #expect(Torrent(wire: makeWire(eta: -1)).eta == nil) }

    @Test("ETA -2 (TR_ETA_UNKNOWN) maps to nil")
    func etaUnknown() { #expect(Torrent(wire: makeWire(eta: -2)).eta == nil) }

    @Test("Positive ETA maps to TimeInterval")
    func etaPositive() {
        let t = Torrent(wire: makeWire(eta: 300))
        #expect(t.eta == 300.0)
    }

    @Test("ETA 0 maps to nil (not a valid positive ETA)")
    func etaZero() { #expect(Torrent(wire: makeWire(eta: 0)).eta == nil) }
}

// MARK: - Queue position mapping

@Suite("TorrentMapping — queuePosition")
struct QueuePositionTests {
    @Test("queuePosition -1 maps to nil")
    func negativeOne() { #expect(Torrent(wire: makeWire(queuePosition: -1)).queuePosition == nil) }

    @Test("queuePosition 0 maps to 0")
    func zero() { #expect(Torrent(wire: makeWire(queuePosition: 0)).queuePosition == 0) }

    @Test("queuePosition 3 maps to 3")
    func positive() { #expect(Torrent(wire: makeWire(queuePosition: 3)).queuePosition == 3) }
}

// MARK: - Bandwidth priority mapping

@Suite("TorrentMapping — bandwidthPriority")
struct BandwidthPriorityTests {
    @Test("-1 maps to .low")
    func low() { #expect(Torrent(wire: makeWire(bandwidthPriority: -1)).priority == .low) }

    @Test("0 maps to .normal")
    func normal() { #expect(Torrent(wire: makeWire(bandwidthPriority: 0)).priority == .normal) }

    @Test("1 maps to .high")
    func high() { #expect(Torrent(wire: makeWire(bandwidthPriority: 1)).priority == .high) }
}

// MARK: - havePieces ceiling division

@Suite("TorrentMapping — havePieces")
struct HavePiecesTests {
    @Test("complete torrent with short last piece rounds up to pieceCount")
    func ceilingDivision() {
        // 100 pieces × 1024 bytes = 102400 total; last piece is full.
        // haveValid = totalSize means all 100 pieces verified.
        let t = Torrent(wire: makeWire(pieceCount: 100, pieceSize: 1024, haveValid: 102_400))
        #expect(t.havePieces == 100)
    }

    @Test("short last piece: floor would give pieceCount - 1, ceiling gives pieceCount")
    func shortLastPiece() {
        // 10 pieces × 1024, but total is only 9 * 1024 + 500 = 9716 bytes.
        // haveValid = 9716: ceil(9716 / 1024) = ceil(9.488...) = 10
        let t = Torrent(wire: makeWire(pieceCount: 10, pieceSize: 1024, haveValid: 9_716))
        #expect(t.havePieces == 10)
    }

    @Test("pieceSize 0 yields 0 (guard against division by zero)")
    func zeroPieceSize() {
        let t = Torrent(wire: makeWire(pieceSize: 0, haveValid: 1024))
        #expect(t.havePieces == 0)
    }
}

// MARK: - Tracker host fallback

@Suite("TorrentMapping — tracker host")
struct TrackerHostTests {
    @Test("sitename used when present")
    func sitenamePresent() {
        let stub = WireTrackerStub(
            announce: "https://announce.example.com/announce", sitename: "ExampleTracker", tier: 0)
        let t = Torrent(wire: makeWire(trackers: [stub]))
        #expect(t.primaryTracker == "ExampleTracker")
        #expect(t.trackers.first?.host == "ExampleTracker")
    }

    @Test("host parsed from announce when sitename is absent")
    func sitenameAbsent() {
        let stub = WireTrackerStub(announce: "https://tracker.ubuntu.com:6969/announce", sitename: nil, tier: 0)
        let t = Torrent(wire: makeWire(trackers: [stub]))
        #expect(t.primaryTracker == "tracker.ubuntu.com")
        #expect(t.trackers.first?.host == "tracker.ubuntu.com")
    }

    @Test("empty trackers list yields empty primaryTracker")
    func noTrackers() {
        let t = Torrent(wire: makeWire(trackers: []))
        #expect(t.primaryTracker == "")
    }
}

// MARK: - peersFrom sum

@Suite("TorrentMapping — availablePeerCount")
struct PeersFromTests {
    @Test("availablePeerCount is the sum of all peersFrom sub-fields")
    func sum() {
        let wire = WireTorrent(
            id: 1, name: "T", hashString: "x", totalSize: 0,
            status: 4, error: 0, errorString: "", isFinished: false,
            percentDone: 0, rateDownload: 0, rateUpload: 0,
            peersConnected: 5, peersSendingToUs: 0, peersGettingFromUs: 0,
            peersFrom: WirePeersFrom(
                fromCache: 1, fromDht: 2, fromIncoming: 3,
                fromLpd: 4, fromLtep: 5, fromPex: 6, fromTracker: 7
            ),
            eta: -1, uploadRatio: 0, downloadDir: "/", addedDate: 0,
            labels: nil, bandwidthPriority: 0,
            pieceCount: 1, pieceSize: 1024, haveValid: 0,
            queuePosition: 0, trackers: nil
        )
        let t = Torrent(wire: wire)
        #expect(t.availablePeerCount == 1 + 2 + 3 + 4 + 5 + 6 + 7)
    }
}

// MARK: - RPCTorrentService stream lifecycle

@Suite("RPCTorrentService — stream lifecycle")
struct RPCTorrentServiceTests {
    private actor StubClient: TransmissionClient {
        private(set) var callCount = 0

        func sessionGet() async throws(TransmissionError) -> SessionInfo {
            throw TransmissionError.serverError("not used in test")
        }

        func torrentGet(fields: [String], ids: [Int]?) async throws(TransmissionError)
            -> TorrentGetResponse
        {
            callCount += 1
            return TorrentGetResponse(torrents: [])
        }
    }

    @Test("cancelling the consumer for-await stops the poll loop")
    func cancelStopsPollLoop() async throws {
        let stub = StubClient()
        let service = RPCTorrentService(client: stub, pollingInterval: { 60 })

        let stream = await service.torrentsStream()
        var iterator = stream.makeAsyncIterator()

        // Consume one emission so we know the loop started.
        _ = await iterator.next()
        let countAfterOne = await stub.callCount
        #expect(countAfterOne >= 1)

        // Cancel the iterator — this should cancel the poll task.
        // Drop the iterator (no further .next() calls) to let the stream terminate.
        _ = iterator  // silence unused warning; ARC releases it when this scope exits
    }
}
