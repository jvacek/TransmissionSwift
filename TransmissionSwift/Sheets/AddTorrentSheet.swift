import SwiftUI
import TransmissionCore
import UniformTypeIdentifiers

/// Sheet presented from the main window — the mutually-exclusive file vs.
/// magnet source is a segmented picker; the shared options (destination, tags,
/// priority, start) sit below. Everything scrolls together.
struct AddTorrentSheet: View {
    @Environment(TorrentStore.self) private var store
    @Binding var isPresented: Bool

    var initialMagnetMode: Bool = false
    var prefilledURL: URL? = nil

    enum InputMode: Hashable { case file, magnet }
    private enum Field: Hashable { case magnet, destination }

    @FocusState private var focusedField: Field?
    @State private var mode: InputMode = .file
    @State private var fileURL: URL?
    @State private var magnetString: String = ""
    @State private var destination: String = ""
    @State private var tags: [String] = []
    @State private var priority: TorrentPriority = .normal
    @State private var startWhenAdded: Bool = true
    @State private var showFileImporter: Bool = false
    @State private var isAdding: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    modePicker
                    sourceSection
                    optionsSection
                }
                .padding(20)
            }
            footerBar
        }
        .frame(width: 560)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.torrentFile]
        ) { result in
            if case .success(let url) = result {
                fileURL = url
            }
        }
        .onAppear {
            if destination.isEmpty {
                destination = store.downloadDirectory ?? ""
            }
            mode = initialMagnetMode ? .magnet : .file
            if let url = prefilledURL {
                if url.scheme == "magnet" {
                    mode = .magnet
                    magnetString = url.absoluteString
                } else {
                    mode = .file
                    fileURL = url
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

    // MARK: - Sections

    /// File vs. magnet — the only mutually-exclusive choice — as a segmented
    /// picker (a `TabView` clips inside sheets and drags its own chrome in).
    private var modePicker: some View {
        Picker("Source", selection: $mode) {
            Text("File").tag(InputMode.file)
            Text("Magnet Link").tag(InputMode.magnet)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 320)
        .frame(maxWidth: .infinity)
    }

    private func sourceLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
    }

    /// Shared bordered container so the file picker and the magnet input look
    /// alike.
    private func sourceBox(_ content: some View) -> some View {
        content
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

    /// Shared options that apply to either source, in a grouped-form-style
    /// card: fixed-width label column, vertical separator, control leading.
    private var optionsSection: some View {
        VStack(spacing: 0) {
            formRow("Destination") {
                TextField("", text: $destination)
                    .monospaced()
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textFieldStyle(.plain)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.secondary.opacity(0.07))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.secondary.opacity(0.25))
                    )
                    .focused($focusedField, equals: .destination)
            }
            Divider()
            formRow("Tags") {
                TagsInputField(tags: $tags, suggestions: store.facets.labels.map(\.name))
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

    private func formRow(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .foregroundStyle(.primary)
                .frame(width: 90, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// macOS segmented pickers drop `Label` icons, so this is hand-rolled to
    /// keep the priority glyphs visible. Mirrors the glyphs used elsewhere
    /// (`TorrentPriority.systemImage`).
    private var prioritySegments: some View {
        HStack(spacing: 2) {
            ForEach([TorrentPriority.high, .normal, .low], id: \.self) { level in
                let isSelected = priority == level
                Button {
                    priority = level
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: level.systemImage)
                        Text(level.displayLabel)
                    }
                    .font(.callout)
                    .foregroundStyle(
                        isSelected ? Color.white : level.displayColor
                    )
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(
                                isSelected
                                    ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.secondary.opacity(0.07))
                            )
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Priority \(level.displayLabel)")
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
    }

    private var footerBar: some View {
        HStack(spacing: 12) {
            Spacer()
            Button("Cancel") {
                isPresented = false
            }
            .keyboardShortcut(.cancelAction)

            Button(isAdding ? "Adding…" : "Add Torrent") {
                Task { await submit() }
            }
            .buttonStyle(.glassProminent)
            .disabled(!isValid || isAdding)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.regularMaterial)
    }

    // MARK: - Logic

    private var isValid: Bool {
        switch mode {
        case .file: return fileURL != nil
        case .magnet: return magnetString.hasPrefix("magnet:?xt=urn:btih:")
        }
    }

    private func submit() async {
        isAdding = true
        defer { isAdding = false }
        await store.add(
            fileURL: mode == .file ? fileURL : nil,
            magnetURL: mode == .magnet ? magnetString : nil,
            destination: destination,
            labels: tags,
            priority: priority,
            startWhenAdded: startWhenAdded
        )
        isPresented = false
    }
}

extension UTType {
    fileprivate static let torrentFile = UTType(filenameExtension: "torrent") ?? .data
}

#Preview("Add Torrent") {
    AddTorrentSheet(isPresented: .constant(true))
        .environment(TorrentStore(service: MockTorrentService()))
        .environment(TagColorStore())
}

#Preview("Magnet") {
    AddTorrentSheet(isPresented: .constant(true), initialMagnetMode: true)
        .environment(TorrentStore(service: MockTorrentService()))
        .environment(TagColorStore())
}
