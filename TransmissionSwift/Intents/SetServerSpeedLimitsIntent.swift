import AppIntents
import TransmissionCore

/// Sets a server's global (non-turtle) download and upload speed limits, in
/// KB/s, and whether each limit is enforced.
struct SetServerSpeedLimitsIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Server Speed Limits"
    static var description: IntentDescription? {
        IntentDescription(
            "Sets a Transmission server's global download and upload speed limits (KB/s).")
    }
    static let openAppWhenRun = false

    @Parameter(title: "Server")
    var server: ServerEntity?

    @Parameter(title: "Limit Download Speed")
    var downloadLimited: Bool?

    @Parameter(title: "Download Limit (KB/s)")
    var downloadLimitKBps: Int?

    @Parameter(title: "Limit Upload Speed")
    var uploadLimited: Bool?

    @Parameter(title: "Upload Limit (KB/s)")
    var uploadLimitKBps: Int?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let environment = try AppEnvironment.require()
        let (profile, service) = try environment.requireService(server)
        guard let mutations = service.mutations else {
            throw IntentError(message: "This server is read-only.")
        }

        var patch = SessionSettingsPatch()
        patch.downLimited = downloadLimited
        patch.downLimitKBps = downloadLimitKBps
        patch.upLimited = uploadLimited
        patch.upLimitKBps = uploadLimitKBps
        guard !patch.isEmpty else {
            throw IntentError(message: "No speed-limit changes were specified.")
        }

        do {
            try await mutations.applySessionSettings(patch)
        } catch {
            throw IntentError(message: error.localizedDescription)
        }
        return .result(dialog: "Updated speed limits on \(profile.label).")
    }
}
