import Foundation
import Testing

@testable import TransmissionSwift

/// The donation log is what lets Spotlight pruning survive a relaunch: it has to
/// remember the previous set on disk, not just in memory.
struct SpotlightDonationLogTests {
    private func makeDefaults() -> (UserDefaults, String) {
        let name = "SpotlightDonationLogTests-\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    @Test func pruneReportsRemovedAndSurvivesRelaunch() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        let first = SpotlightDonationLog(defaults: defaults, key: "log")
        #expect(first.prune(serverID: "a", current: ["a/1", "a/2", "a/3"]) == [])

        // A fresh instance stands in for a relaunch: it still knows what was
        // donated, so a torrent removed while the app was closed is reported.
        let afterRelaunch = SpotlightDonationLog(defaults: defaults, key: "log")
        let removed = afterRelaunch.prune(serverID: "a", current: ["a/1", "a/3"])
        #expect(Set(removed) == ["a/2"])
    }

    @Test func logsAreKeptPerServer() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let log = SpotlightDonationLog(defaults: defaults, key: "log")

        #expect(log.prune(serverID: "a", current: ["a/1"]) == [])
        #expect(log.prune(serverID: "b", current: ["b/1"]) == [])
        // Pruning one server must not disturb another's bookkeeping.
        #expect(log.prune(serverID: "b", current: []) == ["b/1"])
        #expect(log.prune(serverID: "a", current: []) == ["a/1"])
    }

    @Test func forgetDropsIdsFromTheLog() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let log = SpotlightDonationLog(defaults: defaults, key: "log")

        _ = log.prune(serverID: "a", current: ["a/1", "a/2"])
        log.forget(serverID: "a", ids: ["a/1"])
        // a/1 was forgotten explicitly, so pruning to nothing reports only a/2.
        #expect(log.prune(serverID: "a", current: []) == ["a/2"])
    }
}
