import AppIntents
import TransmissionCore

/// The status buckets a shortcut can filter torrents by — the same set as the
/// app's sidebar (`TorrentStatusFilter`). Kept in the app target so
/// `TransmissionCore` stays AppIntents-free.
enum TorrentStatusOption: String, AppEnum, CaseIterable, Sendable {
    case downloading
    case seeding
    case active
    case paused
    case checking
    case queued
    case error

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Torrent Status")
    static let caseDisplayRepresentations: [TorrentStatusOption: DisplayRepresentation] = [
        .downloading: "Downloading",
        .seeding: "Seeding",
        .active: "Active",
        .paused: "Paused",
        .checking: "Checking",
        .queued: "Queued",
        .error: "Error",
    ]

    var filter: TorrentStatusFilter {
        switch self {
        case .downloading: .downloading
        case .seeding: .seeding
        case .active: .active
        case .paused: .paused
        case .checking: .checking
        case .queued: .queued
        case .error: .error
        }
    }
}

/// Returns a server's torrents as entities, so a shortcut can choose one or
/// loop over them. Optional filters narrow the list (AND semantics). Also
/// donates the result to Spotlight.
struct GetTorrentsIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Torrents"
    static var description: IntentDescription? {
        IntentDescription(
            "Returns the torrents on a Transmission server, so a shortcut can pick one or loop over them."
        )
    }
    static let openAppWhenRun = false

    @Parameter(title: "Server")
    var server: ServerEntity?

    @Parameter(title: "Status")
    var status: TorrentStatusOption?

    @Parameter(title: "Label")
    var label: String?

    @Parameter(title: "Tracker")
    var tracker: String?

    @Parameter(title: "Search")
    var search: String?

    func perform() async throws -> some IntentResult & ReturnsValue<[TorrentEntity]> & ProvidesDialog {
        let environment = try AppEnvironment.require()
        let (profile, service) = try environment.requireService(server)

        var selection = TorrentFilterSelection()
        if let status {
            selection.setStatus(status.filter)
        }
        if let label {
            selection.labels = [label]
        }
        if let tracker {
            selection.trackers = [tracker]
        }
        let torrents = try await TorrentCatalog.torrents(profile: profile, service: service)
            .filtered(by: selection)
            .searched(search ?? "")

        let serverID = profile.id.uuidString
        let entities = torrents.map { TorrentEntity(torrent: $0, serverID: serverID) }
        await SpotlightIndexer.indexTorrents(entities)
        let dialog =
            entities.isEmpty
            ? "No matching torrents on \(profile.label)."
            : "\(entities.count) torrent\(entities.count == 1 ? "" : "s") on \(profile.label)."
        return .result(value: entities, dialog: "\(dialog)")
    }
}
