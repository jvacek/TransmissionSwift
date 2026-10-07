import AppIntents
import CoreSpotlight
import TransmissionCore

/// Donates servers and torrents to Spotlight so their `OpenIntent`s have
/// something to open from. Best-effort: a failed index never fails the action.
enum SpotlightIndexer {
    static func indexServers(_ profiles: [ServerProfile]) async {
        try? await CSSearchableIndex.default().indexAppEntities(
            profiles.map(ServerEntity.init(profile:)))
    }

    static func indexTorrents(_ entities: [TorrentEntity]) async {
        try? await CSSearchableIndex.default().indexAppEntities(entities)
    }
}
