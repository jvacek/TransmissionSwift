import SwiftUI
import TransmissionCore
import TransmissionTestSupport

/// Tracker announce endpoints grouped by failover tier, one `GroupBox` card
/// per tracker. Adding, removing and re-tiering all rewrite the whole announce
/// list (`torrent-set` `trackerList`), so every edit reads the trackers from the
/// last poll and sends the new list back.
struct InspectorTrackersTab: View {
    let torrent: Torrent
    @Environment(TorrentStore.self) private var store
    @Environment(FaviconStore.self) private var favicons
    @State private var isAddingTracker = false
    /// A private torrent's last tracker, awaiting confirmation: removing it
    /// leaves the torrent with no way to find peers.
    @State private var pendingPrivateRemoval: Tracker?

    private var tiers: [(tier: Int, trackers: [Tracker])] {
        Dictionary(grouping: torrent.trackers, by: \.tier)
            .sorted { $0.key < $1.key }
            .map { (tier: $0.key, trackers: $0.value) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if torrent.isPrivate {
                    Label(
                        "Private torrent: only these trackers can be used. DHT, PEX and local peer discovery are off.",
                        systemImage: "lock.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
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
                            trackerCard(tracker)
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
        .confirmationDialog(
            "Remove the last tracker?",
            isPresented: Binding(
                get: { pendingPrivateRemoval != nil },
                set: { if !$0 { pendingPrivateRemoval = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingPrivateRemoval
        ) { tracker in
            Button("Remove Tracker", role: .destructive) {
                Task { await store.actions.removeTracker(torrent.id, tracker) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text(
                "This is a private torrent, so DHT, PEX and local peer discovery are off. Without its only tracker it can't find peers."
            )
        }
        // Make sure icons exist for this torrent's trackers — no-op for hosts
        // the sidebar already fetched.
        .task(id: torrent.id) {
            let hosts = Set(torrent.trackers.map(\.host))
            guard !hosts.isEmpty else { return }
            await favicons.refresh(hosts: Array(hosts))
        }
    }

    @ViewBuilder
    private func trackerCard(_ tracker: Tracker) -> some View {
        let card = TrackerCard(
            tracker: tracker,
            // Legacy snapshots carry stats without an announce URL; there is
            // nothing to remove or move.
            canRemove: store.actionsEnabled && !tracker.announce.isEmpty
        ) {
            requestRemoval(of: tracker)
        }
        if store.actionsEnabled {
            card.contextMenu {
                trackerMenu(for: tracker)
            }
        } else {
            card
        }
    }

    /// Removing a private torrent's only tracker strands it: private torrents
    /// can't fall back on DHT, PEX or local discovery, so ask first.
    private func requestRemoval(of tracker: Tracker) {
        if trackerRemovalWouldStrand(torrent) {
            pendingPrivateRemoval = tracker
        } else {
            Task { await store.actions.removeTracker(torrent.id, tracker) }
        }
    }

    /// Tier moves, which are a reorder of the announce list: joining a tier
    /// makes the tracker race with its new peers, a tier past the last one is a
    /// new backup.
    @ViewBuilder
    private func trackerMenu(for tracker: Tracker) -> some View {
        Button("Remove Tracker", role: .destructive) {
            requestRemoval(of: tracker)
        }
        if let last = tiers.last {
            let otherTiers = tiers.map(\.tier).filter { $0 != tracker.tier }
            // A tracker alone in the last tier is already at the end of the
            // list; a new tier would serialize to the same string.
            let canStartNewTier = last.tier != tracker.tier || last.trackers.count > 1
            if !otherTiers.isEmpty || canStartNewTier {
                Divider()
                ForEach(otherTiers, id: \.self) { tier in
                    Button("Move to Tier \(tier + 1)") {
                        Task { await store.actions.moveTracker(torrent.id, tracker, toTier: tier) }
                    }
                }
                if canStartNewTier {
                    Button("Move to New Tier") {
                        Task {
                            await store.actions.moveTracker(
                                torrent.id, tracker, toTier: last.tier + 1)
                        }
                    }
                }
            }
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

/// True when removing one tracker would leave the torrent unable to find
/// peers: a private torrent can't fall back on DHT, PEX or local discovery.
nonisolated func trackerRemovalWouldStrand(_ torrent: Torrent) -> Bool {
    torrent.isPrivate && torrent.trackers.count == 1
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

#Preview("Private Trackers") {
    InspectorTrackersTab(torrent: Torrent.samples[1])
        .environment(previewTorrentStore)
        .environment(FaviconStore())
        .frame(width: 322, height: 500)
}

#Preview("Add Tracker") {
    AddTrackerSheet(torrent: Torrent.samples[4])
        .environment(previewTorrentStore)
        .frame(width: 420)
}
