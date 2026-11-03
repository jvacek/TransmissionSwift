import Foundation
import Testing

@testable import TransmissionCore

/// The announce-list wire format behind `torrent-set`'s `trackerList`: one URL
/// per line, a blank line between tiers (BEP 12).
struct TrackerListTests {
    private func tracker(_ announce: String, tier: Int) -> Tracker {
        Tracker(
            tier: tier,
            host: URL(string: announce)?.host ?? announce,
            announce: announce,
            state: .idle,
            statusMessage: "",
            seedCount: 0,
            leechCount: 0,
            downloadCount: 0
        )
    }

    @Test func wireString_groups_by_tier_with_a_blank_line_between() {
        let trackers = [
            tracker("https://tier0-a.example/announce", tier: 0),
            tracker("https://tier1.example/announce", tier: 1),
            tracker("https://tier0-b.example/announce", tier: 0),
        ]
        #expect(
            TrackerList.wireString(trackers)
                == "https://tier0-a.example/announce\nhttps://tier0-b.example/announce\n\nhttps://tier1.example/announce"
        )
    }

    @Test func wireString_is_empty_for_no_trackers() {
        #expect(TrackerList.wireString([]) == "")
    }

    @Test func wireString_drops_trackers_without_an_announce_url() {
        var unknown = tracker("", tier: 1)
        unknown.host = "legacy.example"
        let trackers = [tracker("https://a.example/announce", tier: 0), unknown]
        #expect(TrackerList.wireString(trackers) == "https://a.example/announce")
    }

    @Test func adding_appends_to_the_last_tier() {
        let trackers = [
            tracker("https://a.example/announce", tier: 0),
            tracker("https://b.example/announce", tier: 1),
        ]
        #expect(
            TrackerList.adding("https://c.example/announce", to: trackers)
                == "https://a.example/announce\n\nhttps://b.example/announce\nhttps://c.example/announce"
        )
    }

    @Test func adding_to_an_empty_list_starts_a_single_tier() {
        #expect(
            TrackerList.adding("https://a.example/announce", to: [])
                == "https://a.example/announce")
    }

    @Test func removing_drops_only_the_matching_announce_url() {
        let trackers = [
            tracker("https://a.example/announce", tier: 0),
            tracker("https://b.example/announce", tier: 0),
            tracker("https://c.example/announce", tier: 1),
        ]
        #expect(
            TrackerList.removing("https://b.example/announce", from: trackers)
                == "https://a.example/announce\n\nhttps://c.example/announce"
        )
    }

    @Test func removing_a_tiers_only_tracker_drops_the_tier() {
        let trackers = [
            tracker("https://a.example/announce", tier: 0),
            tracker("https://b.example/announce", tier: 1),
            tracker("https://c.example/announce", tier: 2),
        ]
        #expect(
            TrackerList.removing("https://b.example/announce", from: trackers)
                == "https://a.example/announce\n\nhttps://c.example/announce"
        )
    }

    @Test func removing_the_last_tracker_clears_the_list() {
        let trackers = [tracker("https://a.example/announce", tier: 0)]
        #expect(TrackerList.removing("https://a.example/announce", from: trackers) == "")
    }

    @Test func removing_an_unknown_url_leaves_the_list_unchanged() {
        let trackers = [tracker("https://a.example/announce", tier: 0)]
        #expect(
            TrackerList.removing("https://other.example/announce", from: trackers)
                == "https://a.example/announce")
    }

    @Test func moving_joins_the_target_tier() {
        let trackers = [
            tracker("https://a.example/announce", tier: 0),
            tracker("https://b.example/announce", tier: 1),
        ]
        #expect(
            TrackerList.moving("https://a.example/announce", toTier: 1, in: trackers)
                == "https://b.example/announce\nhttps://a.example/announce"
        )
    }

    @Test func moving_past_the_last_tier_appends_a_new_tier() {
        let trackers = [
            tracker("https://a.example/announce", tier: 0),
            tracker("https://b.example/announce", tier: 1),
        ]
        #expect(
            TrackerList.moving("https://a.example/announce", toTier: 2, in: trackers)
                == "https://b.example/announce\n\nhttps://a.example/announce"
        )
    }

    @Test func moving_out_of_a_middle_tier_collapses_it() {
        let trackers = [
            tracker("https://a.example/announce", tier: 0),
            tracker("https://b.example/announce", tier: 1),
            tracker("https://c.example/announce", tier: 2),
        ]
        // Tiers are positional, so c takes b's place in the new list.
        #expect(
            TrackerList.moving("https://b.example/announce", toTier: 2, in: trackers)
                == "https://a.example/announce\n\nhttps://c.example/announce\nhttps://b.example/announce"
        )
    }

    @Test func moving_an_unknown_url_leaves_the_list_unchanged() {
        let trackers = [tracker("https://a.example/announce", tier: 0)]
        #expect(
            TrackerList.moving("https://other.example/announce", toTier: 3, in: trackers)
                == "https://a.example/announce")
    }

    // MARK: - Replacing

    @Test func replacing_swaps_the_url_and_keeps_the_tier() {
        let trackers = [
            tracker("https://old.example/announce", tier: 0),
            tracker("https://b.example/announce", tier: 1),
        ]
        #expect(
            TrackerList.replacing(
                "https://old.example/announce", with: "https://new.example/announce", in: trackers)
                == "https://new.example/announce\n\nhttps://b.example/announce"
        )
    }

    @Test func replacing_an_unknown_url_leaves_the_list_unchanged() {
        let trackers = [tracker("https://a.example/announce", tier: 0)]
        #expect(
            TrackerList.replacing(
                "https://other.example/announce", with: "https://new.example/announce", in: trackers)
                == "https://a.example/announce")
    }

    // MARK: - Private torrents

    /// A private tracker's announce URL carries the passkey. Nothing may
    /// normalize, escape or drop it while the list is rebuilt.
    @Test func private_announce_url_survives_adding_and_removing() {
        let passkey = "https://tracker.private.example/announce?passkey=abc123&torrent=42"
        let privateTracker = tracker(passkey, tier: 0)
        let publicTracker = tracker("https://open.example/announce", tier: 1)

        #expect(
            TrackerList.adding("https://extra.example/announce", to: [privateTracker, publicTracker])
                == "\(passkey)\n\nhttps://open.example/announce\nhttps://extra.example/announce")
        #expect(
            TrackerList.removing("https://open.example/announce", from: [privateTracker, publicTracker])
                == passkey)
        #expect(
            TrackerList.moving(passkey, toTier: 1, in: [privateTracker, publicTracker])
                == "https://open.example/announce\n\(passkey)")
    }

    @Test func changing_a_private_trackers_domain_keeps_its_passkey() {
        let before = "https://old.private.example/announce?passkey=abc123"
        let after = "https://new.private.example/announce?passkey=abc123"
        let trackers = [
            tracker(before, tier: 0),
            tracker("https://open.example/announce", tier: 1),
        ]
        #expect(
            TrackerList.replacing(before, with: after, in: trackers)
                == "\(after)\n\nhttps://open.example/announce")
    }
}
