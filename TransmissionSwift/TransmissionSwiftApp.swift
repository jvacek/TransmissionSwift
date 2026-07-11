//
//  TransmissionSwiftApp.swift
//  TransmissionSwift
//
//  Created by Jonas Vacek on 10/06/2026.
//

import AppKit
import Sparkle
import SwiftUI
import TransmissionCore

@main
struct TransmissionSwiftApp: App {
    @State private var profileStore: ServerProfileStore
    @State private var torrentStore: TorrentStore
    @State private var faviconStore = FaviconStore()
    private let mockMode: Bool
    private let updateService = UpdateService()

    init() {
        UserDefaults.standard.register(defaults: ["pollingIntervalSeconds": 5.0])
        #if PRERELEASE
        UserDefaults.standard.register(defaults: ["includePrereleases": true])
        #endif

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
        Window("TransmissionSwift", id: "main") {
            ContentView(mockMode: mockMode)
                .environment(profileStore)
                .environment(torrentStore)
                .environment(faviconStore)
                .onOpenURL { url in
                    // Fires for both magnet: links (CFBundleURLTypes) and
                    // double-clicked / "Open With" .torrent files
                    // (CFBundleDocumentTypes). Reuses the same add-sheet flow as
                    // drag-and-drop in MainWindow.
                    if url.scheme == "magnet" {
                        torrentStore.openAddSheet(magnetMode: true, prefilledURL: url)
                    } else if url.isFileURL {
                        torrentStore.openAddSheet(prefilledURL: url)
                    }
                }
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updateService.checkForUpdates(nil)
                }
            }
            CommandMenu("Server") {
                if profileStore.profiles.isEmpty {
                    Text("No servers configured")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(profileStore.profiles.enumerated()), id: \.element.id) {
                        index, profile in
                        Toggle(
                            isOn: Binding(
                                get: { profileStore.activeProfile?.id == profile.id },
                                set: { on in if on { try? profileStore.setActive(profile.id) } }
                            )
                        ) {
                            Text(profile.label)
                        }
                        .keyboardShortcut(
                            index < 9
                                ? KeyEquivalent(Character(String(index + 1))) : KeyEquivalent("0"),
                            modifiers: .command
                        )
                    }
                }
                Divider()
                Button("Server Settings…") {
                    UserDefaults.standard.set(4, forKey: "prefsPendingNavTab")
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
            }
        }

        Settings {
            PreferencesView()
                .environment(profileStore)
                .environment(faviconStore)
        }
    }
}
