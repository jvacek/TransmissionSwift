import SwiftUI
import TransmissionCore

private enum Layout {
    static let sidebarMin: CGFloat = 180
    static let sidebarIdeal: CGFloat = 212
    static let contentMin: CGFloat = 400
    static let inspectorMin: CGFloat = 280
    static let inspectorIdeal: CGFloat = 322
    static let inspectorAbsMax: CGFloat = 1200
    static let windowMin: CGFloat = 1060
}

struct MainWindow: View {
    @Environment(TorrentStore.self) private var store
    @Environment(ServerProfileStore.self) private var profileStore
    @Environment(\.openSettings) private var openSettings
    @AppStorage("prefsPendingNavTab") private var pendingNavTab: Int = -1
    @AppStorage("inspectorWidth") private var storedInspectorWidth: Double = Double(Layout.inspectorIdeal)
    @State private var windowWidth: CGFloat = Layout.windowMin
    var mockMode: Bool = false

    /// No profile configured (and not running on mock data) — the window shows
    /// the "No Servers" onboarding empty state instead of torrent content.
    private var hasNoServer: Bool {
        !mockMode && profileStore.activeProfile == nil
    }

    /// Inspector width clamped to whatever space is actually available.
    /// Shrinks automatically when the window narrows; never below inspectorMin.
    private var inspectorWidth: CGFloat {
        let available = windowWidth - Layout.sidebarMin - Layout.contentMin
        let cap = max(Layout.inspectorMin, min(Layout.inspectorAbsMax, available))
        return min(CGFloat(storedInspectorWidth), cap)
    }

    var body: some View {
        @Bindable var store = store

        HStack(spacing: 0) {
            splitView
            if store.inspectorVisible {
                InspectorResizeHandle(
                    storedWidth: $storedInspectorWidth,
                    clampedWidth: inspectorWidth,
                    min: Layout.inspectorMin,
                    max: min(Layout.inspectorAbsMax, windowWidth - Layout.sidebarMin - Layout.contentMin)
                )
                InspectorView()
                    .frame(width: inspectorWidth)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(minWidth: Layout.windowMin, minHeight: 600)
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: {
            windowWidth = $0
        }
        .sheet(isPresented: $store.showAddTorrent) {
            AddTorrentSheet(
                isPresented: $store.showAddTorrent,
                initialMagnetMode: store.addTorrentStartInMagnetMode,
                prefilledURL: store.addTorrentPrefilledURL
            )
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            let accepted = url.pathExtension == "torrent" || url.scheme == "magnet"
            if accepted {
                store.openAddSheet(magnetMode: url.scheme == "magnet", prefilledURL: url)
            }
            return accepted
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
        return NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: Layout.sidebarMin, ideal: Layout.sidebarIdeal)
        } detail: {
            listPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(profileStore.activeProfile?.label ?? "Transmission")
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    // No connection exists in the no-server state, so the status
                    // bar's counts/connection text would be misleading — hide it.
                    if !hasNoServer {
                        StatusBarView()
                    }
                }
                .searchable(
                    text: $store.searchQuery,
                    placement: .toolbar,
                    prompt: "Search torrents"
                )
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        serverSwitcherMenu
                    }
                    MainToolbar(mockMode: mockMode)
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Server switcher

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
                pendingNavTab = 4
                openSettings()
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
                if !store.searchQuery.isEmpty && store.visibleTorrents.isEmpty {
                    ContentUnavailableView.search(text: store.searchQuery)
                        .overlay(alignment: .bottom) {
                            HStack(spacing: 8) {
                                Button("Clear Search") { store.searchQuery = "" }
                                Button("Reset Filters") {
                                    store.searchQuery = ""
                                    store.selectedFilter = .status(.all)
                                }
                            }
                            .buttonStyle(.borderless)
                            .padding(.bottom, 48)
                        }
                } else if store.torrents.isEmpty {
                    noTorrentsView
                } else {
                    TorrentListView()
                }
            }
        }
    }

    private func connectingPlaceholder(message: String) -> some View {
        TorrentListView()
            .overlay {
                ZStack {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text(message)
                            .font(.headline)
                        Button("Cancel") {
                            store.simulateConnection(.disconnected(reason: "Cancelled by user"))
                        }
                    }
                    .padding(.horizontal, 36)
                    .padding(.vertical, 28)
                    .background(
                        .regularMaterial,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                    .shadow(radius: 12, y: 4)
                }
            }
    }

    private func disconnectedView(reason: String) -> some View {
        let profile = profileStore.activeProfile
        let address = profile.map { "\($0.host):\($0.port)" } ?? "unknown host"
        return ContentUnavailableView {
            Label("Connection Lost", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        } description: {
            Text("Could not connect to \(address).\n\(reason)")
        } actions: {
            Button("Reconnect") {
                store.reconnect()
            }
            .buttonStyle(.glassProminent)
            Button("Server Settings…") {
                pendingNavTab = 4
                openSettings()
            }
        }
    }

    private var noTorrentsView: some View {
        ContentUnavailableView {
            Label("No Torrents Yet", systemImage: "arrow.down.circle")
        } description: {
            Text("Add a torrent file or magnet link to get started.")
        } actions: {
            Button("Add Torrent…") { store.openAddSheet() }
                .buttonStyle(.glassProminent)
            Button("Add Magnet Link…") { store.openAddSheet(magnetMode: true) }
        }
    }

    private var noServersView: some View {
        ContentUnavailableView {
            Label("No Servers", systemImage: "server.rack")
        } description: {
            Text("Add a Transmission server in Settings to connect and start managing torrents.")
        } actions: {
            Button("Add Server…") {
                pendingNavTab = 4
                openSettings()
            }
            .buttonStyle(.glassProminent)
        }
    }
}

// MARK: - Inspector resize handle

private struct InspectorResizeHandle: View {
    @Binding var storedWidth: Double
    let clampedWidth: CGFloat
    let min: CGFloat
    let max: CGFloat

    @GestureState private var dragStartWidth: CGFloat? = nil

    var body: some View {
        Color.clear
            .frame(width: 8)
            .overlay(
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(width: 1)
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .updating($dragStartWidth) { _, state, _ in
                        if state == nil { state = clampedWidth }
                    }
                    .onChanged { value in
                        let start = dragStartWidth ?? clampedWidth
                        let proposed = start - value.translation.width
                        storedWidth = Double(Swift.max(min, Swift.min(max, proposed)))
                    }
            )
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
    }
}

#Preview("No Servers") {
    let emptyProfiles = ServerProfileStore(
        fileURL: URL.temporaryDirectory.appending(path: "preview-no-servers.json")
    )
    MainWindow(mockMode: false)
        .environment(TorrentStore(service: MockTorrentService(initial: [])))
        .environment(emptyProfiles)
        .frame(width: 1100, height: 640)
}
