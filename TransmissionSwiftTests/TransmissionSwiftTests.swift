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
