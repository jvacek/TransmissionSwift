import Foundation
import Testing
import TransmissionCore

@testable import TransmissionSwift

/// Removing a tracker is normally unremarkable: public torrents fall back on
/// DHT, PEX and local peer discovery. A private torrent (BEP 27) may only use
/// the trackers in its own list, so dropping the last one leaves it stranded.
struct PrivateTrackerRemovalTests {
    private func torrent(_ trackerCount: Int, isPrivate: Bool) -> Torrent {
        Torrent(
            id: 1,
            name: "Private",
            hash: String(repeating: "a", count: 40),
            size: 1024,
            status: .seeding,
            progress: 1,
            primaryTracker: "tracker0.example",
            downloadFolder: "/downloads",
            addedAt: Date(),
            pieces: 2,
            pieceSize: 512,
            havePieces: 2,
            trackers: (0..<trackerCount).map { index in
                Tracker(
                    tier: 0,
                    host: "tracker\(index).example",
                    announce: "https://tracker\(index).example/announce",
                    state: .working,
                    statusMessage: "",
                    seedCount: 1,
                    leechCount: 1,
                    downloadCount: 1
                )
            },
            isPrivate: isPrivate
        )
    }

    @Test func the_last_tracker_of_a_private_torrent_needs_confirmation() {
        #expect(trackerRemovalWouldStrand(torrent(1, isPrivate: true)))
    }

    @Test func a_private_torrent_with_another_tracker_left_is_fine() {
        #expect(!trackerRemovalWouldStrand(torrent(2, isPrivate: true)))
    }

    @Test func a_public_torrent_falls_back_on_dht() {
        #expect(!trackerRemovalWouldStrand(torrent(1, isPrivate: false)))
        #expect(!trackerRemovalWouldStrand(torrent(0, isPrivate: true)))
    }
}
