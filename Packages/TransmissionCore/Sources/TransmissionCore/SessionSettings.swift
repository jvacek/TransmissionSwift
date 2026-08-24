import Foundation
import TransmissionRPC

/// The daemon's encryption preference. Mirrors the RPC `encryption` string;
/// Transmission 4.0.6 uses `required` / `preferred` / `tolerated`.
public enum SessionEncryption: String, Sendable, Equatable, CaseIterable {
    case required
    case preferred
    case tolerated
}

/// The readable, Swift-named snapshot of the connected daemon's session-level
/// settings (the `session-get` surface). Backs the Speed / Network / Global
/// Speed panes. Never includes daemon config that isn't exposed over the RPC
/// (the web-interface `rpc-*` keys are `settings.json`-only).
public struct SessionSettings: Sendable, Equatable {
    public var downLimited: Bool
    public var downLimitKBps: Int
    public var upLimited: Bool
    public var upLimitKBps: Int

    public var altSpeedEnabled: Bool
    public var altSpeedDownKBps: Int
    public var altSpeedUpKBps: Int
    public var altSpeedTimeEnabled: Bool
    public var altSpeedTimeBeginMinutes: Int
    public var altSpeedTimeEndMinutes: Int
    public var altSpeedTimeDayMask: Int

    public var peerPort: Int
    public var peerPortRandomOnStart: Bool
    public var portForwardingEnabled: Bool
    public var encryption: SessionEncryption

    public var blocklistEnabled: Bool
    public var blocklistURL: String

    public var pexEnabled: Bool
    public var dhtEnabled: Bool
    public var utpEnabled: Bool
    public var lpdEnabled: Bool

    public var downloadQueueEnabled: Bool
    public var downloadQueueSize: Int
    public var seedQueueEnabled: Bool
    public var seedQueueSize: Int
    public var queueStalledEnabled: Bool
    public var queueStalledMinutes: Int

    public var seedRatioLimited: Bool
    public var seedRatioLimit: Double
    public var idleSeedingLimitEnabled: Bool
    public var idleSeedingLimitMinutes: Int

    public init(
        downLimited: Bool = false,
        downLimitKBps: Int = 1000,
        upLimited: Bool = false,
        upLimitKBps: Int = 100,
        altSpeedEnabled: Bool = false,
        altSpeedDownKBps: Int = 50,
        altSpeedUpKBps: Int = 10,
        altSpeedTimeEnabled: Bool = false,
        altSpeedTimeBeginMinutes: Int = 540,
        altSpeedTimeEndMinutes: Int = 1020,
        altSpeedTimeDayMask: Int = 0b0111110,
        peerPort: Int = 51413,
        peerPortRandomOnStart: Bool = false,
        portForwardingEnabled: Bool = true,
        encryption: SessionEncryption = .preferred,
        blocklistEnabled: Bool = false,
        blocklistURL: String = "",
        pexEnabled: Bool = true,
        dhtEnabled: Bool = true,
        utpEnabled: Bool = true,
        lpdEnabled: Bool = true,
        downloadQueueEnabled: Bool = true,
        downloadQueueSize: Int = 5,
        seedQueueEnabled: Bool = true,
        seedQueueSize: Int = 5,
        queueStalledEnabled: Bool = true,
        queueStalledMinutes: Int = 30,
        seedRatioLimited: Bool = true,
        seedRatioLimit: Double = 1.0,
        idleSeedingLimitEnabled: Bool = false,
        idleSeedingLimitMinutes: Int = 30
    ) {
        self.downLimited = downLimited
        self.downLimitKBps = downLimitKBps
        self.upLimited = upLimited
        self.upLimitKBps = upLimitKBps
        self.altSpeedEnabled = altSpeedEnabled
        self.altSpeedDownKBps = altSpeedDownKBps
        self.altSpeedUpKBps = altSpeedUpKBps
        self.altSpeedTimeEnabled = altSpeedTimeEnabled
        self.altSpeedTimeBeginMinutes = altSpeedTimeBeginMinutes
        self.altSpeedTimeEndMinutes = altSpeedTimeEndMinutes
        self.altSpeedTimeDayMask = altSpeedTimeDayMask
        self.peerPort = peerPort
        self.peerPortRandomOnStart = peerPortRandomOnStart
        self.portForwardingEnabled = portForwardingEnabled
        self.encryption = encryption
        self.blocklistEnabled = blocklistEnabled
        self.blocklistURL = blocklistURL
        self.pexEnabled = pexEnabled
        self.dhtEnabled = dhtEnabled
        self.utpEnabled = utpEnabled
        self.lpdEnabled = lpdEnabled
        self.downloadQueueEnabled = downloadQueueEnabled
        self.downloadQueueSize = downloadQueueSize
        self.seedQueueEnabled = seedQueueEnabled
        self.seedQueueSize = seedQueueSize
        self.queueStalledEnabled = queueStalledEnabled
        self.queueStalledMinutes = queueStalledMinutes
        self.seedRatioLimited = seedRatioLimited
        self.seedRatioLimit = seedRatioLimit
        self.idleSeedingLimitEnabled = idleSeedingLimitEnabled
        self.idleSeedingLimitMinutes = idleSeedingLimitMinutes
    }

