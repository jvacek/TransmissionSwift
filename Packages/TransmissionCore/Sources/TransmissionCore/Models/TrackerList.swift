import Foundation

/// Editing for a torrent's announce list in the batch format RPC `torrent-set`
/// takes: one announce URL per line, a blank line between tiers (BEP 12).
///
/// The daemon replaces the whole list, so adding or removing is a
/// read-modify-write: build the new string from the trackers last polled.
public enum TrackerList {
    private typealias Tiers = [[String]]

    /// The wire string for `trackers`, ordered by tier. Entries without an
    /// announce URL are dropped — the daemon can't be told about them.
    public static func wireString(_ trackers: [Tracker]) -> String {
        wireString(tiers(of: trackers))
    }

    /// `trackers` with `announce` added to its last tier. An empty list starts
    /// tier 1.
    public static func adding(_ announce: String, to trackers: [Tracker]) -> String {
        var tiers = tiers(of: trackers)
        if tiers.isEmpty {
            tiers = [[announce]]
        } else {
            tiers[tiers.count - 1].append(announce)
        }
        return wireString(tiers)
    }

    /// `trackers` with `announce` moved into `tier`. Setting the tier of an
    /// existing tier joins it (same-tier trackers race); a tier past the last
    /// one becomes a new backup tier.
    public static func moving(_ announce: String, toTier tier: Int, in trackers: [Tracker]) -> String {
        guard let moving = trackers.first(where: { $0.announce == announce }) else {
            return wireString(trackers)
        }
        var updated = trackers.filter { $0.announce != announce }
        var moved = moving
        moved.tier = tier
        updated.append(moved)
        return wireString(updated)
    }

    /// `trackers` with `announce` swapped for `replacement`, keeping its tier.
    /// This is the move a private torrent needs when its tracker moves domains:
    /// the URL carries the passkey, so it must be carried over exactly.
    public static func replacing(_ announce: String, with replacement: String, in trackers: [Tracker])
        -> String
    {
        guard let existing = trackers.first(where: { $0.announce == announce }) else {
            return wireString(trackers)
        }
        var updated = trackers.filter { $0.announce != announce }
        var replaced = existing
        replaced.announce = replacement
        updated.append(replaced)
        return wireString(updated)
    }

    /// `trackers` without the entry whose announce URL matches. Removing the
    /// last tracker yields an empty string, which clears the list.
    public static func removing(_ announce: String, from trackers: [Tracker]) -> String {
        wireString(tiers(of: trackers).map { $0.filter { $0 != announce } })
    }

    private static func tiers(of trackers: [Tracker]) -> Tiers {
        Dictionary(grouping: trackers.filter { !$0.announce.isEmpty }, by: \.tier)
            .sorted { $0.key < $1.key }
            .map { $0.value.map(\.announce) }
    }

    private static func wireString(_ tiers: Tiers) -> String {
        tiers.filter { !$0.isEmpty }
            .map { $0.joined(separator: "\n") }
            .joined(separator: "\n\n")
    }
}
