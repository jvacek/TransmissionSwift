import AppIntents
import CoreSpotlight
import Foundation
import TransmissionCore

/// One torrent on a server, selectable in Shortcuts, indexable in Spotlight and
/// openable by URL. The `@Property` fields are what a shortcut can chain out of
/// the list.
struct TorrentEntity: AppEntity, URLRepresentableEntity, Identifiable, Hashable, Sendable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Torrent")
    static let defaultQuery = TorrentEntityQuery()

    /// The deep link the system opens the entity with, e.g.
    /// `transmissionswift://<serverUUID>/<torrentID>`. See `OpenRequest`.
    static var urlRepresentation = URLRepresentation("transmissionswift://\(.id)")

    /// `"<serverUUID>/<torrentID>"`. Daemon torrent ids are only unique per
    /// server, so the server is baked in: an identifier of just the torrent id
    /// would collide two servers' torrent `1` in Spotlight and Shortcuts.
    let id: String
    /// The owning profile's UUID string, carried so an action can scope a
    /// selection to the right server.
    let serverID: String
    /// The daemon's torrent id, the value the service actions take.
    let torrentID: Int

    @Property(title: "Name") var name: String
    @Property(title: "Status") var status: String
    @Property(title: "Progress (%)") var progressPercent: Int
    @Property(title: "Size") var size: Measurement<UnitInformationStorage>
    @Property(title: "Download Speed (bytes/s)") var downloadSpeed: Int
    @Property(title: "Upload Speed (bytes/s)") var uploadSpeed: Int
    @Property(title: "Ratio") var ratio: Double
    @Property(title: "Labels") var labels: String
    @Property(title: "Tracker") var tracker: String
    /// Whether this torrent enforces its own download/upload speed limits. The
    /// limit values below are always present, so this pair is what tells a
    /// shortcut whether they mean anything (0 is "no limit", not "unset").
    @Property(title: "Download Limited") var downloadLimited: Bool
    @Property(title: "Download Limit (KB/s)") var downloadLimitKBps: Int
    @Property(title: "Upload Limited") var uploadLimited: Bool
    @Property(title: "Upload Limit (KB/s)") var uploadLimitKBps: Int

    init(torrent: Torrent, serverID: String) {
        self.serverID = serverID
        self.torrentID = torrent.id
        self.id = "\(serverID)/\(torrent.id)"
        name = torrent.name
        status = torrent.status.rawValue.capitalized
        progressPercent = Int((torrent.progress * 100).rounded())
        size = Measurement(value: Double(torrent.size), unit: .bytes)
        downloadSpeed = Int(torrent.downloadSpeed)
        uploadSpeed = Int(torrent.uploadSpeed)
        ratio = torrent.ratio
        labels = torrent.labels.joined(separator: ", ")
        tracker = torrent.primaryTracker
        downloadLimited = torrent.options.downloadLimited
        downloadLimitKBps = torrent.options.downloadLimitKBps
        uploadLimited = torrent.options.uploadLimited
        uploadLimitKBps = torrent.options.uploadLimitKBps
    }

    /// Splits a `"<serverUUID>/<torrentID>"` identifier, or nil when it isn't one.
    static func parse(identifier: String) -> (serverID: String, torrentID: Int)? {
        let parts = identifier.split(separator: "/", maxSplits: 1)
        guard parts.count == 2, let torrentID = Int(parts[1]) else { return nil }
        return (String(parts[0]), torrentID)
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
    static func entities(profile: ServerProfile, service: any TorrentReading) async -> [TorrentEntity] {
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
    static func torrents(profile: ServerProfile, service: any TorrentReading) async throws
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
        _ selected: [TorrentEntity]?, profile: ServerProfile, service: any TorrentReading
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

    /// Resolves identifiers without needing a server context: the server UUID is
    /// baked into the identifier, so a torrent can be resolved even when it
    /// belongs to a profile other than the active one. That is what lets
    /// `Open Torrent` accept a torrent from `Get Torrents` instead of falling
    /// back to a picker.
    func entities(for identifiers: [String]) async throws -> [TorrentEntity] {
        guard let environment = AppEnvironment.current else { return [] }
        let parsed = identifiers.compactMap(TorrentEntity.parse(identifier:))
        var result: [TorrentEntity] = []
        for (serverID, entries) in Dictionary(grouping: parsed, by: \.serverID) {
            guard let uuid = UUID(uuidString: serverID),
                let profile = environment.profile(withID: uuid),
                let service = environment.service(for: profile)
            else { continue }
            let wanted = Set(entries.map(\.torrentID))
            let torrents = (try? await service.torrents()) ?? []
            result +=
                torrents
                .filter { wanted.contains($0.id) }
                .map { TorrentEntity(torrent: $0, serverID: serverID) }
        }
        return result
    }

    func suggestedEntities() async throws -> [TorrentEntity] {
        await TorrentCatalog.entities(server: server)
    }
}
