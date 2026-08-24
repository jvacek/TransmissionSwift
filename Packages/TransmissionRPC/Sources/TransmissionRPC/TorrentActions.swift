import Foundation

// MARK: - torrent-start / torrent-stop / torrent-verify

public struct TorrentIDArguments: Encodable, Sendable {
    public var ids: [Int]

    public init(ids: [Int]) {
        self.ids = ids
    }
}

// MARK: - torrent-remove

public struct TorrentRemoveArguments: Encodable, Sendable {
    public var ids: [Int]
    public var deleteLocalData: Bool

    enum CodingKeys: String, CodingKey {
        case ids
        case deleteLocalData = "delete-local-data"
    }

    public init(ids: [Int], deleteLocalData: Bool) {
        self.ids = ids
        self.deleteLocalData = deleteLocalData
    }
}

// MARK: - torrent-set
//
// Key casing is deliberately mixed — spec §3.2 uses kebab-case for file/priority
// arrays and camelCase for speed/ratio/peer settings. Explicit CodingKeys required;
// do NOT add a global keyEncodingStrategy to the client.
//
// nil optionals are omitted by Swift's synthesised encoder (encodeIfPresent).
// Never assign [] to the file-index arrays — an empty array means "all files".

public struct TorrentSetArguments: Encodable, Sendable {
    public var ids: [Int]

    // File selection (spec §3.2: array of file indices)
    public var filesWanted: [Int]?
    public var filesUnwanted: [Int]?
    public var priorityHigh: [Int]?
    public var priorityNormal: [Int]?
    public var priorityLow: [Int]?

    // Speed limits (KB/s)
    public var downloadLimit: Int?
    public var downloadLimited: Bool?
    public var uploadLimit: Int?
    public var uploadLimited: Bool?
    public var honorsSessionLimits: Bool?

    // Seeding thresholds
    public var seedRatioLimit: Double?
    /// 0 = use global, 1 = use this torrent's limit, 2 = no limit.
    public var seedRatioMode: Int?
    public var seedIdleLimit: Int?
    /// 0 = use global, 1 = use this torrent's limit, 2 = no limit.
    public var seedIdleMode: Int?

    // Misc
    public var peerLimit: Int?
    public var queuePosition: Int?
    public var bandwidthPriority: Int?
    /// Whole-set replace of the torrent's labels. Requires RPC ≥ 17
    /// (Transmission 4.0). Omit on older daemons.
    public var labels: [String]?

    enum CodingKeys: String, CodingKey {
        case ids
        case filesWanted = "files-wanted"
        case filesUnwanted = "files-unwanted"
        case priorityHigh = "priority-high"
        case priorityNormal = "priority-normal"
        case priorityLow = "priority-low"
        case downloadLimit
        case downloadLimited
        case uploadLimit
        case uploadLimited
        case honorsSessionLimits
        case seedRatioLimit
        case seedRatioMode
        case seedIdleLimit
        case seedIdleMode
        case peerLimit = "peer-limit"
        case queuePosition
        case bandwidthPriority
        case labels
    }

    public init(ids: [Int]) {
        self.ids = ids
    }
}

// MARK: - torrent-add

public struct TorrentAddArguments: Encodable, Sendable {
    /// URL string or magnet link. Mutually exclusive with `metainfo`.
    public var filename: String?
    /// Base64-encoded .torrent file content. Mutually exclusive with `filename`.
    public var metainfo: String?
    public var downloadDir: String?
    /// Inverted `startWhenAdded` — true means start paused.
    public var paused: Bool?
    public var bandwidthPriority: Int?
    /// Requires RPC ≥ 17 (Transmission 4.0). Omit on older daemons.
    public var labels: [String]?

    enum CodingKeys: String, CodingKey {
        case filename
        case metainfo
        case downloadDir = "download-dir"
        case paused
        case bandwidthPriority
        case labels
    }

    public init(
        filename: String? = nil,
        metainfo: String? = nil,
        downloadDir: String? = nil,
        paused: Bool? = nil,
        bandwidthPriority: Int? = nil,
        labels: [String]? = nil
    ) {
        self.filename = filename
        self.metainfo = metainfo
        self.downloadDir = downloadDir
        self.paused = paused
        self.bandwidthPriority = bandwidthPriority
        self.labels = labels
    }
}

