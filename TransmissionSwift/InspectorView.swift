import SwiftUI
import TransmissionCore

/// Slice-1 placeholder. The five-tab inspector lands in slice 2.
struct InspectorView: View {
    @Environment(TorrentStore.self) private var store

    var body: some View {
        if let torrent = store.selectedTorrents.first {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 8) {
                    StatusDot(status: torrent.status, size: 10)
                        .padding(.top, 6)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(torrent.name)
                            .font(.headline)
                            .lineLimit(2)
                        Text("\(torrent.size.formattedSize) · \(torrent.status.displayLabel)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                Divider()
                Text("Inspector tabs land in slice 2.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .topLeading)
        } else {
            ContentUnavailableView(
                "No Selection",
                systemImage: "info.circle",
                description: Text("Select a torrent to see its details.")
            )
        }
    }
}
