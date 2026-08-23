import Foundation
import Testing

@testable import TransmissionCore
@testable import TransmissionRPC

/// Runs the exact pipeline `TorrentStore.captureSnapshot` uses, minus the file
/// write: raw → redact → leak check → serialize.
private func runPipeline(
    _ raw: SnapshotFile,
    options: SnapshotRedactionOptions = SnapshotRedactionOptions()
) throws -> (data: Data, summary: SnapshotRedactionSummary) {
    let redactor = SnapshotRedactor(options: options)
    let (tree, summary) = try redactor.redact(raw)
    try SnapshotLeakChecker.check(
        tree,
        namesKept: options.includeNames,
        anonymizeTrackers: options.anonymizeTrackers
    )
    let data = try JSONSerialization.data(
        withJSONObject: tree,
        options: [.sortedKeys, .prettyPrinted]
    )
    return (data, summary)
}

/// A `TorrentService` that only supports snapshot capture — everything else is
/// a no-op. Lets `TorrentStore.captureSnapshot` be tested in isolation.
private struct StubSnapshotService: TorrentService {
    let raw: SnapshotFile

    private var domainTorrents: [Torrent] { raw.torrents.map { Torrent(wire: $0) } }

    func captureRawSnapshot() async throws -> SnapshotFile { raw }
    func torrents() async throws -> [Torrent] { domainTorrents }
    func torrentsStream() async -> AsyncThrowingStream<[Torrent], Error> {
        let torrents = domainTorrents
        return AsyncThrowingStream { continuation in
            continuation.yield(torrents)
            continuation.finish()
        }
    }
    func freeSpace() async -> Int64? { nil }
    func downloadDirectory() async -> String? { nil }
    func start(_ ids: [Torrent.ID]) async throws {}
    func stop(_ ids: [Torrent.ID]) async throws {}
    func remove(_ ids: [Torrent.ID], deleteLocalData: Bool) async throws {}
    func verify(_ ids: [Torrent.ID]) async throws {}
    func setFilesWanted(_ id: Torrent.ID, fileIDs: [TorrentFile.ID], wanted: Bool) async throws {}
    func setFilePriority(_ id: Torrent.ID, fileIDs: [TorrentFile.ID], priority: TorrentPriority)
        async throws
    {}
    func setOptions(_ id: Torrent.ID, options: TorrentOptions) async throws {}
    func setLabels(_ ids: [Torrent.ID], labels: [String]) async throws {}
    func setAlternativeSpeedEnabled(_ enabled: Bool) async throws {}
    func isAlternativeSpeedEnabled() async -> Bool { false }
    func add(
        fileURL: URL?, magnetURL: String?, destination: String, labels: [String],
        priority: TorrentPriority, startWhenAdded: Bool
    ) async throws {}
    func inspectorData(for id: Torrent.ID) async throws -> Torrent {
        struct NotFound: Error {}
        throw NotFound()
    }
}

