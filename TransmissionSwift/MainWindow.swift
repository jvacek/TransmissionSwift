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
}

/// The frame AppKit autosaves for a `Window` scene, repaired before the window
/// is restored.
///
/// A frame saved on a larger display, or before a resolution change, comes back
/// on every launch. macOS 27 can throw while placing one that no longer fits,
/// which kills the app during its first layout, and the saved frame puts it back
/// in the same state next launch. Clamping the stored value before the window
/// exists leaves AppKit nothing to repair, without touching the frame of a
/// window that is already visible.
enum RestoredWindowFrame {
    /// The default AppKit uses for a scene's window, keyed by its `Window` id.
    nonisolated static func key(for windowID: String) -> String { "NSWindow Frame \(windowID)" }

    /// Rewrites the saved frame when it no longer fits the current displays.
    /// Returns the replacement, or nil when nothing needed to change.
    @discardableResult
    static func clampToDisplays(
        named windowID: String, screens: [CGRect]? = nil, defaults: UserDefaults = .standard
    ) -> String? {
        let key = key(for: windowID)
        guard let stored = defaults.string(forKey: key),
            let clamped = clamped(stored, screens: screens ?? NSScreen.screens.map(\.visibleFrame))
        else { return nil }
        defaults.set(clamped, forKey: key)
        return clamped
    }

    /// The stored value is eight space-separated numbers: the window frame,
    /// then the visible frame of the display it was saved on. Nil when the
    /// value is unreadable or already fits a current display.
    nonisolated static func clamped(_ stored: String, screens: [CGRect]) -> String? {
        let values = stored.split(whereSeparator: \.isWhitespace).compactMap { Double($0) }
        guard values.count == 8, values.allSatisfy(\.isFinite), !screens.isEmpty else { return nil }
        let frame = CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
        guard frame.width > 0, frame.height > 0 else { return nil }

        let visible = screens.filter { $0.intersects(frame) }
        let fitted: CGRect
        let screen: CGRect
        if visible.isEmpty {
            // The display it was saved on is gone: centre it on the primary one.
            guard let primary = screens.first else { return nil }
            fitted = centred(frame, in: primary)
            screen = primary
        } else if visible.count == 1,
            frame.width > visible[0].width || frame.height > visible[0].height
        {
            // Too big for the display it sits on: shrink it back into view. A
            // frame spanning two displays is a placement the user chose; leave
            // it alone.
            fitted = centred(frame, in: visible[0])
            screen = visible[0]
        } else {
            return nil
        }

        return [
            fitted.minX, fitted.minY, fitted.width, fitted.height,
            screen.minX, screen.minY, screen.width, screen.height,
        ].map { String(format: "%g", $0) }.joined(separator: " ")
    }

    /// `frame` shrunk to `screen` if needed and centred inside it.
    nonisolated private static func centred(_ frame: CGRect, in screen: CGRect) -> CGRect {
        let size = CGSize(
            width: min(frame.width, screen.width), height: min(frame.height, screen.height))
        return CGRect(
            x: screen.midX - size.width / 2, y: screen.midY - size.height / 2,
            width: size.width, height: size.height)
    }
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

    /// No profile configured — the window shows the "No Servers" onboarding
    /// empty state instead of torrent content.
    private var hasNoServer: Bool {
        profileStore.activeProfile == nil
    }

    /// Observes the torrent list only while an open request is pending, so a
    /// regular poll does not re-evaluate the whole window.
    private var pendingOpenTorrentIDs: [Torrent.ID] {
        guard openBus.request != nil else { return [] }
        return store.list.torrents.map(\.id)
    }

