import AppIntents
import TransmissionCore
import TransmissionRPC

/// Reads torrent counts and transfer speeds from a Transmission server.
struct GetServerStatsIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Server Stats"
    static var description: IntentDescription? {
        IntentDescription(
            "Shows torrent counts and transfer speeds from a Transmission server.")
    }
    static let openAppWhenRun = false

    @Parameter(title: "Server")
    var server: ServerEntity?

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let environment = try AppEnvironment.require()
        let (profile, service) = try environment.requireService(server)

        // Prefer the daemon's own session-stats; fall back to aggregating the
        // torrent list so replay/snapshot mode (which carries no stats) still
        // answers.
        let summary: String
        if let stats = await service.sessionStats() {
            summary = Self.summary(stats, server: profile.label)
        } else if let torrents = try? await service.torrents() {
            summary = Self.summary(torrents, server: profile.label)
        } else {
            throw IntentError(message: "Couldn't reach “\(profile.label)”.")
        }
        return .result(value: summary, dialog: "\(summary)")
    }

    nonisolated static func summary(_ stats: SessionStats, server: String) -> String {
        let down = ColumnFormatters.humanizedSpeed(stats.downloadSpeed)
        let up = ColumnFormatters.humanizedSpeed(stats.uploadSpeed)
        return
            "\(server): \(stats.torrentCount) torrents · \(stats.activeTorrentCount) active · "
            + "\(stats.pausedTorrentCount) paused · ↓ \(down) ↑ \(up)"
    }

    /// Derived summary for services that don't report `session-stats` (snapshot
    /// replay). Counts and speeds come from the torrent list.
    nonisolated static func summary(_ torrents: [Torrent], server: String) -> String {
        let active = torrents.filter { $0.status == .downloading || $0.status == .seeding }.count
        let paused = torrents.filter { $0.status == .paused }.count
        let down = torrents.reduce(Int64(0)) { $0 + $1.downloadSpeed }
        let up = torrents.reduce(Int64(0)) { $0 + $1.uploadSpeed }
        return
            "\(server): \(torrents.count) torrents · \(active) active · \(paused) paused · "
            + "↓ \(ColumnFormatters.humanizedSpeed(down)) ↑ \(ColumnFormatters.humanizedSpeed(up))"
    }
}
