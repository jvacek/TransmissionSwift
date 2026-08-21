import Foundation

@testable import TransmissionCore
@testable import TransmissionRPC

/// Realistic raw (pre-redaction) snapshot for the slice A test suites: private
/// and open trackers (passkeys, host:port, IP-hosted), IPv4 + IPv6 peers, file
/// paths, labels, an error torrent with identifying free text.
enum SnapshotFixtures {
    /// 2026-01-01T00:00:00Z — the timestamp anchor the redactor shifts to.
    static let anchor: TimeInterval = 1_767_225_600

    static let privateTrackerAnnounce =
        "https://private-tracker.example/announce.php?passkey=deadbeefcafe0123456789abcdef0123456789"
    static let openTrackerAnnounce = "https://tracker.example.org:8080/announce"

    static func rawSnapshot() -> SnapshotFile {
        SnapshotFile(
            version: snapshotFormatVersion,
            capturedAt: "2026-08-21T10:00:00Z",
            source: SnapshotSourceInfo(
                daemonVersion: "4.1.2 (f234716f3e)",
                rpcVersion: 19,
                redacted: false
            ),
            session: SessionInfo(
                version: "4.1.2 (f234716f3e)",
                rpcVersion: 19,
                rpcVersionMinimum: 14,
                downloadDirFreeSpace: 123_456_789_012,
                altSpeedEnabled: true,
                downloadDir: "/Users/jonas/Downloads"
            ),
            torrents: [downloadingTorrent(), errorTorrent()]
        )
    }

    static func downloadingTorrent() -> WireTorrent {
        WireTorrent(
            id: 1,
            name: "Ubuntu 24.04 LTS.iso",
            hashString: "aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111",
            totalSize: 4_294_967_296,
            status: 4,
            error: 0,
            errorString: "",
            isFinished: false,
            percentDone: 0.42,
            rateDownload: 1_048_576,
            rateUpload: 65_536,
            peersConnected: 3,
            peersSendingToUs: 2,
            peersGettingFromUs: 1,
            peersFrom: WirePeersFrom(
                fromCache: 1, fromDht: 2, fromIncoming: 3,
                fromLpd: 0, fromLtep: 0, fromPex: 0, fromTracker: 4
            ),
            eta: 3600,
            uploadRatio: 1.25,
            downloadDir: "/Users/jonas/Downloads",
            addedDate: 1_750_000_000,
            labels: ["My Label"],
            bandwidthPriority: 0,
            pieceCount: 4096,
            pieceSize: 1_048_576,
            haveValid: 1_800_000_000,
            queuePosition: 1,
            trackers: [
                WireTrackerStub(announce: privateTrackerAnnounce, sitename: "PT", tier: 0),
                WireTrackerStub(announce: openTrackerAnnounce, sitename: "Tracker Org", tier: 0),
            ],
            files: [
                WireFile(name: "ubuntu-24.04.iso", length: 4_294_967_296, bytesCompleted: 1_800_000_000)
            ],
            fileStats: [WireFileStat(bytesCompleted: 1_800_000_000, wanted: true, priority: 0)],
            peers: [
                WirePeer(
                    address: "192.168.1.42:51413", clientName: "Transmission 4.0.6",
                    flagStr: "U", progress: 0.5, rateToClient: 1024, rateToPeer: 2048
                ),
                WirePeer(
                    address: "2001:db8::ffff", clientName: "qBittorrent 4.6.7",
                    flagStr: "X", progress: 1.0, rateToClient: 0, rateToPeer: 0
                ),
            ],
            trackerStats: [
                WireTrackerStat(
                    id: 1, tier: 0, host: "private-tracker.example",
                    lastAnnounceResult:
                        "Could not connect to https://private-tracker.example/announce.php?passkey=deadbeef",
                    lastAnnounceTime: 1_751_000_000, lastAnnounceSucceeded: false,
                    hasAnnounced: true, announceState: 1,
                    seederCount: 10, leecherCount: 2, downloadCount: 500, isBackup: false
                ),
                WireTrackerStat(
                    id: 2, tier: 0, host: "tracker.example.org:8080",
                    lastAnnounceResult: "Success",
                    lastAnnounceTime: 1_751_000_100, lastAnnounceSucceeded: true,
                    hasAnnounced: true, announceState: 3,
                    seederCount: 100, leecherCount: 20, downloadCount: 5_000, isBackup: false
                ),
            ]
        )
    }

    static func errorTorrent() -> WireTorrent {
        WireTorrent(
            id: 2,
            name: "movies/Interstellar 2014.mkv",
            hashString: "bbbb2222bbbb2222bbbb2222bbbb2222bbbb2222",
            totalSize: 12_884_901_888,
            status: 6,
            error: 2,
            errorString:
                "Error: Unable to create directory /Users/jonas/Downloads/Interstellar — contact admin@example.com or http://support.example.net/faq",
            isFinished: false,
            percentDone: 1.0,
            rateDownload: 0,
            rateUpload: 1_048_576,
            peersConnected: 2,
            peersSendingToUs: 0,
            peersGettingFromUs: 2,
            peersFrom: WirePeersFrom(
                fromCache: 0, fromDht: 0, fromIncoming: 0,
                fromLpd: 0, fromLtep: 0, fromPex: 0, fromTracker: 2
            ),
            eta: -1,
            uploadRatio: 0.42,
            downloadDir: "/Users/jonas/Downloads",
            addedDate: 1_751_000_000,
            labels: ["Movies", "Family"],
            bandwidthPriority: -1,
            pieceCount: 12_288,
            pieceSize: 1_048_576,
            haveValid: 12_884_901_888,
            queuePosition: 2,
            trackers: [
                WireTrackerStub(announce: "http://10.0.0.5:9090/announce", sitename: "Local", tier: 0)
            ],
            files: [
                WireFile(name: "Interstellar 2014.mkv", length: 12_884_901_888, bytesCompleted: 12_884_901_888)
            ],
            fileStats: [WireFileStat(bytesCompleted: 12_884_901_888, wanted: true, priority: -1)],
            peers: [
                WirePeer(
                    address: "198.51.100.9:6881", clientName: "libtorrent 1.2.19",
                    flagStr: "S", progress: 0.9, rateToClient: 4096, rateToPeer: 512
                )
            ],
            trackerStats: [
                WireTrackerStat(
                    id: 3, tier: 0, host: "10.0.0.5:9090",
                    lastAnnounceResult: "Success",
                    lastAnnounceTime: 1_751_000_200, lastAnnounceSucceeded: true,
                    hasAnnounced: true, announceState: 2,
                    seederCount: 1, leecherCount: 0, downloadCount: 1, isBackup: false
                )
            ]
        )
    }
}
