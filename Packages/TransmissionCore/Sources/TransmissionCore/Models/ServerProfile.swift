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

    /// Whether the daemon is reachable on this Mac or the local network:
    /// `localhost`, a loopback, private (RFC 1918) or link-local address, or a
    /// `.local` Bonjour name. The complement is treated as remote. Drives the
    /// "All Local Servers" / "All Remote Servers" mapping scopes.
    public var isLocal: Bool {
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if host.isEmpty { return false }
        if host == "localhost" || host == "::1" || host == "[::1]" { return true }
        if host.hasSuffix(".local") { return true }
        if host.hasPrefix("fe80:") { return true }  // IPv6 link-local
        let octets = host.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4,
            let first = Int(octets[0]), let second = Int(octets[1]),
            octets.allSatisfy({ Int($0).map { (0...255).contains($0) } ?? false })
        else { return false }
        switch first {
        case 10, 127: return true
        case 172: return (16...31).contains(second)
        case 192: return second == 168
        case 169: return second == 254
        default: return false
        }
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