    /// Maps a `session-get` wire payload, defaulting absent optional fields.
    public init(wire: SessionInfo) {
        self.init(
            downLimited: wire.speedLimitDownEnabled ?? false,
            downLimitKBps: wire.speedLimitDown ?? 1000,
            upLimited: wire.speedLimitUpEnabled ?? false,
            upLimitKBps: wire.speedLimitUp ?? 100,
            altSpeedEnabled: wire.altSpeedEnabled,
            altSpeedDownKBps: wire.altSpeedDown ?? 50,
            altSpeedUpKBps: wire.altSpeedUp ?? 10,
            altSpeedTimeEnabled: wire.altSpeedTimeEnabled ?? false,
            altSpeedTimeBeginMinutes: wire.altSpeedTimeBegin ?? 540,
            altSpeedTimeEndMinutes: wire.altSpeedTimeEnd ?? 1020,
            altSpeedTimeDayMask: wire.altSpeedTimeDay ?? 0b0111110,
            peerPort: wire.peerPort ?? 51413,
            peerPortRandomOnStart: wire.peerPortRandomOnStart ?? false,
            portForwardingEnabled: wire.portForwardingEnabled ?? true,
            encryption: wire.encryption.flatMap(SessionEncryption.init(rawValue:)) ?? .preferred,
            blocklistEnabled: wire.blocklistEnabled ?? false,
            blocklistURL: wire.blocklistURL ?? "",
            pexEnabled: wire.pexEnabled ?? true,
            dhtEnabled: wire.dhtEnabled ?? true,
            utpEnabled: wire.utpEnabled ?? true,
            lpdEnabled: wire.lpdEnabled ?? true,
            downloadQueueEnabled: wire.downloadQueueEnabled ?? true,
            downloadQueueSize: wire.downloadQueueSize ?? 5,
            seedQueueEnabled: wire.seedQueueEnabled ?? true,
            seedQueueSize: wire.seedQueueSize ?? 5,
            queueStalledEnabled: wire.queueStalledEnabled ?? true,
            queueStalledMinutes: wire.queueStalledMinutes ?? 30,
            seedRatioLimited: wire.seedRatioLimited ?? true,
            seedRatioLimit: wire.seedRatioLimit ?? 1.0,
            idleSeedingLimitEnabled: wire.idleSeedingLimitEnabled ?? false,
            idleSeedingLimitMinutes: wire.idleSeedingLimit ?? 30
        )
    }

    /// A realistic mid-flight configuration for previews and the mock
    /// no-server state: global + turtle limits on, queue seeded, ratio under
    /// control. Keeps the Settings panes looking live in `#Preview`.
    public static let sample = SessionSettings(
        downLimited: true,
        downLimitKBps: 1000,
        upLimited: true,
        upLimitKBps: 100,
        altSpeedEnabled: true,
        altSpeedDownKBps: 50,
        altSpeedUpKBps: 10,
        altSpeedTimeEnabled: true,
        altSpeedTimeBeginMinutes: 540,
        altSpeedTimeEndMinutes: 1020,
        altSpeedTimeDayMask: 0b0111110,
        downloadQueueEnabled: true,
        downloadQueueSize: 5,
        seedQueueEnabled: true,
        seedQueueSize: 5,
        queueStalledEnabled: true,
        queueStalledMinutes: 30,
        seedRatioLimited: true,
        seedRatioLimit: 1.0
    )
}

