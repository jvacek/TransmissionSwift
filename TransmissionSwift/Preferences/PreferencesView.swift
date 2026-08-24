import SwiftUI
import TransmissionCore

/// The name of the "Server Settings…" deep-link pref: a `PrefsTab.rawValue`
/// written by menu call-sites and consumed by `PreferencesView` on appear.
private let prefsPendingTabKey = "prefsPendingNavTab"

/// The Preferences window, registered as a `Settings` scene.
///
/// Uses the standard, off-the-shelf macOS 26 appearance: a `TabView` with
/// `.tabViewStyle(.sidebarAdaptable)`, which the system renders as a Liquid
/// Glass Settings window — a detached, hovering sidebar of categories on the
/// left and the selected pane on the right. The per-category title is the
/// sidebar row (the window title follows the selection). The sidebar's default
/// collapse toggle is removed via `.toolbar(removing: .sidebarToggle)`.
///
/// `pendingTab` is written by any "Server Settings…" call-site before invoking
/// `openSettings()` / `showSettingsWindow:`. `onAppear` handles the fresh-open
/// case; `onChange` handles the already-visible case.
struct PreferencesView: View {
    @State private var selection: PrefsTab = .general
    @AppStorage(prefsPendingTabKey) private var pendingTab: String = ""

    var body: some View {
        TabView(selection: $selection) {
            ForEach(PrefsTab.allCases) { tab in
                Tab(tab.title, systemImage: tab.systemImage, value: tab) {
                    pane(for: tab)
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .toolbar(removing: .sidebarToggle)
        .frame(minWidth: 660, minHeight: 480)
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
        case .seeding: SeedingPrefsPane()
        case .network: NetworkPrefsPane()
        case .remote: RemotePrefsPane()
        case .updates: UpdatesPrefsPane()
        case .developer: DeveloperPrefsPane()
        case .tags: TagsPrefsPane()
        }
    }
}

/// The preferences sidebar categories, in display order. Persisted by raw value
/// so "Server Settings…" can deep-link to a specific pane without depending on
/// the sidebar order.
enum PrefsTab: String, Hashable, CaseIterable, Identifiable {
    case general, servers, speed, seeding, network, remote, updates, developer, tags

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .servers: return "Servers"
        case .speed: return "Speed"
        case .seeding: return "Seeding"
        case .network: return "Network"
        case .remote: return "Remote"
        case .updates: return "Updates"
        case .developer: return "Developer"
        case .tags: return "Tags"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .servers: return "server.rack"
        case .speed: return "tortoise"
        case .seeding: return "gauge"
        case .network: return "globe"
        case .remote: return "antenna.radiowaves.left.and.right"
        case .updates: return "arrow.down.circle"
        case .developer: return "wrench.and.screwdriver"
        case .tags: return "tag"
        }
    }
}
