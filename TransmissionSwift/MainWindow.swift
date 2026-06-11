import SwiftUI
import TransmissionCore

/// The main window — sidebar · torrent list · optional inspector, with a
/// grouped toolbar on top and a status bar attached to the bottom safe area.
///
/// `.inspector` is attached to the outer `NavigationSplitView` (not the
/// detail) so it sits as a peer pane to the split view. That keeps the
/// toolbar's search field anchored to the detail's column and stops the
/// inspector pane from creeping under the toolbar's Liquid Glass.
struct MainWindow: View {
    @Environment(TorrentStore.self) private var store
    @Environment(ServerProfileStore.self) private var profileStore
    @Environment(\.openSettings) private var openSettings
    @AppStorage("prefsPendingNavTab") private var pendingNavTab: Int = -1
    var mockMode: Bool = false

    var body: some View {
        @Bindable var store = store

        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 180, ideal: 212)
        } detail: {
            listPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(profileStore.activeProfile?.label ?? "Transmission")
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    StatusBarView()
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
        .inspector(isPresented: $store.inspectorVisible) {
            InspectorView()
                .inspectorColumnWidth(min: 280, ideal: 322)
        }
        .frame(minWidth: 1060, minHeight: 600)
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
        switch store.connection {
        case .connecting:
            connectingPlaceholder
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

    private var connectingPlaceholder: some View {
        let serverName = profileStore.activeProfile?.label ?? "server"
        return TorrentListView()
            .overlay {
                ZStack {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Connecting to \(serverName)…")
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
                store.simulateConnection(.connecting)
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
}
