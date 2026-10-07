import AppIntents
import TransmissionCore

/// Sets per-torrent download and upload speed limits, in KB/s. With no torrents
/// chosen, applies to every torrent on the server.
struct SetTorrentSpeedLimitsIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Torrent Speed Limits"
    static var description: IntentDescription? {
        IntentDescription(
            "Sets per-torrent download and upload speed limits (KB/s). Leave Torrents empty to apply to every torrent on the server."
        )
    }
    static let openAppWhenRun = false

    @Parameter(title: "Server")
    var server: ServerEntity?

    @Parameter(title: "Torrents")
    var torrents: [TorrentEntity]?

    @Parameter(title: "Limit Download Speed")
    var downloadLimited: Bool?

    @Parameter(title: "Download Limit (KB/s)")
    var downloadLimitKBps: Int?

    @Parameter(title: "Limit Upload Speed")
    var uploadLimited: Bool?

    @Parameter(title: "Upload Limit (KB/s)")
    var uploadLimitKBps: Int?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        var patch = TorrentSpeedLimitPatch()
        patch.downloadLimited = downloadLimited
        patch.downloadLimitKBps = downloadLimitKBps
        patch.uploadLimited = uploadLimited
        patch.uploadLimitKBps = uploadLimitKBps
        guard !patch.isEmpty else {
            throw IntentError(message: "No speed-limit changes were specified.")
        }

        let environment = try AppEnvironment.require()
        let (profile, service) = try environment.requireService(server)

        let targets = try await TorrentCatalog.targets(torrents, profile: profile, service: service)
        guard !targets.isEmpty else {
            throw IntentError(message: "No matching torrents on \(profile.label).")
        }

        do {
            try await service.setSpeedLimits(targets.map(\.id), patch)
        } catch {
            throw IntentError(message: error.localizedDescription)
        }

        return .result(
            dialog:
                "Updated speed limits for \(targets.count) torrent\(targets.count == 1 ? "" : "s") on \(profile.label)."
        )
    }
}
