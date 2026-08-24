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

    private enum Field: Hashable { case magnet, destination }

    @FocusState private var focusedField: Field?
    @State private var mode: AddTorrentInputMode = .file
    @Namespace private var selectionNamespace
    @State private var fileURL: URL?
    @State private var magnetString: String = ""
    @State private var destination: String = ""
    @State private var tags: [String] = []
    @State private var priority: TorrentPriority = .normal
    @State private var startWhenAdded: Bool = true
    @State private var showFileImporter: Bool = false
    @State private var isAdding: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                modePicker
                sourceSection
                optionsSection
            }
            // Clear the floating glass header so content starts below it,
            // then scrolls underneath its blur layer.
            .padding(.top, 68)
            .padding([.horizontal, .bottom], 20)
        }
        .overlay(alignment: .top) { headerBar }
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
