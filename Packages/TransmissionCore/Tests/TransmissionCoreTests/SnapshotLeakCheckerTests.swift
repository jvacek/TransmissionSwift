import Foundation
import Testing

@testable import TransmissionCore
@testable import TransmissionRPC

private func checkValue(
    _ string: String, key: String, namesKept: Bool = false, anonymizeTrackers: Bool = true
) throws {
    try SnapshotLeakChecker.check([key: string], namesKept: namesKept, anonymizeTrackers: anonymizeTrackers)
}

private func expectLeak(
    _ string: String, key: String, namesKept: Bool = false, anonymizeTrackers: Bool = true
) {
    #expect(throws: SnapshotError.self) {
        try checkValue(string, key: key, namesKept: namesKept, anonymizeTrackers: anonymizeTrackers)
    }
}

private func expectClean(
    _ string: String, key: String, namesKept: Bool = false, anonymizeTrackers: Bool = true
) {
    #expect(throws: Never.self) {
        try checkValue(string, key: key, namesKept: namesKept, anonymizeTrackers: anonymizeTrackers)
    }
}

@Suite("SnapshotLeakChecker")
struct SnapshotLeakCheckerTests {
    // MARK: - IPv4

    @Test("real IPv4 in a tracker host is a leak")
    func realIPv4InHost() {
        expectLeak("8.8.8.8:51413", key: "host")
    }

    @Test("real IPv4 in free text is a leak")
    func realIPv4InFreeText() {
        expectLeak("Could not connect to 8.8.8.8", key: "errorString")
    }

    @Test("real IPv4 in a peer address is a leak")
    func realIPv4InAddress() {
        expectLeak("10.0.0.5:9090", key: "address")
    }

    @Test("doc-range IPv4 passes")
    func docIPv4Passes() {
        expectClean("203.0.113.42:51413", key: "address")
    }

    @Test("fuzzed name fields are skipped — dotted digits inside names pass")
    func nameFieldSkipped() {
        expectClean("backup-10.0.0.1-2024", key: "name")
    }

    @Test("kept names are checked for embedded IPs (but not hostname shapes)")
    func keptNamesCheckedForIPs() {
        // A real IP inside a kept name is a leak.
        expectLeak("server-192.168.1.5-backup", key: "name", namesKept: true)
        // Dotted real names are fine — no FQDN check on names.
        expectClean("Ubuntu 24.04 LTS.iso", key: "name", namesKept: true)
        expectClean("My Label", key: "labels", namesKept: true)
    }

    @Test("real FQDN in a tracker host is a leak when trackers are anonymized")
    func realFQDNInHost() {
        expectLeak("tracker.example.org", key: "host")
    }

    @Test("kept tracker hosts are intentional — pass, but passkey queries still fail")
    func keptTrackerHostPasses() {
        expectClean("tracker.example.org", key: "host", anonymizeTrackers: false)
        expectClean("tracker.example.org:8080", key: "host", anonymizeTrackers: false)
        expectLeak("https://tracker.example.org/announce?passkey=abc123", key: "announce", anonymizeTrackers: false)
    }

    // MARK: - IPv6

    @Test("real IPv6 is a leak")
    func realIPv6Fails() {
        expectLeak("fe80::21c:42ff:fe00:0", key: "address")
    }

    @Test("2001:db8::/32 fake passes")
    func docIPv6Passes() {
        expectClean("2001:db8:abcd:ef01", key: "address")
    }

    // MARK: - Hostnames

    @Test("fake .invalid host passes")
    func fakeHostPasses() {
        expectClean("tracker-1.invalid", key: "host")
        expectClean("https://tracker-1.invalid:8080/announce", key: "announce")
    }

    @Test("localhost passes")
    func localhostPasses() {
        expectClean("localhost:51413", key: "host")
    }

    @Test(".onion host is a leak")
    func onionFails() {
        expectLeak("xyz.onion", key: "host")
        expectLeak("contact us at xyz.onion", key: "lastAnnounceResult")
    }

    @Test("hostname-looking tokens in fuzzed names pass")
    func hostShapeInNamePasses() {
        expectClean("qwer.ty 42.5", key: "name")
    }

    // MARK: - Passkey remnants

    @Test("query string on a tracker URL is a leak")
    func passkeyQueryFails() {
        expectLeak("https://tracker-1.invalid/announce?passkey=abc123", key: "announce")
    }

    @Test("unscrubbed URL in free text is a leak")
    func unscrubbedURLFails() {
        expectLeak("see https://example.com/faq for details", key: "lastAnnounceResult")
    }

    // MARK: - Passthrough fields

    @Test("version strings and client names are not scanned")
    func benignPassthrough() {
        expectClean("4.1.2 (f234716f3e)", key: "version")
        expectClean("Transmission 4.0.6", key: "clientName")
        expectClean("qBittorrent 4.6.7", key: "clientName")
    }

    // MARK: - Whole-tree

    @Test("a real IP injected anywhere in the redacted tree refuses the file")
    func injectedLeakRefuses() throws {
        let raw = SnapshotFixtures.rawSnapshot()
        let (tree, _) = try SnapshotRedactor().redact(raw)

        var leaking = tree
        var torrents = try #require(leaking["torrents"] as? [Any])
        var first = try #require(torrents[0] as? [String: Any])
        var peers = try #require(first["peers"] as? [Any])
        var peer = try #require(peers[0] as? [String: Any])
        peer["address"] = "8.8.8.8:51413"
        peers[0] = peer
        first["peers"] = peers
        torrents[0] = first
        leaking["torrents"] = torrents

        #expect(throws: SnapshotError.self) {
            try SnapshotLeakChecker.check(leaking)
        }
    }

    @Test("the fully redacted fixture passes the leak check")
    func redactedFixturePasses() throws {
        let raw = SnapshotFixtures.rawSnapshot()
        let (tree, _) = try SnapshotRedactor().redact(raw)
        // Default capture: names kept, trackers anonymized.
        #expect(throws: Never.self) {
            try SnapshotLeakChecker.check(tree, namesKept: true, anonymizeTrackers: true)
        }
    }

    @Test("kept-tracker variant passes the leak check (passkeys still stripped)")
    func keptTrackersFixturePasses() throws {
        let raw = SnapshotFixtures.rawSnapshot()
        let (tree, _) = try SnapshotRedactor(options: SnapshotRedactionOptions(anonymizeTrackers: false))
            .redact(raw)
        #expect(throws: Never.self) {
            try SnapshotLeakChecker.check(tree, namesKept: true, anonymizeTrackers: false)
        }
    }
}
