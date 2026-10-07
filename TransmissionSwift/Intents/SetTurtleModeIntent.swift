import AppIntents
import TransmissionCore

/// Turns a server's alternative (turtle) speed limits on or off.
struct SetTurtleModeIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Turtle Mode"
    static var description: IntentDescription? {
        IntentDescription(
            "Turns a Transmission server's alternative (turtle) speed limits on or off.")
    }
    static let openAppWhenRun = false

    @Parameter(title: "Server")
    var server: ServerEntity?

    @Parameter(title: "Enabled")
    var enabled: Bool

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let environment = try AppEnvironment.require()
        let (profile, service) = try environment.requireService(server)
        do {
            try await service.setAlternativeSpeedEnabled(enabled)
        } catch {
            throw IntentError(message: error.localizedDescription)
        }
        return .result(dialog: "Turtle mode \(enabled ? "enabled" : "disabled") on \(profile.label).")
    }
}
