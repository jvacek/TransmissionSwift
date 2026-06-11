import Foundation

// MARK: - Inspector wire types

public struct WireFile: Decodable, Sendable {
    public var name: String
    public var length: Int64
    public var bytesCompleted: Int64
}

public struct WireFileStat: Decodable, Sendable {
    public var bytesCompleted: Int64
    public var wanted: Bool
    /// -1 = low, 0 = normal, 1 = high.
    public var priority: Int
}

public struct WirePeer: Decodable, Sendable {
    public var address: String
    public var clientName: String
    public var flagStr: String
    public var progress: Double
    /// Bytes/s flowing from the peer to us.
    public var rateToClient: Int64
    /// Bytes/s flowing from us to the peer.
    public var rateToPeer: Int64
}

public struct WireTrackerStat: Decodable, Sendable {
    public var id: Int
    public var tier: Int
    public var host: String
    public var lastAnnounceResult: String
    public var lastAnnounceTime: Int64
    public var lastAnnounceSucceeded: Bool
    public var hasAnnounced: Bool
    /// 0 = inactive, 1 = waiting, 2 = queued, 3 = active (announcing now).
    public var announceState: Int
    public var seederCount: Int
    public var leecherCount: Int
    public var downloadCount: Int
    public var isBackup: Bool
}

// MARK: - Peers-from breakdown

public struct WirePeersFrom: Decodable, Sendable {
    public var fromCache: Int
    public var fromDht: Int
    public var fromIncoming: Int
    public var fromLpd: Int
    public var fromLtep: Int
    public var fromPex: Int
    public var fromTracker: Int

    public var total: Int {
        fromCache + fromDht + fromIncoming + fromLpd + fromLtep + fromPex + fromTracker
    }
}

public struct WireTrackerStub: Decodable, Sendable {
    public var announce: String
    /// Added in Transmission 4.0.0 (rpc-version 17); falls back to host parsed from `announce`.
    public var sitename: String?
    public var tier: Int
}

public struct WireTorrent: Decodable, Sendable {
    public var id: Int
    public var name: String
    public var hashString: String
    public var totalSize: Int64
    public var status: Int
    public var error: Int
    public var errorString: String
    public var isFinished: Bool
    public var percentDone: Double
    public var rateDownload: Int64
    public var rateUpload: Int64
    public var peersConnected: Int
    public var peersSendingToUs: Int
    public var peersGettingFromUs: Int
    public var peersFrom: WirePeersFrom
    public var eta: Int
    public var uploadRatio: Double
    public var downloadDir: String
    public var addedDate: Int64
    /// Absent on daemons < 3.00 (rpc-version 16).
    public var labels: [String]?
    public var bandwidthPriority: Int
    public var pieceCount: Int
    public var pieceSize: Int64
    public var haveValid: Int64
    public var queuePosition: Int
    public var trackers: [WireTrackerStub]?
    // Inspector-only fields — absent on list polls; present when inspectorFields are requested.
    public var files: [WireFile]? = nil
    public var fileStats: [WireFileStat]? = nil
    public var peers: [WirePeer]? = nil
    public var trackerStats: [WireTrackerStat]? = nil
}

struct TorrentGetArguments: Encodable {
    var fields: [String]
    var ids: [Int]?
}

public struct TorrentGetResponse: Decodable, Sendable {
    public var torrents: [WireTorrent]

    public init(torrents: [WireTorrent]) {
        self.torrents = torrents
    }
}

extension TorrentGetResponse {
    public static let listFields: [String] = [
        "id", "name", "hashString", "totalSize",
        "status", "error", "errorString", "isFinished",
        "percentDone", "rateDownload", "rateUpload",
        "peersConnected", "peersSendingToUs", "peersGettingFromUs", "peersFrom",
        "eta", "uploadRatio",
        "downloadDir", "addedDate",
        "labels", "bandwidthPriority",
        "pieceCount", "pieceSize", "haveValid",
        "queuePosition", "trackers",
    ]

    /// Extra fields fetched for the inspector — only requested for the selected
    /// torrent, not the full list.
    public static let inspectorFields: [String] = [
        "files", "fileStats",
        "peers",
        "trackerStats",
    ]
}
