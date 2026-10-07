import AppIntents
import CoreSpotlight
import TransmissionCore

/// One torrent on a server, selectable in Shortcuts and indexable in Spotlight.
struct TorrentEntity: AppEntity, Identifiable, Hashable, Sendable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Torrent")
    static let defaultQuery = TorrentEntityQuery()

    let id: String
    let name: String
    /// The owning profile's UUID string, carried so `OpenTorrentIntent` can switch
    /// to the right server.
    let serverID: String

    init(id: String, name: String, serverID: String) {
        self.id = id
        self.name = name
        self.serverID = serverID
    }

    init(torrent: Torrent, serverID: String) {
        self.init(id: String(torrent.id), name: torrent.name, serverID: serverID)
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

extension TorrentEntity: IndexedEntity {
    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet(contentType: .item)
        attributes.title = name
        attributes.keywords = ["Transmission", "torrent", name]
        return attributes
    }
}

/// Resolves the torrents a server exposes. Shared by the query and the
/// "Get Torrents" action.
enum TorrentCatalog {
    static func entities(profile: ServerProfile, service: any TorrentService) async -> [TorrentEntity] {
        let serverID = profile.id.uuidString
        let torrents = (try? await service.torrents()) ?? []
        return torrents.map { TorrentEntity(torrent: $0, serverID: serverID) }
    }

    static func entities(server: ServerEntity?) async -> [TorrentEntity] {
        guard let environment = AppEnvironment.current,
            let profile = environment.resolve(server),
            let service = environment.service(for: profile)
        else { return [] }
        return await entities(profile: profile, service: service)
    }

    /// The `[Torrent]` an action should target: the selected torrents, or every
    /// torrent when none are selected.
    static func targets(_ selected: [TorrentEntity]?, service: any TorrentService) async -> [Torrent] {
        let all = (try? await service.torrents()) ?? []
        let ids = Set((selected ?? []).compactMap { Int($0.id) })
        return ids.isEmpty ? all : all.filter { ids.contains($0.id) }
    }
}

/// The torrent picker. It learns the selected server from whichever carrying
/// intent is being configured, so the list is scoped to that server.
struct TorrentEntityQuery: EntityQuery {
    @IntentParameterDependency<SetTorrentSpeedLimitsIntent>(\.$server) var setLimits
    @IntentParameterDependency<PauseTorrentsIntent>(\.$server) var pause
    @IntentParameterDependency<ResumeTorrentsIntent>(\.$server) var resume
    @IntentParameterDependency<RemoveTorrentsIntent>(\.$server) var remove
    @IntentParameterDependency<VerifyTorrentsIntent>(\.$server) var verify
    @IntentParameterDependency<ReannounceTorrentsIntent>(\.$server) var reannounce
    @IntentParameterDependency<GetTorrentStatsIntent>(\.$server) var stats

    private var server: ServerEntity? {
        setLimits?.server ?? pause?.server ?? resume?.server ?? remove?.server
            ?? verify?.server ?? reannounce?.server ?? stats?.server
    }

    func entities(for identifiers: [String]) async throws -> [TorrentEntity] {
        let wanted = Set(identifiers)
        return await TorrentCatalog.entities(server: server).filter { wanted.contains($0.id) }
    }

    func suggestedEntities() async throws -> [TorrentEntity] {
        await TorrentCatalog.entities(server: server)
    }
}
