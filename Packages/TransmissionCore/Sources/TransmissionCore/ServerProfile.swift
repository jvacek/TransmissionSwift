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

    public init(
        id: UUID = UUID(),
        label: String,
        host: String,
        port: Int = 9091,
        rpcPath: String = "/transmission/rpc",
        username: String? = nil,
        useHTTPS: Bool = false
    ) {
        self.id = id
        self.label = label
        self.host = host
        self.port = port
        self.rpcPath = rpcPath
        self.username = username
        self.useHTTPS = useHTTPS
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
