import SwiftUI
import TransmissionCore
import os

private let logger = Logger(subsystem: "net.jvacek.TransmissionSwift", category: "SidebarView")

/// Source-list sidebar — status filters, then dynamic tracker / folder / label
/// rollups derived from the torrent set. The store normalizes selection to one
/// active row per section while allowing sections to combine.
struct SidebarView: View {
    @Environment(TorrentStore.self) private var store
    @Environment(FaviconStore.self) private var favicons

    @AppStorage("sidebar.section.expanded.status") private var isStatusExpanded = true
    @AppStorage("sidebar.section.expanded.trackers") private var isTrackersExpanded = true
    @AppStorage("sidebar.section.expanded.folders") private var isFoldersExpanded = true
    @AppStorage("sidebar.section.expanded.labels") private var isLabelsExpanded = true

    @AppStorage("fetchTrackerFavicons") private var fetchFavicons = true
    @State private var hasDoneStartupRefresh = false
    @State private var refreshDebounceTask: Task<Void, Never>?
    @State private var lastRefreshedHosts: Set<String> = []

    private var trackerHosts: [String] {
        // Limit to tier 0 and 1 (primary trackers) to avoid flooding with fallback trackers
        let maxTier = 1
        let allHosts = store.torrents.flatMap { torrent in
            torrent.trackers.filter { $0.tier <= maxTier }.map(\.host)
        }
        // Filter out obviously invalid hosts (IPs, localhost) but allow short names
        // for private trackers that may resolve via local DNS/VPN.
        let filtered = allHosts.filter { host in
            // Skip IPs (contains only digits and dots/colons)
            let isIP = host.allSatisfy { $0.isNumber || $0 == "." || $0 == ":" }
            // Skip localhost variants
            let isLocalhost = host == "localhost" || host.hasPrefix("localhost.")
            // Skip empty
            let isEmpty = host.isEmpty
            return !isIP && !isLocalhost && !isEmpty
        }
        let unique = Array(Set(filtered)).sorted()
        logger.info("Favicon hosts: \(unique.count, privacy: .public) unique hosts (from \(allHosts.count) trackers)")
        return unique
    }

    var body: some View {
        List {
            Section(isExpanded: $isStatusExpanded) {
                ForEach(TorrentStatusFilter.allCases, id: \.self) { filter in
                    SidebarFilterRow(
                        label: filter.displayLabel,
                        leading: { Image(systemName: filter.systemImage) },
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
                            leading: { FaviconView(host: entry.name) },
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
                            leading: {
                                Image(systemName: isDefaultFolder ? "folder.fill" : "folder")
                            },
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
                            leading: { Image(systemName: "tag") },
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
        .onAppear {
            if !hasDoneStartupRefresh {
                hasDoneStartupRefresh = true
                let hosts = trackerHosts
                lastRefreshedHosts = Set(hosts)
                Task { await favicons.startupRefresh(hosts: hosts) }
            }
        }
        .onChange(of: trackerHosts) { _, newHosts in
            guard hasDoneStartupRefresh, fetchFavicons else { return }
            let newSet = Set(newHosts)
            // Only refresh if the set of hosts actually changed (not just order)
            guard newSet != lastRefreshedHosts else { return }
            lastRefreshedHosts = newSet

            refreshDebounceTask?.cancel()
            let hosts = newHosts
            refreshDebounceTask = Task {
                try? await Task.sleep(for: .seconds(0.5))
                guard !Task.isCancelled else { return }
                await favicons.refresh(hosts: hosts)
            }
        }
        .onChange(of: fetchFavicons) { _, newValue in
            if newValue {
                let hosts = trackerHosts
                lastRefreshedHosts = Set(hosts)
                Task { await favicons.refresh(hosts: hosts) }
            }
        }
        .onDisappear {
            refreshDebounceTask?.cancel()
        }
    }
}

private struct SidebarFilterRow<Leading: View>: View {
    let label: String
    @ViewBuilder let leading: () -> Leading
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Label {
            Text(label)
        } icon: {
            leading()
        }
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
