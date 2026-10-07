import Foundation

/// Per-torrent transfer settings, as the inspector's Options tab edits them.
/// Maps onto `torrent-set` / `torrent-get` fields in slice 7 — the Bool+value
/// pairs here collapse Transmission's tri-state seed-limit modes (global /
/// single / unlimited) down to the two the UI exposes: "use this torrent's
/// limit" (single) vs "follow the session default" (global).
public struct TorrentOptions: Hashable, Sendable, Codable {
    public var honorsSessionLimits: Bool
    public var downloadLimited: Bool
    /// KB/s, matching the RPC unit for `downloadLimit`.
    public var downloadLimitKBps: Int
    public var uploadLimited: Bool
    public var uploadLimitKBps: Int
    public var seedRatioLimited: Bool
    public var seedRatioLimit: Double
    public var seedIdleLimited: Bool
    public var seedIdleMinutes: Int
    public var peerLimit: Int

    public init(
        honorsSessionLimits: Bool = true,
        downloadLimited: Bool = false,
        downloadLimitKBps: Int = 2000,
        uploadLimited: Bool = false,
        uploadLimitKBps: Int = 500,
        seedRatioLimited: Bool = false,
        seedRatioLimit: Double = 2.0,
        seedIdleLimited: Bool = false,
        seedIdleMinutes: Int = 30,
        peerLimit: Int = 60
    ) {
        self.honorsSessionLimits = honorsSessionLimits
        self.downloadLimited = downloadLimited
        self.downloadLimitKBps = downloadLimitKBps
        self.uploadLimited = uploadLimited
        self.uploadLimitKBps = uploadLimitKBps
        self.seedRatioLimited = seedRatioLimited
        self.seedRatioLimit = seedRatioLimit
        self.seedIdleLimited = seedIdleLimited
        self.seedIdleMinutes = seedIdleMinutes
        self.peerLimit = peerLimit
    }
}

/// A partial change to one or more torrents' speed limits. Only the non-nil
/// fields are sent, so an unrelated per-torrent setting is never clobbered.
/// Used by `TorrentService.setSpeedLimits`, which applies the same delta to
/// many torrents in a single `torrent-set`.
public struct TorrentSpeedLimitPatch: Sendable, Equatable {
    public var downloadLimited: Bool?
    public var downloadLimitKBps: Int?
    public var uploadLimited: Bool?
    public var uploadLimitKBps: Int?

    public init(
        downloadLimited: Bool? = nil,
        downloadLimitKBps: Int? = nil,
        uploadLimited: Bool? = nil,
        uploadLimitKBps: Int? = nil
    ) {
        self.downloadLimited = downloadLimited
        self.downloadLimitKBps = downloadLimitKBps
        self.uploadLimited = uploadLimited
        self.uploadLimitKBps = uploadLimitKBps
    }

    public var isEmpty: Bool {
        downloadLimited == nil && downloadLimitKBps == nil
            && uploadLimited == nil && uploadLimitKBps == nil
    }
}
