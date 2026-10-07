//
//  AppIntentsUITests.swift
//  TransmissionSwiftUITests
//
//  Integration tests for the App Intents surface, using Apple's
//  `AppIntentsTesting` framework: the app runs in its own process and the
//  intents execute through the real App Intents stack — no mocks, no
//  `@testable import`. See `doc/app-intents.md`.
//
//  Signing-gated: AppIntentsTesting requires the app and the test runner to be
//  signed with the same development team, which local ad-hoc builds are not. Set
//  TEST_RUNNER_TRANSMISSION_APPINTENTS=1 and a DEVELOPMENT_TEAM to run these.
//
//  The framework only exists in the macOS 27 SDK / Xcode 27, so the whole file
//  is compiled out on older toolchains (e.g. a macos-26 CI runner). Runtime
//  availability is still guarded by @available below.
//

#if canImport(AppIntentsTesting)
import AppIntentsTesting
import XCTest

/// These tests boot the app on the committed snapshot fixture (`--snapshot`), so
/// the intents resolve against the frozen 10-torrent dataset via
/// `AppEnvironment` — deterministic, no daemon, no credentials.
@available(macOS 27.0, *)
final class AppIntentsUITests: XCTestCase {
    // The app target's "UI Testing" build configuration (which the scheme's Test
    // action builds) sets PRODUCT_BUNDLE_IDENTIFIER to this value, so the app
    // under test is a different bundle id from the shipping app. IntentDefinitions
    // must look up the app that is actually running, or the framework reports
    // AppIntentsServicesMetadataErrorDomain "… is not present".
    private let bundleIdentifier = "jvacek.TransmissionSwift.uitesting"

    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["TRANSMISSION_APPINTENTS"] == "1",
            """
            AppIntentsTesting needs the app and test runner signed with the same \
            development team; an ad-hoc build fails with \
            AppIntentsServicesSecurityError (code 800). Set \
            TEST_RUNNER_TRANSMISSION_APPINTENTS=1 and DEVELOPMENT_TEAM to enable \
            (see doc/app-intents.md).
            """)
    }

    /// `GetServerStatsIntent` runs end-to-end and returns structured stats.
    /// Snapshot replay carries no `session-stats`, so this also exercises the
    /// torrent-derived fallback (10 fixture torrents).
    @MainActor
    func testGetServerStatsFromSnapshot() async throws {
        try launchOnSnapshot()

        let definitions = IntentDefinitions(bundleIdentifier: bundleIdentifier)
        let result = try await definitions.intents["GetServerStatsIntent"]
            .makeIntent()
            .run()

        let stats: AnyTransientAppEntity = try result.value
        let count: Int = try stats.torrentCount
        XCTAssertEqual(count, 10, "Expected the 10 fixture torrents")
    }

    /// The server-selection contract: the entity query lists the app's
    /// profiles — here the synthetic snapshot profile, proving the intent reads
    /// the app's ephemeral profile file, not the real `servers.json`.
    @MainActor
    func testServerEntityQueryListsSnapshotProfile() async throws {
        try launchOnSnapshot()

        let definitions = IntentDefinitions(bundleIdentifier: bundleIdentifier)
        let entities = try await definitions.entities["ServerEntity"].suggestedEntities()
        // Snapshot replay registers exactly one synthetic server profile. (Entity
        // properties aren't queryable via dynamic lookup unless the entity declares
        // them, so this asserts on the count, not the label.)
        XCTAssertEqual(entities.count, 1, "Expected the single snapshot profile")
    }

    /// The torrent picker lists the snapshot's torrents, so torrent-selection
    /// actions (pause/resume/limits) have real choices.
    @MainActor
    func testTorrentEntityQueryListsSnapshotTorrents() async throws {
        try launchOnSnapshot()

        let definitions = IntentDefinitions(bundleIdentifier: bundleIdentifier)
        let entities = try await definitions.entities["TorrentEntity"].suggestedEntities()
        XCTAssertEqual(entities.count, 10, "Expected the 10 fixture torrents")
    }

    /// Writes are rejected in snapshot replay (`SnapshotTorrentService` throws
    /// `replayReadOnly`), so a mutating action must fail rather than no-op.
    @MainActor
    func testPauseTorrentsRejectedOnReadOnlySnapshot() async throws {
        try launchOnSnapshot()

        let definitions = IntentDefinitions(bundleIdentifier: bundleIdentifier)
        do {
            _ = try await definitions.intents["PauseTorrentsIntent"].makeIntent().run()
            XCTFail("Snapshot replay is read-only; pausing should have failed")
        } catch {
            // Must be the read-only rejection, not an unrelated "no servers" /
            // "couldn't reach" failure — otherwise this passes for the wrong
            // reason and green-lights a broken launch.
            let detail = String(describing: error)
            XCTAssertTrue(
                detail.contains("read-only"),
                "Expected the read-only rejection, got a different failure: \(detail)")
        }
    }

    // MARK: - Helpers

    @MainActor
    private func launchOnSnapshot() throws {
        guard let fixture = fixtureURL() else {
            throw XCTSkip("Missing committed snapshot fixture")
        }
        let app = XCUIApplication()
        app.launchArguments = ["--snapshot", fixture.path]
        app.launch()
    }

    private func fixtureURL() -> URL? {
        let candidates: [URL?] = [
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .appendingPathComponent("Fixtures/snapshot-10-torrents.json"),
            Bundle(for: Self.self).url(forResource: "snapshot-10-torrents", withExtension: "json"),
        ]
        return candidates.compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.path) }
    }
}
#endif
