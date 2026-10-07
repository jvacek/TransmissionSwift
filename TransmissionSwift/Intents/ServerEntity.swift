import AppIntents
import CoreSpotlight
import TransmissionCore

/// One server profile, selectable in Shortcuts. Every TransmissionSwift action
/// takes one of these, so the user picks which daemon it targets; leaving it
/// blank falls back to the active profile.
struct ServerEntity: AppEntity, Identifiable, Hashable, Sendable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Server")
    static let defaultQuery = ServerEntityQuery()

    let id: String
    let label: String

    init(id: String, label: String) {
        self.id = id
        self.label = label
    }

    init(profile: ServerProfile) {
        self.init(id: profile.id.uuidString, label: profile.label)
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(label)")
    }
}

extension ServerEntity: IndexedEntity {
    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet(contentType: .item)
        attributes.title = label
        attributes.keywords = ["Transmission", "server", label]
        return attributes
    }
}

struct ServerEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [ServerEntity] {
        let wanted = Set(identifiers)
        return load().profiles
            .filter { wanted.contains($0.id.uuidString) }
            .map(ServerEntity.init(profile:))
    }

    func suggestedEntities() async throws -> [ServerEntity] {
        load().profiles.map(ServerEntity.init(profile:))
    }

    /// Default when the Server parameter is left blank: the active profile, so
    /// the action behaves like the app would on launch.
    func defaultResult() async -> ServerEntity? {
        guard let active = AppEnvironment.current?.resolve(nil) else { return nil }
        return ServerEntity(profile: active)
    }

    private func load() -> (profiles: [ServerProfile], activeProfileID: UUID?) {
        AppEnvironment.current?.profiles() ?? ([], nil)
    }
}
