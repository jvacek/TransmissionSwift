// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing

@testable import TransmissionCore

@Suite("TorrentAddFileSelection")
struct TorrentAddFileSelectionTests {
    @Test("all wanted at normal priority sends no file arguments")
    func defaults() {
        let selection = TorrentAddFileSelection(files: [
            TorrentAddFile(index: 0, path: ["a.txt"], length: 1),
            TorrentAddFile(index: 1, path: ["b.txt"], length: 2),
        ])

        #expect(selection.filesWanted == nil)
        #expect(selection.filesUnwanted == nil)
        #expect(selection.priorityHigh == nil)
        #expect(selection.priorityNormal == nil)
        #expect(selection.priorityLow == nil)
    }

    @Test("unwanted files go in files-unwanted and leave wanted ones")
    func unwanted() {
        let selection = TorrentAddFileSelection(files: [
            TorrentAddFile(index: 0, path: ["a.txt"], length: 1),
            TorrentAddFile(index: 1, path: ["b.txt"], length: 2, wanted: false),
            TorrentAddFile(index: 2, path: ["c.txt"], length: 3),
        ])

        #expect(selection.filesWanted == [0, 2])
        #expect(selection.filesUnwanted == [1])
        #expect(selection.priorityNormal == [0, 2])
        #expect(selection.priorityHigh == nil)
        #expect(selection.priorityLow == nil)
    }

    @Test("priority arrays only cover wanted files")
    func priorities() {
        let selection = TorrentAddFileSelection(files: [
            TorrentAddFile(index: 0, path: ["high"], length: 1, priority: .high),
            TorrentAddFile(index: 1, path: ["normal"], length: 2),
            TorrentAddFile(index: 2, path: ["low"], length: 3, priority: .low),
            TorrentAddFile(index: 3, path: ["skipped"], length: 4, wanted: false, priority: .high),
        ])

        #expect(selection.priorityHigh == [0])
        #expect(selection.priorityNormal == [1])
        #expect(selection.priorityLow == [2])
        #expect(selection.filesUnwanted == [3])
    }

    @Test("all files unwanted still sends the complete unwanted list")
    func everythingUnwanted() {
        let selection = TorrentAddFileSelection(files: [
            TorrentAddFile(index: 0, path: ["a.txt"], length: 1, wanted: false),
            TorrentAddFile(index: 1, path: ["b.txt"], length: 2, wanted: false),
        ])

        #expect(selection.filesWanted == nil)
        #expect(selection.filesUnwanted == [0, 1])
        #expect(selection.priorityHigh == nil)
        #expect(selection.priorityNormal == nil)
        #expect(selection.priorityLow == nil)
    }

    @Test("no files means no arguments")
    func empty() {
        let selection = TorrentAddFileSelection(files: [])

        #expect(selection.filesWanted == nil)
        #expect(selection.filesUnwanted == nil)
        #expect(selection.priorityHigh == nil)
        #expect(selection.priorityNormal == nil)
        #expect(selection.priorityLow == nil)
    }
}
