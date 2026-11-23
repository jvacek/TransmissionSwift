// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Testing
import TransmissionCore

@testable import TransmissionSwift

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
