import AppIntents
import CoreSpotlight
import TransmissionCore

/// One torrent on a server, selectable in Shortcuts and indexable in Spotlight.
/// The `@Property` fields are what a shortcut can chain out of the list.
struct TorrentEntity: AppEntity, Identifiable, Hashable, Sendable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Torrent")
    static let defaultQuery = TorrentEntityQuery()

    /// `"<serverUUID>/<torrentID>"`. Daemon torrent ids are only unique per
    /// server, so the server is baked in: an identifier of just the torrent id
    /// would collide two servers' torrent `1` in Spotlight and Shortcuts.
    let id: String
    /// The owning profile's UUID string, carried so `OpenTorrentIntent` can switch
    /// to the right server.
    let serverID: String
    /// The daemon's torrent id, the value the service actions take.
    let torrentID: Int

    @Property(title: "Name") var name: String
    @Property(title: "Status") var status: String
    @Property(title: "Progress (%)") var progressPercent: Int
    @Property(title: "Size (bytes)") var size: Int
    @Property(title: "Download Speed (bytes/s)") var downloadSpeed: Int
    @Property(title: "Upload Speed (bytes/s)") var uploadSpeed: Int
    @Property(title: "Ratio") var ratio: Double
    @Property(title: "Labels") var labels: String
    @Property(title: "Tracker") var tracker: String

    init(torrent: Torrent, serverID: String) {
        self.serverID = serverID
        self.torrentID = torrent.id
        self.id = "\(serverID)/\(torrent.id)"
        name = torrent.name
        status = torrent.status.rawValue.capitalized
        progressPercent = Int((torrent.progress * 100).rounded())
        size = Int(torrent.size)
        downloadSpeed = Int(torrent.downloadSpeed)
        uploadSpeed = Int(torrent.uploadSpeed)
        ratio = torrent.ratio
        labels = torrent.labels.joined(separator: ", ")
        tracker = torrent.primaryTracker
    }

    // `@Property` wrappers aren't `Hashable`, so identity is explicit.
    static func == (lhs: TorrentEntity, rhs: TorrentEntity) -> Bool {
        lhs.id == rhs.id && lhs.serverID == rhs.serverID
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(serverID)
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

    /// A server's torrents for an action to operate on. Throws when the daemon
    /// can't be reached, so the action reports the real cause instead of a
    /// misleading "no matching torrents".
    static func torrents(profile: ServerProfile, service: any TorrentService) async throws
        -> [Torrent]
    {
        do {
            return try await service.torrents()
        } catch {
            throw IntentError(message: "Couldn't reach “\(profile.label)”.")
        }
    }

    /// The `[Torrent]` an action should target: the selected torrents, or every
    /// torrent when none are selected. Selections are scoped to `profile` so an
    /// entity picked from another server can't silently target this server's
    /// same-numbered torrent.
    static func targets(
        _ selected: [TorrentEntity]?, profile: ServerProfile, service: any TorrentService
    ) async throws -> [Torrent] {
        let all = try await torrents(profile: profile, service: service)
        guard let selected, !selected.isEmpty else { return all }
        let serverID = profile.id.uuidString
        let ids = Set(selected.filter { $0.serverID == serverID }.map(\.torrentID))
        return all.filter { ids.contains($0.id) }
    }
}

/// The torrent picker. It learns the selected server from whichever carrying
/// intent is being configured, so the list is scoped to that server.
///
/// Add a `@IntentParameterDependency` here for any new intent that takes both a
/// `server` and `torrents`, or its picker falls back to the active profile.
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
