import Foundation
import Testing
import TransmissionCore

@testable import TransmissionSwift

/// Unit coverage for the Add Tracker sheet's input checks. Transmission rejects
/// an unparseable announce URL by failing the whole `trackerList` write, so the
/// client filters it out before the round-trip.
struct TrackerAnnounceValidationTests {
    private func tracker(_ announce: String) -> Tracker {
        Tracker(
            tier: 0,
            host: URL(string: announce)?.host ?? announce,
            announce: announce,
            state: .idle,
            statusMessage: "",
            seedCount: 0,
            leechCount: 0,
            downloadCount: 0
        )
    }

    @Test func empty_input_is_rejected() {
        #expect(trackerAnnounceValidation("", existing: []) == "Enter an announce URL.")
        #expect(trackerAnnounceValidation("   ", existing: []) == "Enter an announce URL.")
    }

    @Test func full_urls_on_supported_schemes_are_accepted() {
        for announce in [
            "https://tracker.example.org/announce",
            "http://tracker.example.org:8080/announce",
            "udp://tracker.example.org:1337/announce",
        ] {
            #expect(trackerAnnounceValidation(announce, existing: []) == nil)
        }
    }

    @Test func surrounding_whitespace_is_ignored() {
        #expect(
            trackerAnnounceValidation("  https://tracker.example.org/announce  ", existing: [])
                == nil)
        #expect(
            normalizedTrackerAnnounce("  https://tracker.example.org/announce\n")
                == "https://tracker.example.org/announce")
    }

    @Test func bare_hosts_are_rejected() {
        #expect(
            trackerAnnounceValidation("tracker.example.org/announce", existing: [])
                == "Enter a full announce URL, like https://tracker.example.org/announce.")
    }

    @Test func unsupported_schemes_are_rejected() {
        for announce in [
            "ftp://tracker.example.org/announce",
            "magnet:?xt=urn:btih:abc",
        ] {
            #expect(
                trackerAnnounceValidation(announce, existing: [])
                    == "Enter a full announce URL, like https://tracker.example.org/announce.")
        }
    }

    @Test func a_url_without_a_host_is_rejected() {
        #expect(
            trackerAnnounceValidation("https:///announce", existing: [])
                == "Enter a full announce URL, like https://tracker.example.org/announce.")
    }

    @Test func an_already_listed_tracker_is_rejected() {
        let existing = [tracker("https://tracker.example.org/announce")]
        #expect(
            trackerAnnounceValidation("https://tracker.example.org/announce", existing: existing)
                == "This tracker is already in the list.")
    }

    @Test func duplicate_detection_ignores_case() {
        let existing = [tracker("https://Tracker.Example.org/announce")]
        #expect(
            trackerAnnounceValidation("https://tracker.example.ORG/announce", existing: existing)
                == "This tracker is already in the list.")
    }

    @Test func trackers_without_an_announce_url_never_match() {
        let existing = [
            Tracker(
                tier: 0, host: "legacy.example", state: .idle, statusMessage: "",
                seedCount: 0, leechCount: 0, downloadCount: 0)
        ]
        #expect(trackerAnnounceValidation("https://legacy.example/announce", existing: existing) == nil)
    }

    /// Private trackers put the passkey in the URL. The sheet must hand it to
    /// the daemon exactly as typed.
    @Test func passkey_urls_are_accepted_unchanged() {
        let announce = "https://tracker.private.example/announce?passkey=abc123&torrent=42"
        #expect(trackerAnnounceValidation(announce, existing: []) == nil)
        #expect(normalizedTrackerAnnounce(" \(announce) ") == announce)
    }

    // MARK: - Changing an existing URL

    @Test func replacing_rejects_the_url_it_already_has() {
        let existing = [tracker("https://tracker.example.org/announce")]
        #expect(
            trackerAnnounceValidation(
                "https://tracker.example.org/announce", existing: existing, replacing: existing[0])
                == "Enter a different announce URL.")
    }

    @Test func replacing_rejects_another_trackers_url() {
        let first = tracker("https://a.example/announce")
        let second = tracker("https://b.example/announce")
        #expect(
            trackerAnnounceValidation(
                "https://b.example/announce", existing: [first, second], replacing: first)
                == "This tracker is already in the list.")
    }

    @Test func replacing_accepts_a_new_url_for_the_same_tracker() {
        let existing = [tracker("https://old.private.example/announce?passkey=abc123")]
        #expect(
            trackerAnnounceValidation(
                "https://new.private.example/announce?passkey=abc123", existing: existing,
                replacing: existing[0]) == nil)
    }
}