/// A partial write for `session-set`: only the non-nil fields get sent, so an
/// unrelated toggle never clobbers another setting. Built by diffing the before
/// and after `SessionSettings` in `TorrentStore.updateSessionSettings`.
public struct SessionSettingsPatch: Sendable, Equatable {
    public var downLimited: Bool?
    public var downLimitKBps: Int?
    public var upLimited: Bool?
    public var upLimitKBps: Int?

    public var altSpeedEnabled: Bool?
    public var altSpeedDownKBps: Int?
    public var altSpeedUpKBps: Int?
    public var altSpeedTimeEnabled: Bool?
    public var altSpeedTimeBeginMinutes: Int?
    public var altSpeedTimeEndMinutes: Int?
    public var altSpeedTimeDayMask: Int?

    public var peerPort: Int?
    public var peerPortRandomOnStart: Bool?
    public var portForwardingEnabled: Bool?
    public var encryption: SessionEncryption?

    public var blocklistEnabled: Bool?
    public var blocklistURL: String?

    public var pexEnabled: Bool?
    public var dhtEnabled: Bool?
    public var utpEnabled: Bool?
    public var lpdEnabled: Bool?

    public var downloadQueueEnabled: Bool?
    public var downloadQueueSize: Int?
    public var seedQueueEnabled: Bool?
    public var seedQueueSize: Int?
    public var queueStalledEnabled: Bool?
    public var queueStalledMinutes: Int?

    public var seedRatioLimited: Bool?
    public var seedRatioLimit: Double?
    public var idleSeedingLimitEnabled: Bool?
    public var idleSeedingLimitMinutes: Int?

    public init() {}

