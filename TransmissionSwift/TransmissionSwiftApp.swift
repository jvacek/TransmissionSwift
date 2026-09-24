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
    @State private var tagColorStore: TagColorStore
    private let snapshotPath: String?
    private let updateService = UpdateService()

    init() {
        UserDefaults.standard.register(defaults: [
            "pollingIntervalSeconds": 5.0,
            "showAddDialogBeforeAdding": true,
            "confirmRemove": true,
            "badgeAppIcon": false,
        ])
        #if PRERELEASE
        UserDefaults.standard.register(defaults: ["includePrereleases": true])
        #endif

        let args = CommandLine.arguments
        let snapshotPath = Self.parseSnapshotPath(from: args)
        self.snapshotPath = snapshotPath

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
        // (read-only, frozen). Otherwise we hand the store an empty mock — the real
        // RPC-backed service lands in slice 7 of doc/ui-buildout.md.
        let service: any TorrentService
        var snapshotTagColors: [String: TagColor] = [:]
        if let snapshotPath {
            do {
                let snapshotService = try SnapshotTorrentService(
                    fileURL: URL(fileURLWithPath: snapshotPath))
                // Colours are captured in the snapshot, so replay shows the same
                // assignments without touching the user's real prefs.
                snapshotTagColors = snapshotService.tagColors
                service = snapshotService
            } catch {
                NSLog("Snapshot load failed: \(error.localizedDescription)")
                service = MockTorrentService(initial: [])
            }
        } else {
            service = MockTorrentService(initial: [])
        }
        let store = TorrentStore(service: service)
        self._torrentStore = State(wrappedValue: store)

        let tagColorStore = TagColorStore()
        if !snapshotTagColors.isEmpty {
            tagColorStore.seed(snapshotTagColors)
        }
        self._tagColorStore = State(wrappedValue: tagColorStore)
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
            ContentView(snapshotMode: snapshotPath != nil)
                .environment(profileStore)
                .environment(torrentStore)
                .environment(faviconStore)
                .environment(tagColorStore)
                .onOpenURL { url in
                    // Fires for both magnet: links (CFBundleURLTypes) and
                    // double-clicked / "Open With" .torrent files
                    // (CFBundleDocumentTypes). Reuses the same add flow as
                    // drag-and-drop in MainWindow, honouring the "Show dialog
                    // before adding" pref.
                    torrentStore.addFromExternalURL(url)
                }
        }
        .commands {
            FileCommands(torrentStore: torrentStore)
            AboutCommands(updateService: updateService)
            PreferencesCommands()
            ServerCommands(profileStore: profileStore)
            HelpCommands(torrentStore: torrentStore)
        }

        Window("About TransmissionSwift", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        // A plain Window (not the Settings scene): on macOS 26 the Settings scene
        // always renders an unremovable "<App name> Settings" centered title. A
        // regular window hosting PreferencesView's NavigationSplitView gets the
        // Xcode-Settings look — traffic lights inside the sidebar's glass card.
        // The title is blank: the detail column draws its own pane title in a
        // material inset bar, so a window title would just double it.
        Window("", id: "preferences") {
            PreferencesView()
                .environment(profileStore)
                .environment(faviconStore)
                .environment(torrentStore)
                .environment(tagColorStore)
        }
        // Unified: titlebar and toolbar share one row, so the blank window
        // title doesn't render as a dead strip above the lights/title row.
        .windowToolbarStyle(.unified)
        .defaultSize(width: 880, height: 580)
    }
}

// MARK: - File commands

private struct FileCommands: Commands {
    let torrentStore: TorrentStore

    var body: some Commands {
        CommandGroup(before: .newItem) {
            Button("Add Torrent…") {
                torrentStore.openAddSheet()
            }
            .keyboardShortcut("o", modifiers: .command)

            Button("Add Magnet Link…") {
                torrentStore.openAddSheet(magnetMode: true)
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
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

// MARK: - Preferences commands

/// The Preferences window lives in a plain `Window` scene (so we can hide the
/// title bar), so we re-add the app-menu Settings item manually.
private struct PreferencesCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Preferences…") {
                openWindow(id: "preferences")
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}

// MARK: - Help commands

/// Opens the GitHub bug-report form with the app and daemon versions
/// pre-filled where known. Shared by the Help menu item and the status-bar
/// ladybug button — both read through this one URL builder.
enum BugReport {
    static var appVersion: String? {
        let info = Bundle.main.infoDictionary
        let short = (info?["CFBundleShortVersionString"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let build = (info?["CFBundleVersion"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        if let short, let build {
            return "\(short) (\(build))"
        }
        return short ?? build
    }

    static func url(daemonVersion: String?) -> URL? {
        var components = URLComponents(
            string: "https://github.com/jvacek/TransmissionSwift/issues/new")
        var items = [URLQueryItem(name: "template", value: "bug_report.yml")]
        if let appVersion {
            items.append(URLQueryItem(name: "app-version", value: appVersion))
        }
        if let daemonVersion, !daemonVersion.isEmpty {
            items.append(URLQueryItem(name: "daemon-version", value: daemonVersion))
        }
        items.append(URLQueryItem(name: "macos-version", value: macOSVersion))
        components?.queryItems = items
        return components?.url
    }

    private static var macOSVersion: String {
        ProcessInfo.processInfo.operatingSystemVersionString
    }
}

private struct HelpCommands: Commands {
    let torrentStore: TorrentStore
    @Environment(\.openURL) private var openURL

    var body: some Commands {
        CommandGroup(after: .help) {
            Button("Report Bug…") {
                if let url = BugReport.url(daemonVersion: torrentStore.daemonVersion) {
                    openURL(url)
                }
            }
            .accessibilityIdentifier("help.reportBug")
        }
    }
}

// MARK: - Server commands

private struct ServerCommands: Commands {
    let profileStore: ServerProfileStore
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
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
                UserDefaults.standard.set(PrefsTab.servers.rawValue, forKey: "prefsPendingNavTab")
                openWindow(id: "preferences")
            }
        }
    }
}
