import Foundation

/// Hand-curated sample data — ported from the design handoff's `data.jsx`.
/// Used by `MockTorrentService` and by SwiftUI previews. Don't depend on these
/// values for tests of derived behaviour; assert on what derivations produce
/// for *any* input rather than on these specific counts.
public enum MockFixtures {
    static let kiB: Int64 = 1024
    static let miB: Int64 = 1024 * 1024
    static let giB: Int64 = 1024 * 1024 * 1024

    /// Reference "now" — fixtures use offsets from this so `addedAt` is stable
    /// for a single call but reads sensibly when rendered as relative dates.
    private static func referenceNow() -> Date { Date() }

    public static func torrents() -> [Torrent] {
        let now = referenceNow()
        func ago(days: Double = 0, hours: Double = 0) -> Date {
            now.addingTimeInterval(-(days * 86400 + hours * 3600))
        }

        return [
            Torrent(
                id: 1,
                name: "Ubuntu 24.04.2 Desktop (amd64).iso",
                hash: "1f0c4d3b2e1a9876fedc54321089abcdef000001",
                size: Int64(5.9 * Double(giB)),
                status: .downloading,
                progress: 0.62,
                downloadSpeed: Int64(11.4 * Double(miB)),
                uploadSpeed: 820 * kiB,
                connectedPeerCount: 38,
                availablePeerCount: 142,
                seedCount: 96,
                eta: 320,
                ratio: 0.42,
                primaryTracker: "releases.ubuntu.com",
                downloadFolder: "Linux ISOs",
                addedAt: ago(hours: 5),
                label: "Linux",
                priority: .normal,
                pieces: 11800,
                pieceSize: 512 * kiB,
                havePieces: 7316,
                queuePosition: 1,
                files: stubFile(
                    named: "ubuntu-24.04.2-desktop-amd64.iso", size: Int64(5.9 * Double(giB)), progress: 0.62),
                peers: stubPeers(progressNear: 0.62, count: 4),
                trackers: stubTrackers(primary: "releases.ubuntu.com")
            ),
            Torrent(
                id: 2,
                name: "Blender 4.2 LTS — Splash & Demo Files",
                hash: "1f0c4d3b2e1a9876fedc54321089abcdef000002",
                size: Int64(2.3 * Double(giB)),
                status: .seeding,
                progress: 1,
                downloadSpeed: 0,
                uploadSpeed: Int64(2.1 * Double(miB)),
                connectedPeerCount: 6,
                availablePeerCount: 54,
                seedCount: 0,
                eta: .infinity,
                ratio: 3.18,
                primaryTracker: "tracker.blender.org",
                downloadFolder: "Creative",
                addedAt: ago(days: 1, hours: 3),
                label: "3D",
                priority: .normal,
                pieces: 4600,
                pieceSize: 512 * kiB,
                havePieces: 4600,
                files: stubFile(named: "blender-4.2-splash-demo.tar.zst", size: Int64(2.3 * Double(giB)), progress: 1),
                peers: stubPeers(progressNear: 0.9, count: 3),
                trackers: stubTrackers(primary: "tracker.blender.org")
            ),
            Torrent(
                id: 3,
                name: "archlinux-2026.06.01-x86_64.iso",
                hash: "1f0c4d3b2e1a9876fedc54321089abcdef000003",
                size: Int64(1.1 * Double(giB)),
                status: .seeding,
                progress: 1,
                downloadSpeed: 0,
                uploadSpeed: 640 * kiB,
                connectedPeerCount: 3,
                availablePeerCount: 21,
                seedCount: 0,
                eta: .infinity,
                ratio: 1.92,
                primaryTracker: "archlinux.org",
                downloadFolder: "Linux ISOs",
                addedAt: ago(days: 3),
                label: "Linux",
                priority: .low,
                pieces: 2200,
                pieceSize: 512 * kiB,
                havePieces: 2200,
                files: stubFile(named: "archlinux-2026.06.01-x86_64.iso", size: Int64(1.1 * Double(giB)), progress: 1),
                peers: stubPeers(progressNear: 0.95, count: 2),
                trackers: stubTrackers(primary: "archlinux.org")
            ),
            Torrent(
                id: 4,
                name: "LibreOffice 24.8 — Full Source Tarball",
                hash: "1f0c4d3b2e1a9876fedc54321089abcdef000004",
                size: 980 * miB,
                status: .paused,
                progress: 0.34,
                downloadSpeed: 0,
                uploadSpeed: 0,
                connectedPeerCount: 0,
                availablePeerCount: 88,
                seedCount: 40,
                eta: nil,
                ratio: 0.08,
                primaryTracker: "documentfoundation.org",
                downloadFolder: "Source",
                addedAt: ago(days: 3),
                priority: .normal,
                pieces: 1960,
                pieceSize: 512 * kiB,
                havePieces: 666,
                files: stubFile(named: "libreoffice-24.8.0.source.tar.xz", size: 980 * miB, progress: 0.34),
                peers: [],
                trackers: stubTrackers(primary: "documentfoundation.org")
            ),
            // Torrent 5 — the "selected" fixture with rich files/peers/trackers
            // from the design handoff.
            Torrent(
                id: 5,
                name: "Debian 12.6 — netinst (multi-arch) collection",
                hash: "1f0c4d3b2e1a9876fedc54321089abcdef000005",
                size: Int64(14.2 * Double(giB)),
                status: .downloading,
                progress: 0.18,
                downloadSpeed: Int64(6.8 * Double(miB)),
                uploadSpeed: 240 * kiB,
                connectedPeerCount: 22,
                availablePeerCount: 210,
                seedCount: 71,
                eta: 5400,
                ratio: 0.03,
                primaryTracker: "bittorrent.debian.org",
                downloadFolder: "Linux ISOs",
                addedAt: ago(days: 4),
                label: "Linux",
                priority: .high,
                pieces: 28400,
                pieceSize: 512 * kiB,
                havePieces: 5112,
                queuePosition: 2,
                options: TorrentOptions(
                    downloadLimited: true,
                    downloadLimitKBps: 2000,
                    seedRatioLimited: true,
                    seedRatioLimit: 2.0
                ),
                files: debianFiles(),
                peers: debianPeers(),
                trackers: debianTrackers()
            ),
            Torrent(
                id: 6,
                name: "Internet Archive — NASA Apollo Imagery Pack",
                hash: "1f0c4d3b2e1a9876fedc54321089abcdef000006",
                size: Int64(41.6 * Double(giB)),
                status: .downloading,
                progress: 0.07,
                downloadSpeed: Int64(3.2 * Double(miB)),
                uploadSpeed: 60 * kiB,
                connectedPeerCount: 9,
                availablePeerCount: 64,
                seedCount: 12,
                eta: 36000,
                ratio: 0.01,
                primaryTracker: "bt.archive.org",
                downloadFolder: "Archive",
                addedAt: ago(days: 5),
                label: "Media",
                priority: .low,
                pieces: 83200,
                pieceSize: 512 * kiB,
                havePieces: 5824,
                queuePosition: 3,
                files: stubFile(named: "nasa-apollo-imagery-pack.zip", size: Int64(41.6 * Double(giB)), progress: 0.07),
                peers: stubPeers(progressNear: 0.10, count: 3),
                trackers: stubTrackers(primary: "bt.archive.org")
            ),
            Torrent(
                id: 7,
                name: "FreeBSD 14.1 RELEASE — disc1 (amd64).iso",
                hash: "1f0c4d3b2e1a9876fedc54321089abcdef000007",
                size: Int64(4.3 * Double(giB)),
                status: .checking,
                progress: 0.91,
                connectedPeerCount: 0,
                availablePeerCount: 33,
                seedCount: 18,
                eta: nil,
                ratio: 0.55,
                primaryTracker: "tracker.freebsd.org",
                downloadFolder: "Linux ISOs",
                addedAt: ago(days: 7),
                priority: .normal,
                pieces: 8600,
                pieceSize: 512 * kiB,
                havePieces: 7826,
                files: stubFile(
                    named: "FreeBSD-14.1-RELEASE-amd64-disc1.iso", size: Int64(4.3 * Double(giB)), progress: 0.91),
                peers: [],
                trackers: stubTrackers(primary: "tracker.freebsd.org")
            ),
            Torrent(
                id: 8,
                name: "Wikipedia EN — ZIM full archive (2026-05)",
                hash: "1f0c4d3b2e1a9876fedc54321089abcdef000008",
                size: 102 * giB,
                status: .error,
                progress: 0.44,
                connectedPeerCount: 0,
                availablePeerCount: 4,
                seedCount: 1,
                eta: nil,
                ratio: 0.12,
                primaryTracker: "tracker.kiwix.org",
                downloadFolder: "Archive",
                addedAt: ago(days: 14),
                label: "Media",
                priority: .normal,
                pieces: 204000,
                pieceSize: 512 * kiB,
                havePieces: 89760,
                errorMessage: "Tracker returned: connection timed out",
                files: stubFile(named: "wikipedia_en_all_2026-05.zim", size: 102 * giB, progress: 0.44),
                peers: [],
                trackers: [
                    Tracker(
                        tier: 0, host: "tracker.kiwix.org", state: .error,
                        statusMessage: "Error — connection timed out",
                        seedCount: 0, leechCount: 0, downloadCount: 0
                    )
                ]
            ),
            Torrent(
                id: 9,
                name: "GIMP 2.99 — flatpak bundle + brushes",
                hash: "1f0c4d3b2e1a9876fedc54321089abcdef000009",
                size: 720 * miB,
                status: .seeding,
                progress: 1,
                uploadSpeed: 410 * kiB,
                connectedPeerCount: 2,
                availablePeerCount: 17,
                seedCount: 0,
                eta: .infinity,
                ratio: 5.04,
                primaryTracker: "tracker.blender.org",
                downloadFolder: "Creative",
                addedAt: ago(days: 14),
                label: "3D",
                priority: .normal,
                pieces: 1440,
                pieceSize: 512 * kiB,
                havePieces: 1440,
                files: stubFile(named: "gimp-2.99-flatpak.bundle", size: 720 * miB, progress: 1),
                peers: stubPeers(progressNear: 0.85, count: 2),
                trackers: stubTrackers(primary: "tracker.blender.org")
            ),
            Torrent(
                id: 10,
                name: "Project Gutenberg — Top 1000 (EPUB)",
                hash: "1f0c4d3b2e1a9876fedc54321089abcdef000010",
                size: Int64(3.8 * Double(giB)),
                status: .queued,
                progress: 0,
                connectedPeerCount: 0,
                availablePeerCount: 29,
                seedCount: 14,
                eta: nil,
                ratio: 0,
                primaryTracker: "bt.archive.org",
                downloadFolder: "Archive",
                addedAt: ago(days: 14),
                label: "Media",
                priority: .normal,
                pieces: 7600,
                pieceSize: 512 * kiB,
                havePieces: 0,
                queuePosition: 4,
                files: stubFile(named: "gutenberg-top1000-epub.zip", size: Int64(3.8 * Double(giB)), progress: 0),
                peers: [],
                trackers: stubTrackers(primary: "bt.archive.org")
            ),
        ]
    }

