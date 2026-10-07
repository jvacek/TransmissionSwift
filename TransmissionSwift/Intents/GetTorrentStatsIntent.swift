import AppIntents
import TransmissionCore

/// Structured torrent statistics, so Shortcuts can chain individual fields
/// (counts, speeds) instead of parsing a string.
struct TorrentStatsEntity: TransientAppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Torrent Stats")

    @Property(title: "Summary") var summary: String
    @Property(title: "Name") var name: String
    @Property(title: "Status") var status: String
    @Property(title: "Progress (%)") var progressPercent: Int
    @Property(title: "Torrents") var torrentCount: Int
    @Property(title: "Active") var activeCount: Int
    @Property(title: "Paused") var pausedCount: Int
    @Property(title: "Download Speed (bytes/s)") var downloadSpeed: Int
    @Property(title: "Upload Speed (bytes/s)") var uploadSpeed: Int
    @Property(title: "Ratio") var ratio: Double

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(summary)")
    }

    init() {
        summary = ""
        name = ""
        status = ""
        progressPercent = 0
        torrentCount = 0
        activeCount = 0
        pausedCount = 0
        downloadSpeed = 0
        uploadSpeed = 0
        ratio = 0
    }

    init(torrents: [Torrent], server: String) {
        let download = torrents.reduce(Int64(0)) { $0 + $1.downloadSpeed }
        let upload = torrents.reduce(Int64(0)) { $0 + $1.uploadSpeed }
        torrentCount = torrents.count
        activeCount = torrents.filter { $0.status == .downloading || $0.status == .seeding }.count
        pausedCount = torrents.filter { $0.status == .paused }.count
        downloadSpeed = Int(download)
        uploadSpeed = Int(upload)
        if let only = torrents.count == 1 ? torrents.first : nil {
            name = only.name
            status = only.status.rawValue.capitalized
            progressPercent = Int((only.progress * 100).rounded())
            ratio = only.ratio
            summary =
                "\(server) · \(only.name): \(status) · \(progressPercent)% · "
                + "↓ \(ColumnFormatters.humanizedSpeed(download)) ↑ \(ColumnFormatters.humanizedSpeed(upload))"
        } else {
            name = ""
            status = ""
            progressPercent = 0
            ratio = 0
            summary =
                "\(server): \(torrentCount) torrents · \(activeCount) active · \(pausedCount) paused · "
                + "↓ \(ColumnFormatters.humanizedSpeed(download)) ↑ \(ColumnFormatters.humanizedSpeed(upload))"
        }
    }
}

/// Reports counts and speeds for a server's torrents — one torrent or the whole
/// list.
struct GetTorrentStatsIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Torrent Stats"
    static var description: IntentDescription? {
        IntentDescription(
            "Reports counts and transfer speeds for a server's torrents, or a single torrent's progress."
        )
    }
    static let openAppWhenRun = false

    @Parameter(title: "Server")
    var server: ServerEntity?

    @Parameter(title: "Torrents")
    var torrents: [TorrentEntity]?

    func perform() async throws -> some IntentResult & ReturnsValue<TorrentStatsEntity> & ProvidesDialog {
        let environment = try AppEnvironment.require()
        let (profile, service) = try environment.requireService(server)
        let targets = await TorrentCatalog.targets(torrents, service: service)
        guard !targets.isEmpty else {
            throw IntentError(message: "No matching torrents on \(profile.label).")
        }
        let stats = TorrentStatsEntity(torrents: targets, server: profile.label)
        return .result(value: stats, dialog: "\(stats.summary)")
    }
}
