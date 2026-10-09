import Foundation

/// What should happen to the URL a mapping expands to.
public enum OpenMappingAction: String, Codable, Sendable, Equatable {
    /// Reveal the resolved `file://` URL in Finder (Finder opens and selects it).
    case finder
    /// Open the resolved URL with the system's default handler for its scheme,
    /// or with `OpenMapping.applicationBundleID` when that is set.
    case open
}

/// Which servers an app-wide `OpenMapping` applies to.
public enum MappingServerScope: Sendable, Equatable {
    /// Every server, including servers added later.
    case all
    /// Servers on this Mac or the local network, including ones added later.
    case local
    /// Servers that aren't local, including ones added later.
    case remote
    /// Only the given server profile IDs. A stale ID (a deleted server) simply
    /// matches nothing.
    case only(Set<UUID>)

    public func includes(_ server: ServerProfile) -> Bool {
        switch self {
        case .all: return true
        case .local: return server.isLocal
        case .remote: return !server.isLocal
        case .only(let ids): return ids.contains(server.id)
        }
    }
}

/// Encoded as `"all"`, `"local"`, `"remote"`, or a sorted array of server UUID
/// strings, so the JSON stays readable and stable. Anything unrecognized widens
/// to `.all`.
extension MappingServerScope: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let ids = try? container.decode([UUID].self) {
            self = .only(Set(ids))
            return
        }
        switch try? container.decode(String.self) {
        case "local": self = .local
        case "remote": self = .remote
        default: self = .all
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .all: try container.encode("all")
        case .local: try container.encode("local")
        case .remote: try container.encode("remote")
        case .only(let ids): try container.encode(ids.sorted { $0.uuidString < $1.uuidString })
        }
    }
}

/// One app-wide "Open with…" entry. The `template` is a URI template describing
/// how a daemon's download folders are reachable from this Mac (see
/// `MappingTemplate` for placeholder substitution); `scope` says which servers
/// it applies to.
public struct OpenMapping: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var template: String
    /// What to do with the expanded URL.
    public var action: OpenMappingAction
    /// Bundle ID of the app that should receive the URL (e.g.
    /// `com.google.Chrome`). nil = the system default handler.
    public var applicationBundleID: String?
    /// Which servers this mapping applies to. Defaults to `.all`.
    public var scope: MappingServerScope
    /// Security-scoped bookmarks for the folders the user granted access to, so
    /// a sandboxed app can hand the mapping's `file://` URLs to another app via
    /// LaunchServices. A mapping that targets local files on several servers may
    /// need more than one (each server's files can live in a different folder);
    /// the opener activates the one whose folder contains the target.
    public var accessBookmarks: [Data]

    public init(
        id: UUID = UUID(),
        name: String,
        template: String,
        action: OpenMappingAction = .open,
        applicationBundleID: String? = nil,
        scope: MappingServerScope = .all,
        accessBookmarks: [Data] = []
    ) {
        self.id = id
        self.name = name
        self.template = template
        self.action = action
        self.applicationBundleID = applicationBundleID
        self.scope = scope
        self.accessBookmarks = accessBookmarks
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, template, action, applicationBundleID, scope, accessBookmarks
    }

    /// The pre-scope shape stored a single bookmark. Read (never written) so a
    /// `servers.json` written by an older build still yields its grant.
    private enum LegacyCodingKeys: String, CodingKey {
        case accessBookmark
    }

    /// `action`, `applicationBundleID`, `scope` and `accessBookmarks` are
    /// `decodeIfPresent` so mappings saved before they existed still load;
    /// `encode(to:)` stays synthesized and drops the legacy key.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        template = try container.decode(String.self, forKey: .template)
        action = try container.decodeIfPresent(OpenMappingAction.self, forKey: .action) ?? .open
        applicationBundleID = try container.decodeIfPresent(String.self, forKey: .applicationBundleID)
        scope = try container.decodeIfPresent(MappingServerScope.self, forKey: .scope) ?? .all
        accessBookmarks = try container.decodeIfPresent([Data].self, forKey: .accessBookmarks) ?? []
        if accessBookmarks.isEmpty {
            let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
            if let bookmark = try legacy.decodeIfPresent(Data.self, forKey: .accessBookmark) {
                accessBookmarks = [bookmark]
            }
        }
    }
}
