//
//  AppIntentsUITests.swift
//  TransmissionSwiftUITests
//
//  Integration tests for the App Intents surface, using Apple's
//  `AppIntentsTesting` framework: the app runs in its own process and the
//  intents execute through the real App Intents stack — no mocks, no
//  `@testable import`. See `doc/app-intents.md`.
//
//  Opt-in: AppIntentsTesting requires the app and the test runner to be signed
//  with the same development team, which local ad-hoc builds are not. Set
//  TEST_RUNNER_TRANSMISSION_APPINTENTS=1 and a DEVELOPMENT_TEAM to run these.
//

import AppIntentsTesting
import XCTest

/// These tests boot the app on the committed snapshot fixture (`--snapshot`), so
/// the intents resolve against the frozen 10-torrent dataset via
/// `AppEnvironment` — deterministic, no daemon, no credentials.
@available(macOS 27.0, *)
final class AppIntentsUITests: XCTestCase {
    private let bundleIdentifier = "jvacek.TransmissionSwift"

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

    /// `GetServerStatsIntent` runs end-to-end and returns a summary. Snapshot
    /// replay carries no `session-stats`, so this also exercises the
    /// torrent-derived fallback.
    @MainActor
    func testGetServerStatsFromSnapshot() async throws {
        try launchOnSnapshot()

        let definitions = IntentDefinitions(bundleIdentifier: bundleIdentifier)
        let result = try await definitions.intents["GetServerStatsIntent"]
            .makeIntent()
            .run()

        let summary: String = try result.value
        XCTAssertTrue(
            summary.contains("torrents"),
            "Expected a stats summary, got: \(summary)")
    }

    /// The server-selection contract: the entity query lists the app's
    /// profiles — here the synthetic snapshot profile, proving the intent reads
    /// the app's ephemeral profile file, not the real `servers.json`.
    @MainActor
    func testServerEntityQueryListsSnapshotProfile() async throws {
        try launchOnSnapshot()

        let definitions = IntentDefinitions(bundleIdentifier: bundleIdentifier)
        let entities = try await definitions.entities["ServerEntity"].suggestedEntities()
        XCTAssertFalse(entities.isEmpty, "Expected at least the snapshot profile")

        let labels = try entities.map { (entity: AnyAppEntity) -> String in
            try entity.label
        }
        XCTAssertTrue(
            labels.contains { $0.hasPrefix("Snapshot") },
            "Expected the synthetic snapshot profile, got: \(labels)")
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
