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
