import Foundation
import Testing

@testable import TransmissionRPC

/// Capture re-encodes the app's decoded wire types into the snapshot file, so
/// the re-encoded JSON must match the daemon's key names — that's what makes
/// replay decode through the identical code path as a live poll.
@Suite("Wire types — re-encode shape")
struct WireEncodableTests {
    @Test("WireTorrent re-encodes with daemon field names; nil optionals omitted")
    func torrentReencodesWithDaemonShape() throws {
        let torrent = WireTorrent(
            id: 7,
            name: "Test",
            hashString: "abc",
            totalSize: 1024,
            status: 4,
            error: 0,
            errorString: "",
            isFinished: false,
            percentDone: 0.5,
            rateDownload: 1,
            rateUpload: 2,
            peersConnected: 1,
            peersSendingToUs: 1,
            peersGettingFromUs: 0,
            peersFrom: WirePeersFrom(
                fromCache: 1, fromDht: 0, fromIncoming: 0,
                fromLpd: 0, fromLtep: 0, fromPex: 0, fromTracker: 0
            ),
            eta: 10,
            uploadRatio: 0.1,
            downloadDir: "/x",
            addedDate: 100,
            labels: nil,
            bandwidthPriority: 0,
            pieceCount: 10,
            pieceSize: 1024,
            haveValid: 512,
            queuePosition: 0,
            trackers: nil
        )
        let data = try JSONEncoder().encode(torrent)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["hashString"] as? String == "abc")
        #expect(object["downloadDir"] as? String == "/x")
        #expect(object["peersFrom"] is [String: Any])
        // Nil optionals encode as absent keys, matching the daemon.
        #expect(object["labels"] == nil)
        #expect(object["trackers"] == nil)
        #expect(object["files"] == nil)
        #expect(object["trackerStats"] == nil)
    }

    @Test("SessionInfo re-encodes with kebab-case keys")
    func sessionReencodesWithKebabKeys() throws {
        let session = SessionInfo(
            version: "4.1.2 (f234716f3e)",
            rpcVersion: 19,
            rpcVersionMinimum: 14,
            downloadDirFreeSpace: 5,
            altSpeedEnabled: true,
            downloadDir: "/downloads"
        )
        let data = try JSONEncoder().encode(session)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["rpc-version"] as? Int == 19)
        #expect(object["rpc-version-minimum"] as? Int == 14)
        #expect(object["download-dir"] as? String == "/downloads")
        #expect(object["download-dir-free-space"] as? Int64 == 5)
        #expect(object["alt-speed-enabled"] as? Bool == true)
        // camelCase variants must not appear.
        #expect(object["rpcVersion"] == nil)
        #expect(object["downloadDir"] == nil)
    }
}
