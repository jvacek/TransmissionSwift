import Foundation
import Testing
import TransmissionTestSupport

@testable import TransmissionCore

/// Direct tests for `InspectorModel`: the fetch, both refresh gates and the
/// guard that keeps a stale response from winning.
@Suite("InspectorModel")
@MainActor
struct InspectorModelTests {
    /// Isolated defaults: the visibility preference must not leak between tests
    /// or touch the developer's real setting.
    private func ephemeralDefaults() throws -> UserDefaults {
        let suite = "InspectorModelTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("fetch loads the selected torrent's detail from the service")
    func fetchLoadsDetail() async throws {
        let service = MockTorrentService()
        let model = InspectorModel(list: TorrentListModel(), defaults: try ephemeralDefaults())
        model.connect(reading: service)
        let id = MockFixtures.torrents()[0].id

        await model.fetch(for: id)

        #expect(model.detail?.id == id)
    }

    @Test("refreshIfShowing fetches only when the id is the current selection")
    func refreshGate() async throws {
        let service = MockTorrentService()
        let list = TorrentListModel()
        list.setTorrents(MockFixtures.torrents())
        let model = InspectorModel(list: list, defaults: try ephemeralDefaults())
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
    func pollGate() async throws {
        let service = MockTorrentService()
        let list = TorrentListModel()
        list.setTorrents(MockFixtures.torrents())
        let model = InspectorModel(list: list, defaults: try ephemeralDefaults())
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

        // Visible with a selection: one fetch per changed snapshot.
        list.selectedTorrentIDs = [id]
        await model.poll()
        fetches = await service.inspectorFetchCount
        #expect(fetches == 1)
        #expect(model.detail?.id == id)

        // Same snapshot again: nothing new to fetch.
        await model.poll()
        fetches = await service.inspectorFetchCount
        #expect(fetches == 1)

        // A changed torrent refetches.
        var changed = MockFixtures.torrents()
        changed[0].name = "renamed"
        list.setTorrents(changed)
        await model.poll()
        fetches = await service.inspectorFetchCount
        #expect(fetches == 2)
    }

    @Test("poll retries after a failed detail fetch")
    func failedFetchRetries() async throws {
        let reader = FlakyReader()
        let list = TorrentListModel()
        list.setTorrents(MockFixtures.torrents())
        let model = InspectorModel(list: list, defaults: try ephemeralDefaults())
        model.connect(reading: reader)
        let id = MockFixtures.torrents()[0].id
        list.selectedTorrentIDs = [id]

        await model.poll()
        #expect(model.detail == nil)

        // Same list snapshot, but the failure must not have closed the gate.
        await model.poll()
        #expect(model.detail?.id == id)
        let calls = await reader.calls
        #expect(calls == 2)
    }

    @Test("a stale detail response cannot overwrite a newer one")
    func staleResponseDropped() async throws {
        let reader = GatedReader()
        let list = TorrentListModel()
        list.setTorrents(MockFixtures.torrents())
        let model = InspectorModel(list: list, defaults: try ephemeralDefaults())
        model.connect(reading: reader)
        let id = MockFixtures.torrents()[0].id

        // The first fetch blocks inside the reader.
        let stale = Task { _ = await model.fetch(for: id) }
        while !(await reader.isSuspended) {
            try await Task.sleep(for: .milliseconds(5))
        }

        // A newer fetch completes and wins.
        await model.fetch(for: id)
        #expect(model.detail?.name == "newer")

        // The older response now lands; the generation guard drops it.
        await reader.release()
        await stale.value
        #expect(model.detail?.name == "newer")
    }

    @Test("a fetch in flight when the server changes cannot land in the new pane")
    func connectDropsInFlightFetch() async throws {
        let oldServer = GatedReader()
        let list = TorrentListModel()
        list.setTorrents(MockFixtures.torrents())
        let model = InspectorModel(list: list, defaults: try ephemeralDefaults())
        model.connect(reading: oldServer)
        let id = MockFixtures.torrents()[0].id

        let inFlight = Task { _ = await model.fetch(for: id) }
        while !(await oldServer.isSuspended) {
            try await Task.sleep(for: .milliseconds(5))
        }

        // The user switches servers while the old fetch is still in flight.
        model.connect(reading: MockTorrentService())
        await oldServer.release()
        await inFlight.value

        #expect(model.detail == nil)
    }
}

/// Reader whose first detail fetch blocks until `release()`, so the test can
/// make an old response land after a newer one.
private actor GatedReader: TorrentReading {
    private var gate: CheckedContinuation<Void, Never>?
    private(set) var isSuspended = false
    private var calls = 0

    func torrents() async throws -> [Torrent] { [] }
    func torrentsStream() async -> AsyncThrowingStream<[Torrent], Error> {
        AsyncThrowingStream { _ in }
    }
    func isAlternativeSpeedEnabled() async -> Bool { false }

    func inspectorData(for id: Torrent.ID) async throws -> Torrent {
        calls += 1
        let isFirst = calls == 1
        if isFirst {
            await withCheckedContinuation { continuation in
                gate = continuation
                isSuspended = true
            }
        }
        var torrent = MockFixtures.torrents()[0]
        torrent.id = id
        torrent.name = isFirst ? "stale" : "newer"
        return torrent
    }

    func release() {
        gate?.resume()
        gate = nil
    }
}

/// Reader that fails the first detail fetch, so the retry path can be tested.
private actor FlakyReader: TorrentReading {
    private(set) var calls = 0

    func torrents() async throws -> [Torrent] { [] }
    func torrentsStream() async -> AsyncThrowingStream<[Torrent], Error> {
        AsyncThrowingStream { _ in }
    }
    func isAlternativeSpeedEnabled() async -> Bool { false }

    func inspectorData(for id: Torrent.ID) async throws -> Torrent {
        calls += 1
        if calls == 1 {
            throw URLError(.timedOut)
        }
        var torrent = MockFixtures.torrents()[0]
        torrent.id = id
        return torrent
    }
}
