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
}
