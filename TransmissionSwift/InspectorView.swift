import SwiftUI
import TransmissionCore

/// Right-pane inspector — header, icon-segmented tab bar, and one of five
/// tab bodies. Renders the first selected torrent; selection changes flow in
/// through `TorrentStore` so content refreshes instantly.
struct InspectorView: View {
    @Environment(TorrentStore.self) private var store

    var body: some View {
        @Bindable var store = store

        if let torrent = store.selectedTorrents.first {
            VStack(spacing: 0) {
                InspectorHeader(torrent: torrent, selectionCount: store.selectedTorrents.count)

                Picker("Inspector Tab", selection: $store.inspectorTab) {
                    ForEach(InspectorTab.allCases, id: \.self) { tab in
                        Image(systemName: tab.systemImage)
                            .accessibilityLabel(tab.displayLabel)
                            .tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
                .accessibilityIdentifier("inspector.tabs")

                Divider()

                tabContent(for: torrent)
                    // Re-key per torrent: scroll positions and the Options
                    // tab's draft state reset on selection change, but stay
                    // put across 1s polling snapshots.
                    .id(torrent.id)
            }
            // Fetch rich inspector data whenever the selected torrent changes.
            .task(id: torrent.id) {
                await store.fetchInspectorDetail(for: torrent.id)
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
        // For tabs that need rich per-file/peer/tracker data, use the separately-
        // fetched inspectorDetail when it matches the current torrent. The main
        // list poll only carries list fields, so those arrays would otherwise
        // always be empty.
        let detail = store.inspectorDetail?.id == torrent.id ? store.inspectorDetail! : torrent
        switch store.inspectorTab {
        case .general: InspectorGeneralTab(torrent: torrent)
        case .files: InspectorFilesTab(torrent: detail)
        case .peers: InspectorPeersTab(torrent: detail)
        case .trackers: InspectorTrackersTab(torrent: detail)
        case .options: InspectorOptionsTab(torrent: torrent)
        }
    }
}

private struct InspectorHeader: View {
    let torrent: Torrent
    let selectionCount: Int

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            StatusDot(status: torrent.status, size: 10)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(torrent.name)
                    .font(.headline)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if selectionCount > 1 {
                    Text("First of \(selectionCount) selected")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var subtitle: String {
        let added = torrent.addedAt.formatted(.relative(presentation: .named))
        return "\(ColumnFormatters.humanizedSize(torrent.size)) · \(torrent.status.displayLabel) · added \(added)"
    }
}

#Preview("Selected") {
    let service = MockTorrentService()
    let store = TorrentStore(service: service)
    return InspectorView()
        .environment(store)
        .frame(width: 322, height: 600)
        .task { store.selectedTorrentIDs = [5] }
}

#Preview("Empty") {
    InspectorView()
        .environment(TorrentStore(service: MockTorrentService(initial: [])))
        .frame(width: 322, height: 600)
}
