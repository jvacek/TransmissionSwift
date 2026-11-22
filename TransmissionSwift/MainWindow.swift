// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import TransmissionCore

#if DEBUG
import TransmissionTestSupport
#endif

private enum Layout {
    static let sidebarMin: CGFloat = 180
    static let sidebarIdeal: CGFloat = 212
    static let sidebarMax: CGFloat = 600
    static let inspectorMin: CGFloat = 280
    static let inspectorIdeal: CGFloat = 322
    static let inspectorMax: CGFloat = 600
    static let contentMin: CGFloat = 480
    static let contentIdeal: CGFloat = 640
    /// The narrowest the window may get: the three columns' minimums.
    static let windowMinWidth: CGFloat = 960
}

struct MainWindow: View {
    @Environment(TorrentStore.self) private var store
    @Environment(ServerProfileStore.self) private var profileStore
    @Environment(ConnectionCoordinator.self) private var connection
    @Environment(\.openWindow) private var openWindow
    @AppStorage(PreferenceKeys.prefsPendingNavTab) private var pendingNavTab: String = ""
    /// The saved inspector width, read once. It is written back through plain
    /// `UserDefaults`, not `@AppStorage`: invalidating this view on every width
    /// change re-applies `inspectorColumnWidth` and pins the column.
    @State private var initialInspectorWidth: CGFloat = {
        let saved = UserDefaults.standard.double(forKey: PreferenceKeys.inspectorWidth)
        let width = saved > 0 ? CGFloat(saved) : Layout.inspectorIdeal
        return min(max(width, Layout.inspectorMin), Layout.inspectorMax)
    }()
    /// The View menu's sidebar command writes this preference from outside any
    /// animation, so changes are mirrored into `columnVisibility` inside one.
    @AppStorage(PreferenceKeys.sidebarVisible) private var sidebarVisible = true
    @State private var columnVisibility: NavigationSplitViewVisibility =
        UserDefaults.standard.object(forKey: PreferenceKeys.sidebarVisible) as? Bool == false
        ? .detailOnly : .all
    @AppStorage(PreferenceKeys.startMinimized) private var startMinimized = false
    @State private var didApplyStartMinimized = false
    @State private var openBus = OpenRequestBus.shared
    @FocusState private var searchFocused: Bool

    /// No profile configured — the window shows the "No Servers" onboarding
    /// empty state instead of torrent content.
    private var hasNoServer: Bool {
        profileStore.activeProfile == nil
    }

