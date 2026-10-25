import Foundation
import Testing
import TransmissionTestSupport

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

    @Test("poll fetches only while the inspector is visible with a selection")
    func pollGate() async {
        // Visibility persists to the shared defaults, so put the real value back.
        let key = PreferenceKeys.inspectorVisible
        let saved = UserDefaults.standard.object(forKey: key)
        defer {
            if let saved {
                UserDefaults.standard.set(saved, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        let service = MockTorrentService()
        let list = TorrentListModel()
        list.setTorrents(MockFixtures.torrents())
        let model = InspectorModel(list: list)
        model.connect(reading: service)
        let id = MockFixtures.torrents()[0].id

        // Hidden: no fetch, even with a selection.
        model.isVisible = false
        list.selectedTorrentIDs = [id]
        await model.poll()
        var fetches = await service.inspectorFetchCount
        #expect(fetches == 0)

        // Visible but nothing selected: no fetch.
        list.selectedTorrentIDs = []
        model.isVisible = true
        await model.poll()
        fetches = await service.inspectorFetchCount
        #expect(fetches == 0)

        // Visible with a selection: one fetch per tick.
        list.selectedTorrentIDs = [id]
        await model.poll()
        fetches = await service.inspectorFetchCount
        #expect(fetches == 1)
        #expect(model.detail?.id == id)

        await model.poll()
        fetches = await service.inspectorFetchCount
        #expect(fetches == 2)
    }
}