    /// Builds a patch containing only the fields that changed between `before`
    /// and `after`. Equatable comparison per field; nil means "unchanged".
    public init(before: SessionSettings, updated: SessionSettings) {
        if before.downLimited != updated.downLimited { downLimited = updated.downLimited }
        if before.downLimitKBps != updated.downLimitKBps { downLimitKBps = updated.downLimitKBps }
        if before.upLimited != updated.upLimited { upLimited = updated.upLimited }
        if before.upLimitKBps != updated.upLimitKBps { upLimitKBps = updated.upLimitKBps }

        if before.altSpeedEnabled != updated.altSpeedEnabled { altSpeedEnabled = updated.altSpeedEnabled }
        if before.altSpeedDownKBps != updated.altSpeedDownKBps { altSpeedDownKBps = updated.altSpeedDownKBps }
        if before.altSpeedUpKBps != updated.altSpeedUpKBps { altSpeedUpKBps = updated.altSpeedUpKBps }
        if before.altSpeedTimeEnabled != updated.altSpeedTimeEnabled {
            altSpeedTimeEnabled = updated.altSpeedTimeEnabled
        }
        if before.altSpeedTimeBeginMinutes != updated.altSpeedTimeBeginMinutes {
            altSpeedTimeBeginMinutes = updated.altSpeedTimeBeginMinutes
        }
        if before.altSpeedTimeEndMinutes != updated.altSpeedTimeEndMinutes {
            altSpeedTimeEndMinutes = updated.altSpeedTimeEndMinutes
        }
        if before.altSpeedTimeDayMask != updated.altSpeedTimeDayMask {
            altSpeedTimeDayMask = updated.altSpeedTimeDayMask
        }

        if before.peerPort != updated.peerPort { peerPort = updated.peerPort }
        if before.peerPortRandomOnStart != updated.peerPortRandomOnStart {
            peerPortRandomOnStart = updated.peerPortRandomOnStart
        }
        if before.portForwardingEnabled != updated.portForwardingEnabled {
            portForwardingEnabled = updated.portForwardingEnabled
        }
        if before.encryption != updated.encryption { encryption = updated.encryption }

        if before.blocklistEnabled != updated.blocklistEnabled { blocklistEnabled = updated.blocklistEnabled }
        if before.blocklistURL != updated.blocklistURL { blocklistURL = updated.blocklistURL }

        if before.pexEnabled != updated.pexEnabled { pexEnabled = updated.pexEnabled }
        if before.dhtEnabled != updated.dhtEnabled { dhtEnabled = updated.dhtEnabled }
        if before.utpEnabled != updated.utpEnabled { utpEnabled = updated.utpEnabled }
        if before.lpdEnabled != updated.lpdEnabled { lpdEnabled = updated.lpdEnabled }

        if before.downloadQueueEnabled != updated.downloadQueueEnabled {
            downloadQueueEnabled = updated.downloadQueueEnabled
        }
        if before.downloadQueueSize != updated.downloadQueueSize {
            downloadQueueSize = updated.downloadQueueSize
        }
        if before.seedQueueEnabled != updated.seedQueueEnabled {
            seedQueueEnabled = updated.seedQueueEnabled
        }
        if before.seedQueueSize != updated.seedQueueSize { seedQueueSize = updated.seedQueueSize }
        if before.queueStalledEnabled != updated.queueStalledEnabled {
            queueStalledEnabled = updated.queueStalledEnabled
        }
        if before.queueStalledMinutes != updated.queueStalledMinutes {
            queueStalledMinutes = updated.queueStalledMinutes
        }

        if before.seedRatioLimited != updated.seedRatioLimited { seedRatioLimited = updated.seedRatioLimited }
        if before.seedRatioLimit != updated.seedRatioLimit { seedRatioLimit = updated.seedRatioLimit }
        if before.idleSeedingLimitEnabled != updated.idleSeedingLimitEnabled {
            idleSeedingLimitEnabled = updated.idleSeedingLimitEnabled
        }
        if before.idleSeedingLimitMinutes != updated.idleSeedingLimitMinutes {
            idleSeedingLimitMinutes = updated.idleSeedingLimitMinutes
        }
    }

    /// True when every field is nil (no change to send).
    public var isEmpty: Bool {
        self == SessionSettingsPatch()
    }

    /// Applies the non-nil fields onto an RPC `SessionSetArguments` payload.
    public func apply(to args: inout SessionSetArguments) {
        args.altSpeedEnabled = altSpeedEnabled
        args.altSpeedDown = altSpeedDownKBps
        args.altSpeedUp = altSpeedUpKBps
        args.altSpeedTimeEnabled = altSpeedTimeEnabled
        args.altSpeedTimeBegin = altSpeedTimeBeginMinutes
        args.altSpeedTimeEnd = altSpeedTimeEndMinutes
        args.altSpeedTimeDay = altSpeedTimeDayMask

        args.speedLimitDownEnabled = downLimited
        args.speedLimitDown = downLimitKBps
        args.speedLimitUpEnabled = upLimited
        args.speedLimitUp = upLimitKBps

        args.peerPort = peerPort
        args.peerPortRandomOnStart = peerPortRandomOnStart
        args.portForwardingEnabled = portForwardingEnabled
        args.encryption = encryption?.rawValue

        args.blocklistEnabled = blocklistEnabled
        args.blocklistURL = blocklistURL

        args.pexEnabled = pexEnabled
        args.dhtEnabled = dhtEnabled
        args.utpEnabled = utpEnabled
        args.lpdEnabled = lpdEnabled

        args.downloadQueueEnabled = downloadQueueEnabled
        args.downloadQueueSize = downloadQueueSize
        args.seedQueueEnabled = seedQueueEnabled
        args.seedQueueSize = seedQueueSize
        args.queueStalledEnabled = queueStalledEnabled
        args.queueStalledMinutes = queueStalledMinutes

        args.seedRatioLimited = seedRatioLimited
        args.seedRatioLimit = seedRatioLimit
        args.idleSeedingLimitEnabled = idleSeedingLimitEnabled
        args.idleSeedingLimit = idleSeedingLimitMinutes
    }
}
