// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import TransmissionCore
import UniformTypeIdentifiers

/// Sheet presented from the main window — the mutually-exclusive file and link
/// source is a segmented picker; the shared options (destination, tags,
/// priority, start) sit below. Everything scrolls together.
struct AddTorrentSheet: View {
    @Environment(TorrentStore.self) private var store
    @Binding var isPresented: Bool

    var initialMode: AddTorrentInputMode = .file
    var prefilledURL: URL? = nil
    var serverName: String? = nil

    private enum Field: Hashable { case link, destination }

    @FocusState private var focusedField: Field?
    @State private var mode: AddTorrentInputMode = .file
    @State private var fileURL: URL?
    @State private var fileTorrentName: String?
    @State private var addFiles: [TorrentAddFile] = []
    @State private var fileFilter = ""
    /// Built only when the file set or filter changes, so toggling a checkbox or
    /// changing a priority doesn't rebuild the tree and collapse its folders.
    @State private var fileTree: [AddTorrentFileNode] = []
    /// Flat lookup for selection expansion, rebuilt with the tree instead of
    /// walking the forest on every body pass.
    @State private var fileNodeByID: [String: AddTorrentFileNode] = [:]
    /// Every folder starts expanded; collapsing one only affects this session
    /// until the file or filter changes again.
    @State private var expandedFolderIDs: Set<String> = []
    /// Native list selection. Folder IDs expand to their descendant files when
    /// a bulk action runs, so selecting a directory changes its files too.
    @State private var selectedNodeIDs: Set<String> = []
    @State private var linkString: String = ""
    @State private var destination: String = ""
    @State private var tags: [String] = []
    @State private var priority: TorrentPriority = .normal
    @State private var startWhenAdded: Bool = true
    /// Read-only mirror of the Settings default. The row below flips the
    /// `@State` copy for this add only — it must never write back.
    @AppStorage(PreferenceKeys.deleteTorrentFileAfterAdding) private var deleteTorrentFileByDefault = false
    @State private var deleteSourceFile = false
    /// Persisted so collapsing the file list once keeps it collapsed.
    @AppStorage(PreferenceKeys.addTorrentFilesExpanded) private var filesExpanded = true
    @State private var showFileImporter: Bool = false
    @State private var isAdding: Bool = false
    @State private var isLoadingFile: Bool = false
    @State private var saveError: String? = nil

