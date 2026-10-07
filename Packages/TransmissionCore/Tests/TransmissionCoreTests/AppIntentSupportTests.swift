import Foundation
import Security
import Testing

@testable import TransmissionCore
@testable import TransmissionRPC

/// A `TransmissionClient` whose `session-get` returns fixed values, used to
/// prove that a cold-cache `RPCTorrentService` warms itself before reading
/// session-derived state.
private actor CacheStubClient: TransmissionClient {
    private let rpcVersion: Int
    private let altSpeedEnabled: Bool
    private let sessionGetError: TransmissionError?
    private(set) var sessionGetCount = 0
    private(set) var lastAddLabels: [String]?
    private(set) var torrentSetCalls: [TorrentSetArguments] = []

    init(rpcVersion: Int, altSpeedEnabled: Bool, sessionGetError: TransmissionError? = nil) {
        self.rpcVersion = rpcVersion
        self.altSpeedEnabled = altSpeedEnabled
        self.sessionGetError = sessionGetError
    }

    func sessionGet() async throws(TransmissionError) -> SessionInfo {
        if let sessionGetError { throw sessionGetError }
        sessionGetCount += 1
        return SessionInfo(
            version: "test", rpcVersion: rpcVersion, rpcVersionMinimum: 16,
            downloadDirFreeSpace: 0, altSpeedEnabled: altSpeedEnabled, downloadDir: "/x")
    }

    func sessionStats() async throws(TransmissionError) -> SessionStats {
        throw TransmissionError.serverError("not used in test")
    }

    func torrentGet(fields: [String], ids: [Int]?) async throws(TransmissionError)
        -> TorrentGetResponse
    {
        TorrentGetResponse(torrents: [])
    }

    func torrentAction(_ method: String, ids: [Int]) async throws(TransmissionError) {}
    func torrentRemove(ids: [Int], deleteLocalData: Bool) async throws(TransmissionError) {}
    func torrentSet(_ args: TorrentSetArguments) async throws(TransmissionError) {
        torrentSetCalls.append(args)
    }

    func torrentAdd(_ args: TorrentAddArguments) async throws(TransmissionError)
        -> TorrentAddResponse
    {
        lastAddLabels = args.labels
        return TorrentAddResponse(torrentAdded: nil, torrentDuplicate: nil)
    }

    func torrentSetLocation(_ args: TorrentSetLocationArguments) async throws(TransmissionError) {}
    func torrentRenamePath(_ args: TorrentRenamePathArguments) async throws(TransmissionError)
        -> TorrentRenamePathResponse
    {
        TorrentRenamePathResponse(id: args.ids.first ?? 0, path: args.path, name: args.name)
    }
    func sessionSet(_ args: SessionSetArguments) async throws(TransmissionError) {}
    func portTest() async throws(TransmissionError) -> Bool { true }
}

@Suite("RPCTorrentService — cold session cache")
struct RPCSessionCacheWarmTests {
    @Test("alt-speed reads true on a cold cache instead of defaulting to off")
    func altSpeedWarmsCache() async {
        let stub = CacheStubClient(rpcVersion: 17, altSpeedEnabled: true)
        let service = RPCTorrentService(client: stub, pollingInterval: { 60 })

        #expect(await service.isAlternativeSpeedEnabled() == true)
        #expect(await stub.sessionGetCount == 1)

        // A second read uses the warmed cache — no extra session-get.
        #expect(await service.isAlternativeSpeedEnabled() == true)
        #expect(await stub.sessionGetCount == 1)
    }

    @Test("add keeps labels on a cold cache by warming the session first")
    func addKeepsLabelsOnColdCache() async throws {
        let stub = CacheStubClient(rpcVersion: 17, altSpeedEnabled: false)
        let service = RPCTorrentService(client: stub, pollingInterval: { 60 })

        try await service.add(
            fileURL: nil, magnetURL: "magnet:?xt=urn:btih:abc",
            destination: "", labels: ["Linux"], priority: .normal, startWhenAdded: true)

        #expect(await stub.sessionGetCount == 1)
        #expect(await stub.lastAddLabels == ["Linux"])
    }

    @Test("add drops labels on a daemon that predates them")
    func addDropsLabelsOnOldDaemon() async throws {
        let stub = CacheStubClient(rpcVersion: 16, altSpeedEnabled: false)
        let service = RPCTorrentService(client: stub, pollingInterval: { 60 })

        try await service.add(
            fileURL: nil, magnetURL: "magnet:?xt=urn:btih:abc",
            destination: "", labels: ["Linux"], priority: .normal, startWhenAdded: true)

        #expect(await stub.lastAddLabels == nil)
    }