    public static func servers() -> [ServerProfile] {
        [
            ServerProfile(label: "Home NAS", host: "nas.local", port: 9091, username: "admin", useHTTPS: false),
            ServerProfile(
                label: "Seedbox — Frankfurt", host: "sb-fra.feralhosting.net", port: 9091, username: "casey",
                useHTTPS: true),
            ServerProfile(label: "Raspberry Pi", host: "10.0.0.42", port: 9091, username: "pi", useHTTPS: false),
        ]
    }

    // MARK: - Per-torrent sub-fixtures

    private static func stubFile(named name: String, size: Int64, progress: Double) -> [TorrentFile] {
        [TorrentFile(id: 0, name: name, size: size, progress: progress)]
    }

    private static func stubPeers(progressNear target: Double, count: Int) -> [Peer] {
        let template: [Peer] = [
            Peer(
                ipAddress: "94.142.241.111", client: "Transmission 4.0.5", countryCode: "NL", flags: "UDEH",
                progress: target, downloadSpeed: Int64(1.4 * Double(miB)), uploadSpeed: 12 * kiB),
            Peer(
                ipAddress: "188.40.94.6", client: "qBittorrent 5.0.1", countryCode: "DE", flags: "udEH",
                progress: max(0, target - 0.15), downloadSpeed: 880 * kiB, uploadSpeed: 0),
            Peer(
                ipAddress: "70.34.209.18", client: "Deluge 2.1.1", countryCode: "US", flags: "UDe",
                progress: max(0, target - 0.30), downloadSpeed: 640 * kiB, uploadSpeed: 4 * kiB),
            Peer(
                ipAddress: "203.0.113.42", client: "libtorrent 2.0", countryCode: "AU", flags: "UEX", progress: 1.0,
                downloadSpeed: 410 * kiB, uploadSpeed: 0),
        ]
        return Array(template.prefix(count))
    }

