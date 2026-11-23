// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import TransmissionCore
import UniformTypeIdentifiers

/// Sheet presented from the main window — the mutually-exclusive file and link
/// source is a segmented picker; the file selection and the shared options
/// (destination, tags, priority, start) sit below.
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
    @State private var linkString: String = ""
    @State private var destination: String = ""
    @State private var tags: [String] = []
    @State private var priority: TorrentPriority = .normal
    @State private var startWhenAdded: Bool = true
    /// Read-only mirror of the Settings default. The row below flips the
    /// `@State` copy for this add only — it must never write back.
    @AppStorage(PreferenceKeys.deleteTorrentFileAfterAdding) private var deleteTorrentFileByDefault = false
    @State private var deleteSourceFile = false
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
            Text("Add Torrent")
                .font(.headline)
            modePicker
            sourceSection
            // Links and single-file torrents have nothing to choose.
            if mode == .file, addFiles.count > 1 {
                AddTorrentFilesSection(addFiles: $addFiles)
            }
            optionsSection
            SheetButtonRow(
                "Add",
                busyTitle: "Adding…",
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

    /// Shared bordered container so the file picker and the link input look
    /// alike. The content row gets a fixed height so switching modes doesn't
    /// shift the content below by a few pixels.
    private func sourceBox(_ content: some View) -> some View {
        content
            .frame(height: 24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(InsetCardBackground())
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
            AddTorrentSectionLabel(title: "Torrent File", systemImage: "doc.fill")
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
            AddTorrentSectionLabel(title: "Magnet Link or URL", systemImage: "link")
            sourceBox(
                TextField("magnet:… or https://…", text: $linkString)
                    .textFieldStyle(.plain)
                    .monospaced()
                    .focused($focusedField, equals: .link)
            )
        }
    }

    private func inputField(for mode: AddTorrentInputMode) -> Field? {
        switch mode {
        case .file: nil
        case .link: .link
        }
    }

    /// Shared options that apply to either source, in a grouped-form-style
    /// card. A Grid lets the label column size to its longest label at any
    /// text size; the toggles below span the full row.
    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow(alignment: .top) {
                    Text("Destination")
                    ServerPathField(
                        path: $destination,
                        defaultDirectory: store.list.downloadDirectory,
                        folders: knownFolders,
                        serverName: serverName,
                        torrentName: expectedTorrentName)
                }
                Divider().gridCellColumns(2)
                GridRow {
                    Text("Tags")
                    TagsInputField(tags: $tags, suggestions: store.list.facets.labels.map(\.name))
                        .help(
                            "Type a tag and press Return to add it, or pick an existing one from the list that appears."
                        )
                }
                Divider().gridCellColumns(2)
                GridRow {
                    Text("Priority")
                    prioritySegments
                }
            }
            Divider()
            fullWidthToggle("Start when added", isOn: $startWhenAdded)
            // Links have no local file, so the cleanup option only makes
            // sense (and only shows) for file adds.
            if mode == .file {
                Divider()
                fullWidthToggle("Delete .torrent file after adding", isOn: $deleteSourceFile)
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
        .background(InsetCardBackground(cornerRadius: 10))
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
            isLoadingFile = false
        }
    }

    private static func priorityAccessibilityLabel(_ level: TorrentPriority) -> String {
        "Priority \(level.displayLabel)"
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
        do {
            try await store.actions.add(
                fileURL: mode == .file ? fileURL : nil,
                linkURL: mode == .file ? nil : linkString.trimmingCharacters(in: .whitespacesAndNewlines),
                destination: resolveServerPath(destination, relativeTo: store.list.downloadDirectory),
                labels: tags,
                priority: priority,
                startWhenAdded: startWhenAdded,
                files: mode == .file ? addFiles : [],
                deleteFileAfterAdding: mode == .file && deleteSourceFile
            )
            isPresented = false
        } catch {
            saveError = error.localizedDescription
        }
    }
}

extension UTType {
    fileprivate static let torrentFile = UTType(filenameExtension: "torrent") ?? .data
}

extension AddTorrentInputMode {
    fileprivate var label: String {
        switch self {
        case .file: "File"
        case .link: "Magnet / URL"
        }
    }
}

#if DEBUG
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
#endif
