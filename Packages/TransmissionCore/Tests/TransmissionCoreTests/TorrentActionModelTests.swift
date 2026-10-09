import Foundation
import Testing
import TransmissionTestSupport

@testable import TransmissionCore

/// Direct tests for `TorrentActionModel` against the mock service: simple
/// actions, the staged remove confirmation, labels and rename.
@Suite("TorrentActionModel")
@MainActor
struct TorrentActionModelTests {
    private func make() async throws -> (TorrentActionModel, TorrentListModel, MockTorrentService) {
        let service = MockTorrentService()
        let list = TorrentListModel()
        list.setTorrents(try await service.torrents())
        let inspector = InspectorModel(list: list)
        let actions = TorrentActionModel(list: list, inspector: inspector)
        actions.connect(mutations: service)
        return (actions, list, service)
    }

    @Test("start resumes a paused torrent through the service")
    func start() async throws {
        let (actions, _, service) = try await make()
        let paused = try #require(try await service.torrents().first { $0.status == .paused })

        await actions.start([paused.id])

        let updated = try await service.torrents().first { $0.id == paused.id }
        #expect(updated?.status != .paused)
    }

    @Test("remove prunes the removed ids from the selection")
    func removePrunesSelection() async throws {
        let (actions, list, _) = try await make()
        let id = list.torrents[0].id
        list.selectedTorrentIDs = [id]

        await actions.remove([id])

        #expect(list.selectedTorrentIDs.isEmpty)
    }

    private struct RemoveFailed: Error {}

    @Test("a failed removal keeps the selection and the torrent")
    func removeFailureKeepsSelection() async throws {
        let (actions, list, service) = try await make()
        let id = list.torrents[0].id
        list.selectedTorrentIDs = [id]
        await service.setRemoveError(RemoveFailed())

        await actions.remove([id])

        // The daemon never removed it, so the user's selection must survive.
        #expect(list.selectedTorrentIDs == [id])
        #expect(list.torrents.contains { $0.id == id })
    }

    @Test("requestRemove stages a confirmation when asked, and cancel clears it")
    func requestRemoveStages() async throws {
        let (actions, list, _) = try await make()
        let id = list.torrents[0].id

        actions.requestRemove([id], confirm: true)

        #expect(actions.pendingRemoval?.ids == [id])

        actions.cancelPendingRemoval()
        #expect(actions.pendingRemoval == nil)
    }

    @Test("setLabels replaces the label set through the service")
    func setLabels() async throws {
        let (actions, list, service) = try await make()
        let id = list.torrents[0].id

        await actions.setLabels([id], labels: ["Alpha", "Beta"])

        let updated = try await service.torrents().first { $0.id == id }
        #expect(updated?.labels == ["Alpha", "Beta"])
    }

    @Test("renameTorrent renames the torrent root through the service")
    func rename() async throws {
        let (actions, list, service) = try await make()
        let id = list.torrents[0].id

        let ok = await actions.renameTorrent(id, newName: "Renamed")

        #expect(ok)
        let updated = try await service.torrents().first { $0.id == id }
        #expect(updated?.name == "Renamed")
    }
}
