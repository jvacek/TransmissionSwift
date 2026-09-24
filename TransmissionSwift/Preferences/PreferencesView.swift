import SwiftUI
import TransmissionCore

/// The name of the "Server Settings…" deep-link pref: a `PrefsTab.rawValue`
/// written by menu call-sites and consumed by `PreferencesView` on appear.
private let prefsPendingTabKey = "prefsPendingNavTab"

/// The Preferences window, hosted in a regular titled `Window` scene (see
/// `TransmissionSwiftApp`).
///
/// A `NavigationSplitView` — a Liquid Glass `List` sidebar on the left and the
/// selected pane on the right. The sidebar's collapse toggle is removed
/// (`.toolbar(removing: .sidebarToggle)` + ``columnVisibility == .all``) so the
/// window reads like System Settings / Xcode's settings. The detail's pane
/// title is a material inset bar at the top of the content (not a ToolbarItem,
/// which Tahoe would wrap in a glass capsule) — the window title stays blank
/// so the two never double up.
///
/// `pendingTab` is written by any "Server Settings…" call-site before opening
/// the window. `onAppear` handles the fresh-open case; `onChange` handles the
/// already-visible case.
struct PreferencesView: View {
    @Environment(ServerProfileStore.self) private var profileStore
    @State private var selection: PrefsTab = .general
    @AppStorage(prefsPendingTabKey) private var pendingTab: String = ""

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(selection: $selection) {
                Section("Application") {
                    ForEach(PrefsTab.applicationTabs) { tab in
                        Label(tab.title, systemImage: tab.systemImage)
                            .tag(tab)
                    }
                }
                Section(serverSectionTitle) {
                    ForEach(PrefsTab.serverTabs) { tab in
                        Label(tab.title, systemImage: tab.systemImage)
                            .tag(tab)
                    }
                }
            }
            .listStyle(.sidebar)
            .toolbar(removing: .sidebarToggle)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            pane(for: selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                // Title lives here, not in a ToolbarItem: Tahoe wraps every
                // toolbar item in a glass capsule with no opt-out. This inset
                // bar wears the toolbar material directly, so scrolled content
                // stays legible behind plain 20pt text.
                .safeAreaInset(edge: .top, spacing: 0) {
                    Text(selection.title)
                        .font(.system(size: 22, weight: .semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 20)
                        .padding(.vertical, 10)
                        .background(.bar)
                }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 760, minHeight: 480)
        .onAppear {
            if let tab = PrefsTab(rawValue: pendingTab) {
                selection = tab
            }
            pendingTab = ""
        }
        .onChange(of: pendingTab) { _, newValue in
            guard let tab = PrefsTab(rawValue: newValue) else { return }
            selection = tab
            pendingTab = ""
        }
    }

    @ViewBuilder
    private func pane(for tab: PrefsTab) -> some View {
        switch tab {
        case .general: GeneralPrefsPane()
        case .servers: ServersPrefsPane()
        case .speed: SpeedPrefsPane()
        case .transfers: TransfersPrefsPane()
        case .network: NetworkPrefsPane()
        case .updates: UpdatesPrefsPane()
        case .developer: DeveloperPrefsPane()
        case .tags: TagsPrefsPane()
        }
    }

    /// "Server (Home NAS)" — the server panes act on the active profile.
    private var serverSectionTitle: String {
        if let label = profileStore.activeProfile?.label, !label.isEmpty {
            return "Server (\(label))"
        }
        return "Server"
    }
}

/// The preferences sidebar categories. Persisted by raw value
/// so "Server Settings…" can deep-link to a specific pane without depending on
/// the sidebar order.
enum PrefsTab: String, Hashable, CaseIterable, Identifiable {
    case general, servers, speed, transfers, network, updates, developer, tags

    /// App-local prefs, with the server list last.
    static var applicationTabs: [PrefsTab] { [.general, .tags, .updates, .developer, .servers] }
    /// Daemon-side settings for the active server.
    static var serverTabs: [PrefsTab] { [.speed, .transfers, .network] }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .servers: return "Servers"
        case .speed: return "Speed"
        case .transfers: return "Transfers"
        case .network: return "Network"
        case .updates: return "Updates"
        case .developer: return "Developer"
        case .tags: return "Tags"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .servers: return "server.rack"
        case .speed: return "gauge"
        case .transfers: return "arrow.up.arrow.down"
        case .network: return "globe"
        case .updates: return "arrow.down.circle"
        case .developer: return "wrench.and.screwdriver"
        case .tags: return "tag"
        }
    }
}

#Preview("Preferences — Connected") {
    PreferencesView()
        .environment(prefsPreviewProfileStore)
        .environment(prefsPreviewStore)
        .environment(FaviconStore())
        .environment(TagColorStore())
        .frame(width: 700, height: 560)
}
