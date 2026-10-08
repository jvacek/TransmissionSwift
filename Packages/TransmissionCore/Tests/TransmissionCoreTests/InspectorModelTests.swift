import Foundation
import Testing

@testable import TransmissionCore

/// Direct tests for `InspectorModel`: the fetch and the selection-gated
/// post-mutation refresh.
@Suite("InspectorModel")
@MainActor
struct InspectorModelTests {
    @Test("fetch loads the selected torrent's detail from the service")
    func fetchLoadsDetail() async {
        let service = MockTorrentService()
        let model = InspectorModel(list: TorrentListModel())
        model.connect(reading: service)
        let id = MockFixtures.torrents()[0].id

        await model.fetch(for: id)

        #expect(model.detail?.id == id)
    }

    @Test("refreshIfShowing fetches only when the id is the current selection")
    func refreshGate() async {
        let service = MockTorrentService()
        let list = TorrentListModel()
        list.setTorrents(MockFixtures.torrents())
        let model = InspectorModel(list: list)
        model.connect(reading: service)
        let id = MockFixtures.torrents()[0].id

        // Nothing selected: no fetch.
        await model.refreshIfShowing(id)
        #expect(model.detail == nil)

        // Selected: fetches.
        list.selectedTorrentIDs = [id]
        await model.refreshIfShowing(id)
        #expect(model.detail?.id == id)
    }
}
