import AppIntents
import TransmissionCore

/// Free space as a structured result: raw bytes plus a humanized string, so a
/// shortcut can both branch on the number and show a unit-bearing value. The
/// humanized field is what carries the unit (e.g. "12.3 GB").
struct FreeSpaceEntity: TransientAppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Free Space")

    @Property(title: "Bytes") var bytes: Int
    @Property(title: "Free Space") var humanized: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(humanized)")
    }

    init() {
        bytes = 0
        humanized = ""
    }

    init(bytes: Int64) {
        self.bytes = Int(bytes)
        humanized = ColumnFormatters.humanizedSize(bytes)
    }
}

/// Returns the free space on a server's download volume, so a shortcut can
/// branch on it.
struct GetFreeSpaceIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Free Space"
    static var description: IntentDescription? {
        IntentDescription(
            "Returns the free space on the download volume of a Transmission server.")
    }
    static let openAppWhenRun = false

    @Parameter(title: "Server")
    var server: ServerEntity?

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<FreeSpaceEntity> {
        let environment = try AppEnvironment.require()
        let (profile, service) = try environment.requireService(server)
        guard let bytes = await service.freeSpace() else {
            throw IntentError(message: "“\(profile.label)” didn't report its free space.")
        }
        let free = FreeSpaceEntity(bytes: bytes)
        return .result(value: free, dialog: "\(free.humanized) free on \(profile.label).")
    }
}
