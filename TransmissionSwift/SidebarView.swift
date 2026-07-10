import SwiftUI
import TransmissionCore

/// Source-list sidebar — status filters, then dynamic tracker / folder / label
/// rollups derived from the torrent set. The store normalizes selection to one
/// active row per section while allowing sections to combine.
struct SidebarView: View {
    @Environment(TorrentStore.self) private var store

    @AppStorage("sidebar.section.expanded.status") private var isStatusExpanded = true
    @AppStorage("sidebar.section.expanded.trackers") private var isTrackersExpanded = true
    @AppStorage("sidebar.section.expanded.folders") private var isFoldersExpanded = true
    @AppStorage("sidebar.section.expanded.labels") private var isLabelsExpanded = true

    var body: some View {
        List {
            Section(isExpanded: $isStatusExpanded) {
                ForEach(TorrentStatusFilter.allCases, id: \.self) { filter in
                    SidebarFilterRow(
                        label: filter.displayLabel,
                        systemImage: filter.systemImage,
                        count: store.facets.statusCounts[filter] ?? 0,
                        isSelected: store.selectedSidebarFilters.contains(.status(filter))
                    ) {
                        store.setStatusFilter(filter)
                    }
                    .accessibilityIdentifier("sidebar.status.\(filter.rawValue)")
                }
            } header: {
                Text("Status")
                    .padding(.trailing, 16)
            }

            if !store.facets.trackers.isEmpty {
                Section(isExpanded: $isTrackersExpanded) {
                    ForEach(store.facets.trackers) { entry in
                        SidebarFilterRow(
                            label: entry.name,
                            systemImage: "globe",
                            count: entry.count,
                            isSelected: store.selectedSidebarFilters.contains(.tracker(host: entry.name))
                        ) {
                            store.toggleTrackerFilter(entry.name)
                        }
                    }
                } header: {
                    Text("Trackers")
                        .padding(.trailing, 16)
                }
            }

            if !store.facets.folders.isEmpty {
                Section(isExpanded: $isFoldersExpanded) {
                    ForEach(store.facets.folders) { entry in
                        let isDefaultFolder = entry.name == FolderFilter.defaultFolderName
                        SidebarFilterRow(
                            label: isDefaultFolder ? "Default Folder" : entry.name,
                            systemImage: isDefaultFolder ? "folder.fill" : "folder",
                            count: entry.count,
                            isSelected: store.selectedSidebarFilters.contains(.folder(name: entry.name))
                        ) {
                            store.toggleFolderFilter(entry.name)
                        }
                    }
                } header: {
                    Text("Folders")
                        .padding(.trailing, 16)
                }
            }

            if !store.facets.labels.isEmpty {
                Section(isExpanded: $isLabelsExpanded) {
                    ForEach(store.facets.labels) { entry in
                        SidebarFilterRow(
                            label: entry.name,
                            systemImage: "tag",
                            count: entry.count,
                            isSelected: store.selectedSidebarFilters.contains(.label(name: entry.name))
                        ) {
                            store.toggleLabelFilter(entry.name)
                        }
                    }
                } header: {
                    Text("Labels")
                        .padding(.trailing, 16)
                }
            }
        }
        .listStyle(.sidebar)
    }
}

private struct SidebarFilterRow: View {
    let label: String
    let systemImage: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Label(label, systemImage: systemImage)
            .badge(count)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(Color.clear)
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .listRowBackground(
                isSelected
                    ? Color.accentColor.opacity(0.15)
                    : Color.clear
            )
            .listRowInsets(EdgeInsets())
    }
}
