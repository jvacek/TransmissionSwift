// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import TransmissionCore

#if DEBUG
import TransmissionTestSupport
#endif

/// Right-pane inspector: a full-width tab bar and one of four tab bodies.
/// No header: name and status already show in the list row. Renders the
/// first selected torrent; selection changes flow in through `TorrentStore`
/// so content refreshes instantly.
struct InspectorView: View {
    @Environment(TorrentStore.self) private var store
    /// The toolbar above the inspector holds the tabs when the window is wide
    /// enough; a narrow window shows them at the top of the column instead.
    let usesToolbarTabs: Bool

    var body: some View {
        @Bindable var inspector = store.inspector

        if let torrent = store.list.selectedTorrents.first {
            VStack(spacing: 0) {
                if !usesToolbarTabs {
                    InspectorTabPicker()
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)

                    Divider()
                }

                tabContent(for: torrent)
                    // Re-key per torrent: scroll positions and the Options
                    // tab's draft state reset on selection change, but stay
                    // put across 1s polling snapshots.
                    .id(torrent.id)
            }
            // Fetch rich inspector data whenever the selected torrent changes.
            .task(id: torrent.id) {
                await store.inspector.fetch(for: torrent.id)
            }
        } else {
            ContentUnavailableView(
                "No Selection",
                systemImage: "info.circle",
                description: Text("Select a torrent to see its details.")
            )
        }
    }

    @ViewBuilder
    private func tabContent(for torrent: Torrent) -> some View {
        // For tabs that need rich per-file/peer data, use the separately-fetched
        // inspectorDetail when it matches the current torrent. The main list poll
        // only carries list fields, so those arrays would otherwise be empty.
        // Trackers ride the list poll (`trackerStats` is a list field), so they
        // stay live without the detail fetch.
        let detail = store.inspector.detail?.id == torrent.id ? store.inspector.detail! : torrent
        switch store.inspector.tab {
        case .general: InspectorGeneralTab(torrent: torrent.mergingMetadata(from: store.inspector.detail))
        case .files: InspectorFilesTab(torrent: detail)
        case .peers: InspectorPeersTab(torrent: detail)
        case .trackers: InspectorTrackersTab(torrent: torrent)
        }
    }
}

/// The inspector's tabs: a glass pill per tab, after Xcode's inspector.
/// Sits in the inspector's toolbar section on a wide window (see `MainWindow`),
/// else at the top of the column.
struct InspectorTabPicker: View {
    @Environment(TorrentStore.self) private var store

    var body: some View {
        @Bindable var inspector = store.inspector
        GlassSegmentedControl(
            selection: $inspector.tab,
            values: InspectorTab.allCases,
            indicator: .glass,
            fillsWidth: true,
            accessibilityLabel: \.displayLabel
        ) { tab, isSelected in
            Image(systemName: tab.systemImage)
                .foregroundStyle(isSelected ? .primary : .secondary)
                .frame(minHeight: 24)
                .help(tab.displayLabel)
        }
        .accessibilityIdentifier("inspector.tabs")
    }
}

#if DEBUG
#Preview("Selected") {
    let service = MockTorrentService()
    let store = TorrentStore(service: service)
    return InspectorView(usesToolbarTabs: false)
        .environment(store)
        .environment(TagColorStore())
        .environment(GeoIPStore())
        .frame(width: 322, height: 600)
        .task { store.list.selectedTorrentIDs = [5] }
}
#endif

#if DEBUG
#Preview("Empty") {
    InspectorView(usesToolbarTabs: false)
        .environment(TorrentStore(service: MockTorrentService(initial: [])))
        .environment(TagColorStore())
        .environment(GeoIPStore())
        .frame(width: 322, height: 600)
}
#endif
