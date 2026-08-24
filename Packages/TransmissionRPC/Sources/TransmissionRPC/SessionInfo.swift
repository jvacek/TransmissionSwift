/// The subset of `session-get` fields the app uses today.
///
/// Field names per the RPC spec (`reference/rpc-spec-4.0.6.md` §4.1.1):
/// the legacy protocol uses kebab-case keys. Newer fields are optional so a
/// daemon that doesn't report them (or an older snapshot fixture) still decodes.
///
/// The web-interface (`rpc-*`) settings are deliberately absent: they are
/// daemon `settings.json` configuration, not part of the `session-get`/`session-set`
/// surface in RPC 4.0.6 or 4.1.2.
public struct SessionInfo: Codable, Sendable, Equatable {
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

    public var altSpeedDown: Int?
    public var altSpeedUp: Int?
    public var altSpeedTimeBegin: Int?
    public var altSpeedTimeDay: Int?
    public var altSpeedTimeEnabled: Bool?
    public var altSpeedTimeEnd: Int?

    public var speedLimitDownEnabled: Bool?
    public var speedLimitDown: Int?
    public var speedLimitUpEnabled: Bool?
    public var speedLimitUp: Int?

    public var blocklistEnabled: Bool?
    public var blocklistURL: String?

    public var dhtEnabled: Bool?
    public var downloadQueueEnabled: Bool?
    public var downloadQueueSize: Int?

    public var encryption: String?

    public var idleSeedingLimitEnabled: Bool?
    public var idleSeedingLimit: Int?

    public var lpdEnabled: Bool?
    public var peerPort: Int?
    public var peerPortRandomOnStart: Bool?
    public var pexEnabled: Bool?
    public var portForwardingEnabled: Bool?

    public var queueStalledEnabled: Bool?
    public var queueStalledMinutes: Int?

    public var seedQueueEnabled: Bool?
    public var seedQueueSize: Int?
    public var seedRatioLimit: Double?
    public var seedRatioLimited: Bool?

    public var utpEnabled: Bool?

    enum CodingKeys: String, CodingKey {
        case version
        case rpcVersion = "rpc-version"
        case rpcVersionMinimum = "rpc-version-minimum"
        case downloadDirFreeSpace = "download-dir-free-space"
        case altSpeedEnabled = "alt-speed-enabled"
        case downloadDir = "download-dir"

        case altSpeedDown = "alt-speed-down"
        case altSpeedUp = "alt-speed-up"
        case altSpeedTimeBegin = "alt-speed-time-begin"
        case altSpeedTimeDay = "alt-speed-time-day"
        case altSpeedTimeEnabled = "alt-speed-time-enabled"
        case altSpeedTimeEnd = "alt-speed-time-end"

        case speedLimitDownEnabled = "speed-limit-down-enabled"
        case speedLimitDown = "speed-limit-down"
        case speedLimitUpEnabled = "speed-limit-up-enabled"
        case speedLimitUp = "speed-limit-up"

        case blocklistEnabled = "blocklist-enabled"
        case blocklistURL = "blocklist-url"

        case dhtEnabled = "dht-enabled"
        case downloadQueueEnabled = "download-queue-enabled"
        case downloadQueueSize = "download-queue-size"

        case encryption

        case idleSeedingLimitEnabled = "idle-seeding-limit-enabled"
        case idleSeedingLimit = "idle-seeding-limit"

        case lpdEnabled = "lpd-enabled"
        case peerPort = "peer-port"
        case peerPortRandomOnStart = "peer-port-random-on-start"
        case pexEnabled = "pex-enabled"
        case portForwardingEnabled = "port-forwarding-enabled"

        case queueStalledEnabled = "queue-stalled-enabled"
        case queueStalledMinutes = "queue-stalled-minutes"

        case seedQueueEnabled = "seed-queue-enabled"
        case seedQueueSize = "seed-queue-size"
        case seedRatioLimit
        case seedRatioLimited

        case utpEnabled = "utp-enabled"
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
