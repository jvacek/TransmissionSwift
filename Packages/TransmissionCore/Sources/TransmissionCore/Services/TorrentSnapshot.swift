import Foundation

/// The poll loop's snapshot state: the last full list plus the incremental
/// changes merged into it. A value type so the merge and the schedule can be
/// tested without a clock or a daemon.
struct TorrentSnapshot {
    private(set) var torrents: [Torrent] = []
    private(set) var lastFullPoll: Date?

    /// Start over for a new connection; the next tick is a full poll.
    mutating func reset() {
        torrents = []
        lastFullPoll = nil
    }

    mutating func applyFull(_ fresh: [Torrent], at now: Date) {
        torrents = fresh
        lastFullPoll = now
    }

    /// Overlay a recently-active response. Unlike a partial keyed on cached ids
    /// this can bring torrents we have never seen and ids the daemon removed.
    /// Existing entries keep their order; new ones go on the end until the next
    /// full poll restores the daemon's order.
    mutating func applyChanges(_ fresh: [Torrent], removed: [Torrent.ID]) {
        let dropped = Set(removed)
        // `uniquingKeysWith` rather than `uniqueKeysWithValues`: a duplicate id
        // in a daemon response must not trap.
        var byID = Dictionary(
            fresh.lazy.filter { !dropped.contains($0.id) }.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first })
        var merged = torrents.compactMap { torrent -> Torrent? in
            guard !dropped.contains(torrent.id) else { return nil }
            return byID.removeValue(forKey: torrent.id) ?? torrent
        }
        merged.append(contentsOf: byID.values.sorted { $0.id < $1.id })
        torrents = merged
    }

    /// Full list once per refresh interval, and on the first tick.
    func isFullPollDue(base: TimeInterval, now: Date) -> Bool {
        guard let lastFullPoll else { return true }
        return now.timeIntervalSince(lastFullPoll) >= base
    }
}
