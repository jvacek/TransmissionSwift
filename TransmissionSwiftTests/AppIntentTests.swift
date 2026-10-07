import Foundation
import Testing
import TransmissionCore

@testable import TransmissionSwift

/// Unit coverage for the App Intents surface: `AppEnvironment` resolution, the
/// `Torrent` catalog/stats helpers, and each action's effect on a
/// `MockTorrentService`. Serialized because `AppEnvironment.register` sets a
/// process-wide value.
///
/// Value-returning intents (`GetTorrentsIntent`, `GetFreeSpaceIntent`, …) assert
/// their contract through the integration suite (`AppIntentsUITests`), since an
/// `AppIntent`'s result is opaque to plain unit tests. Here we assert the
/// side effects that matter.
@MainActor
@Suite(.serialized)
struct AppIntentTests {

    // MARK: - Harness

    private struct Harness {
        let environment: AppEnvironment
        let service: MockTorrentService
        let profile: ServerProfile
        let directory: URL
    }

    /// Registers a live-mode `AppEnvironment` backed by a temp `servers.json` and
    /// a connected `MockTorrentService`, so intents resolve without a daemon,
    /// network, or Keychain.
    private func makeHarness() throws -> Harness {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppIntentTests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directory.appendingPathComponent("servers.json")
        let profile = ServerProfile(label: "Test Server", host: "test.local")
        try ServerProfileStore(fileURL: fileURL).add(profile)

        let service = MockTorrentService(initial: MockFixtures.torrents())
        let environment = AppEnvironment(mode: .live, profileFileURL: fileURL)
        environment.setConnected(service, for: profile)
        AppEnvironment.register(environment)
        return Harness(
            environment: environment, service: service, profile: profile, directory: directory)
    }

    private func cleanup(_ harness: Harness) {
        try? FileManager.default.removeItem(at: harness.directory)
    }

    // MARK: - AppEnvironment

    @Test func resolvePrefersChosenThenActive() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppIntentTests-resolve-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ServerProfileStore(fileURL: directory.appendingPathComponent("servers.json"))
        let first = ServerProfile(label: "First", host: "first.local")
        let second = ServerProfile(label: "Second", host: "second.local")
        try store.add(first)
        try store.add(second)
        try store.setActive(second.id)

        let environment = AppEnvironment(
            mode: .live, profileFileURL: directory.appendingPathComponent("servers.json"))

        #expect(environment.resolve(nil)?.id == second.id)
        #expect(environment.resolve(ServerEntity(profile: first))?.id == first.id)

