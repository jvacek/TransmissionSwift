// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

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

    @Test("with a poll interval the stream keeps ticking, and the list moves")
    func streamTicksWhenPolling() async throws {
        let url = try writeFixture()
        defer { try? FileManager.default.removeItem(at: url) }

        let service = try SnapshotTorrentService(
            fileURL: url, options: SnapshotReplayOptions(pollInterval: .milliseconds(10)))
        var emissions: [[Torrent]] = []
        for try await snapshot in await service.torrentsStream() {
            emissions.append(snapshot)
            if emissions.count == 3 { break }
        }
        #expect(emissions.count == 3)
        // The downloading torrent's speed wobbles and its progress advances.
        #expect(emissions[0][0].downloadSpeed != emissions[1][0].downloadSpeed)
        #expect(emissions[2][0].progress > emissions[0][0].progress)
        // The inspector reads the same live state as the list.
        let inspected = try await service.inspectorData(for: emissions[2][0].id)
        #expect(inspected.progress == emissions[2][0].progress)
    }

    @Test("latency delays every response")
    func latencyDelaysResponses() async throws {
        let url = try writeFixture()
        defer { try? FileManager.default.removeItem(at: url) }

        let service = try SnapshotTorrentService(
            fileURL: url, options: SnapshotReplayOptions(latency: .milliseconds(150)))
        let start = ContinuousClock.now
        _ = try await service.torrents()
        #expect(ContinuousClock.now - start >= .milliseconds(150))
    }

    @Test("is read-only: conforms to TorrentReading only, not TorrentMutating")
    func isReadOnly() async throws {
        let url = try writeFixture()
        defer { try? FileManager.default.removeItem(at: url) }

        let service = try SnapshotTorrentService(fileURL: url)
        // Erase to the reading existential so the check is a dynamic one: the
        // read-only replay must not be downcastable to the mutation capability.
        let reading: any TorrentReading = service
        #expect(!(reading is any TorrentMutating))
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

    @Test("exposes the server name the snapshot should replay as")
    func exposesServerName() throws {
        var file = SnapshotFixtures.rawSnapshot()
        file.source.serverName = "My remote server"
        let url = try writeFixture(file)
        defer { try? FileManager.default.removeItem(at: url) }

        let service = try SnapshotTorrentService(fileURL: url)
        #expect(service.displayServerName == "My remote server")
    }

    @Test("has no server name when the file carries none")
    func noServerNameWhenAbsent() throws {
        let url = try writeFixture()
        defer { try? FileManager.default.removeItem(at: url) }

        let service = try SnapshotTorrentService(fileURL: url)
        #expect(service.displayServerName == nil)
    }

    @Test("exposes the captured tag colours for seeding the replay store")
    func exposesTagColors() throws {
        let url = try writeFixture()
        defer { try? FileManager.default.removeItem(at: url) }

        let service = try SnapshotTorrentService(fileURL: url)
        #expect(service.tagColors == ["My Label": .green, "Movies": .blue, "Family": .purple])
    }

    @Test("exposes an empty colour map when the file carries none")
    func emptyTagColorsWhenAbsent() throws {
        var file = SnapshotFixtures.rawSnapshot()
        file.tagColors = nil
        let url = try writeFixture(file)
        defer { try? FileManager.default.removeItem(at: url) }

        let service = try SnapshotTorrentService(fileURL: url)
        #expect(service.tagColors.isEmpty)
    }
}

/// The per-tick changes the live replay applies. Pure, so the moving parts are
/// checked without timers.
@Suite("SnapshotLiveSimulation")
struct SnapshotLiveSimulationTests {
    private func torrent(
        id: Int, down: Int64, up: Int64 = 0, progress: Double, size: Int64 = 1_000_000
    ) -> Torrent {
        var torrent = Torrent(wire: SnapshotFixtures.rawSnapshot().torrents[0])
        torrent.id = id
        torrent.downloadSpeed = down
        torrent.uploadSpeed = up
        torrent.progress = progress
        torrent.size = size
        torrent.sizeWhenDone = size
        torrent.leftUntilDone = Int64(Double(size) * (1 - progress))
        return torrent
    }

    @Test func isDeterministic() {
        let captured = [torrent(id: 1, down: 1000, up: 500, progress: 0.5)]
        let a = SnapshotLiveSimulation.tick(captured, captured: captured, number: 3, interval: .seconds(1))
        let b = SnapshotLiveSimulation.tick(captured, captured: captured, number: 3, interval: .seconds(1))
        #expect(a == b)
    }

    @Test func speedsWobbleAroundTheCapturedValue() {
        let captured = [torrent(id: 1, down: 1000, up: 1000, progress: 0.1, size: 1_000_000_000)]
        var current = captured
        var speeds: Set<Int64> = []
        for tick in 1...20 {
            current = SnapshotLiveSimulation.tick(
                current, captured: captured, number: tick, interval: .seconds(1))
            #expect((500..<1500).contains(current[0].downloadSpeed))
            speeds.insert(current[0].downloadSpeed)
        }
        #expect(speeds.count > 1)
    }

    @Test func idleTorrentsStayIdle() {
        let captured = [torrent(id: 1, down: 0, up: 0, progress: 0.5)]
        let next = SnapshotLiveSimulation.tick(
            captured, captured: captured, number: 1, interval: .seconds(1))
        #expect(next == captured)
    }

    @Test func downloadsProgressAndNeverOvershoot() {
        let captured = [torrent(id: 1, down: 400_000, progress: 0.5)]
        let one = SnapshotLiveSimulation.tick(
            captured, captured: captured, number: 1, interval: .seconds(1))
        #expect(one[0].progress > 0.5)
        #expect(one[0].eta != nil)
        var current = one
        for tick in 2...10 {
            current = SnapshotLiveSimulation.tick(
                current, captured: captured, number: tick, interval: .seconds(1))
        }
        #expect(current[0].progress == 1)
        #expect(current[0].leftUntilDone == 0)
    }

    @Test func derivesWhatIsLeftForCapturesWithoutIt() {
        var bare = torrent(id: 1, down: 100_000, progress: 0.5)
        bare.leftUntilDone = 0
        bare.sizeWhenDone = 0
        let next = SnapshotLiveSimulation.tick([bare], captured: [bare], number: 1, interval: .seconds(1))
        #expect(next[0].progress > 0.5)
    }
}
