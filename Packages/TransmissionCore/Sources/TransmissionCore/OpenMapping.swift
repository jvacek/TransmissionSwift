import Foundation

/// One "Open with…" entry for a server profile. The `template` is a URI
/// template describing how the daemon's download folders are reachable from
/// this Mac (see `MappingTemplate` for placeholder substitution).
public struct OpenMapping: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var template: String
    /// Bundle ID of the app that should receive the URL (e.g.
    /// `com.google.Chrome`). nil = the system default handler.
    public var applicationBundleID: String?

    public init(
        id: UUID = UUID(),
        name: String,
        template: String,
        applicationBundleID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.template = template
        self.applicationBundleID = applicationBundleID
    }

    /// `applicationBundleID` is `decodeIfPresent` so mappings saved before it
    /// existed still load. `encode(to:)` stays synthesized.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        template = try container.decode(String.self, forKey: .template)
        applicationBundleID = try container.decodeIfPresent(String.self, forKey: .applicationBundleID)
    }
}
