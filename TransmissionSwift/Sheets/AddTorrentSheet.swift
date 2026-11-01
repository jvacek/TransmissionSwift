import SwiftUI
import TransmissionCore
import UniformTypeIdentifiers

/// File vs. magnet source. `nonisolated` + file-scope so its `Hashable`
/// conformance isn't main-actor-isolated — `glassEffectID` needs a `Sendable`
/// hashable.
nonisolated enum AddTorrentInputMode: Hashable, Sendable { case file, magnet }

/// Sheet presented from the main window — the mutually-exclusive file vs.
/// magnet source is a segmented picker; the shared options (destination, tags,
/// priority, start) sit below. Everything scrolls together.
struct AddTorrentSheet: View {
    @Environment(TorrentStore.self) private var store
    @Binding var isPresented: Bool

    var initialMagnetMode: Bool = false
    var prefilledURL: URL? = nil
    var serverName: String? = nil

    private enum Field: Hashable { case magnet, destination }

    @FocusState private var focusedField: Field?
    @State private var mode: AddTorrentInputMode = .file
    @Namespace private var selectionNamespace
    @State private var fileURL: URL?
    @State private var fileTorrentName: String?
    @State private var addFiles: [TorrentAddFile] = []
    @State private var fileFilter = ""
    @State private var magnetString: String = ""
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
                mode = initialMagnetMode ? .magnet : .file
                // Seed the per-add option from the Settings default; the
                // toggle below never writes back.
                deleteSourceFile = deleteTorrentFileByDefault
                if let url = prefilledURL {
                    if url.scheme == "magnet" {
                        mode = .magnet
                        magnetString = url.absoluteString
                    } else {
                        mode = .file
                        fileURL = url
                        loadFile(at: url)
                    }
                }
                // Explicit focus so macOS doesn't auto-focus (and select-all) the
                // Destination field. In magnet mode, focus the input so a paste lands
                // immediately; in file mode, leave focus unset.
                focusedField = mode == .magnet ? .magnet : nil
            }
            .onChange(of: mode) { _, newMode in
                focusedField = newMode == .magnet ? .magnet : nil
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

    /// File vs. magnet — the only mutually-exclusive choice — as a Liquid
    /// Glass segmented control in the system style: one glass capsule holding
    /// all segments, with the selected one as a raised accent pill that slides
    /// between segments (droplet-style, via `matchedGeometryEffect`). The pill
    /// is a plain fill, not nested glass — glass can't sample glass. The stock
    /// `.segmented` picker keeps its pre-Tahoe chrome in content areas, hence
    /// hand-rolled.
    private var modePicker: some View {
        HStack(spacing: 0) {
            ForEach([AddTorrentInputMode.file, .magnet], id: \.self) { segment in
                let isSelected = mode == segment
                Button {
                    withAnimation(.smooth(duration: 0.35)) { mode = segment }
                } label: {
                    Text(segment == .file ? "File" : "Magnet Link")
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
                .accessibilityLabel(segment == .file ? "File" : "Magnet Link")
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

    /// Shared bordered container so the file picker and the magnet input look
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
        case .magnet: magnetSection
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
                    Spacer()
                    Button("Choose…") { showFileImporter = true }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                }
            )
        }
    }

    private var magnetSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sourceLabel("Magnet Link", systemImage: "link")
            sourceBox(
                TextField("magnet:?xt=urn:btih:…", text: $magnetString)
                    .textFieldStyle(.plain)
                    .monospaced()
                    .focused($focusedField, equals: .magnet)
            )
        }
    }

    /// Add-time file selection. Hidden for magnets and single-file torrents,
    /// which have nothing to choose. The expanded state persists.
    @ViewBuilder
    private var filesSection: some View {
        if mode == .file, addFiles.count > 1 {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    withAnimation(.snappy(duration: 0.2)) { filesExpanded.toggle() }
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
                            .foregroundStyle(hasNoWantedFiles ? Color.red : Color.secondary)
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
                                Button("Select All") { setAllWanted(true) }
                                Divider().frame(height: 12)
                                Button("None") { setAllWanted(false) }
                            }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                        }

                        if filteredFileIndices.isEmpty {
                            Text("No files match the filter.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 40)
                        } else {
                            ScrollView {
                                LazyVStack(spacing: 0) {
                                    ForEach(Array(filteredFileIndices.enumerated()), id: \.element) {
                                        offset, index in
                                        AddTorrentFileRow(
                                            file: $addFiles[index],
                                            shaded: !offset.isMultiple(of: 2))
                                    }
                                }
                            }
                            .frame(height: filesListHeight)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.secondary.opacity(0.07))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.secondary.opacity(0.25))
                    )

                    if hasNoWantedFiles {
                        Text("Choose at least one file to download.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
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
            // Magnets have no local file, so the cleanup option only makes
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
    /// can't be decoded, or the magnet's `dn` display name.
    private var expectedTorrentName: String? {
        if mode == .file, let fileURL {
            return fileTorrentName ?? fileURL.deletingPathExtension().lastPathComponent
        }
        if mode == .magnet,
            let dn = URLComponents(string: magnetString)?
                .queryItems?.first(where: { $0.name == "dn" })?.value,
            !dn.isEmpty
        {
            return dn
        }
        return nil
    }

    private func loadFile(at url: URL) {
        fileTorrentName = TorrentMetainfoReader.displayName(at: url)
        addFiles = TorrentMetainfoReader.files(at: url) ?? []
        fileFilter = ""
    }

    private var filteredFileIndices: [Int] {
        let query = fileFilter.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return Array(addFiles.indices) }
        return addFiles.indices.filter {
            addFiles[$0].pathString.localizedCaseInsensitiveContains(query)
        }
    }

    private var filesListHeight: CGFloat {
        CGFloat(min(max(filteredFileIndices.count, 1), 8)) * addFileRowHeight
    }

    private var selectedFiles: [TorrentAddFile] {
        addFiles.filter(\.wanted)
    }

    private var hasNoWantedFiles: Bool {
        mode == .file && !addFiles.isEmpty && selectedFiles.isEmpty
    }

    private var selectionSummary: String {
        let size = ColumnFormatters.humanizedSize(selectedFiles.reduce(0) { $0 + $1.length })
        return "\(selectedFiles.count) of \(addFiles.count) files, \(size)"
    }

    private func setAllWanted(_ wanted: Bool) {
        for index in addFiles.indices {
            addFiles[index].wanted = wanted
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
            case .magnet: magnetString.hasPrefix("magnet:?xt=urn:btih:")
            }
        return sourceValid && !hasNoWantedFiles
            && isSubmittableServerPath(destination, relativeTo: store.list.downloadDirectory)
    }

    private func submit() async {
        isAdding = true
        defer { isAdding = false }
        saveError = nil
        let succeeded = await store.actions.add(
            fileURL: mode == .file ? fileURL : nil,
            magnetURL: mode == .magnet ? magnetString : nil,
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

/// One row in the add sheet's flat file list. Skip and the checkbox both write
/// `wanted`, so the two controls stay in sync.
private let addFileRowHeight: CGFloat = 26

private struct AddTorrentFileRow: View {
    @Binding var file: TorrentAddFile
    let shaded: Bool

    var body: some View {
        HStack(spacing: 8) {
            Toggle("Download", isOn: $file.wanted)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .accessibilityLabel("Download \(file.pathString)")

            Text(file.pathString)
                .font(.callout.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(file.wanted ? Color.primary : Color.secondary)

            Spacer(minLength: 8)

            Text(ColumnFormatters.humanizedSize(file.length))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

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
        .padding(.horizontal, 6)
        .frame(height: addFileRowHeight)
        .background(shaded ? Color.secondary.opacity(0.05) : Color.clear)
        .contentShape(Rectangle())
    }
}

#Preview("Add Torrent") {
    AddTorrentSheet(isPresented: .constant(true))
        .environment(previewTorrentStore)
        .environment(TagColorStore())
}

#Preview("Magnet") {
    AddTorrentSheet(isPresented: .constant(true), initialMagnetMode: true)
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
