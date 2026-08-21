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
    private let snapshotPath: String?
    private let updateService = UpdateService()

    init() {
        UserDefaults.standard.register(defaults: ["pollingIntervalSeconds": 5.0])
        #if PRERELEASE
        UserDefaults.standard.register(defaults: ["includePrereleases": true])
        #endif

        let args = CommandLine.arguments
        let snapshotPath = Self.parseSnapshotPath(from: args)
        self.snapshotPath = snapshotPath
        // --snapshot wins over --mock-data: replaying a captured file supersedes
        // the synthetic fixtures.
        self.mockMode = args.contains("--mock-data") && snapshotPath == nil

        // --- profile store
        // Snapshot replay implies ephemeral profiles so the synthetic
        // "Snapshot — <name>" profile never lands in the real servers.json.
        let ephemeral = args.contains("--ephemeral-profiles") || snapshotPath != nil
        let profileURL: URL
        if ephemeral {
            profileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("ephemeral-profiles-\(UUID().uuidString)", isDirectory: true)
                .appendingPathComponent("servers.json")
        } else {
            profileURL =
                (try? ServerProfileStore.defaultFileURL())
                ?? FileManager.default.temporaryDirectory.appendingPathComponent("servers.json")
        }
        let profileStore = ServerProfileStore(fileURL: profileURL)
        if let snapshotPath {
            let label =
                URL(fileURLWithPath: snapshotPath).deletingPathExtension().lastPathComponent
            try? profileStore.add(
                ServerProfile(label: "Snapshot — \(label)", host: "snapshot", port: 0)
            )
        }
        self._profileStore = State(wrappedValue: profileStore)

        // --- torrent store
        // Snapshot mode decodes the captured file through SnapshotTorrentService
        // (read-only, frozen). Mock mode seeds from `MockFixtures` and ticks
        // progress forward. Otherwise we hand the store an empty mock — the real
        // RPC-backed service lands in slice 7 of doc/ui-buildout.md.
        let service: any TorrentService
        let tickingMock: MockTorrentService?
        if let snapshotPath {
            do {
                service = try SnapshotTorrentService(fileURL: URL(fileURLWithPath: snapshotPath))
                tickingMock = nil
            } catch {
                NSLog("Snapshot load failed: \(error.localizedDescription)")
                service = MockTorrentService(initial: [])
                tickingMock = nil
            }
        } else if self.mockMode {
            let mock = MockTorrentService()
            service = mock
            tickingMock = mock
        } else {
            service = MockTorrentService(initial: [])
            tickingMock = nil
        }
        let store = TorrentStore(service: service)
        self._torrentStore = State(wrappedValue: store)
        if let tickingMock {
            Task { await tickingMock.startTicking() }
        }
    }

    /// Extracts the snapshot path from `--snapshot <path>` or `--snapshot=<path>`.
    private static func parseSnapshotPath(from args: [String]) -> String? {
        if let index = args.firstIndex(of: "--snapshot"), args.indices.contains(index + 1) {
            return args[index + 1]
        }
        if let arg = args.first(where: { $0.hasPrefix("--snapshot=") }) {
            return String(arg.dropFirst("--snapshot=".count))
        }
        return nil
    }

    var body: some Scene {
        Window("TransmissionSwift", id: "main") {
            ContentView(mockMode: mockMode, snapshotMode: snapshotPath != nil)
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
            AboutCommands(updateService: updateService)
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

        Window("About TransmissionSwift", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Settings {
            PreferencesView()
                .environment(profileStore)
                .environment(faviconStore)
                .environment(torrentStore)
        }
    }
}

// MARK: - About commands

private struct AboutCommands: Commands {
    let updateService: UpdateService
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About TransmissionSwift") {
                openWindow(id: "about")
            }
            Button("Check for Updates…") {
                updateService.checkForUpdates(nil)
            }
        }
    }
}
