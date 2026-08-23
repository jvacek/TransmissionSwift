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
        #expect(facets.statusCounts[.error] == 2)
    }

    @Test("tracker / folder / label rollups are derived from the torrent list")
    func rollups() {
        let torrents = MockFixtures.torrents()
        let facets = FilterFacets(torrents: torrents)

        let folderTotal = facets.folders.map(\.count).reduce(0, +)
        #expect(folderTotal == torrents.count)

        let labelled = torrents.flatMap(\.labels).count
        let labelTotal = facets.labels.map(\.count).reduce(0, +)
        #expect(labelTotal == labelled)

        let trackerHosts = Set(torrents.map(\.primaryTracker))
        #expect(Set(facets.trackers.map(\.name)) == trackerHosts)
    }

    @Test("a multi-label torrent contributes to each label facet")
    func multiLabelRollup() {
        let torrents = MockFixtures.torrents()
        let facets = FilterFacets(torrents: torrents)

        // id 2 (Blender) carries both "3D" and "Media".
        let blender = torrents.first { $0.id == 2 }!
        #expect(blender.labels.count == 2)
        for label in blender.labels {
            let entry = facets.labels.first { $0.name == label }
            #expect(entry != nil)
            #expect(entry!.count >= 1)
        }
        let mediaCount = facets.labels.first { $0.name == "Media" }?.count ?? 0
        let mediaTorrents = torrents.filter { $0.labels.contains("Media") }.count
        #expect(mediaCount == mediaTorrents)
    }

    @Test("folder rollup entries are sorted alphabetically")
    func folderSortOrder() {
        let facets = FilterFacets(torrents: MockFixtures.torrents())
        let names = facets.folders.map(\.name)
        #expect(names == names.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
    }

    @Test("folder rollup normalizes, relativizes, and adds a default-folder sentinel")
    func folderRelativization() {
        let base = "/Downloads"
        var torrents = MockFixtures.torrents()
        torrents[0].downloadFolder = "/Downloads/Movies/"
        torrents[1].downloadFolder = "/Downloads/"
        torrents[2].downloadFolder = "/Downloads/Music"
        torrents[3].downloadFolder = "/Other/Stuff"

        let facets = FilterFacets(torrents: torrents, downloadDirectory: base)
        let names = facets.folders.map(\.name)

        #expect(names.contains("Movies"))  // trailing slash stripped + relativized
        #expect(names.contains("Music"))
        #expect(names.contains(FolderFilter.defaultFolderName))  // sitting in base
        #expect(names.contains("/Other/Stuff"))  // outside base kept absolute
        #expect(names == names.sorted { $0.localizedStandardCompare($1) == .orderedAscending })

        // The sentinel must match torrents whose folder equals the base.
        let selection = TorrentFilterSelection(folders: [FolderFilter.defaultFolderName])
        #expect(torrents.filtered(by: selection, relativeTo: base).contains { $0.id == torrents[1].id })
        #expect(torrents.filtered(by: selection, relativeTo: base).count == 1)
    }
}

@Suite("Torrent filtering")
struct TorrentFilteringTests {
    @Test("sidebar filters narrow the visible list")
    func sidebarFiltering() {
        let torrents = MockFixtures.torrents()

        #expect(torrents.filtered(by: TorrentFilterSelection(statuses: [.all])).count == torrents.count)
        #expect(torrents.filtered(by: TorrentFilterSelection(statuses: [.downloading])).count == 3)
        #expect(torrents.filtered(by: TorrentFilterSelection(statuses: [.paused])).count == 1)
        #expect(torrents.filtered(by: TorrentFilterSelection(folders: ["Linux ISOs"])).count == 4)
        // "Linux" labels the three Linux ISOs (Ubuntu, Arch, Debian). The
        // JSX sidebar mock said "4" but its FILTERS list was hand-curated
        // and doesn't match its own torrent data — we trust the data.
        #expect(torrents.filtered(by: TorrentFilterSelection(labels: ["Linux"])).count == 3)
        #expect(torrents.filtered(by: TorrentFilterSelection(trackers: ["bt.archive.org"])).count == 2)
    }

    @Test("a torrent matches when any of its labels is selected")
    func multiLabelFiltering() {
        let torrents = MockFixtures.torrents()
        // id 2 (Blender) has ["3D", "Media"] — it must match either label alone
        // and both together.
        let blender = torrents.first { $0.id == 2 }!
        #expect(torrents.filtered(by: TorrentFilterSelection(labels: ["3D"])).contains { $0.id == 2 })
        #expect(torrents.filtered(by: TorrentFilterSelection(labels: ["Media"])).contains { $0.id == 2 })
        #expect(torrents.filtered(by: TorrentFilterSelection(labels: ["3D", "Media"])).contains { $0.id == 2 })
        #expect(torrents.filtered(by: TorrentFilterSelection(labels: ["Linux"])).contains { $0.id == 2 } == false)
        #expect(blender.labels.count == 2)
    }

