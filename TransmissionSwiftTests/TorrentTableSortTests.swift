// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
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

/// Fast header clicks arrive with a click count of 2+, which AppKit would send to
/// the table's double action instead of sorting. The header resets the count.
@Suite("SortingTableHeaderView")
@MainActor
struct SortingTableHeaderViewTests {
    private func mouseDown(clickCount: Int) throws -> NSEvent {
        try #require(
            NSEvent.mouseEvent(
                with: .leftMouseDown, location: NSPoint(x: 42, y: 7), modifierFlags: [.option],
                timestamp: 12, windowNumber: 0, context: nil, eventNumber: 3,
                clickCount: clickCount, pressure: 1))
    }

    @Test func fastClicksBecomeSingleClicks() throws {
        let double = try mouseDown(clickCount: 2)
        let single = SortingTableHeaderView.singleClick(double)
        #expect(single.clickCount == 1)
        #expect(single.type == .leftMouseDown)
        #expect(single.locationInWindow == double.locationInWindow)
        #expect(single.modifierFlags.contains(.option))
        #expect(single.timestamp == double.timestamp)
    }

    @Test func singleClicksPassThroughUntouched() throws {
        let event = try mouseDown(clickCount: 1)
        #expect(SortingTableHeaderView.singleClick(event) === event)
    }
}
