import AppKit
import SwiftUI
import TransmissionCore

/// Per-file selection and bandwidth priority. Mutations dispatch through the
/// store; the service broadcasts a fresh snapshot, which flows back in via
/// the parent's `torrent`.
struct InspectorFilesTab: View {
    @Environment(TorrentStore.self) private var store
    @Environment(ServerProfileStore.self) private var profileStore
    let torrent: Torrent

    @State private var selectedFiles: Set<TorrentFile.ID> = []
    @State private var sortKey: FileSortKey = .name
    @State private var sortAscending: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(sortedFiles) { file in
                        FileRow(
                            file: file,
                            sizeColumnWidth: sizeColumnWidth,
                            wanted: wantedBinding(for: file),
                            priority: priorityBinding(for: file)
                        )
                        .padding(.horizontal, 4)
                        .padding(.vertical, 3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .background(rowBackground(for: file))
                        .onTapGesture {
                            toggleSelection(file.id)
                        }
                        .contextMenu {
                            mappingMenu(for: file)
                        }
                    }
                }
            }
            .accessibilityIdentifier("inspector.files.list")
        }
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

    private var sortedFiles: [TorrentFile] {
        torrent.files.sorted { isOrderedBefore($0, $1) }
    }

    /// Zebra only on real rows (no phantom stripes), using the native stripe
    /// colour so it adapts to light/dark mode. Selected rows get the standard
    /// selection fill instead.
    private func rowBackground(for file: TorrentFile) -> Color {
        if selectedFiles.contains(file.id) {
            return Color(nsColor: .selectedContentBackgroundColor)
        }
        guard !file.id.isMultiple(of: 2) else { return .clear }
        return Color(nsColor: NSColor.alternatingContentBackgroundColors[1])
    }

    /// Click selects just this file; ⌘-click toggles it in/out of the selection.
    private func toggleSelection(_ id: TorrentFile.ID) {
        if NSEvent.modifierFlags.contains(.command) {
            if selectedFiles.contains(id) {
                selectedFiles.remove(id)
            } else {
                selectedFiles.insert(id)
            }
        } else {
            selectedFiles = [id]
        }
    }

    @ViewBuilder
    private func mappingMenu(for file: TorrentFile) -> some View {
        let mappings = profileStore.activeProfile?.mappings ?? []
        if mappings.isEmpty {
            Button("No file mappings configured") {}.disabled(true)
        } else {
            ForEach(mappings) { mapping in
                Button {
                    guard let profile = profileStore.activeProfile else { return }
                    Task {
                        await MappingOpener.open(
                            mapping, torrent: torrent, file: file, profile: profile, store: store,
                            profileStore: profileStore)
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
    private var sizeColumnWidth: CGFloat {
        let font = NSFont.monospacedDigitSystemFont(
            ofSize: NSFont.systemFontSize(for: .small), weight: .regular)
        let widths = torrent.files.map { file in
            (ColumnFormatters.humanizedSize(file.size) as NSString).size(
                withAttributes: [.font: font]).width
        }
        return (widths.max().map { ceil($0) + 2 }) ?? 60
    }

    private func wantedBinding(for file: TorrentFile) -> Binding<Bool> {
        Binding(
            get: { file.wanted },
            set: { wanted in
                Task { await store.setFilesWanted(torrent.id, fileIDs: [file.id], wanted: wanted) }
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
                            await store.setFilesWanted(
                                torrent.id, fileIDs: [file.id], wanted: true)
                        }
                        await store.setFilePriority(
                            torrent.id, fileIDs: [file.id], priority: priority)
                    } else {
                        await store.setFilesWanted(torrent.id, fileIDs: [file.id], wanted: false)
                    }
                }
            }
        )
    }
}

/// One file: name + priority chevron on the first line, size and progress
/// sharing the second. Compact enough for the narrow inspector.
private struct FileRow: View {
    let file: TorrentFile
    let sizeColumnWidth: CGFloat
    @Binding var wanted: Bool
    @Binding var priority: FilePriorityChoice

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .top, spacing: 7) {
                Toggle("Download", isOn: $wanted)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .accessibilityLabel("Download \(file.displayName)")
                    .disabled(true)
                    .padding(.top, 2)
                Text(file.displayName)
                    .font(.callout.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                priorityMenu
                    .padding(.top, 2)
            }

            HStack(spacing: 8) {
                Text(ColumnFormatters.humanizedSize(file.size))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: sizeColumnWidth, alignment: .trailing)
                ProgressBar(
                    value: file.progress,
                    status: file.progress >= 1 ? .seeding : .downloading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var priorityMenu: some View {
        Menu {
            ForEach(FilePriorityChoice.allCases, id: \.self) { choice in
                Button {
                    priority = choice
                } label: {
                    Label(choice.displayLabel, systemImage: choice.systemImage)
                }
            }
        } label: {
            Image(systemName: priority.systemImage)
                .foregroundStyle(priority.displayColor)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(true)
        .accessibilityLabel("Priority for \(file.displayName)")
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

/// The Priority popup folds "don't download" into the priority choice, like
/// Transmission's own UI: High / Normal / Low / Skip.
private enum FilePriorityChoice: CaseIterable, Hashable {
    case high, normal, low, skip

    init(file: TorrentFile) {
        guard file.wanted else {
            self = .skip
            return
        }
        switch file.priority {
        case .high: self = .high
        case .normal: self = .normal
        case .low: self = .low
        }
    }

    var priority: TorrentPriority? {
        switch self {
        case .high: return .high
        case .normal: return .normal
        case .low: return .low
        case .skip: return nil
        }
    }

    var displayLabel: String {
        switch self {
        case .high: return "High"
        case .normal: return "Normal"
        case .low: return "Low"
        case .skip: return "Skip"
        }
    }

    /// Mirrors the torrent table's priority glyphs (TorrentTableCellView).
    var systemImage: String {
        switch self {
        case .high: return "chevron.up"
        case .normal: return "minus"
        case .low: return "chevron.down"
        case .skip: return "slash.circle"
        }
    }

    var displayColor: Color {
        switch self {
        case .high: return .orange
        case .normal: return .gray
        case .low: return .blue
        case .skip: return .secondary
        }
    }

    /// High > Normal > Low > Skip, for sorting.
    var sortRank: Int {
        switch self {
        case .high: return 0
        case .normal: return 1
        case .low: return 2
        case .skip: return 3
        }
    }
}

#Preview {
    InspectorFilesTab(torrent: Torrent.samples[4])
        .environment(TorrentStore(service: MockTorrentService()))
        .environment(
            ServerProfileStore(
                fileURL: URL.temporaryDirectory.appending(path: "preview-servers.json"))
        )
        .frame(width: 322, height: 400)
}
