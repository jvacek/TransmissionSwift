// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import TransmissionCore

@testable import TransmissionSwift

/// Pure sort-descriptor normalisation for the single-sort torrent table.
@Suite("TorrentTableSort")
struct TorrentTableSortTests {
    @Test func sort_takesThePrimaryDescriptorNotTheOldest() {
        let descriptors = [
            NSSortDescriptor(key: TableColumn.size.rawValue, ascending: false),
            NSSortDescriptor(key: TableColumn.name.rawValue, ascending: true),
        ]
        let normalized = TorrentTableSort.normalize(descriptors)
        #expect(normalized?.column == .size)
        #expect(normalized?.ascending == false)
    }

    @Test func sort_unknownOrEmptyReturnsNil() {
        #expect(TorrentTableSort.normalize([]) == nil)
        #expect(TorrentTableSort.normalize([NSSortDescriptor(key: "nope", ascending: true)]) == nil)
    }
}
