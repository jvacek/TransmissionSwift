import SwiftUI
import TransmissionCore

/// Source-list sidebar — status filters, then dynamic tracker / folder / label
/// rollups derived from the torrent set. Selection is a `SidebarFilter` driven
/// off the store; `List(selection:)` wants an Optional binding, so we wrap.
struct SidebarView: View {
    @Environment(TorrentStore.self) private var store

    var body: some View {
        let selectionBinding = Binding<SidebarFilter?>(
            get: { store.selectedFilter },
            set: { if let new = $0 { store.selectedFilter = new } }
        )

        List(selection: selectionBinding) {
            Section("Status") {
                ForEach(TorrentStatusFilter.allCases, id: \.self) { filter in
                    Label(filter.displayLabel, systemImage: filter.systemImage)
                        .badge(store.facets.statusCounts[filter] ?? 0)
                        .tag(SidebarFilter.status(filter))
                        .accessibilityIdentifier("sidebar.status.\(filter.rawValue)")
                }
            }

            if !store.facets.trackers.isEmpty {
                Section("Trackers") {
                    ForEach(store.facets.trackers) { entry in
                        Label(entry.name, systemImage: "globe")
                            .badge(entry.count)
                            .tag(SidebarFilter.tracker(host: entry.name))
                    }
                }
            }

            if !store.facets.folders.isEmpty {
                Section("Folders") {
                    ForEach(store.facets.folders) { entry in
                        Label(entry.name, systemImage: "folder")
                            .badge(entry.count)
                            .tag(SidebarFilter.folder(name: entry.name))
                    }
                }
            }

            if !store.facets.labels.isEmpty {
                Section("Labels") {
                    ForEach(store.facets.labels) { entry in
                        Label(entry.name, systemImage: "tag")
                            .badge(entry.count)
                            .tag(SidebarFilter.label(name: entry.name))
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}