    @Test("add fails instead of silently dropping labels when the session is unreadable")
    func addThrowsWhenSessionUnknown() async {
        let stub = CacheStubClient(
            rpcVersion: 17, altSpeedEnabled: false, sessionGetError: .serverError("offline"))
        let service = RPCTorrentService(client: stub, pollingInterval: { 60 })

        await #expect(throws: TransmissionError.self) {
            try await service.add(
                fileURL: nil, magnetURL: "magnet:?xt=urn:btih:abc",
                destination: "", labels: ["Linux"], priority: .normal, startWhenAdded: true)
        }
        #expect(await stub.lastAddLabels == nil)
    }

    @Test("sessionSettings warms the cache once and reuses it")
    func sessionSettingsWarmsCache() async {
        let stub = CacheStubClient(rpcVersion: 17, altSpeedEnabled: true)
        let service = RPCTorrentService(client: stub, pollingInterval: { 60 })

        #expect(await service.sessionSettings() != nil)
        #expect(await service.sessionSettings() != nil)
        // The second read must come from the warmed cache, not a second RPC.
        #expect(await stub.sessionGetCount == 1)
    }

    @Test("setSpeedLimits sends one torrent-set for every id with only the changed fields")
    func setSpeedLimitsBatches() async throws {
        let stub = CacheStubClient(rpcVersion: 17, altSpeedEnabled: false)
        let service = RPCTorrentService(client: stub, pollingInterval: { 60 })

        var patch = TorrentSpeedLimitPatch()
        patch.downloadLimited = true
        patch.downloadLimitKBps = 99
        try await service.setSpeedLimits([1, 2, 3], patch)

        let calls = await stub.torrentSetCalls
        #expect(calls.count == 1)
        #expect(calls.first?.ids == [1, 2, 3])
        #expect(calls.first?.downloadLimited == true)
        #expect(calls.first?.downloadLimit == 99)
        // Untouched fields stay off the wire, so per-torrent settings survive.
        #expect(calls.first?.uploadLimited == nil)
        #expect(calls.first?.uploadLimit == nil)
        #expect(calls.first?.honorsSessionLimits == nil)
    }
}

@Suite("TransmissionServiceFactory")
struct TransmissionServiceFactoryTests {
    @Test("returns nil for a profile with no valid RPC URL")
    func invalidURL() {
        let profile = ServerProfile(label: "x", host: "not a valid host")
        #expect(TransmissionServiceFactory.make(for: profile, credentials: nil) == nil)
    }

    @Test("builds a service for a valid profile")
    func validProfile() {
        let profile = ServerProfile(label: "x", host: "nas.local")
        #expect(TransmissionServiceFactory.make(for: profile, credentials: nil) != nil)
    }

    @Test("a keychain read failure throws instead of becoming a blank password")
    func keychainFailureThrows() {
        let profile = ServerProfile(label: "x", host: "nas.local", username: "u")
        #expect(throws: TransmissionServiceFactory.Failure.keychain(status: errSecInteractionNotAllowed)) {
            _ = try TransmissionServiceFactory.make(
                for: profile,
                passwordProvider: { (_: UUID) throws(KeychainError) -> String? in
                    throw KeychainError(status: errSecInteractionNotAllowed)
                })
        }
    }

    @Test("a missing password entry stays the empty-password path")
    func missingPasswordStaysEmpty() {
        // The app never stores an empty password, so a missing entry is a
        // legitimate username-with-no-password setup, not an error.
        let profile = ServerProfile(label: "x", host: "nas.local", username: "u")
        #expect(throws: Never.self) {
            _ = try TransmissionServiceFactory.make(for: profile, passwordProvider: { _ in nil })
        }
    }

    @Test("throws invalidRPCURL for a profile with no valid RPC URL")
    func invalidURLThrows() {
        let profile = ServerProfile(label: "x", host: "not a valid host")
        #expect(throws: TransmissionServiceFactory.Failure.invalidRPCURL) {
            _ = try TransmissionServiceFactory.make(for: profile) { _ in nil }
        }
    }
}

@Suite("ServerProfileStore — readProfiles")
struct ReadProfilesTests {
    private func tempFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ReadProfiles-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("servers.json")
    }

    @Test("reads profiles and the active id without constructing the store")
    @MainActor
    func readsActiveID() throws {
        let fileURL = tempFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let store = ServerProfileStore(fileURL: fileURL)
        let first = ServerProfile(label: "Home", host: "home.local")
        let second = ServerProfile(label: "Office", host: "office.local")
        try store.add(first)
        try store.add(second)
        try store.setActive(second.id)

        let loaded = ServerProfileStore.readProfiles(from: fileURL)
        #expect(loaded.profiles.map(\.label) == ["Home", "Office"])
        #expect(loaded.activeProfileID == second.id)
    }

    @Test("missing file yields an empty result")
    func missingFile() {
        let loaded = ServerProfileStore.readProfiles(
            from: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)/servers.json"))
        #expect(loaded.profiles.isEmpty)
        #expect(loaded.activeProfileID == nil)
    }
}
