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

    enum CodingKeys: String, CodingKey {
        case altSpeedEnabled = "alt-speed-enabled"
    }

    public init(altSpeedEnabled: Bool? = nil) {
        self.altSpeedEnabled = altSpeedEnabled
    }
}
