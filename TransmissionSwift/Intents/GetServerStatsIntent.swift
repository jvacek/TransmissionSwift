import AppIntents
import Foundation
import TransmissionCore
import TransmissionRPC

/// Server-wide stats as a structured result, so a shortcut can chain individual
/// fields (counts, speeds, free space) instead of parsing the dialog string.
/// Free space lives here rather than in its own action: it is a server fact, and
/// a single "server stats" result is easier to chain than two.
struct ServerStatsEntity: TransientAppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Server Info")

    @Property(title: "Server") var server: String
    /// The profile UUID, so the result is self-describing and a shortcut can
    /// build a `transmissionswift://<serverID>/<torrentID>` link.
    @Property(title: "Server ID") var serverID: String
    @Property(title: "Torrent Count") var torrentCount: Int
    @Property(title: "Active Count") var activeCount: Int
    @Property(title: "Paused Count") var pausedCount: Int
    @Property(title: "Download Speed (bytes/s)") var downloadSpeed: Int
    @Property(title: "Upload Speed (bytes/s)") var uploadSpeed: Int
    @Property(title: "Turtle Mode Active") var turtleModeActive: Bool
    /// A real file-size measurement, so Shortcuts can convert it and shows units,
    /// instead of a bare byte count plus a duplicate humanized string.
    @Property(title: "Free Space") var freeSpace: Measurement<UnitInformationStorage>

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(summary)")
    }

    /// Human-readable one-liner for `displayRepresentation` and tests. Not a
    /// `@Property`, so it doesn't show up as a duplicate in the Shortcuts
    /// variable picker.
    var summary: String {
        let free = ColumnFormatters.humanizedSize(Int64(freeSpace.value))
        let base =
            "\(server): \(torrentCount) torrents · \(activeCount) active · "
            + "\(pausedCount) paused · ↓ \(ColumnFormatters.humanizedSpeed(Int64(downloadSpeed))) "
            + "↑ \(ColumnFormatters.humanizedSpeed(Int64(uploadSpeed))) · \(free) free"
        return turtleModeActive ? base + " · turtle on" : base
    }

    init() {
        server = ""
        serverID = ""
        torrentCount = 0
        activeCount = 0
        pausedCount = 0
        downloadSpeed = 0
        uploadSpeed = 0
        turtleModeActive = false
        freeSpace = Measurement(value: 0, unit: .bytes)
    }

    init(
        stats: SessionStats, server: String, serverID: String, freeSpaceBytes: Int64?,
        turtleModeActive: Bool
    ) {
        self.init()
        self.server = server
        self.serverID = serverID
        torrentCount = stats.torrentCount
        activeCount = stats.activeTorrentCount
        pausedCount = stats.pausedTorrentCount
        downloadSpeed = Int(stats.downloadSpeed)
        uploadSpeed = Int(stats.uploadSpeed)
        self.turtleModeActive = turtleModeActive
        freeSpace = Self.measurement(freeSpaceBytes)
    }

    /// Derived stats for services that don't report `session-stats` (snapshot
    /// replay). Counts and speeds come from the torrent list. Note: the daemon's
    /// `activeTorrentCount` counts every non-stopped torrent, so `activeCount`
    /// here can read lower than `sessionStats()` for the same state.
    init(
        torrents: [Torrent], server: String, serverID: String, freeSpaceBytes: Int64?,
        turtleModeActive: Bool
    ) {
        self.init()
        self.server = server
        self.serverID = serverID
        torrentCount = torrents.count
        activeCount = torrents.filter(\.isActive).count
        pausedCount = torrents.filter { $0.status == .paused }.count
        let down = torrents.reduce(Int64(0)) { $0 + $1.downloadSpeed }
        let up = torrents.reduce(Int64(0)) { $0 + $1.uploadSpeed }
        downloadSpeed = Int(down)
        uploadSpeed = Int(up)
        self.turtleModeActive = turtleModeActive
        freeSpace = Self.measurement(freeSpaceBytes)
    }

    private static func measurement(_ bytes: Int64?) -> Measurement<UnitInformationStorage> {
        Measurement(value: Double(bytes ?? 0), unit: .bytes)
    }
}

/// Reads torrent counts, transfer speeds, free space and turtle state from a
/// Transmission server.
struct GetServerStatsIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Server Info"
    static var description: IntentDescription? {
        IntentDescription(
            "Returns torrent counts, transfer speeds, free space and turtle state from a Transmission server."
        )
    }
    static let openAppWhenRun = false

    @Parameter(title: "Server")
    var server: ServerEntity?

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<ServerStatsEntity> {
        let environment = try AppEnvironment.require()
        let (profile, service) = try environment.requireService(server)

        let freeSpaceBytes = await service.freeSpace()
        let turtleModeActive = await service.isAlternativeSpeedEnabled()

        // Prefer the daemon's own session-stats; fall back to aggregating the
        // torrent list so replay/snapshot mode (which carries no stats) still
        // answers.
        let stats: ServerStatsEntity
        if let sessionStats = await service.sessionStats() {
            stats = ServerStatsEntity(
                stats: sessionStats, server: profile.label, serverID: profile.id.uuidString,
                freeSpaceBytes: freeSpaceBytes, turtleModeActive: turtleModeActive)
        } else if let torrents = try? await service.torrents() {
            stats = ServerStatsEntity(
                torrents: torrents, server: profile.label, serverID: profile.id.uuidString,
                freeSpaceBytes: freeSpaceBytes, turtleModeActive: turtleModeActive)
        } else {
            throw IntentError(message: "Couldn't reach “\(profile.label)”.")
        }
        return .result(value: stats, dialog: "\(stats.summary)")
    }
}
