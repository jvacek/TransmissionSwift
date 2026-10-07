import AppIntents
import TransmissionCore

/// Structured statistics for one torrent, so Shortcuts can chain individual
/// fields (progress, speeds, ratio) instead of parsing a string.
struct TorrentStatsEntity: TransientAppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Torrent Stats")

    @Property(title: "Summary") var summary: String
    @Property(title: "Name") var name: String
    @Property(title: "Status") var status: String
    @Property(title: "Progress (%)") var progressPercent: Int
    @Property(title: "Download Speed (bytes/s)") var downloadSpeed: Int
    @Property(title: "Upload Speed (bytes/s)") var uploadSpeed: Int
    @Property(title: "Peers") var connectedPeerCount: Int
    @Property(title: "Ratio") var ratio: Double

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(summary)")
    }

    init() {
        summary = ""
        name = ""
        status = ""
        progressPercent = 0
        downloadSpeed = 0
        uploadSpeed = 0
        connectedPeerCount = 0
        ratio = 0
    }

    init(torrent: Torrent, server: String) {
        self.init()
        name = torrent.name
        status = torrent.status.rawValue.capitalized
        progressPercent = Int((torrent.progress * 100).rounded())
        downloadSpeed = Int(torrent.downloadSpeed)
        uploadSpeed = Int(torrent.uploadSpeed)
        connectedPeerCount = torrent.connectedPeerCount
        ratio = torrent.ratio
        summary =
            "\(server) · \(name): \(status) · \(progressPercent)% · "
            + "↓ \(ColumnFormatters.humanizedSpeed(torrent.downloadSpeed)) "
            + "↑ \(ColumnFormatters.humanizedSpeed(torrent.uploadSpeed))"
    }
}

/// Reports progress and speeds for one torrent. Server-wide counts and speeds
/// are `GetServerStatsIntent`; this action is always scoped to a torrent.
struct GetTorrentStatsIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Torrent Stats"
    static var description: IntentDescription? {
        IntentDescription(
            "Reports progress and transfer speeds for a single torrent on a Transmission server.")
    }
    static let openAppWhenRun = false

    @Parameter(title: "Server")
    var server: ServerEntity?

    @Parameter(title: "Torrent")
    var torrent: TorrentEntity

    func perform() async throws -> some IntentResult & ReturnsValue<TorrentStatsEntity> & ProvidesDialog {
        let environment = try AppEnvironment.require()
        let (profile, service) = try environment.requireService(server)
        let targets = await TorrentCatalog.targets([torrent], service: service)
        guard let target = targets.first else {
            throw IntentError(message: "That torrent isn't on \(profile.label).")
        }
        let stats = TorrentStatsEntity(torrent: target, server: profile.label)
        return .result(value: stats, dialog: "\(stats.summary)")
    }
}
