// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing

@testable import TransmissionCore
@testable import TransmissionRPC

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

/// The poll loop against a scripted client: when it gives up and how it
/// reports health across reconnects.
@Suite("RPCTorrentService — poll loop")
struct RPCPollLoopTests {
    private actor ScriptedClient: TransmissionClient {
        private var failing: Bool
        private(set) var pollCount = 0

        init(failing: Bool) { self.failing = failing }

        func setFailing(_ value: Bool) { failing = value }

        func torrentGet(fields: [String], ids: TorrentIDs?) async throws(TransmissionError)
            -> TorrentGetResponse
        {
            pollCount += 1
            if failing { throw TransmissionError.network(URLError(.cannotConnectToHost)) }
            return TorrentGetResponse(torrents: [])
        }

        func sessionGet() async throws(TransmissionError) -> SessionInfo {
            throw TransmissionError.serverError("not used in test")
        }
        func sessionStats() async throws(TransmissionError) -> SessionStats {
            throw TransmissionError.serverError("not used in test")
        }
        func torrentAction(_ method: String, ids: [Int]) async throws(TransmissionError) {}
        func torrentRemove(ids: [Int], deleteLocalData: Bool) async throws(TransmissionError) {}
        func torrentSet(_ args: TorrentSetArguments) async throws(TransmissionError) {}
        func torrentAdd(_ args: TorrentAddArguments) async throws(TransmissionError)
            -> TorrentAddResponse
        {
            TorrentAddResponse(torrentAdded: nil, torrentDuplicate: nil)
        }
        func sessionSet(_ args: SessionSetArguments) async throws(TransmissionError) {}
        func torrentSetLocation(_ args: TorrentSetLocationArguments) async throws(TransmissionError) {}
        func torrentRenamePath(_ args: TorrentRenamePathArguments) async throws(TransmissionError)
            -> TorrentRenamePathResponse
        {
            TorrentRenamePathResponse(id: args.ids.first ?? 0, path: args.path, name: args.name)
        }
        func portTest() async throws(TransmissionError) -> Bool { true }
    }

    private func makeService(_ client: ScriptedClient) -> RPCTorrentService {
        RPCTorrentService(
            client: client,
            pollingInterval: { 0 },
            incrementalPollingInterval: { 0 },
            retryDelayProvider: { _ in 0 })
    }

    @Test("a replaced loop does not finish the next health stream")
    func healthSurvivesReconnect() async throws {
        let client = ScriptedClient(failing: false)
        let service = makeService(client)

        _ = await service.pollHealth()
        let first = await service.torrentsStream()
        var firstIterator = first.makeAsyncIterator()
        _ = try await firstIterator.next()

        let health = await service.pollHealth()
        let second = await service.torrentsStream()
        var secondIterator = second.makeAsyncIterator()
        _ = try await secondIterator.next()

        await client.setFailing(true)
        var sawFailing = false
        for await state in health where state == .failing {
            sawFailing = true
            break
        }
        #expect(sawFailing)
    }
}
