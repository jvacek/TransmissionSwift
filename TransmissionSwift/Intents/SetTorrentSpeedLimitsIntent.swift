import AppIntents
import TransmissionCore

/// Sets per-torrent download and upload speed limits, in KB/s. With no torrents
/// chosen, applies to every torrent on the server.
struct SetTorrentSpeedLimitsIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Torrent Speed Limits"
    static var description: IntentDescription? {
        IntentDescription(
            "Sets per-torrent download and upload speed limits (KB/s) on the given torrents."
        )
    }
    static let openAppWhenRun = false

    @Parameter(title: "Server")
    var server: ServerEntity?

    @Parameter(title: "Torrents")
    var torrents: [TorrentEntity]

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
        // Mirror the server-level intent: enabling a limit without a value is
        // ambiguous (it would silently reuse whatever limit the torrent already
        // carries), so require the value.
        if downloadLimited == true, downloadLimitKBps == nil {
            throw IntentError(message: "Set a download limit value, or turn the download limit off.")
        }
        if uploadLimited == true, uploadLimitKBps == nil {
            throw IntentError(message: "Set an upload limit value, or turn the upload limit off.")
        }

        let environment = try AppEnvironment.require()
        let (profile, mutations, targets) = try await environment.mutableTargets(
            server: server, torrents: torrents)

        do {
            try await mutations.setSpeedLimits(targets.map(\.id), patch)
        } catch {
            throw IntentError(message: error.localizedDescription)
        }

        return .result(
            dialog:
                "Updated speed limits for \(targets.count) torrent\(targets.count == 1 ? "" : "s") on \(profile.label)."
        )
    }
}
