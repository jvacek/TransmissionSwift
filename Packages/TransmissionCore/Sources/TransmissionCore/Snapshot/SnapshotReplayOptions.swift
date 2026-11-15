// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// How a snapshot replays. Frozen by default; with a poll interval it ticks
/// like a live daemon, so bugs that need a moving list (re-sorts, reloads
/// racing a click) reproduce without a server.
public struct SnapshotReplayOptions: Sendable, Equatable {
    /// Time between simulated polls. Nil replays the frozen capture once.
    public var pollInterval: Duration?
    /// Extra delay on every simulated response, like a slow or remote daemon.
    public var latency: Duration

    public init(pollInterval: Duration? = nil, latency: Duration = .zero) {
        self.pollInterval = pollInterval
        self.latency = latency
    }

    public static let frozen = SnapshotReplayOptions()
}

/// The per-tick changes a live daemon would report: transfer speeds wobble
/// around the captured value, downloads make progress and their ETA follows.
/// Deterministic in (torrent id, tick), so a failing run replays identically.
enum SnapshotLiveSimulation {
    /// Advances `current` by one poll. Speeds derive from `captured` (not the
    /// previous tick) so they wobble around the real value instead of drifting.
    /// Torrents that were idle in the capture stay idle.
    static func tick(
        _ current: [Torrent], captured: [Torrent], number: Int, interval: Duration
    ) -> [Torrent] {
        let baseline = Dictionary(captured.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let seconds =
            Double(interval.components.seconds)
            + Double(interval.components.attoseconds) / 1e18
        return current.map { torrent in
            guard let base = baseline[torrent.id] else { return torrent }
            var next = torrent
            next.downloadSpeed = wobble(base.downloadSpeed, id: torrent.id, tick: number, salt: 1)
            next.uploadSpeed = wobble(base.uploadSpeed, id: torrent.id, tick: number, salt: 2)
            // Older captures carry only size + progress; derive what is left.
            let total = next.sizeWhenDone > 0 ? next.sizeWhenDone : next.size
            let left =
                next.leftUntilDone > 0
                ? next.leftUntilDone : Int64(Double(total) * (1 - next.progress))
            if next.downloadSpeed > 0, left > 0, total > 0 {
                let downloaded = Int64(Double(next.downloadSpeed) * seconds)
                next.leftUntilDone = max(0, left - downloaded)
                next.progress = 1 - Double(next.leftUntilDone) / Double(total)
                next.eta = TimeInterval(next.leftUntilDone / next.downloadSpeed)
            }
            return next
        }
    }

    /// `value` scaled by a factor in 0.5..<1.5, fixed for (id, tick, salt).
    static func wobble(_ value: Int64, id: Int, tick: Int, salt: UInt64) -> Int64 {
        guard value > 0 else { return value }
        // SplitMix64 finaliser: a cheap, well-mixed hash of the inputs.
        var x = UInt64(truncatingIfNeeded: id) &* 0x9E37_79B9_7F4A_7C15
        x ^= UInt64(truncatingIfNeeded: tick) &* 0xBF58_476D_1CE4_E5B9
        x ^= salt &* 0x94D0_49BB_1331_11EB
        x ^= x >> 31
        x &*= 0xBF58_476D_1CE4_E5B9
        x ^= x >> 27
        let factor = 0.5 + Double(x % 1000) / 1000
        return max(1, Int64(Double(value) * factor))
    }
}
