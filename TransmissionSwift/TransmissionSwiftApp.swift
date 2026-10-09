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
import os

private let logger = Logger(subsystem: "net.jvacek.TransmissionSwift", category: "App")

@main
struct TransmissionSwiftApp: App {
    @State private var profileStore: ServerProfileStore
    @State private var mappingStore: OpenMappingStore
    @State private var torrentStore: TorrentStore
    @State private var faviconStore = FaviconStore()
    @State private var tagColorStore: TagColorStore
    private let snapshotPath: String?
    private let disableOnboarding: Bool
    private let updateService = UpdateService()

    init() {
        UserDefaults.standard.register(defaults: [
            PreferenceKeys.pollingIntervalSeconds: 5.0,
            PreferenceKeys.showAddDialogBeforeAdding: true,
            PreferenceKeys.deleteTorrentFileAfterAdding: false,
            PreferenceKeys.confirmRemove: true,
            PreferenceKeys.badgeAppIcon: false,
            PreferenceKeys.sendCrashReports: false,
        ])
        #if PRERELEASE
        UserDefaults.standard.register(defaults: [PreferenceKeys.includePrereleases: true])
        #endif

        let args = CommandLine.arguments

        // Start opt-in crash reporting as early as possible so launch-time
        // crashes are captured; inert until a DSN and the user preference exist.
        CrashReporting.apply()

        // Debug-only crash-reporting verification (see CrashReporting): the
        // first flag crashes after startup, the second only boots the SDK so a
        // previously captured crash uploads. Neither persists anything.
        #if DEBUG
        if args.contains("--crash-test") {
            CrashReporting.startForTesting()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { CrashReporting.crashForTesting() }
        } else if args.contains("--crash-test-send") {
            CrashReporting.startForTesting()
        }
        #endif

        let snapshotPath = Self.parseSnapshotPath(from: args)
        self.snapshotPath = snapshotPath

        // --- profile store
        // Snapshot replay implies ephemeral profiles so the synthetic replay
        // profile never lands in the real servers.json.
        let ephemeral = args.contains("--ephemeral-profiles") || snapshotPath != nil
        // Snapshot replay, ephemeral test profiles and the crash-test hooks are
        // non-interactive: never interrupt them with the first-run consent splash.
        self.disableOnboarding =
            ephemeral || args.contains("--crash-test") || args.contains("--crash-test-send")
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

        // --- mapping store
        // App-wide "Open with…" mappings. First-run migration imports the
        // per-server mappings from servers.json, scoped to their server, so
        // behaviour is unchanged. Ephemeral/snapshot runs use a throwaway file
        // and never migrate.
        let mappingURL: URL
        if ephemeral {
            mappingURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("ephemeral-profiles-\(UUID().uuidString)", isDirectory: true)
                .appendingPathComponent("mappings.json")
        } else {
            mappingURL =
                (try? OpenMappingStore.defaultFileURL())
                ?? FileManager.default.temporaryDirectory.appendingPathComponent("mappings.json")
        }
        let mappingStore: OpenMappingStore
        if !ephemeral, let serversURL = try? ServerProfileStore.defaultFileURL() {
            mappingStore = OpenMappingStore(fileURL: mappingURL, migratingFrom: serversURL)
        } else {
            mappingStore = OpenMappingStore(fileURL: mappingURL)
        }
        self._mappingStore = State(wrappedValue: mappingStore)

        // --- torrent store
        // Snapshot mode decodes the captured file through SnapshotTorrentService
        // (read-only, frozen). Otherwise the store starts on an empty mock; the
        // connect flow swaps in the live RPC service via ConnectionCoordinator.
        let service: any TorrentReading
        var snapshotTagColors: [String: TagColor] = [:]
        var snapshotServerName: String?
        if let snapshotPath {
            do {
                let snapshotService = try SnapshotTorrentService(
                    fileURL: URL(fileURLWithPath: snapshotPath))
                // Colours are captured in the snapshot, so replay shows the same
                // assignments without touching the user's real prefs.
                snapshotTagColors = snapshotService.tagColors
                snapshotServerName = snapshotService.displayServerName
                service = snapshotService
            } catch {
                logger.error(
                    "Snapshot load failed: \(error.localizedDescription, privacy: .public)")
                service = EmptyTorrentService()
            }
        } else {
            service = EmptyTorrentService()
        }
        let store = TorrentStore(service: service)
        self._torrentStore = State(wrappedValue: store)

        // Snapshot replay seeds a synthetic profile so the title bar / server
        // switcher have a label. Prefer the name the snapshot carries (tests set a
        // friendly one); fall back to the filename for captures that don't.
        if let snapshotPath {
            let filename =
                URL(fileURLWithPath: snapshotPath).deletingPathExtension().lastPathComponent
            let label =
                snapshotServerName.flatMap { $0.isEmpty ? nil : $0 } ?? "Snapshot — \(filename)"
            try? profileStore.add(ServerProfile(label: label, host: "snapshot", port: 0))
        }
        self._profileStore = State(wrappedValue: profileStore)

        // Shared with the App Intents (see AppEnvironment). Snapshot replay is
        // the deterministic dataset the intent tests run against.
        AppEnvironment.register(
            AppEnvironment(
                mode: snapshotPath != nil ? .snapshot : .live,
                profileFileURL: profileURL,
                snapshotFileURL: snapshotPath.map { URL(fileURLWithPath: $0) }))

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
            ContentView(
                store: torrentStore,
                snapshotMode: snapshotPath != nil,
                disableOnboarding: disableOnboarding
            )
            .environment(profileStore)
            .environment(mappingStore)
            .environment(torrentStore)
            .environment(faviconStore)
            .environment(tagColorStore)
            .onOpenURL { url in
                // transmissionswift://<serverUUID>/<torrentID> opens the app on a
                // torrent (the URL form of TorrentEntity); magnet: links and
                // double-clicked / "Open With" .torrent files go through the add
                // flow, honouring the "Show dialog before adding" pref.
                if let request = OpenRequest(deepLink: url) {
                    OpenRequestBus.shared.request = request
                } else {
                    torrentStore.addFromExternalURL(url)
                }
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
                .environment(mappingStore)
                .environment(faviconStore)
                .environment(torrentStore)
                .environment(tagColorStore)
        }
        // Compact: the toolbar row collapses to a slim lights-only strip (the
        // title is blank and there are no items), instead of a tall empty bar
        // above the pane title.
        .windowToolbarStyle(.unifiedCompact)
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
                if let url = BugReport.url(daemonVersion: torrentStore.session.daemonVersion) {
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
                UserDefaults.standard.set(PrefsTab.servers.rawValue, forKey: PreferenceKeys.prefsPendingNavTab)
                openWindow(id: "preferences")
            }
        }
    }
}
