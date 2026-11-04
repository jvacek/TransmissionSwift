import SwiftUI
import TransmissionCore
import TransmissionTestSupport

/// Tracker announce endpoints grouped by failover tier, one `GroupBox` card
/// per tracker. Every edit (add, change URL, remove, re-tier) rewrites the
/// whole announce list (`torrent-set` `trackerList`), so it reads the trackers
/// from the last poll and sends the new list back.
struct InspectorTrackersTab: View {
    let torrent: Torrent
    @Environment(TorrentStore.self) private var store
    @Environment(FaviconStore.self) private var favicons
    @State private var isAddingTracker = false
    /// The tracker whose announce URL is being changed.
    @State private var editingTracker: Tracker?
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
                    PrivateTorrentNote(
                        message:
                            "Only the trackers below are used. DHT, PEX and local peer discovery are off."
                    )
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
        .sheet(item: $editingTracker) { tracker in
            AddTrackerSheet(torrent: torrent, editing: tracker)
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
        // Legacy snapshots carry stats without an announce URL; there is
        // nothing to edit.
        let editable = store.actionsEnabled && !tracker.announce.isEmpty
        let card = TrackerCard(tracker: tracker, canRemove: editable) {
            requestRemoval(of: tracker)
        }
        if editable {
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

    /// Everything that rewrites the announce list: swapping one URL, removing
    /// an entry, and re-tiering, which is a reorder of the same list. Joining a
    /// tier makes the tracker race with its members; a tier past the last one
    /// becomes a new backup.
    @ViewBuilder
    private func trackerMenu(for tracker: Tracker) -> some View {
        Button("Change Announce URL…") {
            editingTracker = tracker
        }
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
                // Tiers get a submenu of their own: a public torrent can list
                // dozens of them, and they would swamp the card's own actions.
                if otherTiers.isEmpty {
                    Button("Move to New Tier") {
                        move(tracker, toTier: last.tier + 1)
                    }
                } else {
                    Menu("Move to Tier") {
                        ForEach(otherTiers, id: \.self) { tier in
                            Button("Tier \(tier + 1)") {
                                move(tracker, toTier: tier)
                            }
                        }
                        if canStartNewTier {
                            Divider()
                            Button("New Tier") {
                                move(tracker, toTier: last.tier + 1)
                            }
                        }
                    }
                }
            }
        }
    }

    private func move(_ tracker: Tracker, toTier tier: Int) {
        Task { await store.actions.moveTracker(torrent.id, tracker, toTier: tier) }
    }
}

/// The private-torrent caveat, as an amber-tinted card. The body stays in the
/// ordinary text colours: a saturated amber caption fails contrast on the light
/// themes, so the tint and the icon carry the warning instead.
private struct PrivateTorrentNote: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(.top, 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Private torrent")
                    .font(.caption.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            .orange.opacity(0.12),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.orange.opacity(0.25))
        }
        .accessibilityElement(children: .combine)
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

/// Adds one announce URL to a torrent, or changes an existing tracker's URL.
/// The daemon gets the rebuilt list through `TrackerList`; this sheet only
/// validates the URL.
private struct AddTrackerSheet: View {
    @Environment(TorrentStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let torrent: Torrent
    /// Set when changing an existing tracker's announce URL.
    var editing: Tracker? = nil

    @State private var announce = ""
    @State private var isSaving = false
    @State private var saveError: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(editing == nil ? "Add Tracker" : "Change Tracker URL")
                .font(.headline)
            Text(hint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if torrent.isPrivate {
                PrivateTorrentNote(
                    message:
                        "Use the announce URL from the tracker you got this torrent from. Another tracker won't have this torrent, and a public one won't count toward your ratio."
                )
            }

            TextField("Announce URL", text: $announce)
                .textFieldStyle(.roundedBorder)
                .font(.callout.monospaced())
                .disabled(isSaving)
                .onSubmit { Task { await submit() } }
                .accessibilityIdentifier("inspector.trackers.announce")

            // Nothing to complain about until there's input: the button is
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
                Button(submitLabel) {
                    Task { await submit() }
                }
                .buttonStyle(.glassProminent)
                .disabled(!canSubmit)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            announce = editing?.announce ?? ""
        }
    }

    private var hint: String {
        if editing == nil {
            return "The announce URL, e.g. https://tracker.example.org/announce"
        }
        return "The new announce URL for this tracker. It keeps its tier."
    }

    private var submitLabel: String {
        if isSaving { return editing == nil ? "Adding…" : "Changing…" }
        return editing == nil ? "Add" : "Change"
    }

    private var validationError: String? {
        trackerAnnounceValidation(announce, existing: torrent.trackers, replacing: editing)
    }

    private var canSubmit: Bool {
        !isSaving && validationError == nil && store.actionsEnabled
    }

    private func submit() async {
        guard canSubmit else { return }
        isSaving = true
        defer { isSaving = false }
        saveError = nil
        let url = normalizedTrackerAnnounce(announce)
        let succeeded: Bool
        if let editing {
            succeeded = await store.actions.replaceTracker(torrent.id, editing, announce: url)
        } else {
            succeeded = await store.actions.addTracker(torrent.id, announce: url)
        }
        if succeeded {
            dismiss()
        } else {
            saveError =
                store.lastActionError?.localizedDescription
                ?? (editing == nil ? "Failed to add the tracker." : "Failed to change the tracker URL.")
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

/// Why `input` can't be used as an announce URL, or nil when it's a tracker the
/// daemon will accept. Mirrors Transmission's own checks: a parseable URL on a
/// protocol it announces over, not already in the list. `replacing` is the
/// tracker whose URL is being changed, which may keep its own value.
nonisolated func trackerAnnounceValidation(
    _ input: String, existing: [Tracker], replacing: Tracker? = nil
) -> String? {
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
    if let replacing, replacing.announce.caseInsensitiveCompare(announce) == .orderedSame {
        return "Enter a different announce URL."
    }
    if existing.contains(where: {
        $0.announce != replacing?.announce
            && $0.announce.caseInsensitiveCompare(announce) == .orderedSame
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

#Preview("Change Tracker URL") {
    AddTrackerSheet(torrent: Torrent.samples[4], editing: Torrent.samples[4].trackers[0])
        .environment(previewTorrentStore)
        .frame(width: 420)
}

#Preview("Add Tracker (Private)") {
    AddTrackerSheet(torrent: Torrent.samples[1])
        .environment(previewTorrentStore)
        .frame(width: 420)
}
