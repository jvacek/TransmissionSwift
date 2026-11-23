// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Testing
import TransmissionCore
import TransmissionTestSupport

@testable import TransmissionSwift

/// The Edit Labels sheet: it seeds with the union of the selection's labels,
/// and applies only what the user added or removed to each torrent.
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

    @Test("an added label goes onto every target without spreading the others")
    func addedLabelOnly() {
        let torrents = MockFixtures.torrents()
        let a = torrents[0].id  // ["Linux"]
        let b = torrents[1].id  // ["3D", "Media"]
        let updates = EditLabelsSheet.labelUpdates(
            torrents, ids: [a, b], initial: ["3D", "Linux", "Media"],
            edited: ["3D", "Linux", "Media", "New"])
        #expect(
            updates == [
                .init(labels: ["3D", "Media", "New"], ids: [b]),
                .init(labels: ["Linux", "New"], ids: [a]),
            ])
    }

    @Test("a removed label comes off every target; untouched torrents are skipped")
    func removedLabel() {
        let torrents = MockFixtures.torrents()
        let a = torrents[0].id
        let b = torrents[1].id
        let updates = EditLabelsSheet.labelUpdates(
            torrents, ids: [a, b], initial: ["3D", "Linux", "Media"], edited: ["Linux", "Media"])
        #expect(updates == [.init(labels: ["Media"], ids: [b])])
    }

    @Test("targets ending up with the same set share one write")
    func groupsBySet() {
        let torrents = MockFixtures.torrents()
        let a = torrents[0].id
        let b = torrents[1].id
        let updates = EditLabelsSheet.labelUpdates(
            torrents, ids: [a, b], initial: ["3D", "Linux", "Media"], edited: ["Only"])
        #expect(updates == [.init(labels: ["Only"], ids: [a, b])])
    }

    @Test("no edit means no writes")
    func unchangedIsEmpty() {
        let torrents = MockFixtures.torrents()
        let ids = [torrents[0].id, torrents[1].id]
        let updates = EditLabelsSheet.labelUpdates(
            torrents, ids: ids, initial: ["3D", "Linux", "Media"],
            edited: ["Media", "3D", "Linux"])
        #expect(updates.isEmpty)
    }
}
