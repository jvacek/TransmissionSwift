import SwiftUI
import TransmissionCore

/// The name of the "Server Settings…" deep-link pref: a `PrefsTab.rawValue`
/// written by menu call-sites and consumed by `PreferencesView` on appear.
private let prefsPendingTabKey = "prefsPendingNavTab"

/// The Preferences window, hosted in a hidden-title-bar `Window` scene (see
/// `TransmissionSwiftApp`).
///
/// A `NavigationSplitView` — a Liquid Glass `List` sidebar on the left and the
/// selected pane on the right. The sidebar's collapse toggle is removed
/// (`.toolbar(removing: .sidebarToggle)` + ``columnVisibility == .all``) so the
/// window reads like System Settings. The detail column shows a large,
/// left-aligned pane title above the content (the `Settings` scene would
/// otherwise show a centred "<App> Settings" title bar we can't remove).
///
/// `pendingTab` is written by any "Server Settings…" call-site before opening
/// the window. `onAppear` handles the fresh-open case; `onChange` handles the
/// already-visible case.
struct PreferencesView: View {
    @State private var selection: PrefsTab = .general
    @AppStorage(prefsPendingTabKey) private var pendingTab: String = ""

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(selection: $selection) {
                ForEach(PrefsTab.allCases) { tab in
                    Label(tab.title, systemImage: tab.systemImage)
                        .tag(tab)
                }
            }
            .listStyle(.sidebar)
            .toolbar(removing: .sidebarToggle)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                Text(selection.title)
                    .font(.largeTitle.weight(.semibold))
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 10)

                pane(for: selection)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .navigationSplitViewStyle(.balanced)
        .background(.windowBackground)
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

#Preview("Preferences — Connected") {
    PreferencesView()
        .environment(prefsPreviewProfileStore)
        .environment(prefsPreviewStore)
        .environment(FaviconStore())
        .environment(TagColorStore())
        .frame(width: 700, height: 560)
}
