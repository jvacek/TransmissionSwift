import Foundation
import Testing

@testable import TransmissionCore
@testable import TransmissionRPC

@Suite("SessionSettings")
struct SessionSettingsTests {
    @Test("wire mapping decodes values and defaults absent fields")
    func wireMapping() {
        var wire = SessionInfo(version: "4.0.6", rpcVersion: 17, rpcVersionMinimum: 14)
        wire.speedLimitDown = 1000
        wire.speedLimitDownEnabled = true
        wire.altSpeedDown = 50
        wire.altSpeedTimeBegin = 540
        wire.altSpeedTimeEnd = 1020
        wire.altSpeedTimeDay = 0b0111110
        wire.peerPort = 51413
        wire.lpdEnabled = false
        wire.encryption = "required"
        wire.seedRatioLimit = 1.5
        wire.seedRatioLimited = true
        wire.idleSeedingLimit = 30
        wire.idleSeedingLimitEnabled = false

        let settings = SessionSettings(wire: wire)

        #expect(settings.downLimited == true)
        #expect(settings.downLimitKBps == 1000)
        #expect(settings.altSpeedDownKBps == 50)
        #expect(settings.altSpeedTimeBeginMinutes == 540)
        #expect(settings.altSpeedTimeEndMinutes == 1020)
        #expect(settings.altSpeedTimeDayMask == 0b0111110)
        #expect(settings.peerPort == 51413)
        #expect(settings.lpdEnabled == false)
        #expect(settings.encryption == .required)
        #expect(settings.seedRatioLimit == 1.5)
        #expect(settings.seedRatioLimited == true)
        #expect(settings.idleSeedingLimitMinutes == 30)
        #expect(settings.idleSeedingLimitEnabled == false)
        // Defaults for absent fields.
        #expect(settings.utpEnabled == true)
        #expect(settings.blocklistEnabled == false)
        #expect(settings.blocklistURL == "")
    }

    @Test("unknown encryption string defaults to .preferred")
    func unknownEncryptionDefaults() {
        var wire = SessionInfo(version: "4.0.6", rpcVersion: 17, rpcVersionMinimum: 14)
        wire.encryption = "bogus"
        #expect(SessionSettings(wire: wire).encryption == .preferred)
    }
}

@Suite("SessionSettingsPatch")
struct SessionSettingsPatchTests {
    @Test("diff only includes changed fields")
    func diff() {
        var before = SessionSettings.sample
        var updated = before
        updated.downLimitKBps = 2000
        updated.altSpeedEnabled = false

        let patch = SessionSettingsPatch(before: before, updated: updated)

        #expect(patch.downLimitKBps == 2000)
        #expect(patch.altSpeedEnabled == false)
        #expect(patch.downLimited == nil)
        #expect(patch.seedRatioLimit == nil)
    }

    @Test("unchanged settings produce a diff with no changed fields")
    func noChange() {
        let a = SessionSettings.sample
        let b = SessionSettings.sample
        #expect(SessionSettingsPatch(before: a, updated: b).isEmpty)
    }

    @Test("apply populates only non-nil fields onto SessionSetArguments")
    func applyMapsToArguments() throws {
        var args = SessionSetArguments()
        var before = SessionSettings.sample
        var updated = before
        updated.peerPort = 9090
        updated.encryption = .tolerated
        SessionSettingsPatch(before: before, updated: updated).apply(to: &args)

        let data = try JSONEncoder().encode(args)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["peer-port"] as? Int == 9090)
        #expect(json["encryption"] as? String == "tolerated")
        #expect(json["speed-limit-down"] == nil)
        #expect(json["utp-enabled"] == nil)
    }
}

@Suite("MockTorrentService session settings")
struct MockSessionSettingsTests {
    @Test("sessionSettings returns the sample and reflects applied patches")
    func appliesPatches() async throws {
        let service = MockTorrentService()
        let initial = await service.sessionSettings()
        #expect(initial == .sample)

        let patch = SessionSettingsPatch(
            before: SessionSettings.sample,
            updated: {
                var s = SessionSettings.sample
                s.peerPort = 9090
                return s
            }()
        )
        try await service.applySessionSettings(patch)
        let after = await service.sessionSettings()
        #expect(after?.peerPort == 9090)
        #expect(after?.downLimitKBps == SessionSettings.sample.downLimitKBps)
    }

    @Test("alt-speed toggle syncs the session settings value")
    func altSpeedSyncs() async throws {
        let service = MockTorrentService()
        #expect(await service.isAlternativeSpeedEnabled() == false)
        try await service.setAlternativeSpeedEnabled(true)
        let settings = await service.sessionSettings()
        #expect(settings?.altSpeedEnabled == true)
        #expect(await service.isAlternativeSpeedEnabled() == true)
    }
}

@Suite("TorrentStore.isConnected")
struct StoreIsConnectedTests {
    @MainActor
    @Test("reflects the connection state")
    func reflectsConnection() {
        let store = TorrentStore(service: MockTorrentService())
        // init leaves the state as .connecting (not yet connected).
        #expect(!store.isConnected)

        store.simulateConnection(.connected)
        #expect(store.isConnected)

        store.simulateConnection(.disconnected(reason: "offline"))
        #expect(!store.isConnected)
    }
}
