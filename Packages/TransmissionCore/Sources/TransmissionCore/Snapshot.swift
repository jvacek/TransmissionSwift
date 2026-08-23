import Foundation
import TransmissionRPC

/// Version of the snapshot envelope format. Bump on incompatible changes.
public let snapshotFormatVersion = 1

public enum SnapshotError: Error, LocalizedError, Sendable, Equatable {
    /// The backing service can't capture snapshots (mock / snapshot-replay mode).
    case captureUnsupported
    /// The redacted output still contains something identifying. `details` lists
    /// the offending values with their JSON paths.
    case leakDetected(details: [String])
    /// The raw snapshot couldn't be converted to a JSON tree.
    case malformed(String)
    /// A snapshot file has a format version this app doesn't understand.
    case unsupportedVersion(Int)
    /// A `torrents`-side lookup requested a torrent id absent from the snapshot.
    case torrentNotFound(Torrent.ID)
    /// A mutation was attempted against a read-only snapshot replay.
    case replayReadOnly

    public var errorDescription: String? {
        switch self {
        case .captureUnsupported:
            return "Snapshot capture requires a live server connection."
        case .leakDetected(let details):
            let list = details.prefix(5).joined(separator: "\n")
            return "Snapshot refused: \(details.count) potential leak(s) detected.\(list.isEmpty ? "" : "\n" + list)"
        case .malformed(let message):
            return "Snapshot could not be built: \(message)"
        case .unsupportedVersion(let version):
            return
                "Snapshot format version \(version) is not supported by this build (expected \(snapshotFormatVersion))."
        case .torrentNotFound(let id):
            return "Snapshot does not contain torrent \(id)."
        case .replayReadOnly:
            return "Snapshot replays are read-only; actions are disabled."
        }
    }
}

/// Provenance metadata embedded in every snapshot file.
public struct SnapshotSourceInfo: Codable, Sendable, Equatable {
    /// Daemon version string, e.g. `"4.1.2 (f234716f3e)"`. Kept — needed for
    /// reproducibility, not identifying.
    public var daemonVersion: String
    public var rpcVersion: Int
    /// True once the redaction pass has run. A raw capture has `false`.
    public var redacted: Bool

    public init(daemonVersion: String, rpcVersion: Int, redacted: Bool) {
        self.daemonVersion = daemonVersion
        self.rpcVersion = rpcVersion
        self.redacted = redacted
    }
}

/// The snapshot envelope, wire-shaped: `session` and `torrents` mirror the
/// daemon's `session-get` / `torrent-get` argument objects, so loading a file
/// decodes through the same types (`SessionInfo`, `WireTorrent`) and the same
/// `Torrent(wire:)` mapping as a live poll.
///
/// One type serves both directions: a raw capture has `redactions == nil`; the
/// redactor fills `redactions` in and the written file carries it as
/// provenance.
public struct SnapshotFile: Codable, Sendable {
    public var version: Int
    /// ISO 8601 capture time.
    public var capturedAt: String
    public var source: SnapshotSourceInfo
    public var session: SessionInfo
    public var torrents: [WireTorrent]
    /// Present in redacted files; nil in a raw capture.
    public var redactions: SnapshotRedactionSummary?
    /// Local tag→colour assignments captured alongside the state, so replay
    /// shows the same colours. Optional: files captured before colour support
    /// (or captures with no colour assignments) simply omit it. Only embedded
    /// when the capture keeps real names — an anonymized capture fuzzes labels,
    /// so the colour keys would reference labels that no longer exist.
    public var tagColors: [String: TagColor]?

    public init(
        version: Int,
        capturedAt: String,
        source: SnapshotSourceInfo,
        session: SessionInfo,
        torrents: [WireTorrent],
        redactions: SnapshotRedactionSummary? = nil,
        tagColors: [String: TagColor]? = nil
    ) {
        self.version = version
        self.capturedAt = capturedAt
        self.source = source
        self.session = session
        self.torrents = torrents
        self.redactions = redactions
        self.tagColors = tagColors
    }
}

/// Per-capture anonymization toggles.
///
/// Names are **kept by default** — a snapshot is only useful for talking about
/// a specific torrent if you can still tell them apart. Everything genuinely
/// identifying (peer IPs, paths, hashes, timestamps, passkeys) stays scrubbed
/// unless explicitly opted in; tracker hosts/sitenames are fuzzed by default
/// but can be kept real for tracker-specific bugs.
public struct SnapshotRedactionOptions: Sendable, Equatable {
    /// Keep real torrent / file / label names instead of fuzzing them.
    public var includeNames: Bool
    /// Fuzz tracker hosts (→ `tracker-N.invalid`) and sitenames. Passkeys in
    /// announce URLs are always stripped regardless of this flag.
    public var anonymizeTrackers: Bool
    /// Keep real infohashes instead of fuzzing them.
    public var includeHashes: Bool
    /// Keep real timestamps instead of shifting them to a fixed anchor.
    public var preserveTimestamps: Bool
    /// Cap on how many torrents a capture keeps (`nil` = all). Applied after
    /// the filter scope, in the currently-visible sort order — so with the
    /// defaults you get the top 10 torrents you're looking at.
    public var maxTorrents: Int?
    /// Only capture torrents currently visible under the app's filters/search.
    public var respectFilters: Bool

