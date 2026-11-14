// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import TransmissionCore

#if DEBUG
import TransmissionTestSupport
#endif

/// Per-file selection and bandwidth priority. Mutations dispatch through the
/// store; the service broadcasts a fresh snapshot, which flows back in via
/// the parent's `torrent`.
struct InspectorFilesTab: View {
    @Environment(TorrentStore.self) private var store
    @Environment(ServerProfileStore.self) private var profileStore
    @Environment(OpenMappingStore.self) private var mappingStore
    let torrent: Torrent

    @State private var selectedFiles: Set<TorrentFile.ID> = []
    @State private var sortKey: FileSortKey = .name
    @State private var sortAscending: Bool = true
    @State private var sortedFiles: [TorrentFile] = []
    @State private var sizeColumnWidth: CGFloat = 60

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            Divider()
            List(selection: $selectedFiles) {
                ForEach(sortedFiles) { file in
                    FileRow(
                        file: file,
                        sizeColumnWidth: sizeColumnWidth,
                        wanted: wantedBinding(for: file),
                        priority: priorityBinding(for: file),
                        actionsEnabled: store.actionsEnabled,
                        isSelected: selectedFiles.contains(file.id)
                    )
                    .tag(file.id)
                    .contextMenu { fileMenu(for: file) }
                }
            }
            .listStyle(.inset)
            .alternatingRowBackgrounds()
            .accessibilityIdentifier("inspector.files.list")
        }
        .onChange(of: torrent.files, initial: true) { _, _ in rebuildFileCache() }
        .onChange(of: sortKey) { _, _ in rebuildFileCache() }
        .onChange(of: sortAscending) { _, _ in rebuildFileCache() }
    }

    /// Header row with one sort chip per key. The active chip shows the current
    /// direction; clicking it again flips ascending/descending.
    private var headerRow: some View {
        HStack(spacing: 2) {
            ForEach(FileSortKey.allCases) { key in
                sortButton(for: key)
            }
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
    }

    private func sortButton(for key: FileSortKey) -> some View {
        let isActive = key == sortKey
        return Button {
            if isActive {
                sortAscending.toggle()
            } else {
                sortKey = key
                sortAscending = key.defaultAscending
            }
        } label: {
            HStack(spacing: 3) {
                Text(key.displayLabel)
                if isActive {
                    Image(systemName: sortAscending ? "arrow.up" : "arrow.down")
                        .font(.caption2)
                }
            }
            .font(.caption)
            .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(isActive ? Color.accentColor.opacity(0.12) : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .help(
            isActive
                ? "\(key.displayLabel) \(sortAscending ? "ascending" : "descending")" : "Sort by \(key.displayLabel)")
    }

    private func rebuildFileCache() {
        sortedFiles = torrent.files.sorted { isOrderedBefore($0, $1) }
        sizeColumnWidth = Self.sizeColumnWidth(for: torrent.files)
    }

    private func setWanted(_ wanted: Bool, for ids: [TorrentFile.ID]) {
        Task {
            await store.actions.setFilesWanted(torrent.id, fileIDs: ids, wanted: wanted)
        }
    }

    private func setPriority(_ choice: FilePriorityChoice, for ids: [TorrentFile.ID]) {
        Task {
            if let priority = choice.priority {
                await store.actions.setFilesWanted(torrent.id, fileIDs: ids, wanted: true)
                await store.actions.setFilePriority(torrent.id, fileIDs: ids, priority: priority)
            } else {
                await store.actions.setFilesWanted(torrent.id, fileIDs: ids, wanted: false)
            }
        }
    }

    @ViewBuilder
    private func fileMenu(for file: TorrentFile) -> some View {
        let ids = fileTargetIDs(selected: selectedFiles, clicked: file.id)
        Button("Download Selected") { setWanted(true, for: ids) }
            .disabled(!store.actionsEnabled)
        Button("Don't Download Selected") { setWanted(false, for: ids) }
            .disabled(!store.actionsEnabled)
        Menu("Priority") {
            ForEach(FilePriorityChoice.allCases, id: \.self) { choice in
                Button {
                    setPriority(choice, for: ids)
                } label: {
                    Label(choice.displayLabel, systemImage: choice.systemImage)
                }
            }
        }
        .disabled(!store.actionsEnabled)
        Divider()
        mappingMenu(for: file)
    }

    @ViewBuilder
    private func mappingMenu(for file: TorrentFile) -> some View {
        let profile = profileStore.activeProfile
        let mappings = profile.map { mappingStore.mappings(for: $0) } ?? []
        if mappings.isEmpty {
            Button("No file mappings configured") {}.disabled(true)
        } else {
            ForEach(mappings) { mapping in
                Button {
                    guard let profile else { return }
                    Task {
                        await MappingOpener.open(
                            mapping, torrent: torrent, file: file, profile: profile, store: store,
                            mappingStore: mappingStore)
                    }
                } label: {
                    Label(
                        mapping.action == .finder
                            ? "Reveal in \(mapping.name)" : "Open with \(mapping.name)",
                        systemImage: mapping.action == .finder ? "folder" : "arrow.up.right.square")
                }
                .disabled(!store.actionsEnabled)
            }
        }
    }

    private func isOrderedBefore(_ lhs: TorrentFile, _ rhs: TorrentFile) -> Bool {
        switch sortKey {
        case .name:
            let order = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
            return sortAscending ? order == .orderedAscending : order == .orderedDescending
        case .size:
            return sortAscending ? lhs.size < rhs.size : lhs.size > rhs.size
        case .priority:
            let lhsRank = FilePriorityChoice(file: lhs).sortRank
            let rhsRank = FilePriorityChoice(file: rhs).sortRank
            return sortAscending ? lhsRank < rhsRank : lhsRank > rhsRank
        case .progress:
            return sortAscending ? lhs.progress < rhs.progress : lhs.progress > rhs.progress
        }
    }

    /// Width of the widest size string, so the size column and its trailing
    /// progress bar stay aligned across rows regardless of the values shown.
    /// Computed when the file list changes, not on every body pass.
    private static func sizeColumnWidth(for files: [TorrentFile]) -> CGFloat {
        let font = NSFont.monospacedDigitSystemFont(
            ofSize: NSFont.systemFontSize(for: .small), weight: .regular)
        let widths = files.map { file in
            (ColumnFormatters.humanizedSize(file.size) as NSString).size(
                withAttributes: [.font: font]).width
        }
        return (widths.max().map { ceil($0) + 2 }) ?? 60
    }

    private func wantedBinding(for file: TorrentFile) -> Binding<Bool> {
        Binding(
            get: { file.wanted },
            set: { wanted in
                Task { await store.actions.setFilesWanted(torrent.id, fileIDs: [file.id], wanted: wanted) }
            }
        )
    }

    private func priorityBinding(for file: TorrentFile) -> Binding<FilePriorityChoice> {
        Binding(
            get: { FilePriorityChoice(file: file) },
            set: { choice in
                Task {
                    if let priority = choice.priority {
                        if !file.wanted {
                            await store.actions.setFilesWanted(
                                torrent.id, fileIDs: [file.id], wanted: true)
                        }
                        await store.actions.setFilePriority(
                            torrent.id, fileIDs: [file.id], priority: priority)
                    } else {
                        await store.actions.setFilesWanted(torrent.id, fileIDs: [file.id], wanted: false)
                    }
                }
            }
        )
    }
}

/// Which files a context-menu action targets: the whole selection when the
/// clicked row is part of it, otherwise just that row. Pure so the bulk-target
/// rule is testable without a window.
nonisolated func fileTargetIDs(
    selected: Set<TorrentFile.ID>, clicked: TorrentFile.ID
) -> [TorrentFile.ID] {
    selected.contains(clicked) ? Array(selected) : [clicked]
}

/// One file: checkbox + name + priority capsule on the first line, size +
/// progress on the second. Compact for the narrow inspector.
private struct FileRow: View {
    let file: TorrentFile
    let sizeColumnWidth: CGFloat
    @Binding var wanted: Bool
    @Binding var priority: FilePriorityChoice
    let actionsEnabled: Bool
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .top, spacing: 7) {
                Toggle("Download", isOn: $wanted)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .accessibilityLabel("Download \(file.displayName)")
                    .disabled(!actionsEnabled)
                    .padding(.top, 2)
                Text(file.displayName)
                    .font(.callout.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(
                        isSelected ? Color(nsColor: .selectedTextColor) : Color.primary)
                Spacer(minLength: 8)
                FilePriorityPicker(
                    choice: $priority,
                    isEnabled: actionsEnabled,
                    label: "Priority for \(file.displayName)"
                )
                .padding(.top, 1)
            }

            HStack(spacing: 8) {
                Text(ColumnFormatters.humanizedSize(file.size))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(
                        isSelected
                            ? Color(nsColor: .selectedTextColor).opacity(0.8)
                            : Color.secondary
                    )
                    .frame(width: sizeColumnWidth, alignment: .trailing)
                ProgressBar(
                    value: file.progress,
                    status: file.progress >= 1 ? .seeding : .downloading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Sort keys for the files list. "Don't download" files sort under Priority as
/// their own lowest rank.
private enum FileSortKey: CaseIterable, Identifiable {
    case name, size, priority, progress

    var id: Self { self }

    var displayLabel: String {
        switch self {
        case .name: return "Name"
        case .size: return "Size"
        case .priority: return "Prio"
        case .progress: return "%"
        }
    }

    var defaultAscending: Bool {
        switch self {
        case .name, .priority: return true
        case .size, .progress: return false
        }
    }
}

#if DEBUG
#Preview {
    InspectorFilesTab(torrent: Torrent.samples[4])
        .environment(TorrentStore(service: MockTorrentService()))
        .environment(
            ServerProfileStore(
                fileURL: URL.temporaryDirectory.appending(path: "preview-servers.json"))
        )
        .environment(
            OpenMappingStore(fileURL: URL.temporaryDirectory.appending(path: "preview-mappings.json"))
        )
        .frame(width: 322, height: 400)
}
#endif
