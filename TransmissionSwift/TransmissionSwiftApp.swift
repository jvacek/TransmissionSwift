//
//  TransmissionSwiftApp.swift
//  TransmissionSwift
//
//  Created by Jonas Vacek on 10/06/2026.
//

import SwiftUI
import TransmissionCore

@main
struct TransmissionSwiftApp: App {
    @State private var profileStore: ServerProfileStore
    @State private var torrentStore: TorrentStore
    private let mockMode: Bool

    init() {
        let args = CommandLine.arguments
        self.mockMode = args.contains("--mock-data")

        // --- profile store
        let profileURL: URL
        if args.contains("--ephemeral-profiles") {
            profileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("ephemeral-profiles-\(UUID().uuidString)", isDirectory: true)
                .appendingPathComponent("servers.json")
        } else {
            profileURL =
                (try? ServerProfileStore.defaultFileURL())
                ?? FileManager.default.temporaryDirectory.appendingPathComponent("servers.json")
        }
        self._profileStore = State(wrappedValue: ServerProfileStore(fileURL: profileURL))

        // --- torrent store
        // In mock mode we seed from `MockFixtures` and let the service tick
        // progress forward. Otherwise we hand the store an empty mock — the
        // real RPC-backed service lands in slice 7 of doc/ui-buildout.md.
        let mock = self.mockMode ? MockTorrentService() : MockTorrentService(initial: [])
        let store = TorrentStore(service: mock)
        self._torrentStore = State(wrappedValue: store)
        if self.mockMode {
            Task { await mock.startTicking() }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(mockMode: mockMode)
                .environment(profileStore)
                .environment(torrentStore)
        }
    }
}