    public init(
        includeNames: Bool = true,
        anonymizeTrackers: Bool = true,
        includeHashes: Bool = false,
        preserveTimestamps: Bool = false,
        maxTorrents: Int? = 10,
        respectFilters: Bool = true
    ) {
        self.includeNames = includeNames
        self.anonymizeTrackers = anonymizeTrackers
        self.includeHashes = includeHashes
        self.preserveTimestamps = preserveTimestamps
        self.maxTorrents = maxTorrents
        self.respectFilters = respectFilters
    }
}

/// What a capture produced — the redaction summary plus how many torrents were
/// actually captured (after filter scope + limit), for the result alert.
public struct SnapshotCaptureResult: Sendable, Equatable {
    public var summary: SnapshotRedactionSummary
    public var torrentCount: Int

    public init(summary: SnapshotRedactionSummary, torrentCount: Int) {
        self.summary = summary
        self.torrentCount = torrentCount
    }
}

/// Capture-scope slicing: which torrents a snapshot includes. Lives at the
/// store level because filters/sort are UI state, not wire data.
public enum SnapshotScope {
    /// Filters `wires` down to the ids in `visibleOrder`, preserving that
    /// order (i.e. the torrents the user is currently looking at, in the
    /// current sort), then caps at `maxTorrents`. `nil` visibleOrder keeps
    /// everything in daemon order; `nil` maxTorrents means no cap.
    public static func apply(
        to wires: [WireTorrent],
        visibleOrder: [Torrent.ID]?,
        maxTorrents: Int?
    ) -> [WireTorrent] {
        var scoped = wires
        if let visibleOrder {
            let position = Dictionary(
                uniqueKeysWithValues: visibleOrder.enumerated().map {
                    ($1, $0)
                })
            scoped =
                scoped
                .filter { position[$0.id] != nil }
                .sorted { position[$0.id]! < position[$1.id]! }
        }
        if let maxTorrents, maxTorrents > 0 {
            scoped = Array(scoped.prefix(maxTorrents))
        }
        return scoped
    }
}
/// What the redaction pass changed, both for the capture-complete alert and as
/// provenance embedded in the snapshot file.
public struct SnapshotRedactionSummary: Codable, Sendable, Equatable {
    public var trackerURLs: Int
    public var passkeysStripped: Int
    public var peerIPs: Int
    public var names: Int
    public var hashes: Int
    public var paths: Int
    public var freeTextFields: Int
    public var timestampsShifted: Bool

    public init(
        trackerURLs: Int = 0,
        passkeysStripped: Int = 0,
        peerIPs: Int = 0,
        names: Int = 0,
        hashes: Int = 0,
        paths: Int = 0,
        freeTextFields: Int = 0,
        timestampsShifted: Bool = false
    ) {
        self.trackerURLs = trackerURLs
        self.passkeysStripped = passkeysStripped
        self.peerIPs = peerIPs
        self.names = names
        self.hashes = hashes
        self.paths = paths
        self.freeTextFields = freeTextFields
        self.timestampsShifted = timestampsShifted
    }

    /// One-line summary for the capture-complete alert.
    public var summaryText: String {
        var parts: [String] = []
        if trackerURLs > 0 { parts.append("\(trackerURLs) tracker URL\(trackerURLs == 1 ? "" : "s")") }
        if passkeysStripped > 0 { parts.append("\(passkeysStripped) passkey\(passkeysStripped == 1 ? "" : "s")") }
        if peerIPs > 0 { parts.append("\(peerIPs) peer IP\(peerIPs == 1 ? "" : "s")") }
        if names > 0 { parts.append("\(names) name\(names == 1 ? "" : "s")") }
        if hashes > 0 { parts.append("\(hashes) hash\(hashes == 1 ? "" : "es")") }
        if paths > 0 { parts.append("\(paths) path\(paths == 1 ? "" : "s")") }
        if freeTextFields > 0 { parts.append("\(freeTextFields) message\(freeTextFields == 1 ? "" : "s")") }
        let joined = parts.isEmpty ? "nothing" : parts.joined(separator: ", ")
        let timeNote = timestampsShifted ? " timestamps shifted" : ""
        return "Redacted \(joined)\(timeNote)."
    }
}
