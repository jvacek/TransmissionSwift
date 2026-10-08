import Foundation
import Testing
import TransmissionTestSupport

@testable import TransmissionCore

/// Direct tests for `SessionModel` against the mock service: loads, the turtle
/// toggle, a settings patch, and the port test.
@Suite("SessionModel")
@MainActor
struct SessionModelTests {
    private func connected() async -> (SessionModel, MockTorrentService) {
        let service = MockTorrentService()
        let model = SessionModel()
        model.connect(reading: service, mutations: service)
        await model.load(from: service)
        return (model, service)
    }

    @Test("load pulls the session settings and label support from the service")
    func loadsFromService() async {
        let (model, _) = await connected()

        #expect(model.settings != nil)
        #expect(model.supportsLabels)
    }

    @Test("toggling turtle speed flips the flag and the settings snapshot")
    func togglesAlternativeSpeed() async {
        let (model, service) = await connected()
        #expect(!model.isAlternativeSpeedEnabled)

        await model.toggleAlternativeSpeed()

        #expect(model.isAlternativeSpeedEnabled)
        #expect(model.settings?.altSpeedEnabled == true)
        #expect(await service.isAlternativeSpeedEnabled())
    }

    @Test("a settings patch is applied and re-read from the service")
    func updatesSettings() async {
        let (model, _) = await connected()

        await model.updateSessionSettings {
            $0.downLimited = true
            $0.downLimitKBps = 1234
        }

        #expect(model.settings?.downLimited == true)
        #expect(model.settings?.downLimitKBps == 1234)
    }

    @Test("testPort records the daemon's answer")
    func portTest() async {
        let (model, _) = await connected()

        await model.testPort()

        #expect(model.portIsOpen == true)
    }

    @Test("reset clears the session state")
    func reset() async {
        let (model, _) = await connected()

        model.reset()

        #expect(model.settings == nil)
        #expect(model.freeSpace == nil)
        #expect(model.daemonVersion == nil)
        #expect(!model.isAlternativeSpeedEnabled)
    }
}
