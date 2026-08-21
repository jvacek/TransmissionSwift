import Foundation
import Testing

@testable import TransmissionCore
@testable import TransmissionRPC

private func runRedactor(
    _ raw: SnapshotFile,
    options: SnapshotRedactionOptions = SnapshotRedactionOptions()
) throws -> (tree: [String: Any], summary: SnapshotRedactionSummary) {
    try SnapshotRedactor(options: options).redact(raw)
}

private func torrentTree(_ tree: [String: Any], index: Int) throws -> [String: Any] {
    let torrents = try #require(tree["torrents"] as? [Any])
    return try #require(torrents[index] as? [String: Any])
}

private func firstTracker(_ torrent: [String: Any]) throws -> [String: Any] {
    let trackers = try #require(torrent["trackers"] as? [Any])
    return try #require(trackers[0] as? [String: Any])
}

private func firstPeer(_ torrent: [String: Any]) throws -> [String: Any] {
    let peers = try #require(torrent["peers"] as? [Any])
    return try #require(peers[0] as? [String: Any])
}

@Suite("SnapshotRedactor")
struct SnapshotRedactorTests {
    // MARK: - Trackers

    @Test("announce URLs rewritten to .invalid; query string (passkey) stripped")
    func trackerPasskeyStripped() throws {
        let (tree, summary) = try runRedactor(SnapshotFixtures.rawSnapshot())
        let torrent = try torrentTree(tree, index: 0)
        let tracker = try firstTracker(torrent)

        #expect(tracker["announce"] as? String == "https://tracker-1.invalid/announce")
        #expect(summary.passkeysStripped == 1)
        #expect(summary.trackerURLs == 6)  // 3 announce + 3 host fields
    }

    @Test("same original host always maps to the same fake, across fields and torrents")
    func hostMappingIsStable() throws {
        let (tree, _) = try runRedactor(SnapshotFixtures.rawSnapshot())
        let torrent = try torrentTree(tree, index: 0)
        let tracker = try firstTracker(torrent)
        let stats = try #require(torrent["trackerStats"] as? [Any])
        let firstStat = try #require(stats[0] as? [String: Any])

        #expect(tracker["announce"] as? String == "https://tracker-1.invalid/announce")
        #expect(firstStat["host"] as? String == "tracker-1.invalid")
    }

    @Test("host:port and IP-hosted trackers keep port / map to doc-range IP")
    func trackerHostPortAndIP() throws {
        let (tree, _) = try runRedactor(SnapshotFixtures.rawSnapshot())
        let torrent = try torrentTree(tree, index: 0)
        let trackers = try #require(torrent["trackers"] as? [Any])
        let second = try #require(trackers[1] as? [String: Any])
        #expect(second["announce"] as? String == "https://tracker-2.invalid:8080/announce")

        let errorTorrent = try torrentTree(tree, index: 1)
        let errorTrackers = try #require(errorTorrent["trackers"] as? [Any])
        let ipTracker = try #require(errorTrackers[0] as? [String: Any])
        let announce = try #require(ipTracker["announce"] as? String)
        #expect(announce.hasPrefix("http://203.0.113."))
        #expect(announce.hasSuffix(":9090/announce"))
    }

    // MARK: - Peers

    @Test("IPv4 peer addresses become doc-range IPs, port preserved")
    func peerIPv4() throws {
        let (tree, _) = try runRedactor(SnapshotFixtures.rawSnapshot())
        let torrent = try torrentTree(tree, index: 0)
        let peer = try firstPeer(torrent)
        let address = try #require(peer["address"] as? String)
        #expect(address.hasPrefix("203.0.113."))
        #expect(address.hasSuffix(":51413"))
    }

    @Test("IPv6 peer addresses become 2001:db8::/32 fakes")
    func peerIPv6() throws {
        let (tree, _) = try runRedactor(SnapshotFixtures.rawSnapshot())
        let torrent = try torrentTree(tree, index: 0)
        let peers = try #require(torrent["peers"] as? [Any])
        let second = try #require(peers[1] as? [String: Any])
        let address = try #require(second["address"] as? String)
        #expect(address.hasPrefix("2001:db8:"))
        #expect(address != "2001:db8::ffff")
    }

    // MARK: - Names / paths / hashes / labels

    @Test("names fuzzed length-preserving, extension kept (opt-in)")
    func nameFuzzed() throws {
        let raw = SnapshotFixtures.rawSnapshot()
        let (tree, summary) = try runRedactor(
            raw, options: SnapshotRedactionOptions(includeNames: false)
        )
        let torrent = try torrentTree(tree, index: 0)
        let name = try #require(torrent["name"] as? String)

        #expect(name.count == raw.torrents[0].name.count)
        #expect(name.hasSuffix(".iso"))
        #expect(name != raw.torrents[0].name)
        #expect(summary.names >= 3)  // 2 torrent names + 1 label
    }

