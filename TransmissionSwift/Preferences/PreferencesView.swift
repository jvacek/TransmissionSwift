import AppKit
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
/// the absence of a window title — not from toolbar tricks. The pane title is
/// drawn by `PrefsToolbarHost`'s hand-built AppKit toolbar: SwiftUI
/// `ToolbarItem`s get auto-wrapped in a glass capsule on Tahoe with no
/// opt-out, so the title bypasses them entirely.
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
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            pane(for: selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .navigationSplitViewStyle(.balanced)
        // Plain-text pane title via a hand-built AppKit toolbar (see
        // PrefsToolbarHost) — no SwiftUI ToolbarItems anywhere in this window,
        // so Tahoe has nothing to wrap in glass.
        .background(PrefsToolbarHost(title: selection.title))
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

/// Installs a hand-built AppKit toolbar carrying the plain-text pane title.
///
/// SwiftUI wraps every `ToolbarItem` in a Liquid Glass capsule with no
/// opt-out (verified: placement changes, `.glassEffect(.identity)`, even
/// AppKit-hosted content all still pill). A real `NSToolbarItem` renders
/// exactly the view it's given, so the 22pt title stays plain text on the
/// toolbar's own material — the Xcode-settings look.
///
/// Deliberately the only toolbar in this window: no SwiftUI `.toolbar`
/// modifiers anywhere here, so nothing fights the install. Re-installs if
/// something replaces the toolbar out from under it.
private struct PrefsToolbarHost: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // `window` isn't set during make — defer to the next runloop.
        DispatchQueue.main.async { context.coordinator.install(into: view.window, title: title) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.install(into: view.window, title: title)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, NSToolbarDelegate {
        private static let titleID = NSToolbarItem.Identifier("paneTitle")

        private let titleField: NSTextField = {
            let field = NSTextField(labelWithString: "")
            field.font = .systemFont(ofSize: 22, weight: .semibold)
            return field
        }()

        private lazy var titleItem: NSToolbarItem = {
            let item = NSToolbarItem(itemIdentifier: Self.titleID)
            item.view = titleField
            return item
        }()

        private weak var installedToolbar: NSToolbar?

        func install(into window: NSWindow?, title: String) {
            guard let window else { return }
            if !isInstalled(window.toolbar) {
                let toolbar = NSToolbar(identifier: "preferences")
                toolbar.delegate = self
                toolbar.allowsUserCustomization = false
                toolbar.autosavesConfiguration = false
                toolbar.displayMode = .labelOnly
                window.toolbar = toolbar
                installedToolbar = toolbar
            }
            setTitle(title)
        }

        private func isInstalled(_ toolbar: NSToolbar?) -> Bool {
            guard let toolbar, let installedToolbar else { return false }
            return toolbar === installedToolbar
        }

        private func setTitle(_ title: String) {
            titleField.stringValue = title
            titleField.sizeToFit()
            let size = titleField.fittingSize
            titleItem.minSize = size
            titleItem.maxSize = NSSize(width: 4000, height: size.height)
        }

        // MARK: NSToolbarDelegate

        func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
            [Self.titleID]
        }

        func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
            [Self.titleID]
        }

        func toolbar(
            _ toolbar: NSToolbar,
            itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
            willBeInsertedIntoToolbar flag: Bool
        ) -> NSToolbarItem? {
            itemIdentifier == Self.titleID ? titleItem : nil
        }
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
