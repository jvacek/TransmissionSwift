import Foundation
import Testing

@testable import TransmissionCore

/// The polling interval rules shared by the preferences pane and the service.
@Suite("PollingIntervals")
struct RPCPollCadenceTests {
    @Test("the incremental interval is capped at 45 seconds and at the refresh interval")
    func intervalClamp() {
        #expect(PollingIntervals.clampedIncremental(1, refresh: 5) == 1)
        #expect(PollingIntervals.clampedIncremental(0, refresh: 5) == 1)
        #expect(PollingIntervals.clampedIncremental(0.4, refresh: 5) == 1)
        #expect(PollingIntervals.clampedIncremental(45, refresh: 300) == 45)
        #expect(PollingIntervals.clampedIncremental(60, refresh: 300) == 45)
        #expect(PollingIntervals.clampedIncremental(120, refresh: 10) == 10)
    }

    @Test("interval values are whole seconds inside their bounds")
    func intervalNormalization() {
        #expect(PollingIntervals.normalized(0, to: PollingIntervals.refresh) == 1)
        #expect(PollingIntervals.normalized(0.5, to: PollingIntervals.refresh) == 1)
        #expect(PollingIntervals.normalized(2.6, to: PollingIntervals.refresh) == 3)
        #expect(PollingIntervals.normalized(600, to: PollingIntervals.refresh) == 300)
        #expect(PollingIntervals.normalized(2, to: PollingIntervals.freeSpace) == 5)
        #expect(PollingIntervals.normalized(7200, to: PollingIntervals.freeSpace) == 3600)
    }
}
