import AppIntents
import CoreSpotlight
import Synchronization
import TransmissionCore

/// Donates servers and torrents to Spotlight so their `OpenIntent`s have
/// something to open from. Best-effort: a failed index never fails the action.
///
/// Torrents are indexed on demand (`Get Torrents`) rather than on every poll,
/// and removed when they drop out of the donated set, so Spotlight doesn't keep
/// offering torrents that no longer exist.
enum SpotlightIndexer {
    private static let donationLog = SpotlightDonationLog()

    static func indexServers(_ profiles: [ServerProfile]) async {
        try? await CSSearchableIndex.default().indexAppEntities(
            profiles.map(ServerEntity.init(profile:)))
    }

    static func indexTorrents(_ entities: [TorrentEntity], serverID: String) async {
        let removed = donationLog.prune(serverID: serverID, current: Set(entities.map(\.id)))
        if !removed.isEmpty {
            try? await CSSearchableIndex.default().deleteAppEntities(
                identifiedBy: removed, ofType: TorrentEntity.self)
        }
        try? await CSSearchableIndex.default().indexAppEntities(entities)
    }

    /// Drop torrents removed from a server, so a Spotlight hit can't open
    /// something that no longer exists. App-UI removals are pruned the next time
    /// the server's torrents are donated.
    static func deleteTorrents(ids: [String], serverID: String) async {
        guard !ids.isEmpty else { return }
        donationLog.forget(serverID: serverID, ids: ids)
        try? await CSSearchableIndex.default().deleteAppEntities(
            identifiedBy: ids, ofType: TorrentEntity.self)
    }
}

/// The torrent identifiers last donated to Spotlight, per server. Persisted in
/// `UserDefaults` so the "what did I remove?" diff survives a relaunch: a torrent
/// that vanished while the app was closed is otherwise never unindexed. Daemon
/// torrent ids are only unique per server, so the log is keyed by server and
/// holds fully-qualified identifiers (see `TorrentEntity.id`).
final class SpotlightDonationLog: Sendable {
    private let state: Mutex<[String: Set<String>]>
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "spotlightIndexedTorrentIDs") {
        self.defaults = defaults
        self.key = key
        let stored = defaults.dictionary(forKey: key) as? [String: [String]]
        self.state = Mutex((stored ?? [:]).mapValues(Set.init))
    }

    /// Records `current` as the server's donated set and returns the identifiers
    /// that were donated before but are gone now — the ones to unindex.
    func prune(serverID: String, current: Set<String>) -> [String] {
        state.withLock { map in
            let removed = Array((map[serverID] ?? []).subtracting(current))
            map[serverID] = current
            persist(map)
            return removed
        }
    }

    /// Drops explicitly removed identifiers from the log.
    func forget(serverID: String, ids: [String]) {
        state.withLock { map in
            var set = map[serverID] ?? []
            set.subtract(ids)
            map[serverID] = set
            persist(map)
        }
    }

    private func persist(_ map: [String: Set<String>]) {
        defaults.set(map.mapValues(Array.init), forKey: key)
    }
}