    private static func stubTrackers(primary: String) -> [Tracker] {
        [
            Tracker(
                tier: 0, host: primary, state: .working,
                statusMessage: "Working — announced 2m ago",
                seedCount: 24, leechCount: 8, downloadCount: 412)
        ]
    }

    // MARK: - Debian fixture (id 5)

    private static func debianFiles() -> [TorrentFile] {
        [
            TorrentFile(
                id: 0, name: "debian-12.6.0-amd64-netinst.iso", size: 658 * miB, progress: 1, priority: .normal,
                wanted: true),
            TorrentFile(
                id: 1, name: "debian-12.6.0-arm64-netinst.iso", size: 640 * miB, progress: 1, priority: .normal,
                wanted: true),
            TorrentFile(
                id: 2, name: "debian-12.6.0-i386-netinst.iso", size: 612 * miB, progress: 0.42, priority: .normal,
                wanted: true),
            TorrentFile(
                id: 3, name: "debian-12.6.0-amd64-DVD-1.iso", size: Int64(3.9 * Double(giB)), progress: 0.04,
                priority: .high, wanted: true),
            TorrentFile(id: 4, name: "SHA256SUMS", size: 4 * kiB, progress: 1, priority: .high, wanted: true),
            TorrentFile(id: 5, name: "SHA256SUMS.sign", size: 833, progress: 1, priority: .normal, wanted: true),
            TorrentFile(
                id: 6, name: "README.txt", size: Int64(5.6 * Double(kiB)), progress: 1, priority: .low, wanted: false),
        ]
    }

