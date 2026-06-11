import Foundation

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
}