    var body: some View {
        @Bindable var ui = store.ui

        splitView
            .frame(minHeight: 600)
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
            .onChange(of: pendingOpenTorrentIDs) { _, _ in applyOpenRequest() }
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
                Button(L10n.text("Remove"), role: .destructive) { store.actions.confirmPendingRemoval() }
                Button(L10n.text("Cancel"), role: .cancel) { store.actions.cancelPendingRemoval() }
            } message: { pending in
                Text(removeDialogMessage(for: pending))
            }
            .alert(
                store.lastActionError?.displayTitle ?? L10n.text("Action Failed"),
                isPresented: Binding(
                    get: { store.lastActionError != nil },
                    set: { if !$0 { store.lastActionError = nil } }
                ),
                presenting: store.lastActionError
            ) { _ in
                Button(L10n.text("OK"), role: .cancel) { store.lastActionError = nil }
            } message: { error in
                Text(error.displayMessage)
            }
            .alert(
                L10n.text("Server List Not Loaded"),
                isPresented: Binding(
                    get: { profileStore.loadError != nil },
                    set: { if !$0 { profileStore.acknowledgeLoadError() } }
                ),
                presenting: profileStore.loadError
            ) { _ in
                Button(L10n.text("OK"), role: .cancel) { profileStore.acknowledgeLoadError() }
            } message: { error in
                Text(error.localizedDescription)
            }
    }

    // MARK: - Split view

    private var splitView: some View {
        @Bindable var store = store
        @Bindable var inspector = store.inspector
        return NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(
                    min: Layout.sidebarMin, ideal: Layout.sidebarIdeal, max: Layout.sidebarMax
                )
                .toolbar(removing: .sidebarToggle)
        } detail: {
            listPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationSplitViewColumnWidth(min: Layout.contentMin, ideal: Layout.contentIdeal)
                .navigationTitle(profileStore.activeProfile?.label ?? "Transmission")
                // Kept for the Window menu, but not drawn: in the toolbar the
                // title can't shrink and holds the window ~190pt wider. The
                // server switcher shows the name instead.
                .toolbar(removing: .title)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    // No connection exists in the no-server state, so the status
                    // bar's counts/connection text would be misleading — hide it.
                    if !hasNoServer {
                        StatusBarView()
                    }
                }
                .toolbar {
                    // Our own toggle: the system one lives in the sidebar's
                    // toolbar section, which in Icon and Text mode can't fit
                    // its caption and sends it to the overflow menu.
                    ToolbarItem(placement: .navigation) {
                        let title =
                            columnVisibility == .detailOnly
                            ? L10n.text("Show Sidebar") : L10n.text("Hide Sidebar")
                        Button(title, systemImage: "sidebar.left") { sidebarVisible.toggle() }
                            .help(title)
                            .accessibilityIdentifier("toolbar.sidebar")
                    }
                    ToolbarItem(placement: .navigation) {
                        serverSwitcherMenu
                    }
                    MainToolbar()
                }
        }
        // On the split view, so the inspector is a full-height column with its
        // own toolbar section that pushes the detail's items aside, as in Xcode.
        .inspector(isPresented: $inspector.isVisible) {
            InspectorView()
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.width
                } action: { width in
                    // The column passes through narrower widths while it animates closed.
                    guard store.inspector.isVisible, width >= Layout.inspectorMin else { return }
                    UserDefaults.standard.set(Double(width), forKey: PreferenceKeys.inspectorWidth)
                }
                .inspectorColumnWidth(
                    min: Layout.inspectorMin,
                    ideal: initialInspectorWidth,
                    max: Layout.inspectorMax
                )
                .toolbar {
                    ToolbarSpacer(.flexible)
                    InspectorToggle(shows: inspector.isVisible)
                }
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
        guard let pending = store.actions.pendingRemoval else { return L10n.text("Remove Torrents") }
        if pending.ids.count == 1 { return L10n.text("Remove Torrent?") }
        return L10n.format("Remove %lld Torrents?", Int64(pending.ids.count))
    }

    private func removeDialogMessage(for pending: PendingRemoval) -> String {
        if pending.deleteLocalData {
            return L10n.text("The torrents and their downloaded data will be deleted from the server.")
        }
        return L10n.text(
            "The torrents will be removed from the list. Downloaded data stays on the server.")
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
            Button(L10n.text("Server Settings…")) {
                openServerSettings()
            }
        } label: {
            // Titled "Server" for the toolbar's Icon and Text caption, but drawn
            // with the server's name: the only place the window shows it, as
            // the title is kept out of the toolbar (see `navigationTitle`).
            Label(L10n.text("Server"), systemImage: "server.rack")
                .labelStyle(
                    ServerSwitcherLabelStyle(
                        name: profileStore.activeProfile?.label ?? L10n.text("No Server")))
        }
        // Capped so a long name truncates instead of widening the window.
        .frame(maxWidth: 180)
        .help(profileStore.activeProfile?.label ?? L10n.text("Server"))
        .accessibilityLabel(profileStore.activeProfile?.label ?? L10n.text("No Server"))
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
                connectingPlaceholder(
                    message: L10n.format(
                        "Connecting to %@…",
                        profileStore.activeProfile?.label ?? L10n.text("server")))
            case .awaitingKeychain:
                connectingPlaceholder(message: L10n.text("Waiting for keychain access…"))
            case .disconnected(let reason):
                disconnectedView(reason: reason)
            case .connected:
                if !store.list.searchQuery.isEmpty && store.list.visibleTorrents.isEmpty {
                    ContentUnavailableView {
                        Label(
                            L10n.format("No Results for “%@”", store.list.searchQuery),
                            systemImage: "magnifyingglass")
                    } description: {
                        Text(L10n.text("Check the spelling or try a new search."))
                    } actions: {
                        Button(L10n.text("Clear Search")) { store.list.searchQuery = "" }
                        Button(L10n.text("Reset Filters")) {
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
            Button(L10n.text("Cancel")) {
                store.simulateConnection(.disconnected(reason: L10n.text("Cancelled by user")))
            }
        }
    }

    private func disconnectedView(reason: String) -> some View {
        let profile = profileStore.activeProfile
        let address = profile.map { "\($0.host):\($0.port)" } ?? L10n.text("unknown host")
        return ContentUnavailableView {
            Label(L10n.text("Connection Lost"), systemImage: "network.slash")
        } description: {
            Text(L10n.format("Could not connect to %@.\n%@", address, reason))
        } actions: {
            Button(L10n.text("Reconnect")) {
                guard let profile else { return }
                Task { await connection.connect(to: profile) }
            }
            .buttonStyle(.glassProminent)
            Button(L10n.text("Server Settings…")) {
                openServerSettings()
            }
        }
    }

    private var noTorrentsView: some View {
        ContentUnavailableView {
            Label(L10n.text("No Torrents Yet"), systemImage: "arrow.down.circle")
        } description: {
            Text(L10n.text("Add a torrent file, magnet link, or URL to get started."))
        } actions: {
            Button(L10n.text("Add Torrent…")) { store.openAddSheet() }
                .buttonStyle(.glassProminent)
            Button(L10n.text("Add Link…")) { store.openAddSheet(mode: .link) }
        }
    }

    private var noServersView: some View {
        ContentUnavailableView {
            Label(L10n.text("No Servers"), systemImage: "server.rack")
        } description: {
            Text(
                L10n.text(
                    "Add a Transmission server in Settings to connect and start managing torrents."))
        } actions: {
            Button(L10n.text("Add Server…")) {
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

/// Draws the server switcher's label as its icon and the server's name, while
/// the label's own title ("Server") stays the toolbar item's caption.
private struct ServerSwitcherLabelStyle: LabelStyle {
    let name: String

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
            Text(name).lineLimit(1)
        }
    }
}
