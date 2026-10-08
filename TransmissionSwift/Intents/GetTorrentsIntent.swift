import AppIntents
import TransmissionCore

/// The status buckets a shortcut can filter torrents by — the same set as the
/// app's sidebar (`TorrentStatusFilter`), plus `All` to clear the filter. Kept
/// in the app target so `TransmissionCore` stays AppIntents-free.
enum TorrentStatusOption: String, AppEnum, CaseIterable, Sendable {
    case all
    case downloading
    case seeding
    case active
    case paused
    case checking
    case queued
    case error

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Torrent Status")
    static let caseDisplayRepresentations: [TorrentStatusOption: DisplayRepresentation] = [
        .all: "All",
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
        case .all: .all
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
/// loop over them. Also donates the result to Spotlight.
struct GetTorrentsIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Torrents"
    static var description: IntentDescription? {
        IntentDescription(
            "Returns the torrents on a Transmission server, so a shortcut can pick one or loop over them. The filters are combined with AND: a torrent must match every filter you set, and a filter you leave blank is ignored."
        )
    }
    static let openAppWhenRun = false

    @Parameter(title: "Server")
    var server: ServerEntity?

    @Parameter(
        title: "Status", description: "Only torrents in this state. Defaults to All.",
        default: .all)
    var status: TorrentStatusOption?

    @Parameter(title: "Label", description: "Only torrents carrying this label.")
    var label: String?

    @Parameter(title: "Tracker", description: "Only torrents whose primary tracker is this host.")
    var tracker: String?

    @Parameter(title: "Search", description: "Only torrents whose name contains this text.")
    var search: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Get torrents on \(\.$server)") {
            \.$status
            \.$label
            \.$tracker
            \.$search
        }
    }

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
        await SpotlightIndexer.indexTorrents(entities, serverID: serverID)
        let dialog =
            entities.isEmpty
            ? "No matching torrents on \(profile.label)."
            : "\(entities.count) torrent\(entities.count == 1 ? "" : "s") on \(profile.label)."
        return .result(value: entities, dialog: "\(dialog)")
    }
}
