import Foundation
import Testing

@testable import TransmissionCore

@Suite("FilterFacets")
struct FilterFacetsTests {
    @Test("status buckets account for every fixture")
    func statusCounts() {
        let torrents = MockFixtures.torrents()
        let facets = FilterFacets(torrents: torrents)

        #expect(facets.statusCounts[.all] == torrents.count)
        let active = torrents.filter { $0.status == .downloading || $0.status == .seeding }.count
        #expect(facets.statusCounts[.active] == active)
        #expect(facets.statusCounts[.downloading] == 3)
        #expect(facets.statusCounts[.seeding] == 3)
        #expect(facets.statusCounts[.paused] == 1)
        #expect(facets.statusCounts[.checking] == 1)
        #expect(facets.statusCounts[.queued] == 1)
        #expect(facets.statusCounts[.error] == 1)
    }

    @Test("tracker / folder / label rollups are derived from the torrent list")
    func rollups() {
        let torrents = MockFixtures.torrents()
        let facets = FilterFacets(torrents: torrents)

        let folderTotal = facets.folders.map(\.count).reduce(0, +)
        #expect(folderTotal == torrents.count)

        let labelled = torrents.compactMap(\.label).count
        let labelTotal = facets.labels.map(\.count).reduce(0, +)
        #expect(labelTotal == labelled)

        let trackerHosts = Set(torrents.map(\.primaryTracker))
        #expect(Set(facets.trackers.map(\.name)) == trackerHosts)
    }

    @Test("rollup entries are sorted by descending count then by name")
    func sortOrder() {
        let facets = FilterFacets(torrents: MockFixtures.torrents())
        let counts = facets.folders.map(\.count)
        #expect(counts == counts.sorted(by: >))
    }
}

@Suite("Torrent filtering")
struct TorrentFilteringTests {
    @Test("sidebar filters narrow the visible list")
    func sidebarFiltering() {
        let torrents = MockFixtures.torrents()

        #expect(torrents.filtered(by: .status(.all)).count == torrents.count)
        #expect(torrents.filtered(by: .status(.downloading)).count == 3)
        #expect(torrents.filtered(by: .status(.paused)).count == 1)
        #expect(torrents.filtered(by: .folder(name: "Linux ISOs")).count == 4)
        // "Linux" labels the three Linux ISOs (Ubuntu, Arch, Debian). The
        // JSX sidebar mock said "4" but its FILTERS list was hand-curated
        // and doesn't match its own torrent data — we trust the data.
        #expect(torrents.filtered(by: .label(name: "Linux")).count == 3)
        #expect(torrents.filtered(by: .tracker(host: "bt.archive.org")).count == 2)
    }

    @Test("search is case-insensitive substring on name; empty matches all")
    func searching() {
        let torrents = MockFixtures.torrents()

        #expect(torrents.searched("").count == torrents.count)
        #expect(torrents.searched("   ").count == torrents.count)
        #expect(torrents.searched("ubuntu").count == 1)
        #expect(torrents.searched("UBUNTU").count == 1)
        #expect(torrents.searched("iso").count >= 3)
        #expect(torrents.searched("nope-no-match").isEmpty)
    }
}

@Suite("MockTorrentService")
struct MockTorrentServiceTests {

    @Test("initial snapshot mirrors fixtures")
    func initialSnapshot() async throws {
        let service = MockTorrentService()
        let torrents = try await service.torrents()
        #expect(torrents.count == MockFixtures.torrents().count)
    }

    @Test("tick advances in-flight torrents toward completion")
    func tickAdvancesProgress() async throws {
        let service = MockTorrentService()
        let before = try await service.torrents()
        await service.tick()
        let after = try await service.torrents()

        let downloadingIDs =
            before
            .filter { $0.status == .downloading && $0.downloadSpeed > 0 }
            .map(\.id)
        #expect(!downloadingIDs.isEmpty)
        for id in downloadingIDs {
            let b = before.first { $0.id == id }!
            let a = after.first { $0.id == id }!
            #expect(a.progress > b.progress)
            #expect(a.havePieces >= b.havePieces)
            if let bEta = b.eta, bEta != .infinity, let aEta = a.eta {
                #expect(aEta < bEta)
            }
        }
    }

    @Test("stop pauses, start resumes")
    func startStop() async throws {
        let service = MockTorrentService()
        try await service.stop([1])
        var snapshot = try await service.torrents()
        #expect(snapshot.first { $0.id == 1 }?.status == .paused)

        try await service.start([1])
        snapshot = try await service.torrents()
        #expect(snapshot.first { $0.id == 1 }?.status == .downloading)
    }

    @Test("remove drops the torrent from the snapshot")
    func remove() async throws {
        let service = MockTorrentService()
        try await service.remove([1, 2], deleteLocalData: false)
        let snapshot = try await service.torrents()
        #expect(snapshot.contains { $0.id == 1 } == false)
        #expect(snapshot.contains { $0.id == 2 } == false)
        #expect(snapshot.count == MockFixtures.torrents().count - 2)
    }

    @Test("alt-speed toggle is reflected back")
    func altSpeed() async throws {
        let service = MockTorrentService()
        #expect(await service.isAlternativeSpeedEnabled() == false)
        try await service.setAlternativeSpeedEnabled(true)
        #expect(await service.isAlternativeSpeedEnabled() == true)
    }
}

@Suite("TorrentStore")
struct TorrentStoreTests {

    /// Spins until the predicate holds or the deadline passes. The store's
    /// stream task processes on the MainActor, so this gives the run loop a
    /// chance to drain.
    @MainActor
    private func waitFor(
        timeout seconds: Double = 1,
        _ predicate: () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(seconds)
        while !predicate(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("store receives the initial snapshot from the service")
    @MainActor
    func initialSnapshot() async {
        let service = MockTorrentService()
        let store = TorrentStore(service: service)

        await waitFor { !store.torrents.isEmpty }
        #expect(store.torrents.count == MockFixtures.torrents().count)
        #expect(store.connection == .connected)
    }

    @Test("store mirrors service mutations through the stream")
    @MainActor
    func mirrorsMutations() async throws {
        let service = MockTorrentService()
        let store = TorrentStore(service: service)
        await waitFor { !store.torrents.isEmpty }

        await store.stop([1])
        await waitFor { store.torrents.first { $0.id == 1 }?.status == .paused }
        #expect(store.torrents.first { $0.id == 1 }?.status == .paused)
    }

    @Test("removed selection is cleared")
    @MainActor
    func removeClearsSelection() async {
        let service = MockTorrentService()
        let store = TorrentStore(service: service)
        await waitFor { !store.torrents.isEmpty }

        store.selectedTorrentIDs = [1, 2, 3]
        await store.remove([2])
        #expect(store.selectedTorrentIDs == [1, 3])
    }

    @Test("visibleTorrents applies filter then search")
    @MainActor
    func visibility() async {
        let service = MockTorrentService()
        let store = TorrentStore(service: service)
        await waitFor { !store.torrents.isEmpty }

        store.selectedFilter = .status(.downloading)
        store.searchQuery = "debian"
        #expect(store.visibleTorrents.count == 1)
        #expect(store.visibleTorrents.first?.name.contains("Debian") == true)
    }
}
