// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Testing

@testable import TransmissionCore

@Suite("EmptyTorrentService")
struct EmptyTorrentServiceTests {
    @Test("reports no torrents and a plausible session")
    func placeholderState() async throws {
        let service = EmptyTorrentService()
        #expect(try await service.torrents().isEmpty)
        #expect(await service.sessionSettings() != nil)
        #expect(await service.isAlternativeSpeedEnabled() == false)
        #expect(await service.isPortOpen() == true)
        #expect(await service.freeSpace() == nil)
    }

    @Test("the torrent stream yields an empty snapshot and stays open")
    func streamYieldsEmptySnapshot() async throws {
        let service = EmptyTorrentService()
        var iterator = service.torrentsStream().makeAsyncIterator()
        let first = try await iterator.next()
        #expect(first?.isEmpty == true)
    }
}
