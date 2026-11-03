import SwiftUI
import TransmissionCore
import TransmissionTestSupport

/// Tracker announce endpoints grouped by failover tier, one `GroupBox` card
/// per tracker. Adding and removing rewrites the whole announce list
/// (`torrent-set` `trackerList`), so every edit reads the trackers from the
/// last poll and sends the new list back.
struct InspectorTrackersTab: View {
    let torrent: Torrent
    @Environment(TorrentStore.self) private var store
    @Environment(FaviconStore.self) private var favicons
    @State private var isAddingTracker = false

    private var tiers: [(tier: Int, trackers: [Tracker])] {
        Dictionary(grouping: torrent.trackers, by: \.tier)
            .sorted { $0.key < $1.key }
            .map { (tier: $0.key, trackers: $0.value) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if torrent.trackers.isEmpty {
                    Text("No trackers")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach(tiers, id: \.tier) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        if tiers.count > 1 {
                            Text("Tier \(group.tier + 1)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        ForEach(group.trackers) { tracker in
                            TrackerCard(
                                tracker: tracker,
                                // Legacy snapshots carry stats without an
                                // announce URL; there is nothing to remove.
                                canRemove: store.actionsEnabled && !tracker.announce.isEmpty
                            ) {
                                Task { await store.actions.removeTracker(torrent.id, tracker) }
                            }
                        }
                    }
                }
                if store.actionsEnabled {
                    Button("Add Tracker…", systemImage: "plus") {
                        isAddingTracker = true
                    }
                    .buttonStyle(.borderless)
                    .font(.callout)
                    .accessibilityIdentifier("inspector.trackers.add")
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(isPresented: $isAddingTracker) {
            AddTrackerSheet(torrent: torrent)
        }
        // Make sure icons exist for this torrent's trackers — no-op for hosts
        // the sidebar already fetched.
        .task(id: torrent.id) {
            let hosts = Set(torrent.trackers.map(\.host))
            guard !hosts.isEmpty else { return }
            await favicons.refresh(hosts: Array(hosts))
        }
    }
}

private struct TrackerCard: View {
    let tracker: Tracker
    let canRemove: Bool
    let onRemove: () -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(tracker.state.displayColor)
                        .frame(width: 7, height: 7)
                        .accessibilityLabel(tracker.state.displayLabel)
                    FaviconView(host: tracker.host)
                        .frame(width: 16, height: 16)
                    Text(tracker.host)
                        .font(.callout.weight(.semibold).monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(tracker.announce.isEmpty ? tracker.host : tracker.announce)
                    if canRemove {
                        Spacer(minLength: 4)
                        Button(action: onRemove) {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help("Remove this tracker")
                        .accessibilityLabel("Remove \(tracker.host)")
                    }
                }
                LinkableText(
                    text: tracker.statusMessage,
                    color: tracker.state == .error ? Color.red : Color.secondary
                )
                .font(.caption)
                Text(statsLine)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var statsLine: String {
        "\(tracker.seedCount) seeds · \(tracker.leechCount) leechers"
            + " · \(tracker.downloadCount.formatted()) downloads"
    }
}

/// Adds one announce URL to a torrent. The daemon gets the rebuilt list through
/// `TrackerList`; this sheet only validates the URL.
private struct AddTrackerSheet: View {
    @Environment(TorrentStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let torrent: Torrent

    @State private var announce = ""
    @State private var isSaving = false
    @State private var saveError: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add Tracker")
                .font(.headline)
            Text("The announce URL, e.g. https://tracker.example.org/announce")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Announce URL", text: $announce)
                .textFieldStyle(.roundedBorder)
                .font(.callout.monospaced())
                .disabled(isSaving)
                .onSubmit { Task { await add() } }
                .accessibilityIdentifier("inspector.trackers.announce")

            // Nothing to complain about until there's input: the Add button is
            // already disabled for an empty field.
            if !announce.isEmpty, let validationError {
                Text(validationError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let saveError {
                Text(saveError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isSaving ? "Adding…" : "Add") {
                    Task { await add() }
                }
                .buttonStyle(.glassProminent)
                .disabled(!canAdd)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private var validationError: String? {
        trackerAnnounceValidation(announce, existing: torrent.trackers)
    }

    private var canAdd: Bool {
        !isSaving && validationError == nil && store.actionsEnabled
    }

    private func add() async {
        guard canAdd else { return }
        isSaving = true
        defer { isSaving = false }
        saveError = nil
        let succeeded = await store.actions.addTracker(
            torrent.id, announce: normalizedTrackerAnnounce(announce))
        if succeeded {
            dismiss()
        } else {
            saveError = store.lastActionError?.localizedDescription ?? "Failed to add the tracker."
        }
    }
}

/// The typed announce URL without surrounding whitespace.
nonisolated func normalizedTrackerAnnounce(_ input: String) -> String {
    input.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Why `input` can't be added to `existing`, or nil when it's a tracker the
/// daemon will accept. Mirrors Transmission's own checks: a parseable URL on a
/// protocol it announces over, not already in the list.
nonisolated func trackerAnnounceValidation(_ input: String, existing: [Tracker]) -> String? {
    let announce = normalizedTrackerAnnounce(input)
    if announce.isEmpty { return "Enter an announce URL." }
    guard let url = URL(string: announce),
        let scheme = url.scheme?.lowercased(),
        ["http", "https", "udp"].contains(scheme),
        let host = url.host,
        !host.isEmpty
    else {
        return "Enter a full announce URL, like https://tracker.example.org/announce."
    }
    if existing.contains(where: {
        $0.announce.caseInsensitiveCompare(announce) == .orderedSame
    }) {
        return "This tracker is already in the list."
    }
    return nil
}

#Preview("Multi-tier Trackers") {
    InspectorTrackersTab(torrent: Torrent.samples[4])
        .environment(previewTorrentStore)
        .environment(FaviconStore())
        .frame(width: 322, height: 500)
}

#Preview("Add Tracker") {
    AddTrackerSheet(torrent: Torrent.samples[4])
        .environment(previewTorrentStore)
        .frame(width: 420)
}
