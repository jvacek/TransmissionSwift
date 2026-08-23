import Foundation

/// What should happen to the URL a mapping expands to.
public enum OpenMappingAction: String, Codable, Sendable, Equatable {
    /// Reveal the resolved `file://` URL in Finder (Finder opens and selects it).
    case finder
    /// Open the resolved URL with the system's default handler for its scheme,
    /// or with `OpenMapping.applicationBundleID` when that is set.
    case open
}

/// One "Open with…" entry for a server profile. The `template` is a URI
/// template describing how the daemon's download folders are reachable from
/// this Mac (see `MappingTemplate` for placeholder substitution).
public struct OpenMapping: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var template: String
    /// What to do with the expanded URL.
    public var action: OpenMappingAction
    /// Bundle ID of the app that should receive the URL (e.g.
    /// `com.google.Chrome`). nil = the system default handler.
    public var applicationBundleID: String?
    /// A security-scoped bookmark for the folder the user granted access to, so
    /// a sandboxed app can hand the mapping's `file://` URLs to another app via
    /// LaunchServices. nil until the user allows access once.
    public var accessBookmark: Data?

    public init(
        id: UUID = UUID(),
        name: String,
        template: String,
        action: OpenMappingAction = .open,
        applicationBundleID: String? = nil,
        accessBookmark: Data? = nil
    ) {
        self.id = id
        self.name = name
        self.template = template
        self.action = action
        self.applicationBundleID = applicationBundleID
        self.accessBookmark = accessBookmark
    }

    /// `action`, `applicationBundleID` and `accessBookmark` are `decodeIfPresent`
    /// so mappings saved before they existed still load. `encode(to:)` stays
    /// synthesized.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        template = try container.decode(String.self, forKey: .template)
        action = try container.decodeIfPresent(OpenMappingAction.self, forKey: .action) ?? .open
        applicationBundleID = try container.decodeIfPresent(String.self, forKey: .applicationBundleID)
        accessBookmark = try container.decodeIfPresent(Data.self, forKey: .accessBookmark)
    }
}