public struct WireTorrentAdded: Decodable, Sendable {
    public let id: Int
    public let name: String
    public let hashString: String
}

public struct TorrentAddResponse: Decodable, Sendable {
    /// Present when the torrent was successfully added.
    public let torrentAdded: WireTorrentAdded?
    /// Present when the torrent was already on the daemon (result is still "success").
    public let torrentDuplicate: WireTorrentAdded?

    enum CodingKeys: String, CodingKey {
        case torrentAdded = "torrent-added"
        case torrentDuplicate = "torrent-duplicate"
    }
}

// MARK: - session-set

public struct SessionSetArguments: Encodable, Sendable {
    public var altSpeedEnabled: Bool?
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
        case altSpeedEnabled = "alt-speed-enabled"
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
        altSpeedEnabled: Bool? = nil,
        altSpeedDown: Int? = nil,
        altSpeedUp: Int? = nil,
        altSpeedTimeBegin: Int? = nil,
        altSpeedTimeDay: Int? = nil,
        altSpeedTimeEnabled: Bool? = nil,
        altSpeedTimeEnd: Int? = nil,
        speedLimitDownEnabled: Bool? = nil,
        speedLimitDown: Int? = nil,
        speedLimitUpEnabled: Bool? = nil,
        speedLimitUp: Int? = nil,
        blocklistEnabled: Bool? = nil,
        blocklistURL: String? = nil,
        dhtEnabled: Bool? = nil,
        downloadQueueEnabled: Bool? = nil,
        downloadQueueSize: Int? = nil,
        encryption: String? = nil,
        idleSeedingLimitEnabled: Bool? = nil,
        idleSeedingLimit: Int? = nil,
        lpdEnabled: Bool? = nil,
        peerPort: Int? = nil,
        peerPortRandomOnStart: Bool? = nil,
        pexEnabled: Bool? = nil,
        portForwardingEnabled: Bool? = nil,
        queueStalledEnabled: Bool? = nil,
        queueStalledMinutes: Int? = nil,
        seedQueueEnabled: Bool? = nil,
        seedQueueSize: Int? = nil,
        seedRatioLimit: Double? = nil,
        seedRatioLimited: Bool? = nil,
        utpEnabled: Bool? = nil
    ) {
        self.altSpeedEnabled = altSpeedEnabled
        self.altSpeedDown = altSpeedDown
        self.altSpeedUp = altSpeedUp
        self.altSpeedTimeBegin = altSpeedTimeBegin
        self.altSpeedTimeDay = altSpeedTimeDay
        self.altSpeedTimeEnabled = altSpeedTimeEnabled
        self.altSpeedTimeEnd = altSpeedTimeEnd
        self.speedLimitDownEnabled = speedLimitDownEnabled
        self.speedLimitDown = speedLimitDown
        self.speedLimitUpEnabled = speedLimitUpEnabled
        self.speedLimitUp = speedLimitUp
        self.blocklistEnabled = blocklistEnabled
        self.blocklistURL = blocklistURL
        self.dhtEnabled = dhtEnabled
        self.downloadQueueEnabled = downloadQueueEnabled
        self.downloadQueueSize = downloadQueueSize
        self.encryption = encryption
        self.idleSeedingLimitEnabled = idleSeedingLimitEnabled
        self.idleSeedingLimit = idleSeedingLimit
        self.lpdEnabled = lpdEnabled
        self.peerPort = peerPort
        self.peerPortRandomOnStart = peerPortRandomOnStart
        self.pexEnabled = pexEnabled
        self.portForwardingEnabled = portForwardingEnabled
        self.queueStalledEnabled = queueStalledEnabled
        self.queueStalledMinutes = queueStalledMinutes
        self.seedQueueEnabled = seedQueueEnabled
        self.seedQueueSize = seedQueueSize
        self.seedRatioLimit = seedRatioLimit
        self.seedRatioLimited = seedRatioLimited
        self.utpEnabled = utpEnabled
    }
}
