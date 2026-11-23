// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Testing
import TransmissionCore

@testable import TransmissionSwift

/// `--snapshot-poll` / `--snapshot-latency`: a replay that ticks like a live,
/// slow daemon. Anything missing or malformed falls back to a frozen replay.
@Suite("Snapshot replay launch options")
@MainActor
struct SnapshotReplayLaunchOptionsTests {
    @Test func defaultsToFrozen() {
        #expect(TransmissionSwiftApp.parseReplayOptions(from: ["--snapshot", "x.json"]) == .frozen)
    }

    @Test func readsPollAndLatencyInSeconds() {
        let options = TransmissionSwiftApp.parseReplayOptions(from: [
            "--snapshot", "x.json", "--snapshot-poll", "1.5", "--snapshot-latency", "0.25",
        ])
        #expect(options.pollInterval == .milliseconds(1500))
        #expect(options.latency == .milliseconds(250))
    }

    @Test func ignoresMalformedOrZeroValues() {
        let options = TransmissionSwiftApp.parseReplayOptions(from: [
            "--snapshot-poll", "0", "--snapshot-latency", "fast",
        ])
        #expect(options == .frozen)
        #expect(TransmissionSwiftApp.parseReplayOptions(from: ["--snapshot-poll"]) == .frozen)
    }
}
