// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Testing
import TransmissionCore
import TransmissionTestSupport

@testable import TransmissionSwift

/// The Edit Labels sheet's seeding rule. Applying replaces the whole label set
/// on every target, so seeding must never drop a label the user did not edit.
@Suite("EditLabelsSheet")
struct EditLabelsSheetTests {
    @Test("bulk edit seeds the union of the selection's labels")
    func mergedLabelsIsUnion() {
        let torrents = MockFixtures.torrents()
        let ids = [torrents[0].id, torrents[1].id]
        #expect(
            EditLabelsSheet.mergedLabels(torrents, ids: ids)
                == ["3D", "Linux", "Media"])
    }

    @Test("a single selection keeps exactly its own labels")
    func singleSelection() {
        let torrents = MockFixtures.torrents()
        #expect(
            EditLabelsSheet.mergedLabels(torrents, ids: [torrents[1].id])
                == ["3D", "Media"])
    }

    @Test("torrents outside the target set do not contribute labels")
    func ignoresOtherTorrents() {
        let torrents = MockFixtures.torrents()
        #expect(
            EditLabelsSheet.mergedLabels(torrents, ids: [torrents[0].id]) == ["Linux"])
    }
}

/// The Files tab context menu acts on the whole selection when the clicked row
/// is part of it, and on just that row otherwise.
@Suite("InspectorFilesTab")
struct InspectorFilesTabTests {
    @Test func rightClickInsideSelectionTargetsTheSelection() {
        #expect(Set(fileTargetIDs(selected: [1, 2, 3], clicked: 2)) == [1, 2, 3])
    }

    @Test func rightClickOutsideSelectionTargetsOnlyThatRow() {
        #expect(fileTargetIDs(selected: [1, 2], clicked: 3) == [3])
    }

    @Test func emptySelectionTargetsTheClickedRow() {
        #expect(fileTargetIDs(selected: [], clicked: 4) == [4])
    }
}

/// `--snapshot-poll` / `--snapshot-latency`: a replay that ticks like a live,
/// slow daemon. Anything missing or malformed falls back to a frozen replay.
@Suite("Snapshot replay launch options")
@MainActor
struct SnapshotReplayLaunchOptionsTests {
    @Test func defaultsToFrozen() {
        #expect(TransmissionSwiftApp.parseReplayOptions(from: ["--snapshot", "x.json"]) == .frozen)
    }

    @Test func readsPollAndLatencyInSeconds() {
        let options = TransmissionSwiftApp.parseReplayOptions(from: [
            "--snapshot", "x.json", "--snapshot-poll", "1.5", "--snapshot-latency", "0.25",
        ])
        #expect(options.pollInterval == .milliseconds(1500))
        #expect(options.latency == .milliseconds(250))
    }

    @Test func ignoresMalformedOrZeroValues() {
        let options = TransmissionSwiftApp.parseReplayOptions(from: [
            "--snapshot-poll", "0", "--snapshot-latency", "fast",
        ])
        #expect(options == .frozen)
        #expect(TransmissionSwiftApp.parseReplayOptions(from: ["--snapshot-poll"]) == .frozen)
    }
}