    var body: some View {
        @Bindable var ui = store.ui

        splitView
            .frame(minHeight: 600)
            .background(WindowFitToScreen())
            .onAppear {
                // "Start minimized": miniaturize once on launch. Done here (rather
                // than the app delegate) so it targets the actual main window.
                if startMinimized, !didApplyStartMinimized {
                    didApplyStartMinimized = true
                    NSApp.keyWindow?.miniaturize(nil)
                }
            }
            .onChange(of: hasNoServer) { _, noServer in
                // The status bar (which owns the Dock badge) is hidden with no
                // server configured — clear any stale count.
                if noServer { NSApp.dockTile.badgeLabel = "" }
            }
            // Apply (or retry) a pending "open torrent" request from an App Intent.
            // Retries when the torrent list reloads after a server switch.
            .task { applyOpenRequest() }
            .onChange(of: openBus.request) { _, _ in applyOpenRequest() }
            .onChange(of: store.ui.searchFocusRequest) { searchFocused = true }
            .onChange(of: store.list.torrents) { _, _ in applyOpenRequest() }
            .sheet(isPresented: $ui.showAddTorrent) {
                AddTorrentSheet(
                    isPresented: $ui.showAddTorrent,
                    initialMode: ui.addTorrentStartMode,
                    prefilledURL: ui.addTorrentPrefilledURL,
                    serverName: profileStore.activeProfile?.label
                )
            }
            .sheet(isPresented: $ui.showEditLabels) {
                EditLabelsSheet(
                    isPresented: $ui.showEditLabels,
                    ids: ui.editLabelsTargetIDs
                )
            }
            .sheet(isPresented: $ui.showSetLocation) {
                SetLocationSheet(
                    isPresented: $ui.showSetLocation,
                    ids: ui.setLocationTargetIDs,
                    serverName: profileStore.activeProfile?.label
                )
            }
            .sheet(isPresented: $ui.showRenameTorrent) {
                if let id = ui.renameTorrentTargetID {
                    RenameTorrentSheet(isPresented: $ui.showRenameTorrent, id: id)
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                let scheme = url.scheme?.lowercased()
                let accepted =
                    url.pathExtension == "torrent" || scheme == "magnet" || scheme == "http"
                    || scheme == "https"
                if accepted {
                    store.addFromExternalURL(url)
                }
                return accepted
            }
            .confirmationDialog(
                removeDialogTitle,
                isPresented: Binding(
                    get: { store.actions.pendingRemoval != nil },
                    set: { if !$0 { store.actions.cancelPendingRemoval() } }
                ),
                presenting: store.actions.pendingRemoval
            ) { _ in
                Button("Remove", role: .destructive) { store.actions.confirmPendingRemoval() }
                Button("Cancel", role: .cancel) { store.actions.cancelPendingRemoval() }
            } message: { pending in
                Text(removeDialogMessage(for: pending))
            }
            .alert(
                store.lastActionError?.title ?? "Action Failed",
                isPresented: Binding(
                    get: { store.lastActionError != nil },
                    set: { if !$0 { store.lastActionError = nil } }
                ),
                presenting: store.lastActionError
            ) { _ in
                Button("OK", role: .cancel) { store.lastActionError = nil }
            } message: { error in
                Text(error.localizedDescription)
            }
    }

    // MARK: - Split view

    private var splitView: some View {
        @Bindable var store = store
        @Bindable var list = store.list
        @Bindable var inspector = store.inspector
        return NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(
                    min: Layout.sidebarMin, ideal: Layout.sidebarIdeal, max: Layout.sidebarMax)
        } detail: {
            listPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationSplitViewColumnWidth(min: Layout.contentMin, ideal: Layout.contentIdeal)
                .navigationTitle(profileStore.activeProfile?.label ?? "Transmission")
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    // No connection exists in the no-server state, so the status
                    // bar's counts/connection text would be misleading — hide it.
                    if !hasNoServer {
                        StatusBarView()
                    }
                }
                .searchable(
                    text: $list.searchQuery,
                    placement: .toolbar,
                    prompt: "Search torrents"
                )
                .searchFocused($searchFocused)
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        serverSwitcherMenu
                    }
                    MainToolbar()
                }
        }
        // On the split view, so the inspector is a full-height column that
        // pushes the detail's items aside, as in Xcode.
        .inspector(isPresented: $inspector.isVisible) {
            InspectorView()
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.width
                } action: { width in
                    // The column passes through narrower widths while it animates closed.
                    guard width >= Layout.inspectorMin else { return }
                    UserDefaults.standard.set(Double(width), forKey: PreferenceKeys.inspectorWidth)
                }
                .inspectorColumnWidth(
                    min: Layout.inspectorMin,
                    ideal: initialInspectorWidth,
                    max: Layout.inspectorMax
                )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: sidebarVisible) { _, visible in
            let target: NavigationSplitViewVisibility = visible ? .all : .detailOnly
            guard columnVisibility != target else { return }
            withAnimation { columnVisibility = target }
        }
        .onChange(of: columnVisibility) { _, visibility in
            sidebarVisible = visibility != .detailOnly
        }
    }

    // MARK: - Server switcher

    /// Opens Preferences on the Servers pane. The pane reads
    /// `prefsPendingNavTab` on appear / on change.
    private func openServerSettings() {
        pendingNavTab = PrefsTab.servers.rawValue
        openWindow(id: "preferences")
    }

    /// Title / message for the remove confirmation dialog.
    private var removeDialogTitle: String {
        guard let pending = store.actions.pendingRemoval else { return "Remove Torrents" }
        return pending.ids.count == 1 ? "Remove Torrent?" : "Remove \(pending.ids.count) Torrents?"
    }

    private func removeDialogMessage(for pending: PendingRemoval) -> String {
        if pending.deleteLocalData {
            return "The torrents and their downloaded data will be deleted from the server."
        }
        return "The torrents will be removed from the list. Downloaded data stays on the server."
    }

    /// Applies a pending "open torrent" request from an App Intent: switch to
    /// the owning server, then select the torrent and reveal the inspector.
    /// Retries (via the `torrents` change) until the torrent has loaded, which
    /// matters when the request also switches servers; `OpenRequestBus` drops a
    /// request that never becomes satisfiable.
    private func applyOpenRequest() {
        guard let request = openBus.pending() else { return }

        if let serverID = request.serverID, profileStore.activeProfile?.id != serverID {
            try? profileStore.setActive(serverID)
            return
        }
        guard store.list.torrents.contains(where: { $0.id == request.torrentID }) else { return }

        openBus.request = nil
        store.list.searchQuery = ""
        store.list.resetFilters()
        store.list.selectedTorrentIDs = [request.torrentID]
        store.inspector.isVisible = true
    }

    private var serverSwitcherMenu: some View {
        Menu {
            ForEach(profileStore.profiles) { profile in
                Toggle(
                    isOn: Binding(
                        get: { profileStore.activeProfile?.id == profile.id },
                        set: { on in if on { try? profileStore.setActive(profile.id) } }
                    )
                ) {
                    Text(profile.label)
                }
            }
            Divider()
            Button("Server Settings…") {
                openServerSettings()
            }
        } label: {
            if profileStore.profiles.count > 1 {
                Label(
                    profileStore.activeProfile?.label ?? "No Server",
                    systemImage: "server.rack"
                )
            } else {
                Image(systemName: "server.rack")
            }
        }
        .help(profileStore.activeProfile?.label ?? "Server")
        // With one server the label is icon-only; VoiceOver should still name
        // the server, not the symbol.
        .accessibilityLabel(profileStore.activeProfile?.label ?? "No Server")
        .accessibilityIdentifier("toolbar.serverSwitcher")
    }

    // MARK: - List pane

    @ViewBuilder
    private var listPane: some View {
        if hasNoServer {
            // No server configured yet — must precede the connection switch because
            // the pre-connect store is backed by an empty mock that reports
            // `.connected`, which would otherwise show "No Torrents Yet".
            noServersView
        } else {
            switch store.connection {
            case .connecting:
                connectingPlaceholder(message: "Connecting to \(profileStore.activeProfile?.label ?? "server")…")
            case .awaitingKeychain:
                connectingPlaceholder(message: "Waiting for keychain access…")
            case .disconnected(let reason):
                disconnectedView(reason: reason)
            case .connected:
                if !store.list.searchQuery.isEmpty && store.list.visibleTorrents.isEmpty {
                    ContentUnavailableView {
                        Label("No Results for “\(store.list.searchQuery)”", systemImage: "magnifyingglass")
                    } description: {
                        Text("Check the spelling or try a new search.")
                    } actions: {
                        Button("Clear Search") { store.list.searchQuery = "" }
                        Button("Reset Filters") {
                            store.list.searchQuery = ""
                            store.list.resetFilters()
                        }
                    }
                } else if store.list.torrents.isEmpty {
                    noTorrentsView
                } else {
                    TorrentListView()
                }
            }
        }
    }

    private func connectingPlaceholder(message: String) -> some View {
        // Deliberately NOT a live TorrentListView: a second table bound to the
        // same store during the connecting→connected transition caused
        // coordinators to race each other's selection writes (empty write
        // clobbering the real selection). Inert placeholder only.
        ContentUnavailableView {
            ProgressView()
        } description: {
            Text(message)
        } actions: {
            Button("Cancel") {
                store.simulateConnection(.disconnected(reason: "Cancelled by user"))
            }
        }
    }

    private func disconnectedView(reason: String) -> some View {
        let profile = profileStore.activeProfile
        let address = profile.map { "\($0.host):\($0.port)" } ?? "unknown host"
        return ContentUnavailableView {
            Label("Connection Lost", systemImage: "network.slash")
        } description: {
            Text("Could not connect to \(address).\n\(reason)")
        } actions: {
            Button("Reconnect") {
                guard let profile else { return }
                Task { await connection.connect(to: profile) }
            }
            .buttonStyle(.glassProminent)
            Button("Server Settings…") {
                openServerSettings()
            }
        }
    }

    private var noTorrentsView: some View {
        ContentUnavailableView {
            Label("No Torrents Yet", systemImage: "arrow.down.circle")
        } description: {
            Text("Add a torrent file, magnet link, or URL to get started.")
        } actions: {
            Button("Add Torrent…") { store.openAddSheet() }
                .buttonStyle(.glassProminent)
            Button("Add Link…") { store.openAddSheet(mode: .link) }
        }
    }

    private var noServersView: some View {
        ContentUnavailableView {
            Label("No Servers", systemImage: "server.rack")
        } description: {
            Text("Add a Transmission server in Settings to connect and start managing torrents.")
        } actions: {
            Button("Add Server…") {
                openServerSettings()
            }
            .buttonStyle(.glassProminent)
        }
    }
}

