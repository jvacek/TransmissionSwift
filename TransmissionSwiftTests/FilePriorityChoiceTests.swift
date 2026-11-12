// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Testing
import TransmissionCore

@testable import TransmissionSwift

@MainActor
@Suite("FilePriorityChoice")
struct FilePriorityChoiceTests {
    @Test("a wanted file maps to its download priority")
    func wantedPriorities() {
        #expect(FilePriorityChoice(wanted: true, priority: .high) == .high)
        #expect(FilePriorityChoice(wanted: true, priority: .normal) == .normal)
        #expect(FilePriorityChoice(wanted: true, priority: .low) == .low)
    }

    @Test("an unwanted file maps to skip regardless of its priority")
    func unwantedIsSkip() {
        #expect(FilePriorityChoice(wanted: false, priority: .high) == .skip)
        #expect(FilePriorityChoice(wanted: false, priority: .normal) == .skip)
        #expect(FilePriorityChoice(wanted: false, priority: .low) == .skip)
    }

    @Test("choices map back to the priority or a nil priority for skip")
    func priorityRoundTrip() {
        #expect(FilePriorityChoice.high.priority == .high)
        #expect(FilePriorityChoice.normal.priority == .normal)
        #expect(FilePriorityChoice.low.priority == .low)
        #expect(FilePriorityChoice.skip.priority == nil)
    }

    @Test("a torrent file uses its wanted flag and priority")
    func fromTorrentFile() {
        let wanted = TorrentFile(id: 0, name: "a", size: 1, progress: 0, priority: .high)
        let skipped = TorrentFile(
            id: 1, name: "b", size: 1, progress: 0, priority: .high, wanted: false)

        #expect(FilePriorityChoice(file: wanted) == .high)
        #expect(FilePriorityChoice(file: skipped) == .skip)
    }
}
