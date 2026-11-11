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
    @Namespace private var selectionNamespace
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
            .overlay(alignment: .top) { headerBar }
            .frame(width: 560)
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

    /// The sheet's form. Kept out of a scroll view — it always fits — with top
    /// padding clearing the floating glass header.
    private var sheetContent: some View {
        VStack(alignment: .leading) {
            modePicker
            sourceSection
            filesSection
            optionsSection
        }
        .padding(.top, 45)
        .padding([.horizontal, .bottom], 20)
    }

    // MARK: - Sections

    /// File vs. link — the only mutually-exclusive choice — as a Liquid Glass
    /// segmented control in the system style: one glass capsule holding all
    /// segments, with the selected one as a raised accent pill that slides
    /// between segments (droplet-style, via `matchedGeometryEffect`). The pill
    /// is a plain fill, not nested glass — glass can't sample glass. The stock
    /// `.segmented` picker keeps its pre-Tahoe chrome in content areas, hence
    /// hand-rolled.
    private var modePicker: some View {
        HStack(spacing: 0) {
            ForEach(AddTorrentInputMode.allCases, id: \.self) { segment in
                let isSelected = mode == segment
                Button {
                    withAnimation(.smooth(duration: 0.35)) { mode = segment }
                } label: {
                    Text(segment.label)
                        .font(.callout.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color.white : Color.secondary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(Color.accentColor)
                                    .matchedGeometryEffect(id: "modeSelection", in: selectionNamespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(segment.label)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])

            }
        }
        .glassEffect(.regular.interactive(), in: .capsule)
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
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.secondary.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.secondary.opacity(0.25))
            )
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
            sourceLabel("Torrent File", systemImage: "doc.fill")
            sourceBox(
                HStack(spacing: 10) {
                    if let url = fileURL {
                        Label(url.lastPathComponent, systemImage: "doc.fill")
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Label("No file selected", systemImage: "doc")
                            .foregroundStyle(.secondary)
                    }
                    if isLoadingFile {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Reading torrent file")
                    }
                    Spacer()
                    Button("Choose…") { showFileImporter = true }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                }
            )
        }
    }

    private var linkSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sourceLabel("Magnet Link or URL", systemImage: "link")
            sourceBox(
                TextField("magnet:… or https://…", text: $linkString)
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
                        sourceLabel("Files", systemImage: "doc.on.doc")
                        Spacer()
                        Text(selectionSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(filesExpanded ? "Hide files" : "Show files")
                .accessibilityValue(filesExpanded ? "Expanded" : "Collapsed")
                .help(filesExpanded ? "Hide the file list" : "Show the file list")

                if filesExpanded {
                    VStack(spacing: 6) {
                        HStack(spacing: 8) {
                            fileFilterField
                            HStack(spacing: 6) {
                                Button("Download All") { setAllWanted(true) }
                                Divider().frame(height: 12)
                                Button("None") { setAllWanted(false) }
                            }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                        }

                        if !selectedTargetFileIndices.isEmpty {
                            fileBulkActions
                        }

                        if filteredFileIndices.isEmpty {
                            Text("No files match the filter.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 40)
                        } else {
                            fileList
                        }
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.secondary.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.secondary.opacity(0.15))
                    )
                    .onChange(of: fileFilter) { _, _ in
                        rebuildTree()
                        selectedNodeIDs.removeAll()
                    }

                    if !addFiles.isEmpty, wantedFiles.isEmpty {
                        Text("No files selected. The torrent will be added with every file skipped.")
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
            Text("\(selectedTargetFileIndices.count) files selected")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 6) {
                Button("Download") { setWanted(true, for: selectedTargetFileIndices) }
                Divider().frame(height: 12)
                Button("Skip") { setWanted(false, for: selectedTargetFileIndices) }
                Menu("Priority") {
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
            .accessibilityLabel("Clear selection")
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
        Button("Download") { setWanted(true, for: ids) }
        Button("Skip") { setWanted(false, for: ids) }
        Divider()
        Menu("Priority") {
            priorityMenuItems(ids: ids)
        }
    }

    private var fileFilterField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Filter files", text: $fileFilter)
                .textFieldStyle(.plain)
                .font(.callout)
            if !fileFilter.isEmpty {
                Button {
                    fileFilter = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear file filter")
            }
        }
        .padding(.horizontal, 7)
        .frame(height: 24)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.secondary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.secondary.opacity(0.18))
        )
    }

    private func inputField(for mode: AddTorrentInputMode) -> Field? {
        switch mode {
        case .file: nil
        case .link: .link
        }
    }

    /// Shared options that apply to either source, in a grouped-form-style
    /// card: fixed-width label column, vertical separator, control leading.
    private var optionsSection: some View {
        VStack(spacing: 0) {
            formRow("Destination", alignLabelToTop: true) {
                ServerPathField(
                    path: $destination,
                    defaultDirectory: store.list.downloadDirectory,
                    folders: knownFolders,
                    serverName: serverName,
                    torrentName: expectedTorrentName)
            }
            Divider()
            formRow("Tags") {
                TagsInputField(tags: $tags, suggestions: store.list.facets.labels.map(\.name))
                    .help(
                        "Type a tag and press Return to add it — or pick an existing one from the list that appears."
                    )
            }
            Divider()
            formRow("Priority") {
                prioritySegments
            }
            Divider()
            formRow("") {
                Toggle("Start when added", isOn: $startWhenAdded)
            }
            // Links have no local file, so the cleanup option only makes
            // sense — and only shows — for file adds.
            if mode == .file {
                Divider()
                formRow("") {
                    Toggle("Delete .torrent file after adding", isOn: $deleteSourceFile)
                }
            }
            if let saveError {
                Divider()
                Text(saveError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.secondary.opacity(0.15))
        )
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
        return "\(wantedFiles.count) of \(addFiles.count) files, \(size)"
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

    private let formLabelWidth: CGFloat = 90

    private func formRow(
        _ label: String, alignLabelToTop: Bool = false, @ViewBuilder content: () -> some View
    ) -> some View {
        HStack(alignment: alignLabelToTop ? .top : .center, spacing: 12) {
            Text(label)
                .foregroundStyle(.primary)
                .frame(width: formLabelWidth, alignment: .leading)
                .padding(.top, alignLabelToTop ? 4 : 0)
            content()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// Priority as a Liquid Glass segmented control matching `modePicker`:
    /// one interactive glass capsule, with an accent pill that slides between
    /// segments (`matchedGeometryEffect`). Keeps the priority glyphs visible —
    /// macOS segmented pickers drop `Label` icons.
    private var prioritySegments: some View {
        HStack(spacing: 0) {
            ForEach([TorrentPriority.high, .normal, .low], id: \.self) { level in
                let isSelected = priority == level
                Button {
                    withAnimation(.smooth(duration: 0.35)) { priority = level }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: level.systemImage)
                        Text(level.displayLabel)
                    }
                    .font(.callout)
                    .foregroundStyle(isSelected ? Color.white : level.displayColor)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(Color.accentColor)
                                .matchedGeometryEffect(id: "prioritySelection", in: selectionNamespace)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Priority \(level.displayLabel)")
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    /// Header in the style of a modern modal: glass close button left, big
    /// title centered, prominent glass add button right. Both buttons sit
    /// close to the sheet's corners so their curvature nests concentrically
    /// with the window's rounded corners.
    private var headerBar: some View {
        GlassEffectContainer {
            Text("Add Torrent")
                .font(.title2.weight(.semibold))
                .frame(maxWidth: .infinity)
                .overlay(alignment: .leading) {
                    Button {
                        isPresented = false
                    } label: {
                        // Explicit glassEffect on fixed bounds — the `.glass`
                        // button style's circle doesn't reliably track the
                        // frame, which made it render smaller than the Add
                        // capsule.
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 32, height: 32)
                            .glassEffect(.regular, in: .circle)
                            // Make the whole glass circle the hit target —
                            // `.plain` buttons otherwise only hit-test the
                            // glyph itself.
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .frame(height: 44)
                    .controlSize(.large)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel("Cancel")

                }
                .overlay(alignment: .trailing) {
                    Button(isAdding ? "Adding…" : "Add") {
                        Task { await submit() }
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    //                    .frame(height: 50)
                    .disabled(!isValid || isAdding)
                    .keyboardShortcut(.defaultAction)
                }
        }
        .padding(.horizontal, 10)
        .padding(.top, 14)
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
            saveError = store.lastActionError?.localizedDescription ?? "Failed to add torrent."
        }
    }
}

extension UTType {
    fileprivate static let torrentFile = UTType(filenameExtension: "torrent") ?? .data
}

/// One row of the add sheet's file tree. Folders carry every descendant file
/// index, so folder actions apply to the whole subtree.
nonisolated struct AddTorrentFileNode: Identifiable, Equatable {
    enum Kind: Equatable {
        case folder
        case file(Int)
    }

    let id: String
    let name: String
    let kind: Kind
    let children: [AddTorrentFileNode]?
    let fileIndices: [Int]

    var isFolder: Bool {
        if case .folder = kind { return true }
        return false
    }

    var nodeCount: Int {
        1 + (children?.reduce(0) { $0 + $1.nodeCount } ?? 0)
    }

    /// This node and every descendant, for pruning selection on collapse.
    var nodeIDs: [String] {
        [id] + (children?.flatMap(\.nodeIDs) ?? [])
    }

    /// Every folder ID in this subtree, used to start fully expanded.
    var folderIDs: [String] {
        (isFolder ? [id] : []) + (children?.flatMap(\.folderIDs) ?? [])
    }

    static func tree(from files: [TorrentAddFile]) -> [AddTorrentFileNode] {
        build(
            entries: files.map { (index: $0.index, components: $0.path) },
            parentPath: [])
    }

    private static func build(
        entries: [(index: Int, components: [String])],
        parentPath: [String]
    ) -> [AddTorrentFileNode] {
        let groups = Dictionary(grouping: entries) { $0.components.first ?? "" }
        var nodes: [AddTorrentFileNode] = []
        for (name, group) in groups {
            let folderEntries = group.filter { $0.components.count > 1 }
            if !folderEntries.isEmpty {
                let path = parentPath + [name]
                let children = build(
                    entries: folderEntries.map {
                        ($0.index, Array($0.components.dropFirst()))
                    },
                    parentPath: path)
                nodes.append(
                    AddTorrentFileNode(
                        id: "folder:" + path.map(Self.idFragment).joined(separator: "/"),
                        name: name,
                        kind: .folder,
                        children: children.isEmpty ? nil : children,
                        fileIndices: children.flatMap(\.fileIndices).sorted()))
            }
            for entry in group where entry.components.count == 1 {
                nodes.append(
                    AddTorrentFileNode(
                        id: "file:\(entry.index)",
                        name: name,
                        kind: .file(entry.index),
                        children: nil,
                        fileIndices: [entry.index]))
            }
        }
        return nodes.sorted { lhs, rhs in
            if lhs.isFolder != rhs.isFolder { return lhs.isFolder }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    /// A path component can legally contain anything bencode allows, so keep
    /// the readable separators in normal paths but never let a component's `/`
    /// turn a nested folder and a flat one into the same identity.
    private static func idFragment(_ component: String) -> String {
        component.replacingOccurrences(of: "%", with: "%25")
            .replacingOccurrences(of: "/", with: "%2F")
    }
}

/// One rendered row of the flattened tree.
private struct VisibleFileRow: Identifiable {
    let node: AddTorrentFileNode
    let depth: Int

    var id: String { node.id }
}

/// Row height the native List lays out, and the content height inside it. The
/// outer value is used to size the fixed-height list; the inner one plus the
/// row insets makes each row the same height as the old custom list.
private let addFileRowHeight: CGFloat = 26
private let addFileContentHeight: CGFloat = 22

private struct AddTorrentFileRow: View {
    @Binding var file: TorrentAddFile
    let name: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 4) {
            Color.clear
                .frame(width: 12, height: 18)

            NativeCheckbox(
                state: file.wanted ? true : false,
                allowsMixedState: false,
                label: "Download \(file.pathString)",
                action: { file.wanted.toggle() }
            )
            .frame(width: 18, height: 18)

            Image(systemName: "doc")
                .font(.callout)
                .foregroundStyle(isSelected ? Color.white : Color.secondary)
                .frame(width: 16)

            Text(name)
                .font(.callout.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(fileTextColor)

            Spacer(minLength: 8)

            Text(ColumnFormatters.humanizedSize(file.length))
                .font(.caption.monospacedDigit())
                .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.secondary)

            FilePriorityPicker(
                choice: Binding(
                    get: { FilePriorityChoice(wanted: file.wanted, priority: file.priority) },
                    set: { choice in
                        if let priority = choice.priority {
                            file.wanted = true
                            file.priority = priority
                        } else {
                            file.wanted = false
                        }
                    }),
                label: "Priority for \(file.pathString)"
            )
        }
        .padding(.horizontal, 0)
        .frame(height: addFileContentHeight)
        .contentShape(Rectangle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var fileTextColor: Color {
        if isSelected { return .white }
        return file.wanted ? .primary : .secondary
    }
}

private struct AddTorrentFolderRow: View {
    let name: String
    let size: Int64
    let allWanted: Bool
    let anyWanted: Bool
    let choice: FilePriorityChoice?
    let isExpanded: Bool
    let isSelected: Bool
    let onToggleExpansion: () -> Void
    let onToggle: () -> Void
    let onPriority: (FilePriorityChoice) -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onToggleExpansion) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.white : Color.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 12, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                isExpanded ? "Collapse folder \(name)" : "Expand folder \(name)")

            NativeCheckbox(
                state: allWanted ? true : (anyWanted ? nil : false),
                allowsMixedState: true,
                label: "Download folder \(name)",
                action: onToggle
            )
            .frame(width: 18, height: 18)

            Image(systemName: "folder.fill")
                .font(.callout)
                .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                .frame(width: 16)

            Text(name)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(isSelected ? Color.white : Color.primary)

            Spacer(minLength: 8)

            Text(ColumnFormatters.humanizedSize(size))
                .font(.caption.monospacedDigit())
                .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.secondary)

            FilePriorityPicker(
                choice: Binding(
                    get: { choice ?? .normal },
                    set: { newChoice in
                        MainActor.assumeIsolated { onPriority(newChoice) }
                    }),
                isMixed: choice == nil,
                label: "Priority for folder \(name)")
        }
        .padding(.horizontal, 0)
        .frame(height: addFileContentHeight)
        .contentShape(Rectangle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// AppKit's own checkbox, used for both files and folders so they render
/// identically. Folders opt into AppKit's mixed state; files are plain on/off.
private struct NativeCheckbox: NSViewRepresentable {
    let state: Bool?
    let allowsMixedState: Bool
    let label: String
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(
            checkboxWithTitle: "",
            target: context.coordinator,
            action: #selector(Coordinator.clicked))
        button.setButtonType(.switch)
        button.allowsMixedState = allowsMixedState
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.allowsMixedState = allowsMixedState
        button.state =
            allowsMixedState && state == nil ? .mixed : (state == true ? .on : .off)
        button.setAccessibilityLabel(label)
        button.setAccessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        guard allowsMixedState else { return state == true ? "On" : "Off" }
        if state == true { return "All files" }
        if state == nil { return "Some files" }
        return "No files"
    }

    @MainActor
    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func clicked() {
            action()
        }
    }
}

#Preview("File rows") {
    VStack(spacing: 0) {
        AddTorrentFolderRow(
            name: "Season 01", size: 4_455_000_000,
            allWanted: true, anyWanted: true, choice: .normal,
            isExpanded: true, isSelected: false,
            onToggleExpansion: {}, onToggle: {}, onPriority: { _ in })
        AddTorrentFolderRow(
            name: "Subs", size: 100_000,
            allWanted: false, anyWanted: true, choice: nil,
            isExpanded: true, isSelected: true,
            onToggleExpansion: {}, onToggle: {}, onPriority: { _ in }
        )
        .background(Color(nsColor: .selectedContentBackgroundColor))
        AddTorrentFileRow(
            file: .constant(
                TorrentAddFile(
                    index: 0, path: ["Season 01", "Episode 01.mkv"], length: 1_482_000_000)),
            name: "Episode 01.mkv", isSelected: false)
        AddTorrentFileRow(
            file: .constant(
                TorrentAddFile(
                    index: 1, path: ["Season 01", "Episode 02.mkv"], length: 1_510_000_000,
                    wanted: false)),
            name: "Episode 02.mkv", isSelected: false)
        AddTorrentFileRow(
            file: .constant(
                TorrentAddFile(
                    index: 2, path: ["Season 01", "Episode 03.mkv"], length: 1_463_000_000,
                    priority: .high)),
            name: "Episode 03.mkv", isSelected: true
        )
        .background(Color(nsColor: .selectedContentBackgroundColor))
        AddTorrentFileRow(
            file: .constant(
                TorrentAddFile(
                    index: 3, path: ["Season 01", "Episode 04.mkv"], length: 1_501_000_000,
                    wanted: false)),
            name: "Episode 04.mkv", isSelected: true
        )
        .background(Color(nsColor: .selectedContentBackgroundColor))
    }
    .frame(width: 520)
    .padding()
    .background(Color(nsColor: .windowBackgroundColor))
}

extension AddTorrentInputMode {
    fileprivate var label: String {
        switch self {
        case .file: "File"
        case .link: "Magnet / URL"
        }
    }
}

#Preview("Add Torrent") {
    AddTorrentSheet(isPresented: .constant(true))
        .environment(previewTorrentStore)
        .environment(TagColorStore())
}

#Preview("Magnet / URL") {
    AddTorrentSheet(isPresented: .constant(true), initialMode: .link)
        .environment(previewTorrentStore)
        .environment(TagColorStore())
}

#Preview("File selection") {
    AddTorrentSheet(isPresented: .constant(true), prefilledURL: previewMultiFileTorrentURL())
        .environment(previewTorrentStore)
        .environment(TagColorStore())
}

#Preview("File selection collapsed") {
    AddTorrentSheet(isPresented: .constant(true), prefilledURL: previewMultiFileTorrentURL())
        .defaultAppStorage(previewCollapsedFilesDefaults)
        .environment(previewTorrentStore)
        .environment(TagColorStore())
}

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
