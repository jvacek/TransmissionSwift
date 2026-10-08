import Foundation
import Testing

@testable import TransmissionCore

/// Direct tests for `TorrentListModel` — no service, no coordinator. Exercises
/// the list state machine in isolation: the `setTorrents` cascade, selection
/// pruning, filtering, search, sort and facet/filter maintenance.
@Suite("TorrentListModel")
@MainActor
struct TorrentListModelTests {
    private func loaded(_ torrents: [Torrent] = MockFixtures.torrents()) -> TorrentListModel {
        let model = TorrentListModel()
        model.setTorrents(torrents)
        return model
    }

    @Test("setTorrents prunes selections for torrents the daemon no longer has")
    func prunesSelection() {
        let fixtures = MockFixtures.torrents()
        let model = loaded(fixtures)
        model.selectedTorrentIDs = Set(fixtures.prefix(2).map(\.id))

        model.setTorrents([fixtures[0]])

        #expect(model.selectedTorrentIDs == [fixtures[0].id])
    }

    @Test("an empty snapshot preserves the selection (reconnect must not wipe it)")
    func emptySnapshotKeepsSelection() {
        let fixtures = MockFixtures.torrents()
        let model = loaded(fixtures)
        model.selectedTorrentIDs = [fixtures[0].id]

        model.setTorrents([])

        #expect(model.selectedTorrentIDs == [fixtures[0].id])
        #expect(model.visibleTorrents.isEmpty)
    }

    @Test("a status filter narrows the visible rows")
    func statusFilter() {
        let model = loaded()
        model.setStatusFilter(.downloading)

        #expect(!model.visibleTorrents.isEmpty)
        #expect(model.visibleTorrents.allSatisfy { $0.status == .downloading })
    }

    @Test("search is a case-insensitive name substring")
    func search() {
        let model = loaded()
        model.searchQuery = "debian"

        #expect(model.visibleTorrents.count == 1)
        #expect(model.visibleTorrents.first?.name.contains("Debian") == true)
    }

    @Test("setSortOrder re-sorts the visible rows")
    func sorting() {
        let model = loaded()
        model.setSortOrder(column: .size, ascending: false)

        let sizes = model.visibleTorrents.map(\.size)
        #expect(sizes == sizes.sorted(by: >))
    }

    @Test("a label filter is dropped when its last labelled torrent disappears")
    func prunesLabelFilter() {
        let fixtures = MockFixtures.torrents()
        let model = loaded(fixtures)
        model.toggleLabelFilter("Linux")
        #expect(model.selectedSidebarFilters.contains(.label(name: "Linux")))

        model.setTorrents(fixtures.filter { !$0.labels.contains("Linux") })

        #expect(!model.selectedSidebarFilters.contains(.label(name: "Linux")))
        #expect(model.filterSelection.labels.isEmpty)
    }

    @Test("setDownloadDirectory rebuilds the folder facets against the new base")
    func downloadDirectoryRebuildsFacets() {
        var torrents = MockFixtures.torrents()
        torrents[0].downloadFolder = "/Downloads/Movies/"
        let model = TorrentListModel()
        model.setTorrents(torrents)

        model.setDownloadDirectory("/Downloads")

        // Relativized against the base: the leading "/Downloads/" is stripped.
        #expect(model.facets.folders.map(\.name).contains("Movies"))
    }
}