@Suite("Snapshot pipeline — verifying the produced file")
struct SnapshotPipelineTests {
    @Test("the produced file is valid, anonymized, and maps to sensible torrents")
    func fileRoundTrip() throws {
        let raw = SnapshotFixtures.rawSnapshot()
        let (data, summary) = try runPipeline(raw)

        // The file must load through the same decode path slice B's replay will use.
        let file = try JSONDecoder().decode(SnapshotFile.self, from: data)
        #expect(file.version == snapshotFormatVersion)
        #expect(file.capturedAt == "2026-08-21T10:00:00Z")
        #expect(file.source.redacted)
        #expect(file.source.daemonVersion == "4.1.2 (f234716f3e)")
        #expect(file.redactions == summary)
        #expect(file.torrents.count == 2)
        #expect(file.session.downloadDirFreeSpace == 123_456_789_012)

        // Domain mapping through the live code path (Torrent(wire:)).
        let torrents = file.torrents.map { Torrent(wire: $0) }
        let downloading = torrents[0]
        #expect(downloading.status == .downloading)
        #expect(downloading.primaryTracker == "tracker-1.invalid")
        // Names are kept by default so the user can point at specific torrents.
        #expect(downloading.name == "Ubuntu 24.04 LTS.iso")
        #expect(downloading.files.allSatisfy { $0.name == "ubuntu-24.04.iso" })
        // Everything identifying is still scrubbed.
        #expect(downloading.hash != raw.torrents[0].hashString)
        #expect(downloading.hash.count == 40)
        #expect(downloading.downloadFolder != "/Users/jonas/Downloads")
        #expect(downloading.addedAt == Date(timeIntervalSince1970: SnapshotFixtures.anchor))
        #expect(
            downloading.peers.allSatisfy {
                $0.ipAddress.hasPrefix("203.0.113.") || $0.ipAddress.hasPrefix("2001:db8")
            })
        #expect(
            downloading.trackers.allSatisfy {
                $0.host.contains(".invalid") || $0.host.hasPrefix("203.0.113.")
            })

        let errorTorrent = torrents[1]
        #expect(errorTorrent.status == .error)
        #expect(errorTorrent.errorMessage != nil)
        let message = errorTorrent.errorMessage ?? ""
        #expect(!message.contains("/Users"))
        #expect(!message.contains("example.com"))
        #expect(!message.contains("example.net"))
        #expect(!message.contains("://"))
        #expect(!message.contains("admin"))

        // Belt & braces: re-encode the decoded file and run the leak check again.
        let reencoded = try #require(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(file)) as? [String: Any]
        )
        try SnapshotLeakChecker.check(reencoded)
    }

    @Test("redaction is deterministic — two runs produce byte-identical files")
    func deterministicFile() throws {
        let raw = SnapshotFixtures.rawSnapshot()
        let first = try runPipeline(raw).data
        let second = try runPipeline(raw).data
        #expect(first == second)
    }

    @Test("defaults keep names but scrub trackers, IPs, hashes, paths, timestamps")
    func defaultsScrubIdentity() throws {
        let raw = SnapshotFixtures.rawSnapshot()
        let file = try JSONDecoder().decode(SnapshotFile.self, from: try runPipeline(raw).data)
        let torrent = file.torrents[0]

        // Identifiable on purpose.
        #expect(torrent.name == raw.torrents[0].name)
        #expect(torrent.labels == raw.torrents[0].labels)
        #expect(torrent.files?[0].name == raw.torrents[0].files?[0].name)

        // Everything identifying is scrubbed.
        #expect(torrent.hashString != raw.torrents[0].hashString)
        #expect(torrent.downloadDir != raw.torrents[0].downloadDir)
        #expect(torrent.trackers?[0].announce != SnapshotFixtures.privateTrackerAnnounce)
        let announce = torrent.trackers?[0].announce ?? ""
        #expect(!announce.contains("passkey"))
        #expect(torrent.peers?[0].address.hasPrefix("203.0.113.") ?? false)
    }

    @Test("opting out of name/tracker fuzzing keeps them, but passkeys are always stripped")
    func optOuts() throws {
        let raw = SnapshotFixtures.rawSnapshot()
        let file = try JSONDecoder().decode(
            SnapshotFile.self,
            from: try runPipeline(
                raw,
                options: SnapshotRedactionOptions(includeNames: false, anonymizeTrackers: false)
            ).data
        )
        let torrent = file.torrents[0]

        #expect(torrent.name != raw.torrents[0].name)
        #expect(torrent.name.count == raw.torrents[0].name.count)
        #expect(torrent.trackers?[0].sitename == "PT")
        let announce = torrent.trackers?[0].announce ?? ""
        #expect(announce.hasPrefix("https://private-tracker.example/"))
        #expect(!announce.contains("passkey"))
        #expect(!announce.contains("?"))
    }

    @Test("the leak check refuses a file containing a surviving real IP")
    func leakRefusesFile() throws {
        let raw = SnapshotFixtures.rawSnapshot()
        let redactor = SnapshotRedactor()
        let (tree, _) = try redactor.redact(raw)
        var torrents = try #require(tree["torrents"] as? [Any])
        var first = try #require(torrents[0] as? [String: Any])
        var peers = try #require(first["peers"] as? [Any])
        var peer = try #require(peers[0] as? [String: Any])
        peer["address"] = "172.16.0.1:51413"
        peers[0] = peer
        first["peers"] = peers
        torrents[0] = first

        var leaking = tree
        leaking["torrents"] = torrents
        #expect(throws: SnapshotError.self) {
            try SnapshotLeakChecker.check(leaking)
        }
    }

    @Test("TorrentStore.captureSnapshot writes a loadable file via the stub service")
    @MainActor
    func storeWritesFile() async throws {
        let stub = StubSnapshotService(raw: SnapshotFixtures.rawSnapshot())
        let store = TorrentStore(service: stub)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("snapshot-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        // respectFilters off: don't depend on the store's poll having landed.
        let result = try await store.captureSnapshot(
            to: url, options: SnapshotRedactionOptions(respectFilters: false)
        )

        #expect(result.torrentCount == 2)
        #expect(result.summary.trackerURLs == 6)
        #expect(result.summary.passkeysStripped == 1)
        #expect(result.summary.peerIPs == 3)
        #expect(result.summary.names == 3)  // fuzzed tracker sitenames only — real names are kept

        let data = try Data(contentsOf: url)
        let file = try JSONDecoder().decode(SnapshotFile.self, from: data)
        #expect(file.source.redacted)
        #expect(file.torrents.count == 2)
        #expect(file.redactions == result.summary)
    }

    @Test("capture respects current filters and the torrent limit")
    @MainActor
    func captureScopedToFilters() async throws {
        let stub = StubSnapshotService(raw: SnapshotFixtures.rawSnapshot())
        let store = TorrentStore(service: stub)
        await waitFor { store.visibleTorrents.count == 2 }

        // Narrow to the downloading torrent only.
        store.setStatusFilter(.downloading)
        await waitFor { store.visibleTorrents.count == 1 }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("snapshot-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await store.captureSnapshot(
            to: url,
            options: SnapshotRedactionOptions(maxTorrents: 5)
        )
        #expect(result.torrentCount == 1)

        let file = try JSONDecoder().decode(SnapshotFile.self, from: Data(contentsOf: url))
        #expect(file.torrents.count == 1)
        #expect(file.torrents[0].name == "Ubuntu 24.04 LTS.iso")
    }

    @Test("capture cap applies after the filter scope")
    @MainActor
    func captureCapped() async throws {
        let stub = StubSnapshotService(raw: SnapshotFixtures.rawSnapshot())
        let store = TorrentStore(service: stub)
        await waitFor { store.visibleTorrents.count == 2 }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("snapshot-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await store.captureSnapshot(
            to: url,
            options: SnapshotRedactionOptions(maxTorrents: 1)
        )
        #expect(result.torrentCount == 1)
    }

    /// Polls the main actor until `predicate` holds (store state updates
    /// asynchronously from the service stream).
    @MainActor
    private func waitFor(timeout: TimeInterval = 1, _ predicate: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !predicate(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("capture is unsupported by non-RPC services")
    @MainActor
    func captureUnsupported() async {
        let store = TorrentStore(service: MockTorrentService())
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("snapshot-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        await #expect(throws: SnapshotError.self) {
            try await store.captureSnapshot(to: url)
        }
    }
}
