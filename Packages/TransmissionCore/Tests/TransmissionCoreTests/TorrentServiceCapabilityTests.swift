// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Testing
import TransmissionCore
import TransmissionTestSupport

/// The `TorrentReading.mutations` accessor callers use to resolve the optional
/// mutation half without a repeated `as?` downcast.
@Suite("TorrentReading.mutations")
struct TorrentServiceCapabilityTests {
    @Test("is non-nil for a mutable service")
    func nonNilForMutable() {
        let service: any TorrentReading = MockTorrentService()
        #expect(service.mutations != nil)
    }

    @Test("is nil for a read-only service")
    func nilForReadOnly() {
        let service: any TorrentReading = EmptyTorrentService()
        #expect(service.mutations == nil)
    }
}
