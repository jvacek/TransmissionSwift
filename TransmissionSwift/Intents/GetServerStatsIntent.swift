import AppIntents
import TransmissionCore
import TransmissionRPC

/// Server-wide stats as a structured result, so a shortcut can chain individual
/// fields (counts, speeds) instead of parsing the dialog string.
struct ServerStatsEntity: TransientAppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Server Stats")

    @Property(title: "Server") var server: String
    @Property(title: "Summary") var summary: String
    @Property(title: "Torrents") var torrentCount: Int
    @Property(title: "Active") var activeCount: Int
    @Property(title: "Paused") var pausedCount: Int
    @Property(title: "Download Speed (bytes/s)") var downloadSpeed: Int
    @Property(title: "Upload Speed (bytes/s)") var uploadSpeed: Int

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(summary)")
    }

    init() {
        server = ""
        summary = ""
        torrentCount = 0
        activeCount = 0
        pausedCount = 0
        downloadSpeed = 0
        uploadSpeed = 0
    }

    init(stats: SessionStats, server: String) {
        self.server = server
        torrentCount = stats.torrentCount
        activeCount = stats.activeTorrentCount
        pausedCount = stats.pausedTorrentCount
        downloadSpeed = Int(stats.downloadSpeed)
        uploadSpeed = Int(stats.uploadSpeed)
        summary =
            "\(server): \(torrentCount) torrents · \(activeCount) active · "
            + "\(pausedCount) paused · ↓ \(ColumnFormatters.humanizedSpeed(stats.downloadSpeed)) "
            + "↑ \(ColumnFormatters.humanizedSpeed(stats.uploadSpeed))"
    }

    /// Derived stats for services that don't report `session-stats` (snapshot
    /// replay). Counts and speeds come from the torrent list. Note: the daemon's
    /// `activeTorrentCount` counts every non-stopped torrent, so `activeCount`
    /// here can read lower than `sessionStats()` for the same state.
    init(torrents: [Torrent], server: String) {
        self.init()
        self.server = server
        torrentCount = torrents.count
        activeCount = torrents.filter(\.isActive).count
        pausedCount = torrents.filter { $0.status == .paused }.count
        let down = torrents.reduce(Int64(0)) { $0 + $1.downloadSpeed }
        let up = torrents.reduce(Int64(0)) { $0 + $1.uploadSpeed }
        downloadSpeed = Int(down)
        uploadSpeed = Int(up)
        summary =
            "\(server): \(torrentCount) torrents · \(activeCount) active · "
            + "\(pausedCount) paused · ↓ \(ColumnFormatters.humanizedSpeed(down)) "
            + "↑ \(ColumnFormatters.humanizedSpeed(up))"
    }
}

/// Reads torrent counts and transfer speeds from a Transmission server.
struct GetServerStatsIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Server Stats"
    static var description: IntentDescription? {
        IntentDescription(
            "Returns torrent counts and transfer speeds from a Transmission server.")
    }
    static let openAppWhenRun = false

    @Parameter(title: "Server")
    var server: ServerEntity?

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<ServerStatsEntity> {
        let environment = try AppEnvironment.require()
        let (profile, service) = try environment.requireService(server)

        // Prefer the daemon's own session-stats; fall back to aggregating the
        // torrent list so replay/snapshot mode (which carries no stats) still
        // answers.
        let stats: ServerStatsEntity
        if let sessionStats = await service.sessionStats() {
            stats = ServerStatsEntity(stats: sessionStats, server: profile.label)
        } else if let torrents = try? await service.torrents() {
            stats = ServerStatsEntity(torrents: torrents, server: profile.label)
        } else {
            throw IntentError(message: "Couldn't reach “\(profile.label)”.")
        }
        return .result(value: stats, dialog: "\(stats.summary)")
    }
}
