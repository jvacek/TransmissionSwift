import AppIntents
import TransmissionCore

/// Returns the free space (in bytes) on a server's download volume, so a
/// shortcut can branch on it.
struct GetFreeSpaceIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Free Space"
    static var description: IntentDescription? {
        IntentDescription(
            "Returns the free space, in bytes, on the download volume of a Transmission server.")
    }
    static let openAppWhenRun = false

    @Parameter(title: "Server")
    var server: ServerEntity?

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Int> {
        let environment = try AppEnvironment.require()
        let (profile, service) = try environment.requireService(server)
        guard let bytes = await service.freeSpace() else {
            throw IntentError(message: "“\(profile.label)” didn't report its free space.")
        }
        let human = ColumnFormatters.humanizedSize(bytes)
        return .result(value: Int(bytes), dialog: "\(human) free on \(profile.label).")
    }
}