    @Test("names kept real by default so torrents stay identifiable")
    func namesKeptByDefault() throws {
        let raw = SnapshotFixtures.rawSnapshot()
        let (tree, _) = try runRedactor(raw)
        let torrent = try torrentTree(tree, index: 0)
        #expect(torrent["name"] as? String == raw.torrents[0].name)
        #expect(torrent["labels"] as? [String] == ["My Label"])
    }

    @Test("tracker anonymization off keeps hosts and sitenames, but passkeys are always stripped")
    func trackersKeptWhenAnonymizationOff() throws {
        let raw = SnapshotFixtures.rawSnapshot()
        let (tree, summary) = try runRedactor(
            raw, options: SnapshotRedactionOptions(anonymizeTrackers: false)
        )
        let torrent = try torrentTree(tree, index: 0)
        let tracker = try firstTracker(torrent)

        // Host and sitename kept real.
        #expect(tracker["announce"] as? String == "https://private-tracker.example/announce")
        #expect(tracker["sitename"] as? String == "PT")
        let stats = try #require(torrent["trackerStats"] as? [Any])
        let firstStat = try #require(stats[0] as? [String: Any])
        #expect(firstStat["host"] as? String == "private-tracker.example")

        // Passkey query stripped regardless; nothing counted as tracker URLs.
        #expect(summary.passkeysStripped == 1)
        #expect(summary.trackerURLs == 0)

        // IP-hosted tracker keeps its address.
        let errorTorrent = try torrentTree(tree, index: 1)
        let errorStats = try #require(errorTorrent["trackerStats"] as? [Any])
        let ipStat = try #require(errorStats[0] as? [String: Any])
        #expect(ipStat["host"] as? String == "10.0.0.5:9090")
    }

    @Test("file paths keep structure, extension kept, real segments gone")
    func pathFuzzed() throws {
        let raw = SnapshotFixtures.rawSnapshot()
        let (tree, _) = try runRedactor(raw)
        let torrent = try torrentTree(tree, index: 1)
        let downloadDir = try #require(torrent["downloadDir"] as? String)

        #expect(downloadDir != "/Users/jonas/Downloads")
        #expect(!downloadDir.contains("jonas"))
        #expect(downloadDir.split(separator: "/").count == 3)

        let session = try #require(tree["session"] as? [String: Any])
        let sessionDir = try #require(session["download-dir"] as? String)
        #expect(sessionDir != "/Users/jonas/Downloads")
        #expect(!sessionDir.contains("Users"))
    }

    @Test("labels fuzzed when names opt out")
    func labelsFuzzed() throws {
        let (tree, _) = try runRedactor(
            SnapshotFixtures.rawSnapshot(), options: SnapshotRedactionOptions(includeNames: false)
        )
        let torrent = try torrentTree(tree, index: 0)
        let labels = try #require(torrent["labels"] as? [String])
        #expect(labels.count == 1)
        #expect(labels[0] != "My Label")
        #expect(labels[0].count == "My Label".count)
    }

    @Test("infohashes become 40-char hex fakes")
    func hashFuzzed() throws {
        let raw = SnapshotFixtures.rawSnapshot()
        let (tree, summary) = try runRedactor(raw)
        let torrent = try torrentTree(tree, index: 0)
        let hash = try #require(torrent["hashString"] as? String)

        #expect(hash.count == 40)
        #expect(hash.allSatisfy { "0123456789abcdefABCDEF".contains($0) })
        #expect(hash != raw.torrents[0].hashString)
        #expect(summary.hashes == 2)
    }

    // MARK: - Free text

    @Test("free text: paths, URLs, emails scrubbed; message text preserved")
    func freeTextScrubbed() throws {
        let (tree, _) = try runRedactor(SnapshotFixtures.rawSnapshot())
        let torrent = try torrentTree(tree, index: 1)
        let message = try #require(torrent["errorString"] as? String)

        #expect(!message.contains("/Users"))
        #expect(!message.contains("example.com"))
        #expect(!message.contains("example.net"))
        #expect(!message.contains("://"))
        #expect(!message.contains("admin"))
        #expect(message.hasPrefix("Error: Unable to create directory"))
    }