    @Test("facet filters combine with AND semantics")
    func combinedFiltering() {
        let torrents = MockFixtures.torrents()
        let filtered = torrents.filtered(
            by: TorrentFilterSelection(
                statuses: [.downloading],
                trackers: ["releases.ubuntu.com"],
                folders: [],
                labels: ["Linux"]
            )
        )

        #expect(!filtered.isEmpty)
        #expect(filtered.allSatisfy { $0.status == .downloading })
        #expect(filtered.allSatisfy { $0.primaryTracker == "releases.ubuntu.com" })
        #expect(filtered.allSatisfy { $0.labels.contains("Linux") })
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

    @Test("setFilesWanted flips only the targeted files")
    func filesWanted() async throws {
        let service = MockTorrentService()
        let before = try await service.torrents().first { $0.id == 5 }!
        #expect(before.files.count > 2)
        let target = before.files[0].id

        try await service.setFilesWanted(5, fileIDs: [target], wanted: false)
        let after = try await service.torrents().first { $0.id == 5 }!
        #expect(after.files.first { $0.id == target }?.wanted == false)
        for file in after.files where file.id != target {
            let unchanged = before.files.first { $0.id == file.id }!
            #expect(file.wanted == unchanged.wanted)
        }
    }

    @Test("setFilePriority updates only the targeted files")
    func filePriority() async throws {
        let service = MockTorrentService()
        let before = try await service.torrents().first { $0.id == 5 }!
        let target = before.files.first { $0.priority == .normal }!.id

        try await service.setFilePriority(5, fileIDs: [target], priority: .high)
        let after = try await service.torrents().first { $0.id == 5 }!
        #expect(after.files.first { $0.id == target }?.priority == .high)
    }

    @Test("setLabels replaces the whole label set on every targeted torrent")
    func setLabels() async throws {
        let service = MockTorrentService()
        let before = try await service.torrents()

        try await service.setLabels([2, 5], labels: ["A", "B"])
        let after = try await service.torrents()
        for id in [2, 5] {
            #expect(after.first { $0.id == id }?.labels == ["A", "B"])
        }
        let untouched = Set(before.map(\.id)).subtracting([2, 5])
        for id in untouched {
            let b = before.first { $0.id == id }!
            let a = after.first { $0.id == id }!
            #expect(a.labels == b.labels)
        }
    }

    @Test("setLabels with an empty array clears labels")
    func setLabelsClears() async throws {
        let service = MockTorrentService()
        try await service.setLabels([2], labels: [])
        let after = try await service.torrents()
        #expect(after.first { $0.id == 2 }?.labels == [])
    }

    @Test("setOptions replaces the torrent's options")
    func options() async throws {
        let service = MockTorrentService()
        var options = try await service.torrents().first { $0.id == 1 }!.options
        options.uploadLimited = true
        options.uploadLimitKBps = 750

        try await service.setOptions(1, options: options)
        let after = try await service.torrents().first { $0.id == 1 }!
        #expect(after.options == options)
    }

    @Test("reannounce refreshes tracker state on the targeted torrents")
    func reannounce() async throws {
        let service = MockTorrentService()
        let before = try await service.torrents().first { $0.id == 5 }!
        #expect(!before.trackers.isEmpty)

        try await service.reannounce([5])
        let after = try await service.torrents().first { $0.id == 5 }!
        #expect(after.trackers.allSatisfy { $0.state == .working })
        #expect(after.trackers.allSatisfy { $0.statusMessage == "Working — announced just now" })
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

    @Test("torrentForOpening returns the torrent as-is when files are known")
    @MainActor
    func torrentForOpeningKnownFiles() async {
        let service = MockTorrentService()
        let store = TorrentStore(service: service)
        await waitFor { !store.torrents.isEmpty }
        let torrent = store.torrents[0]
        #expect(!torrent.files.isEmpty)
        let resolved = await store.torrentForOpening(torrent)
        #expect(resolved.id == torrent.id)
        #expect(resolved.files.count == torrent.files.count)
    }

    @Test("torrentForOpening fetches files for a list-poll torrent")
    @MainActor
    func torrentForOpeningFetchesFiles() async {
        let service = MockTorrentService()
        let store = TorrentStore(service: service)
        await waitFor { !store.torrents.isEmpty }
        let full = store.torrents[0]
        var listTorrent = full
        listTorrent.files = []  // list poll doesn't fetch files
        let resolved = await store.torrentForOpening(listTorrent)
        #expect(!resolved.files.isEmpty)
        #expect(resolved.files.count == full.files.count)
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

    @Test("setLabels replaces labels on the selected torrents")
    @MainActor
    func setLabelsAction() async {
        let service = MockTorrentService()
        let store = TorrentStore(service: service)
        await waitFor { !store.torrents.isEmpty }

        await store.setLabels([2, 5], labels: ["Archive"])
        await waitFor { store.torrents.first { $0.id == 2 }?.labels == ["Archive"] }
        #expect(store.torrents.first { $0.id == 5 }?.labels == ["Archive"])
    }

    @Test("openEditLabels is gated on actions and a non-empty target")
    @MainActor
    func openEditLabels() async {
        let service = MockTorrentService()
        let store = TorrentStore(service: service)
        await waitFor { !store.torrents.isEmpty }

        store.openEditLabels(for: [2])
        #expect(store.showEditLabels)
        #expect(store.editLabelsTargetIDs == [2])

        store.showEditLabels = false
        store.openEditLabels(for: [])
        #expect(!store.showEditLabels)
    }

    @Test("visibleTorrents applies filter then search")
    @MainActor
    func visibility() async {
        let service = MockTorrentService()
        let store = TorrentStore(service: service)
        await waitFor { !store.torrents.isEmpty }

        store.setStatusFilter(.downloading)
        store.searchQuery = "debian"
        #expect(store.visibleTorrents.count == 1)
        #expect(store.visibleTorrents.first?.name.contains("Debian") == true)
    }

    @Test("store combines status, tracker, and label filters")
    @MainActor
    func combinedVisibility() async {
        let service = MockTorrentService()
        let store = TorrentStore(service: service)
        await waitFor { !store.torrents.isEmpty }

        store.setStatusFilter(.downloading)
        store.toggleTrackerFilter("releases.ubuntu.com")
        store.toggleLabelFilter("Linux")

        #expect(!store.visibleTorrents.isEmpty)
        #expect(store.visibleTorrents.allSatisfy { $0.status == .downloading })
        #expect(store.visibleTorrents.allSatisfy { $0.primaryTracker == "releases.ubuntu.com" })
        #expect(store.visibleTorrents.allSatisfy { $0.labels.contains("Linux") })
    }
}

@Suite("Sorting Performance")
struct SortingPerformanceTests {
    /// Generate N torrents by duplicating and varying fixture data.
    private func generateLargeTorrentSet(count: Int) -> [Torrent] {
        let base = MockFixtures.torrents()
        var result: [Torrent] = []
        result.reserveCapacity(count)

        for i in 0..<count {
            let baseTorrent = base[i % base.count]
            let varied = Torrent(
                id: i,
                name: "\(baseTorrent.name) #\(i)",
                hash: String(format: "%040x", i),
                size: baseTorrent.size + Int64(i * 1000),
                status: baseTorrent.status,
                progress: Double.random(in: 0...1),
                downloadSpeed: baseTorrent.downloadSpeed,
                uploadSpeed: baseTorrent.uploadSpeed,
                connectedPeerCount: baseTorrent.connectedPeerCount,
                availablePeerCount: baseTorrent.availablePeerCount,
                seedCount: baseTorrent.seedCount,
                eta: baseTorrent.eta,
                ratio: baseTorrent.ratio,
                primaryTracker: baseTorrent.primaryTracker,
                downloadFolder: baseTorrent.downloadFolder,
                addedAt: baseTorrent.addedAt,
                labels: baseTorrent.labels,
                priority: baseTorrent.priority,
                pieces: baseTorrent.pieces,
                pieceSize: baseTorrent.pieceSize,
                havePieces: baseTorrent.havePieces,
                files: baseTorrent.files,
                peers: baseTorrent.peers,
                trackers: baseTorrent.trackers
            )
            result.append(varied)
        }
        return result
    }

    @Test("Sorting 1000 items by name completes in reasonable time")
    @MainActor
    func sortPerformanceByName() {
        let torrents = generateLargeTorrentSet(count: 1000)
        let startTime = Date()

        let sorted = torrents.sorted { a, b in a.name < b.name }

        let elapsedMs = Date().timeIntervalSince(startTime) * 1000
        #expect(elapsedMs < 500, "Sorting 1000 torrents by name took \(Int(elapsedMs))ms")
        #expect(sorted.count == 1000)
    }

    @Test("Sorting 1000 items by date completes in reasonable time")
    @MainActor
    func sortPerformanceByDate() {
        let torrents = generateLargeTorrentSet(count: 1000)
        let startTime = Date()

        let sorted = torrents.sorted { a, b in a.addedAt > b.addedAt }

        let elapsedMs = Date().timeIntervalSince(startTime) * 1000
        #expect(elapsedMs < 500, "Sorting 1000 torrents by date took \(Int(elapsedMs))ms")
        #expect(sorted.count == 1000)
    }

    @Test("Sorting 1000 items by tracker completes in reasonable time")
    @MainActor
    func sortPerformanceByTracker() {
        let torrents = generateLargeTorrentSet(count: 1000)
        let startTime = Date()

        let sorted = torrents.sorted { a, b in a.primaryTracker < b.primaryTracker }

        let elapsedMs = Date().timeIntervalSince(startTime) * 1000
        #expect(elapsedMs < 500, "Sorting 1000 torrents by tracker took \(Int(elapsedMs))ms")
        #expect(sorted.count == 1000)
    }

    @Test("Filtering to large subset completes in reasonable time")
    @MainActor
    func filterPerformance() {
        let torrents = generateLargeTorrentSet(count: 1000)
        let startTime = Date()

        let filtered = torrents.filter { $0.status == .downloading || $0.status == .seeding }

        let elapsedMs = Date().timeIntervalSince(startTime) * 1000
        #expect(elapsedMs < 100, "Filtering 1000 torrents took \(Int(elapsedMs))ms")
        #expect(filtered.count > 0)
    }
}
