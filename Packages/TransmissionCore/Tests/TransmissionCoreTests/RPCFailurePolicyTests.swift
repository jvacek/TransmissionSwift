// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import TransmissionRPC

@testable import TransmissionCore

/// When a failed poll retries and when it ends the stream.
@Suite("RPCTorrentService — failure policy")
struct RPCFailurePolicyTests {
    @Test("fatal errors end the stream at once")
    func fatalStopsImmediately() {
        #expect(RPCTorrentService.shouldStop(for: .unauthorized))
        #expect(RPCTorrentService.shouldStop(for: .network(URLError(.badURL))))
        #expect(RPCTorrentService.shouldStop(for: .network(URLError(.unsupportedURL))))
    }

    @Test("recoverable errors retry forever, however many have failed")
    func recoverableNeverStops() {
        let timeout = TransmissionError.network(URLError(.timedOut))
        #expect(!RPCTorrentService.shouldStop(for: timeout))
        #expect(!RPCTorrentService.shouldStop(for: .serverError("boom")))
        #expect(!RPCTorrentService.shouldStop(for: .decoding("junk")))
    }

    @Test("retry delay starts at 5s and caps at 10s")
    func retryDelayCaps() {
        #expect(RPCTorrentService.retryDelay(afterFailures: 1) == 5)
        #expect(RPCTorrentService.retryDelay(afterFailures: 2) == 10)
        #expect(RPCTorrentService.retryDelay(afterFailures: 3) == 10)
        #expect(RPCTorrentService.retryDelay(afterFailures: 1_000) == 10)
    }

    @Test("4xx HTTP statuses are fatal; timeouts, throttling and 5xx retry")
    func httpStatusPolicy() {
        #expect(RPCTorrentService.shouldStop(for: .http(status: 404, body: "")))
        #expect(RPCTorrentService.shouldStop(for: .http(status: 409, body: "")))
        #expect(!RPCTorrentService.shouldStop(for: .http(status: 408, body: "")))
        #expect(!RPCTorrentService.shouldStop(for: .http(status: 429, body: "")))
        #expect(!RPCTorrentService.shouldStop(for: .http(status: 500, body: "")))
        #expect(!RPCTorrentService.shouldStop(for: .http(status: 302, body: "")))
    }
}