#if DEBUG
#Preview("No Servers") {
    let store = TorrentStore(service: MockTorrentService(initial: []))
    let emptyProfiles = ServerProfileStore(
        fileURL: URL.temporaryDirectory.appending(path: "preview-no-servers.json")
    )
    MainWindow()
        .environment(store)
        .environment(emptyProfiles)
        .environment(
            OpenMappingStore(fileURL: URL.temporaryDirectory.appending(path: "preview-mappings.json"))
        )
        .environment(FaviconStore())
        .environment(GeoIPStore())
        .environment(TagColorStore())
        .environment(ConnectionCoordinator(store: store))
        .frame(width: 1100, height: 640)
}
#endif

/// Fits the window to the display once it is in the window hierarchy: the
/// columns' ideal widths can otherwise open it wider than a small screen.
private struct WindowFitToScreen: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window, let screen = window.screen ?? NSScreen.main else {
                return
            }
            window.contentMinSize = NSSize(
                width: Layout.windowMinWidth, height: window.contentMinSize.height)
            window.minSize = NSSize(
                width: Layout.windowMinWidth, height: window.minSize.height)
            let fitted = window.frame.intersection(screen.visibleFrame)
            if fitted != window.frame {
                window.setFrame(fitted, display: true)
            }
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}
}
