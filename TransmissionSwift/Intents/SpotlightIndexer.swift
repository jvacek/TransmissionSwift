import AppIntents
import CoreSpotlight
import Synchronization
import TransmissionCore

/// Donates servers and torrents to Spotlight so their `OpenIntent`s have
/// something to open from. Best-effort: a failed index never fails the action.
///
/// Torrents are indexed on demand (`Get Torrents`) rather than on every poll,
/// and removed when they drop out of the donated set, so Spotlight doesn't keep
/// offering torrents that no longer exist. Daemon torrent ids are only unique
/// per server, so the last donated set is tracked per server.
enum SpotlightIndexer {
    private static let indexedTorrentIDs = Mutex<[String: Set<String>]>([:])

    static func indexServers(_ profiles: [ServerProfile]) async {
        try? await CSSearchableIndex.default().indexAppEntities(
            profiles.map(ServerEntity.init(profile:)))
    }

    static func indexTorrents(_ entities: [TorrentEntity], serverID: String) async {
        let current = Set(entities.map(\.id))
        let removed = (indexedTorrentIDs.withLock { $0[serverID] } ?? []).subtracting(current)
        if !removed.isEmpty {
            try? await CSSearchableIndex.default().deleteAppEntities(
                identifiedBy: Array(removed), ofType: TorrentEntity.self)
        }
        indexedTorrentIDs.withLock { $0[serverID] = current }
        try? await CSSearchableIndex.default().indexAppEntities(entities)
    }

    /// Drop torrents removed from a server, so a Spotlight hit can't open
    /// something that no longer exists. App-UI removals are pruned the next time
    /// the server's torrents are donated.
    static func deleteTorrents(ids: [String], serverID: String) async {
        guard !ids.isEmpty else { return }
        indexedTorrentIDs.withLock {
            var set = $0[serverID] ?? []
            set.subtract(ids)
            $0[serverID] = set
        }
        try? await CSSearchableIndex.default().deleteAppEntities(
            identifiedBy: ids, ofType: TorrentEntity.self)
    }
}