        try store.setActive(first.id)
        #expect(environment.resolve(nil)?.id == first.id)
    }

    @Test func serviceUsesConnectedThenFactoryElseNil() throws {
        let harness = try makeHarness()
        defer { cleanup(harness) }

        #expect((harness.environment.service(for: harness.profile) as? MockTorrentService) === harness.service)

        // An unrelated, valid profile falls through to the factory.
        let other = ServerProfile(label: "Other", host: "other.local")
        let resolved = harness.environment.service(for: other)
        #expect(resolved != nil)
        #expect((resolved as? MockTorrentService) == nil)

        // An invalid host yields no service.
        let invalid = ServerProfile(label: "Invalid", host: "not a valid host")
        #expect(harness.environment.service(for: invalid) == nil)
    }

    // MARK: - Torrent catalog + stats entity

    @Test func catalogEntitiesCarryServerID() async throws {
        let harness = try makeHarness()
        defer { cleanup(harness) }

        let entities = await TorrentCatalog.entities(
            profile: harness.profile, service: harness.service)
        #expect(entities.count == MockFixtures.torrents().count)
        #expect(entities.allSatisfy { $0.serverID == harness.profile.id.uuidString })
    }

    @Test func catalogTargetsAllWhenEmptyAndFiltersWhenSelected() async throws {
        let harness = try makeHarness()
        defer { cleanup(harness) }

        let all = try await TorrentCatalog.targets(
            nil, profile: harness.profile, service: harness.service)
        #expect(all.count == MockFixtures.torrents().count)

        let empty = try await TorrentCatalog.targets(
            [], profile: harness.profile, service: harness.service)
        #expect(empty.count == all.count)

        let chosen = all[1]
        let entity = TorrentEntity(torrent: chosen, serverID: harness.profile.id.uuidString)
        let filtered = try await TorrentCatalog.targets(
            [entity], profile: harness.profile, service: harness.service)
        #expect(filtered.map(\.id) == [chosen.id])
    }

    @Test func entitiesAreUniqueAcrossServersWithTheSameTorrentID() throws {
        let torrent = try #require(MockFixtures.torrents().first)
        let a = TorrentEntity(torrent: torrent, serverID: "server-a")
        let b = TorrentEntity(torrent: torrent, serverID: "server-b")

        // Same numeric torrent id, different servers — the ids must not collide
        // in Spotlight/Shortcuts.
        #expect(a.torrentID == b.torrentID)
        #expect(a.id != b.id)
        #expect(a.id == "server-a/\(torrent.id)")
    }

    @Test func targetsIgnoreSelectionFromAnotherServer() async throws {
        let harness = try makeHarness()
        defer { cleanup(harness) }

        let torrent = try #require(try await harness.service.torrents().first)
        let foreign = TorrentEntity(torrent: torrent, serverID: "some-other-server")
        let targets = try await TorrentCatalog.targets(
            [foreign], profile: harness.profile, service: harness.service)
        // A selection belonging to a different server must not fall back to
        // "every torrent" — it resolves to nothing, and the caller errors.
        #expect(targets.isEmpty)
    }

    @Test func targetsReportUnreachableServerInsteadOfNoResults() async throws {
        let harness = try makeHarness()
        defer { cleanup(harness) }
        await harness.service.setTorrentsError(URLError(.cannotConnectToHost))

        do {
            _ = try await TorrentCatalog.targets(
                nil, profile: harness.profile, service: harness.service)
            Issue.record("Expected an unreachable server to throw")
        } catch let error as IntentError {
            #expect(error.message.contains("Couldn't reach"))
        }
    }

    @Test func pauseSurfacesUnreachableServer() async throws {
        let harness = try makeHarness()
        defer { cleanup(harness) }
        await harness.service.setTorrentsError(URLError(.cannotConnectToHost))

        let intent = PauseTorrentsIntent()
        do {
            _ = try await intent.perform()
            Issue.record("Expected the unreachable server to throw")
        } catch let error as IntentError {
            #expect(error.message.contains("Couldn't reach"))
        }
    }

    @Test func torrentEntityMapsFields() throws {
        let torrent = try #require(MockFixtures.torrents().first)
        let entity = TorrentEntity(torrent: torrent, serverID: "srv")
        #expect(entity.id == "srv/\(torrent.id)")
        #expect(entity.torrentID == torrent.id)
        #expect(entity.serverID == "srv")
        #expect(entity.name == torrent.name)
        #expect(entity.status == torrent.status.rawValue.capitalized)
        #expect(entity.progressPercent == Int((torrent.progress * 100).rounded()))
        #expect(entity.size == Int(torrent.size))
        #expect(entity.downloadSpeed == Int(torrent.downloadSpeed))
        #expect(entity.tracker == torrent.primaryTracker)
        #expect(entity.labels == torrent.labels.joined(separator: ", "))
    }

    @Test func torrentStatusOptionMapsToCoreFilter() {
        #expect(TorrentStatusOption.downloading.filter == .downloading)
        #expect(TorrentStatusOption.active.filter == .active)
        #expect(TorrentStatusOption.paused.filter == .paused)
    }

    @Test func serverStatsEntityFromTorrentsAggregates() {
        let torrents = MockFixtures.torrents()
        let stats = ServerStatsEntity(torrents: torrents, server: "S")
        let active = torrents.filter { $0.status == .downloading || $0.status == .seeding }.count
        #expect(stats.torrentCount == torrents.count)
        #expect(stats.activeCount == active)
        #expect(stats.downloadSpeed == Int(torrents.reduce(Int64(0)) { $0 + $1.downloadSpeed }))
        #expect(stats.uploadSpeed == Int(torrents.reduce(Int64(0)) { $0 + $1.uploadSpeed }))
        #expect(stats.summary.contains("S"))
    }

    @Test func freeSpaceEntityReportsUnit() {
        let entity = FreeSpaceEntity(bytes: 1_500_000_000)
        #expect(entity.bytes == 1_500_000_000)
        #expect(entity.humanized.contains("GB"))
    }

    @Test func statsEntitySingleTorrent() throws {
        let torrent = try #require(MockFixtures.torrents().first { $0.status == .downloading })
        let stats = TorrentStatsEntity(torrent: torrent, server: "S")
        #expect(stats.name == torrent.name)
        #expect(stats.progressPercent == Int((torrent.progress * 100).rounded()))
        #expect(stats.summary.contains(torrent.name))
    }

    // MARK: - Control intents

    @Test func pausePausesAll() async throws {
        let harness = try makeHarness()
        defer { cleanup(harness) }

        let intent = PauseTorrentsIntent()
        intent.torrents = []
        _ = try await intent.perform()

        let torrents = try await harness.service.torrents()
        #expect(!torrents.isEmpty)
        #expect(torrents.allSatisfy { $0.status == .paused })
    }

    @Test func resumeStartsSelected() async throws {
        let harness = try makeHarness()
        defer { cleanup(harness) }

        let before = try await harness.service.torrents()
        let paused = try #require(before.first { $0.status == .paused })

        let intent = ResumeTorrentsIntent()
        intent.torrents = [
            TorrentEntity(torrent: paused, serverID: harness.profile.id.uuidString)
        ]
        _ = try await intent.perform()

        let after = try await harness.service.torrents()
        #expect(after.first { $0.id == paused.id }?.status != .paused)
    }

    @Test func verifyMarksChecking() async throws {
        let harness = try makeHarness()
        defer { cleanup(harness) }

        let target = try #require(try await harness.service.torrents().first { $0.status != .checking })
        let intent = VerifyTorrentsIntent()
        intent.torrents = [
            TorrentEntity(torrent: target, serverID: harness.profile.id.uuidString)
        ]
        _ = try await intent.perform()

        let after = try await harness.service.torrents()
        #expect(after.first { $0.id == target.id }?.status == .checking)
    }

    @Test func reannounceMarksTrackersWorking() async throws {
        let harness = try makeHarness()
        defer { cleanup(harness) }

        let target = try #require(try await harness.service.torrents().first { !$0.trackers.isEmpty })
        let intent = ReannounceTorrentsIntent()
        intent.torrents = [
            TorrentEntity(torrent: target, serverID: harness.profile.id.uuidString)
        ]
        _ = try await intent.perform()

        let after = try await harness.service.torrents()
        let trackers = try #require(after.first { $0.id == target.id }?.trackers)
        #expect(!trackers.isEmpty)
        #expect(trackers.allSatisfy { $0.state == .working })
    }

    @Test func setTurtleModeEnables() async throws {
        let harness = try makeHarness()
        defer { cleanup(harness) }

        let intent = SetTurtleModeIntent()
        intent.enabled = true
        _ = try await intent.perform()

        #expect(await harness.service.isAlternativeSpeedEnabled())
    }

    @Test func setServerSpeedLimitsPatchesSession() async throws {
        let harness = try makeHarness()
        defer { cleanup(harness) }

        let intent = SetServerSpeedLimitsIntent()
        intent.downloadLimited = true
        intent.downloadLimitKBps = 321
        _ = try await intent.perform()

        let settings = try #require(await harness.service.sessionSettings())
        #expect(settings.downLimited)
        #expect(settings.downLimitKBps == 321)
    }

    @Test func setServerSpeedLimitsRejectsNoChange() async throws {
        let harness = try makeHarness()
        defer { cleanup(harness) }

        let intent = SetServerSpeedLimitsIntent()
        await #expect(throws: IntentError.self) { _ = try await intent.perform() }
    }

    @Test func setTorrentSpeedLimitsPatchesOptions() async throws {
        let harness = try makeHarness()
        defer { cleanup(harness) }

        let target = try #require(try await harness.service.torrents().first)
        let intent = SetTorrentSpeedLimitsIntent()
        intent.torrents = [
            TorrentEntity(torrent: target, serverID: harness.profile.id.uuidString)
        ]
        intent.downloadLimited = true
        intent.downloadLimitKBps = 77
        _ = try await intent.perform()

        let after = try await harness.service.torrents()
        let options = try #require(after.first { $0.id == target.id }?.options)
        #expect(options.downloadLimited)
        #expect(options.downloadLimitKBps == 77)
    }

    // MARK: - Add

    @Test func addMagnetAddsTorrent() async throws {
        let harness = try makeHarness()
        defer { cleanup(harness) }

        let before = try await harness.service.torrents().count
        let intent = AddTorrentIntent()
        intent.magnet = URL(string: "magnet:?xt=urn:btih:abc&dn=My%20Torrent")
        _ = try await intent.perform()

        let after = try await harness.service.torrents()
        #expect(after.count == before + 1)
        #expect(after.contains { $0.name == "My Torrent" })
    }

    @Test func addRejectsMissingPayload() async throws {
        let harness = try makeHarness()
        defer { cleanup(harness) }

        let intent = AddTorrentIntent()
        await #expect(throws: IntentError.self) { _ = try await intent.perform() }
    }

    // MARK: - Open + read

    @Test func openTorrentRequestsNavigation() async throws {
        let harness = try makeHarness()
        defer { cleanup(harness) }

        OpenRequestBus.shared.request = nil
        defer { OpenRequestBus.shared.request = nil }

        let torrent = try #require(try await harness.service.torrents().first)
        let intent = OpenTorrentIntent()
        intent.target = TorrentEntity(torrent: torrent, serverID: harness.profile.id.uuidString)
        _ = try await intent.perform()

        #expect(
            OpenRequestBus.shared.request
                == OpenRequest(serverID: harness.profile.id, torrentID: torrent.id))
    }

    @Test func openRequestExpiresIfNeverSatisfied() {
        let bus = OpenRequestBus.shared
        let saved = bus.request
        defer { bus.request = saved }

        bus.request = OpenRequest(serverID: UUID(), torrentID: 7)
        #expect(bus.pending() != nil)

        // A request whose torrent never loads is dropped once its window passes,
        // instead of firing on a much later poll.
        #expect(bus.pending(now: Date().addingTimeInterval(3600)) == nil)
        #expect(bus.request == nil)
    }

    @Test func getTorrentStatsRunsAgainstService() async throws {
        let harness = try makeHarness()
        defer { cleanup(harness) }

        let target = try #require(try await harness.service.torrents().first)
        let intent = GetTorrentStatsIntent()
        intent.torrent = TorrentEntity(torrent: target, serverID: harness.profile.id.uuidString)
        _ = try await intent.perform()
    }

    @Test func getTorrentStatsRejectsUnknownTorrent() async throws {
        let harness = try makeHarness()
        defer { cleanup(harness) }

        let unknown = Torrent(
            id: 9999, name: "Ghost", hash: "", size: 0, status: .paused, progress: 0,
            primaryTracker: "", downloadFolder: "", addedAt: Date(), pieces: 0, pieceSize: 0, havePieces: 0)
        let intent = GetTorrentStatsIntent()
        intent.torrent = TorrentEntity(torrent: unknown, serverID: harness.profile.id.uuidString)
        await #expect(throws: IntentError.self) { _ = try await intent.perform() }
    }
}
