import Foundation
import Testing

@testable import TransmissionCore
@testable import TransmissionRPC

/// Decode → serve → mapping checks for `SnapshotTorrentService`, the `--snapshot`
/// replay path. Writes `SnapshotFixtures.rawSnapshot()` to a temp file and boots
/// the service off it — same code path the app uses for `--snapshot <path>`.
@Suite("SnapshotTorrentService — replay")
struct SnapshotTorrentServiceTests {
    /// Writes a snapshot file to a temp URL and returns the URL.
    private func writeFixture(
        _ file: SnapshotFile = SnapshotFixtures.rawSnapshot()
    ) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("replay-test-\(UUID().uuidString).json")
        let data = try JSONEncoder().encode(file)
        try data.write(to: url, options: .atomic)
        return url
    }

    @Test("decodes the file and serves torrents mapped through the live code path")
    func servesDecodedTorrents() async throws {
        let url = try writeFixture()
        defer { try? FileManager.default.removeItem(at: url) }

        let service = try SnapshotTorrentService(fileURL: url)
        let torrents = try await service.torrents()
        #expect(torrents.count == 2)

        // Same mapping as a live poll (Torrent(wire:)).
        let downloading = torrents[0]
        #expect(downloading.name == "Ubuntu 24.04 LTS.iso")
        #expect(downloading.status == .downloading)
        #expect(downloading.primaryTracker == "private-tracker.example")
        #expect(downloading.files.count == 1)
        #expect(downloading.files[0].name == "ubuntu-24.04.iso")
        #expect(downloading.peers.count == 2)
        #expect(downloading.trackers.count == 2)

        let errorTorrent = torrents[1]
        #expect(errorTorrent.status == .error)
        #expect(errorTorrent.errorMessage != nil)
    }

    @Test("serves session-derived fields (directory, free space, alt-speed)")
    func servesSessionFields() async throws {
        let url = try writeFixture()
        defer { try? FileManager.default.removeItem(at: url) }

        let service = try SnapshotTorrentService(fileURL: url)
        #expect(await service.downloadDirectory() == "/Users/jonas/Downloads")
        #expect(await service.freeSpace() == 123_456_789_012)
        #expect(await service.isAlternativeSpeedEnabled())
    }

    @Test("stream yields the list once, then closes (frozen — no ticking)")
    func streamIsFrozen() async throws {
        let url = try writeFixture()
        defer { try? FileManager.default.removeItem(at: url) }

        let service = try SnapshotTorrentService(fileURL: url)
        var emissions: [[Torrent]] = []
        for try await snapshot in await service.torrentsStream() {
            emissions.append(snapshot)
        }
        #expect(emissions.count == 1)
        #expect(emissions[0].count == 2)
    }

    @Test("is read-only: actions disabled and mutations throw")
    func isReadOnly() async throws {
        let url = try writeFixture()
        defer { try? FileManager.default.removeItem(at: url) }

        let service = try SnapshotTorrentService(fileURL: url)
        #expect(!service.supportsActions)
        await #expect(throws: SnapshotError.self) {
            try await service.stop([1])
        }
        await #expect(throws: SnapshotError.self) {
            try await service.add(
                fileURL: nil, magnetURL: nil, destination: "/x", labels: [],
                priority: .normal, startWhenAdded: true)
        }
    }

    @Test("inspectorData returns the fully-populated torrent")
    func inspectorData() async throws {
        let url = try writeFixture()
        defer { try? FileManager.default.removeItem(at: url) }

        let service = try SnapshotTorrentService(fileURL: url)
        let detail = try await service.inspectorData(for: 1)
        #expect(detail.files.count == 1)
        #expect(detail.peers.count == 2)
        #expect(detail.trackers.count == 2)
    }

    @Test("missing torrent id throws torrentNotFound")
    func missingTorrent() async throws {
        let url = try writeFixture()
        defer { try? FileManager.default.removeItem(at: url) }

        let service = try SnapshotTorrentService(fileURL: url)
        await #expect(throws: SnapshotError.torrentNotFound(99)) {
            _ = try await service.inspectorData(for: 99)
        }
    }

    @Test("rejects an unsupported format version")
    func rejectsUnknownVersion() throws {
        var file = SnapshotFixtures.rawSnapshot()
        file.version = snapshotFormatVersion + 1
        let url = try writeFixture(file)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: SnapshotError.unsupportedVersion(snapshotFormatVersion + 1)) {
            try SnapshotTorrentService(fileURL: url)
        }
    }
}