    @Test("lastAnnounceResult with embedded tracker URL is scrubbed")
    func announceResultScrubbed() throws {
        let (tree, _) = try runRedactor(SnapshotFixtures.rawSnapshot())
        let torrent = try torrentTree(tree, index: 0)
        let stats = try #require(torrent["trackerStats"] as? [Any])
        let first = try #require(stats[0] as? [String: Any])
        let result = try #require(first["lastAnnounceResult"] as? String)

        #expect(!result.contains("private-tracker"))
        #expect(!result.contains("passkey"))
        #expect(!result.contains("://"))
    }

    // MARK: - Timestamps

    @Test("timestamps shifted to a fixed anchor; earliest addedDate → 2026-01-01")
    func timestampsShifted() throws {
        let (tree, summary) = try runRedactor(SnapshotFixtures.rawSnapshot())
        let torrent = try torrentTree(tree, index: 0)
        #expect(torrent["addedDate"] as? Int64 == Int64(SnapshotFixtures.anchor))

        let stats = try #require(torrent["trackerStats"] as? [Any])
        let first = try #require(stats[0] as? [String: Any])
        // 1_751_000_000 + (anchor − 1_750_000_000) = anchor + 1_000_000
        #expect(first["lastAnnounceTime"] as? Int64 == Int64(SnapshotFixtures.anchor) + 1_000_000)
        #expect(summary.timestampsShifted)
    }

    // MARK: - Options

    @Test("includeNames keeps real names")
    func includeNames() throws {
        let raw = SnapshotFixtures.rawSnapshot()
        let (tree, _) = try runRedactor(raw, options: SnapshotRedactionOptions(includeNames: true))
        let torrent = try torrentTree(tree, index: 0)
        #expect(torrent["name"] as? String == raw.torrents[0].name)
        #expect(torrent["labels"] as? [String] == ["My Label"])
    }

    @Test("includeHashes keeps real infohashes")
    func includeHashes() throws {
        let raw = SnapshotFixtures.rawSnapshot()
        let (tree, _) = try runRedactor(raw, options: SnapshotRedactionOptions(includeHashes: true))
        let torrent = try torrentTree(tree, index: 0)
        #expect(torrent["hashString"] as? String == raw.torrents[0].hashString)
    }

    @Test("preserveTimestamps keeps real times")
    func preserveTimestamps() throws {
        let raw = SnapshotFixtures.rawSnapshot()
        let (tree, summary) = try runRedactor(
            raw, options: SnapshotRedactionOptions(preserveTimestamps: true)
        )
        let torrent = try torrentTree(tree, index: 0)
        #expect(torrent["addedDate"] as? Int64 == 1_750_000_000)
        #expect(!summary.timestampsShifted)
    }

    // MARK: - Fidelity / determinism

    @Test("numbers, rates, and version strings pass through untouched")
    func passthrough() throws {
        let (tree, _) = try runRedactor(SnapshotFixtures.rawSnapshot())
        let torrent = try torrentTree(tree, index: 0)
        #expect(torrent["rateDownload"] as? Int64 == 1_048_576)
        #expect(torrent["totalSize"] as? Int64 == 4_294_967_296)
        #expect(torrent["percentDone"] as? Double == 0.42)

        let session = try #require(tree["session"] as? [String: Any])
        #expect(session["version"] as? String == "4.1.2 (f234716f3e)")
        #expect(session["alt-speed-enabled"] as? Bool == true)
        #expect(session["download-dir-free-space"] as? Int64 == 123_456_789_012)
    }

    @Test("peer client names are not fuzzed")
    func clientNamesKept() throws {
        let (tree, _) = try runRedactor(SnapshotFixtures.rawSnapshot())
        let torrent = try torrentTree(tree, index: 0)
        let peers = try #require(torrent["peers"] as? [Any])
        let first = try #require(peers[0] as? [String: Any])
        #expect(first["clientName"] as? String == "Transmission 4.0.6")
    }

    @Test("source.redacted flips to true and summary is embedded")
    func metadata() throws {
        let (tree, summary) = try runRedactor(SnapshotFixtures.rawSnapshot())
        let source = try #require(tree["source"] as? [String: Any])
        #expect(source["redacted"] as? Bool == true)
        #expect(source["daemonVersion"] as? String == "4.1.2 (f234716f3e)")
        #expect(tree["redactions"] is [String: Any])
        #expect(summary.summaryText.contains("tracker URL"))
    }

    @Test("redaction is deterministic — same input, identical output")
    func deterministic() throws {
        let raw = SnapshotFixtures.rawSnapshot()
        let first = try runRedactor(raw).tree
        let second = try runRedactor(raw).tree
        let data1 = try JSONSerialization.data(withJSONObject: first, options: [.sortedKeys])
        let data2 = try JSONSerialization.data(withJSONObject: second, options: [.sortedKeys])
        #expect(data1 == data2)
    }
}