    private static func debianPeers() -> [Peer] {
        [
            Peer(
                ipAddress: "94.142.241.111", client: "Transmission 4.0.5", countryCode: "NL", flags: "UDEH",
                progress: 0.99, downloadSpeed: Int64(1.4 * Double(miB)), uploadSpeed: 12 * kiB),
            Peer(
                ipAddress: "188.40.94.6", client: "qBittorrent 5.0.1", countryCode: "DE", flags: "udEH", progress: 0.71,
                downloadSpeed: 880 * kiB, uploadSpeed: 0),
            Peer(
                ipAddress: "70.34.209.18", client: "Deluge 2.1.1", countryCode: "US", flags: "UDe", progress: 0.55,
                downloadSpeed: 640 * kiB, uploadSpeed: 4 * kiB),
            Peer(
                ipAddress: "203.0.113.42", client: "libtorrent 2.0", countryCode: "AU", flags: "UEX", progress: 1.0,
                downloadSpeed: 410 * kiB, uploadSpeed: 0),
            Peer(
                ipAddress: "51.158.66.200", client: "rTorrent 0.9.8", countryCode: "FR", flags: "Ud", progress: 0.33,
                downloadSpeed: 220 * kiB, uploadSpeed: 0),
            Peer(
                ipAddress: "45.83.220.9", client: "BiglyBT 3.6", countryCode: "CA", flags: "UDEH", progress: 0.88,
                downloadSpeed: 96 * kiB, uploadSpeed: 2 * kiB),
        ]
    }

    private static func debianTrackers() -> [Tracker] {
        [
            Tracker(
                tier: 0, host: "bittorrent.debian.org", state: .working,
                statusMessage: "Working — announced 2m ago",
                seedCount: 71, leechCount: 22, downloadCount: 4180),
            Tracker(
                tier: 1, host: "tracker.debian.org", state: .working,
                statusMessage: "Working — announced 2m ago",
                seedCount: 54, leechCount: 18, downloadCount: 3902),
            Tracker(
                tier: 2, host: "open.tracker.cl", state: .idle,
                statusMessage: "Idle — next announce in 27m",
                seedCount: 12, leechCount: 4, downloadCount: 311),
            Tracker(
                tier: 2, host: "tracker.opentrackr.org", state: .error,
                statusMessage: "Error — connection timed out",
                seedCount: 0, leechCount: 0, downloadCount: 0),
        ]
    }
}

// MARK: - SwiftUI preview convenience

extension Torrent {
    /// First mock torrent — the in-flight Ubuntu ISO. Use in `#Preview { }`.
    public static var sample: Torrent { MockFixtures.torrents()[0] }
    public static var samples: [Torrent] { MockFixtures.torrents() }
}

extension ServerProfile {
    public static var sample: ServerProfile { MockFixtures.servers()[0] }
    public static var samples: [ServerProfile] { MockFixtures.servers() }
}