    var body: some View {
        // No outer ScrollView: the form is short and fixed-height, so scrolling
        // it only produced rubber-band bounce. The sheet instead grows to fit
        // its content, letting the known-folders list expand the sheet
        // dynamically; only that list itself scrolls when it overflows.
        sheetContent
            .frame(width: 560)
            .interactiveDismissDisabled(isAdding)
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.torrentFile]
            ) { result in
                if case .success(let url) = result {
                    fileURL = url
                    loadFile(at: url)
                }
            }
            .onAppear {
                // Destination stays empty by default — empty resolves to the
                // default download dir via resolveServerPath, same as Set
                // Location. The Full-path preview shows the real target.
                mode = initialMode
                // Seed the per-add option from the Settings default; the
                // toggle below never writes back.
                deleteSourceFile = deleteTorrentFileByDefault
                if let url = prefilledURL {
                    switch url.scheme?.lowercased() {
                    case "magnet", "http", "https":
                        mode = .link
                        linkString = url.absoluteString
                    default:
                        mode = .file
                        fileURL = url
                        loadFile(at: url)
                    }
                }
                // Explicit focus so macOS doesn't auto-focus (and select-all) the
                // Destination field. In link mode, focus the input so a paste lands
                // immediately; in file mode, leave focus unset.
                focusedField = inputField(for: mode)
            }
            .onChange(of: mode) { _, newMode in
                focusedField = inputField(for: newMode)
            }
    }

    /// The sheet's form. Kept out of a scroll view: it always fits, letting the
    /// known-folders list expand the sheet dynamically.
    private var sheetContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.text("Add Torrent"))
                .font(.headline)
            modePicker
            sourceSection
            filesSection
            optionsSection
            SheetButtonRow(
                L10n.text("Add"),
                busyTitle: L10n.text("Adding…"),
                isBusy: isAdding,
                canConfirm: isValid,
                onCancel: { isPresented = false },
                onConfirm: { Task { await submit() } }
            )
        }
        .padding(20)
    }

    // MARK: - Sections

    /// File vs. link, the only mutually exclusive choice.
    private var modePicker: some View {
        GlassSegmentedControl(
            selection: $mode,
            values: AddTorrentInputMode.allCases,
            accessibilityLabel: \.label
        ) { segment, isSelected in
            Text(segment.label)
                .font(.callout.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.white : Color.secondary)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity)
    }

    private func sourceLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
    }

    /// Shared bordered container so the file picker and the link input look
    /// alike. The content row gets a fixed height so switching modes doesn't
    /// shift the content below by a few pixels.
    private func sourceBox(_ content: some View) -> some View {
        content
            .frame(height: 24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(cardBackground())
    }

    @ViewBuilder
    private var sourceSection: some View {
        switch mode {
        case .file: fileSection
        case .link: linkSection
        }
    }

    private var fileSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sourceLabel(L10n.text("Torrent File"), systemImage: "doc.fill")
            sourceBox(
                HStack(spacing: 10) {
                    if let url = fileURL {
                        Label(url.lastPathComponent, systemImage: "doc.fill")
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Label(L10n.text("No file selected"), systemImage: "doc")
                            .foregroundStyle(.secondary)
                    }
                    if isLoadingFile {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel(L10n.text("Reading torrent file"))
                    }
                    Spacer()
                    Button(L10n.text("Choose…")) { showFileImporter = true }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                }
            )
        }
    }

    private var linkSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sourceLabel(L10n.text("Magnet Link or URL"), systemImage: "link")
            sourceBox(
                TextField(L10n.text("magnet:… or https://…"), text: $linkString)
                    .textFieldStyle(.plain)
                    .monospaced()
                    .focused($focusedField, equals: .link)
            )
        }
    }

    /// Add-time file selection. Hidden for links and single-file torrents,
    /// which have nothing to choose. The expanded state persists.
    @ViewBuilder
    private var filesSection: some View {
        if mode == .file, addFiles.count > 1 {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        filesExpanded.toggle()
                        if !filesExpanded { clearFileSelection() }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(filesExpanded ? 90 : 0))
                        sourceLabel(L10n.text("Files"), systemImage: "doc.on.doc")
                        Spacer()
                        Text(selectionSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(filesExpanded ? L10n.text("Hide files") : L10n.text("Show files"))
                .accessibilityValue(filesExpanded ? L10n.text("Expanded") : L10n.text("Collapsed"))
                .help(filesExpanded ? L10n.text("Hide the file list") : L10n.text("Show the file list"))

                if filesExpanded {
                    VStack(spacing: 6) {
                        HStack(spacing: 8) {
                            fileFilterField
                            HStack(spacing: 6) {
                                Button(L10n.text("Download All")) { setAllWanted(true) }
                                Divider().frame(height: 12)
                                Button(L10n.text("None")) { setAllWanted(false) }
                            }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                        }

                        if !selectedTargetFileIndices.isEmpty {
                            fileBulkActions
                        }

                        if filteredFileIndices.isEmpty {
                            Text(L10n.text("No files match the filter."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 40)
                        } else {
                            fileList
                        }
                    }
                    .padding(8)
                    .background(cardBackground())
                    .onChange(of: fileFilter) { _, _ in
                        rebuildTree()
                        selectedNodeIDs.removeAll()
                    }

                    if !addFiles.isEmpty, wantedFiles.isEmpty {
                        Text(L10n.text("No files selected. The torrent will be added with every file skipped."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var fileList: some View {
        List(selection: $selectedNodeIDs) {
            ForEach(visibleRows) { row in
                fileNodeRow(row.node, depth: row.depth)
                    .tag(row.node.id)
                    .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                    .contextMenu { fileContextMenu(for: row.node) }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .focusEffectDisabled()
        .environment(\.defaultMinListRowHeight, addFileRowHeight)
        .frame(height: filesListHeight)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    @ViewBuilder
    private func fileNodeRow(_ node: AddTorrentFileNode, depth: Int) -> some View {
        Group {
            switch node.kind {
            case .file(let index):
                AddTorrentFileRow(
                    file: $addFiles[index],
                    name: node.name,
                    isSelected: selectedNodeIDs.contains(node.id))
            case .folder:
                let wantedCount = node.fileIndices.filter { addFiles[$0].wanted }.count
                AddTorrentFolderRow(
                    name: node.name,
                    size: node.fileIndices.reduce(0) { $0 + addFiles[$1].length },
                    allWanted: wantedCount == node.fileIndices.count,
                    anyWanted: wantedCount > 0,
                    choice: folderPriorityChoice(node),
                    isExpanded: expandedFolderIDs.contains(node.id),
                    isSelected: selectedNodeIDs.contains(node.id),
                    onToggleExpansion: { toggleFolder(node) },
                    onToggle: {
                        let allWanted = node.fileIndices.allSatisfy { addFiles[$0].wanted }
                        setWanted(!allWanted, for: Set(node.fileIndices))
                    },
                    onPriority: { applyPriority($0, to: Set(node.fileIndices)) })
            }
        }
        .padding(.leading, CGFloat(depth) * 16)
    }

    /// Flattens the tree to the rows currently visible. We keep this instead of
    /// `OutlineGroup` so every folder can start expanded and the chevron sits
    /// where the row wants it.
    private var visibleRows: [VisibleFileRow] {
        var rows: [VisibleFileRow] = []
        func visit(_ nodes: [AddTorrentFileNode], depth: Int) {
            for node in nodes {
                rows.append(VisibleFileRow(node: node, depth: depth))
                if node.isFolder, expandedFolderIDs.contains(node.id), let children = node.children {
                    visit(children, depth: depth + 1)
                }
            }
        }
        visit(fileTree, depth: 0)
        return rows
    }

    private func toggleFolder(_ node: AddTorrentFileNode) {
        withAnimation(.snappy(duration: 0.15)) {
            if expandedFolderIDs.contains(node.id) {
                expandedFolderIDs.remove(node.id)
                selectedNodeIDs.subtract(Set(node.children?.flatMap(\.nodeIDs) ?? []))
            } else {
                expandedFolderIDs.insert(node.id)
            }
        }
    }

    /// A folder's priority chip is uniform only when every descendant is wanted
    /// with the same priority. Some/varies shows the mixed state; all skipped
    /// shows Skip.
    private func folderPriorityChoice(_ node: AddTorrentFileNode) -> FilePriorityChoice? {
        let members = node.fileIndices.map { addFiles[$0] }
        if members.allSatisfy({ !$0.wanted }) { return .skip }
        guard members.allSatisfy(\.wanted), let first = members.first else { return nil }
        return members.allSatisfy { $0.priority == first.priority }
            ? FilePriorityChoice(wanted: true, priority: first.priority)
            : nil
    }

    /// Bulk actions for the highlighted rows. Appears only while rows are
    /// selected, so the checkbox and priority are the primary per-file controls.
    private var fileBulkActions: some View {
        HStack(spacing: 8) {
            Text(L10n.format("%lld files selected", Int64(selectedTargetFileIndices.count)))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 6) {
                Button(L10n.text("Download")) { setWanted(true, for: selectedTargetFileIndices) }
                Divider().frame(height: 12)
                Button(L10n.text("Skip")) { setWanted(false, for: selectedTargetFileIndices) }
                Menu(L10n.text("Priority")) {
                    priorityMenuItems(ids: selectedTargetFileIndices)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            Button {
                clearFileSelection()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.text("Clear selection"))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.accentColor.opacity(0.12))
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    @ViewBuilder
    private func priorityMenuItems(ids: Set<Int>) -> some View {
        ForEach(FilePriorityChoice.allCases, id: \.self) { choice in
            Button {
                applyPriority(choice, to: ids)
            } label: {
                Label(choice.displayLabel, systemImage: choice.systemImage)
            }
        }
    }

    @ViewBuilder
    private func fileContextMenu(for node: AddTorrentFileNode) -> some View {
        // Right-clicking a selected row acts on the whole selection; right-clicking
        // an unselected row acts on that row. Folder rows cover their descendants.
        let ids =
            selectedNodeIDs.contains(node.id)
            ? selectedTargetFileIndices : Set(node.fileIndices)
        Button(L10n.text("Download")) { setWanted(true, for: ids) }
        Button(L10n.text("Skip")) { setWanted(false, for: ids) }
        Divider()
        Menu(L10n.text("Priority")) {
            priorityMenuItems(ids: ids)
        }
    }

    /// The system search field, with a clear button beside it: the stock
    /// rounded field has no clear affordance on macOS.
    private var fileFilterField: some View {
        HStack(spacing: 4) {
            TextField(L10n.text("Filter Files"), text: $fileFilter)
                .textFieldStyle(.roundedBorder)
            if !fileFilter.isEmpty {
                Button {
                    fileFilter = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.text("Clear file filter"))
            }
        }
    }

    private func inputField(for mode: AddTorrentInputMode) -> Field? {
        switch mode {
        case .file: nil
        case .link: .link
        }
    }

    /// Shared inset-card surface: one system fill and the system separator, so
    /// every box in the sheet matches in light and dark mode.
    private func cardBackground(cornerRadius: CGFloat = 8) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.quaternary)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor)))
    }

    /// Shared options that apply to either source, in a grouped-form-style
    /// card. A Grid lets the label column size to its longest label at any
    /// text size; the toggles below span the full row.
    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow(alignment: .top) {
                    Text(L10n.text("Destination"))
                    ServerPathField(
                        path: $destination,
                        defaultDirectory: store.list.downloadDirectory,
                        folders: knownFolders,
                        serverName: serverName,
                        torrentName: expectedTorrentName)
                }
                Divider().gridCellColumns(2)
                GridRow {
                    Text(L10n.text("Tags"))
                    TagsInputField(tags: $tags, suggestions: store.list.facets.labels.map(\.name))
                        .help(
                            L10n.text(
                                "Type a tag and press Return to add it, or pick an existing one from the list that appears."
                            )
                        )
                }
                Divider().gridCellColumns(2)
                GridRow {
                    Text(L10n.text("Priority"))
                    prioritySegments
                }
            }
            Divider()
            fullWidthToggle(L10n.text("Start when added"), isOn: $startWhenAdded)
            // Links have no local file, so the cleanup option only makes
            // sense (and only shows) for file adds.
            if mode == .file {
                Divider()
                fullWidthToggle(L10n.text("Delete .torrent file after adding"), isOn: $deleteSourceFile)
            }
            if let saveError {
                Divider()
                Text(saveError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(cardBackground(cornerRadius: 10))
    }

    /// A grouped-form toggle row: label leading, switch trailing. A bare
    /// switch-style `Toggle` keeps its switch next to the label outside a Form.
    private func fullWidthToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
            Spacer()
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }

    /// Folders the daemon already knows about, offered as one-click destinations.
    private var knownFolders: [String] {
        serverPathSuggestions(from: store.list.facets)
    }

    /// Best-effort torrent name for the "Full path" preview: the chosen
    /// `.torrent`'s `info.name`, falling back to its file stem when the file
    /// can't be decoded, or a magnet link's `dn` display name.
    private var expectedTorrentName: String? {
        if mode == .file, let fileURL {
            return fileTorrentName ?? fileURL.deletingPathExtension().lastPathComponent
        }
        if mode == .link,
            let dn = URLComponents(string: linkString)?
                .queryItems?.first(where: { $0.name == "dn" })?.value,
            !dn.isEmpty
        {
            return dn
        }
        return nil
    }

    private func loadFile(at url: URL) {
        isLoadingFile = true
        Task {
            // Decoding a large `.torrent` is not instant; keep the sheet
            // responsive and ignore a result if the user picked another file.
            let preview = await Task.detached { TorrentMetainfoReader.preview(at: url) }.value
            guard fileURL == url else { return }
            fileTorrentName = preview?.name
            addFiles = preview?.files ?? []
            fileFilter = ""
            clearFileSelection()
            rebuildTree()
            isLoadingFile = false
        }
    }

    private func rebuildTree() {
        let tree = AddTorrentFileNode.tree(from: filteredFileIndices.map { addFiles[$0] })
        fileTree = tree
        fileNodeByID = Self.nodeMap(from: tree)
        expandedFolderIDs = Set(tree.flatMap(\.folderIDs))
    }

    private static func nodeMap(
        from nodes: [AddTorrentFileNode]
    ) -> [String: AddTorrentFileNode] {
        var result: [String: AddTorrentFileNode] = [:]
        func visit(_ nodes: [AddTorrentFileNode]) {
            for node in nodes {
                result[node.id] = node
                if let children = node.children { visit(children) }
            }
        }
        visit(nodes)
        return result
    }

    private var filteredFileIndices: [Int] {
        let query = fileFilter.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return Array(addFiles.indices) }
        return addFiles.indices.filter {
            addFiles[$0].pathString.localizedCaseInsensitiveContains(query)
        }
    }

    private var selectedTargetFileIndices: Set<Int> {
        selectedNodeIDs.reduce(into: Set<Int>()) { result, id in
            if let node = fileNodeByID[id] {
                result.formUnion(node.fileIndices)
            }
        }
    }

    private var filesListHeight: CGFloat {
        let rows = min(max(visibleRows.count, 5), 8)
        return CGFloat(rows) * addFileRowHeight
    }

    private var wantedFiles: [TorrentAddFile] {
        addFiles.filter(\.wanted)
    }

    private var selectionSummary: String {
        let size = ColumnFormatters.humanizedSize(wantedFiles.reduce(0) { $0 + $1.length })
        return L10n.format("%lld of %lld files, %@", Int64(wantedFiles.count), Int64(addFiles.count), size)
    }

    private func setAllWanted(_ wanted: Bool) {
        for index in addFiles.indices {
            addFiles[index].wanted = wanted
        }
    }

    private func clearFileSelection() {
        selectedNodeIDs.removeAll()
    }

    private func setWanted(_ wanted: Bool, for ids: Set<Int>) {
        for index in ids where addFiles.indices.contains(index) {
            addFiles[index].wanted = wanted
        }
    }

    private func applyPriority(_ choice: FilePriorityChoice, to ids: Set<Int>) {
        for index in ids where addFiles.indices.contains(index) {
            if let priority = choice.priority {
                addFiles[index].wanted = true
                addFiles[index].priority = priority
            } else {
                addFiles[index].wanted = false
            }
        }
    }

    private static func priorityAccessibilityLabel(_ level: TorrentPriority) -> String {
        L10n.format("Priority %@", level.displayLabel)
    }

    /// Priority, keeping its glyphs visible.
    private var prioritySegments: some View {
        GlassSegmentedControl(
            selection: $priority,
            values: [TorrentPriority.high, .normal, .low],
            accessibilityLabel: Self.priorityAccessibilityLabel
        ) { level, isSelected in
            HStack(spacing: 4) {
                Image(systemName: level.systemImage)
                Text(level.displayLabel)
            }
            .font(.callout)
            .foregroundStyle(isSelected ? Color.white : level.displayColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
    }

    // MARK: - Logic

    private var isValid: Bool {
        let sourceValid: Bool =
            switch mode {
            case .file: fileURL != nil
            case .link: Self.isTorrentLink(linkString)
            }
        return sourceValid && !isLoadingFile
            && isSubmittableServerPath(destination, relativeTo: store.list.downloadDirectory)
    }

    /// A magnet (infohash may sit anywhere after `magnet:?`) or an http(s) URL
    /// with a host — the daemon does the fetching, so endpoints don't have to
    /// end in `.torrent`.
    private static func isTorrentLink(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("magnet:") {
            return trimmed.contains("xt=urn:btih:")
        }
        guard
            let components = URLComponents(string: trimmed),
            let scheme = components.scheme?.lowercased()
        else { return false }
        return (scheme == "http" || scheme == "https") && components.host?.isEmpty == false
    }

    private func submit() async {
        isAdding = true
        defer { isAdding = false }
        saveError = nil
        let succeeded = await store.actions.add(
            fileURL: mode == .file ? fileURL : nil,
            linkURL: mode == .file ? nil : linkString.trimmingCharacters(in: .whitespacesAndNewlines),
            destination: resolveServerPath(destination, relativeTo: store.list.downloadDirectory),
            labels: tags,
            priority: priority,
            startWhenAdded: startWhenAdded,
            files: mode == .file ? addFiles : [],
            deleteFileAfterAdding: mode == .file && deleteSourceFile
        )
        if succeeded {
            isPresented = false
        } else {
            saveError = store.lastActionError?.localizedDescription ?? L10n.text("Failed to add torrent.")
            store.lastActionError = nil
        }
    }
}

extension UTType {
    fileprivate static let torrentFile = UTType(filenameExtension: "torrent") ?? .data
}

extension AddTorrentInputMode {
    fileprivate var label: String {
        switch self {
        case .file: L10n.text("File")
        case .link: L10n.text("Magnet / URL")
        }
    }
}

#if DEBUG
#Preview("Add Torrent") {
    AddTorrentSheet(isPresented: .constant(true))
        .environment(previewTorrentStore)
        .environment(TagColorStore())
}
#endif

#if DEBUG
#Preview("Magnet / URL") {
    AddTorrentSheet(isPresented: .constant(true), initialMode: .link)
        .environment(previewTorrentStore)
        .environment(TagColorStore())
}
#endif

#if DEBUG
#Preview("File selection") {
    AddTorrentSheet(isPresented: .constant(true), prefilledURL: previewMultiFileTorrentURL())
        .environment(previewTorrentStore)
        .environment(TagColorStore())
}
#endif

#if DEBUG
#Preview("File selection collapsed") {
    AddTorrentSheet(isPresented: .constant(true), prefilledURL: previewMultiFileTorrentURL())
        .defaultAppStorage(previewCollapsedFilesDefaults)
        .environment(previewTorrentStore)
        .environment(TagColorStore())
}
#endif

/// A separate defaults store so the collapsed preview doesn't flip the real
/// preview (or the app) into the collapsed state.
private let previewCollapsedFilesDefaults: UserDefaults = {
    let defaults = UserDefaults(suiteName: "preview-collapsed-files") ?? .standard
    defaults.set(false, forKey: PreferenceKeys.addTorrentFilesExpanded)
    return defaults
}()

/// A realistic multi-file `.torrent` for the file-selection preview. The sheet
/// loads its file list from the URL on appear, so this has to be a real file.
private func previewMultiFileTorrentURL() -> URL {
    let entries: [(path: String, length: Int)] = [
        ("Season 01/Episode 01.mkv", 1_482_000_000),
        ("Season 01/Episode 02.mkv", 1_510_000_000),
        ("Season 01/Episode 03.mkv", 1_463_000_000),
        ("Season 01/Episode 04.mkv", 1_501_000_000),
        ("Season 01/Episode 05.mkv", 1_444_000_000),
        ("Season 01/Episode 06.mkv", 1_528_000_000),
        ("Season 01/Episode 07.mkv", 1_490_000_000),
        ("Season 01/Episode 08.mkv", 1_512_000_000),
        ("Season 01/Episode 09.mkv", 1_477_000_000),
        ("Season 01/Episode 10.mkv", 1_538_000_000),
        ("Season 01/Subs/Episode 01.srt", 52_000),
        ("Season 01/Subs/Episode 02.srt", 48_000),
        ("README.nfo", 2_400),
    ]

    var info = "d5:filesl"
    for entry in entries {
        info += "d6:lengthi\(entry.length)e4:pathl"
        info += entry.path.split(separator: "/").map { "\($0.utf8.count):\($0)" }.joined()
        info += "ee"
    }
    let name = "Example Show S01"
    info += "e4:name\(name.utf8.count):\(name)e"

    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("preview-multi-file.torrent")
    try? Data("d4:info\(info)e".utf8).write(to: url)
    return url
}
