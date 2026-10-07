import AppIntents
import TransmissionCore

/// Returns a server's torrents as entities, so a shortcut can choose one or
/// loop over them. Also donates them to Spotlight.
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

    func perform() async throws -> some IntentResult & ReturnsValue<[TorrentEntity]> & ProvidesDialog {
        let environment = try AppEnvironment.require()
        let (profile, service) = try environment.requireService(server)
        let entities = await TorrentCatalog.entities(profile: profile, service: service)
        await SpotlightIndexer.indexTorrents(entities)
        let dialog =
            entities.isEmpty
            ? "No torrents on \(profile.label)."
            : "\(entities.count) torrent\(entities.count == 1 ? "" : "s") on \(profile.label)."
        return .result(value: entities, dialog: "\(dialog)")
    }
}
