import SwiftUI
import TransmissionCore

/// The name of the "Server Settings…" deep-link pref: a `PrefsTab.rawValue`
/// written by menu call-sites and consumed by `PreferencesView` on appear.
private let prefsPendingTabKey = "prefsPendingNavTab"

/// The Preferences window, hosted in a regular titled `Window` scene (see
/// `TransmissionSwiftApp`).
///
/// A `NavigationSplitView` — a Liquid Glass `List` sidebar on the left and the
/// selected pane on the right. Full-height sidebar styling (traffic lights
/// inside the sidebar's glass card) comes from the plain `Window` scene plus
/// a blank window title. The pane title is a material inset bar atop the
/// detail — deliberately not a `ToolbarItem`, which Tahoe wraps in a glass
/// capsule with no opt-out.
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
                // Title as a material inset bar, not a toolbar item: Tahoe
                // wraps every ToolbarItem in a glass capsule (no opt-out),
                // and AppKit toolbar packing won't pin an item to the
                // detail's leading edge either. Regular content sidesteps both.
                .safeAreaInset(edge: .top, spacing: 0) {
                    headerText
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 20)
                        .padding(.trailing, 20)
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
        case .mappings: MappingsPrefsPane()
        }
    }

    /// The pane title, plus an optional help line, as a single `Text`.
    /// Deliberately not a `VStack`: stacking views inside this
    /// `safeAreaInset` under the `NavigationSplitView` detail lays the pane
    /// content out above the window, which shows as a blank window.
    private var headerText: Text {
        var title = AttributedString(selection.title)
        title.font = .system(size: 22, weight: .semibold)
        guard let help = selection.help else { return Text(title) }
        var helpLine = AttributedString("\n" + help)
        helpLine.font = .caption
        helpLine.foregroundColor = .secondary
        return Text(title + helpLine)
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
    case general, servers, speed, transfers, network, updates, developer, tags, mappings

    /// App-local prefs, with the server list last.
    static var applicationTabs: [PrefsTab] {
        [.general, .tags, .updates, .developer, .mappings, .servers]
    }
    /// Daemon-side settings for the active server.
    static var serverTabs: [PrefsTab] { [.speed, .transfers, .network] }

    var id: String { rawValue }

    /// Optional explanation shown under the pane title in the header bar.
    var help: String? {
        switch self {
        case .mappings:
            return
                "A mapping describes how a server's download folders are reachable from this Mac, so a torrent's context menu can open them in an external app. Mappings are app-wide; each one lists the servers it applies to."
        default:
            return nil
        }
    }

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
        case .mappings: return "Mappings"
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
        case .mappings: return "arrow.up.forward.square"
        }
    }
}

#Preview("Preferences — Connected") {
    PreferencesView()
        .environment(prefsPreviewProfileStore)
        .environment(prefsPreviewMappingStore)
        .environment(prefsPreviewStore)
        .environment(FaviconStore())
        .environment(TagColorStore())
        .frame(width: 700, height: 560)
}
