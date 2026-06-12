/// The subset of `session-get` fields the app uses today.
///
/// Field names per the RPC spec (`reference/rpc-spec-4.0.6.md` §4.1.1):
/// the legacy protocol uses kebab-case keys.
public struct SessionInfo: Decodable, Sendable, Equatable {
    /// Long version string, e.g. `"4.1.2 (f234716f3e)"`.
    public let version: String
    /// Current RPC API version, e.g. `19`.
    public let rpcVersion: Int
    /// Oldest RPC API version this daemon still supports.
    public let rpcVersionMinimum: Int
    /// Free bytes on the download directory's volume. Absent on very old daemons.
    public let downloadDirFreeSpace: Int64?
    /// Whether the alternative (turtle) speed limits are currently active.
    public let altSpeedEnabled: Bool
    /// Default download directory on the daemon host.
    public let downloadDir: String?

    enum CodingKeys: String, CodingKey {
        case version
        case rpcVersion = "rpc-version"
        case rpcVersionMinimum = "rpc-version-minimum"
        case downloadDirFreeSpace = "download-dir-free-space"
        case altSpeedEnabled = "alt-speed-enabled"
        case downloadDir = "download-dir"
    }

    public init(
        version: String,
        rpcVersion: Int,
        rpcVersionMinimum: Int,
        downloadDirFreeSpace: Int64? = nil,
        altSpeedEnabled: Bool = false,
        downloadDir: String? = nil
    ) {
        self.version = version
        self.rpcVersion = rpcVersion
        self.rpcVersionMinimum = rpcVersionMinimum
        self.downloadDirFreeSpace = downloadDirFreeSpace
        self.altSpeedEnabled = altSpeedEnabled
        self.downloadDir = downloadDir
    }
}
