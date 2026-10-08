import Foundation

/// Connection settings for one Transmission daemon. The password is not here —
/// it lives in the Keychain, keyed by `id` (see `KeychainStore`).
public struct ServerProfile: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var label: String
    public var host: String
    public var port: Int
    public var rpcPath: String
    public var username: String?
    public var useHTTPS: Bool
    /// "Open with…" entries for this server (see `OpenMapping`). Defaults to
    /// empty so old `servers.json` files decode without it.
    public var mappings: [OpenMapping]

    public init(
        id: UUID = UUID(),
        label: String,
        host: String,
        port: Int = 9091,
        rpcPath: String = "/transmission/rpc",
        username: String? = nil,
        useHTTPS: Bool = false,
        mappings: [OpenMapping] = []
    ) {
        self.id = id
        self.label = label
        self.host = host
        self.port = port
        self.rpcPath = rpcPath
        self.username = username
        self.useHTTPS = useHTTPS
        self.mappings = mappings
    }

    private enum CodingKeys: String, CodingKey {
        case id, label, host, port, rpcPath, username, useHTTPS, mappings
    }

    /// `mappings` is `decodeIfPresent` so servers.json files written before the
    /// field existed still load.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        host = try container.decode(String.self, forKey: .host)
        port = try container.decode(Int.self, forKey: .port)
        rpcPath = try container.decode(String.self, forKey: .rpcPath)
        username = try container.decodeIfPresent(String.self, forKey: .username)
        useHTTPS = try container.decode(Bool.self, forKey: .useHTTPS)
        mappings = try container.decodeIfPresent([OpenMapping].self, forKey: .mappings) ?? []
    }

    /// Full RPC endpoint URL, or nil if host/path don't form a valid URL.
    public var rpcURL: URL? {
        var components = URLComponents()
        components.scheme = useHTTPS ? "https" : "http"
        components.host = host
        components.port = port
        components.path = rpcPath.hasPrefix("/") ? rpcPath : "/" + rpcPath
        return components.url
    }
}
