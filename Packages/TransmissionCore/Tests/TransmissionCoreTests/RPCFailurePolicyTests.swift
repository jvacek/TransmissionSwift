import Foundation
import Testing
import TransmissionRPC

@testable import TransmissionCore

/// When a failed poll retries and when it ends the stream.
@Suite("RPCTorrentService — failure policy")
struct RPCFailurePolicyTests {
    @Test("fatal errors end the stream at once")
    func fatalStopsImmediately() {
        #expect(
            RPCTorrentService.failureDecision(for: .unauthorized, consecutiveFailures: 1)
                == .stop)
        #expect(
            RPCTorrentService.failureDecision(
                for: .network(URLError(.badURL)), consecutiveFailures: 1) == .stop)
        #expect(
            RPCTorrentService.failureDecision(
                for: .network(URLError(.unsupportedURL)), consecutiveFailures: 1) == .stop)
    }

    @Test("recoverable errors retry twice and end the stream on the third")
    func recoverableRetriesThenStops() {
        let timeout = TransmissionError.network(URLError(.timedOut))
        #expect(RPCTorrentService.failureDecision(for: timeout, consecutiveFailures: 1) == .retry)
        #expect(RPCTorrentService.failureDecision(for: timeout, consecutiveFailures: 2) == .retry)
        #expect(RPCTorrentService.failureDecision(for: timeout, consecutiveFailures: 3) == .stop)

        let server = TransmissionError.serverError("boom")
        #expect(RPCTorrentService.failureDecision(for: server, consecutiveFailures: 1) == .retry)
    }
}
