import SwiftUI
import TransmissionCore
import UniformTypeIdentifiers

/// Sheet presented from the main window — the mutually-exclusive file vs.
/// magnet source lives in a `TabView`; the shared options (destination, label,
/// priority, start) sit in a separate card below.
struct AddTorrentSheet: View {
    @Environment(TorrentStore.self) private var store
    @Binding var isPresented: Bool

    var initialMagnetMode: Bool = false
    var prefilledURL: URL? = nil

    enum InputMode: Hashable { case file, magnet }
    private enum Field: Hashable { case magnet, destination, label }

    @FocusState private var focusedField: Field?
    @State private var mode: InputMode = .file
    @State private var fileURL: URL?
    @State private var magnetString: String = ""
    @State private var destination: String = ""
    @State private var labelText: String = ""
    @State private var priority: TorrentPriority = .normal
    @State private var startWhenAdded: Bool = true
    @State private var showFileImporter: Bool = false
    @State private var isAdding: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            sourceTabs
            optionsForm
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

    /// File vs. magnet — the only mutually-exclusive choice — as real tabs.
    private var sourceTabs: some View {
        TabView(selection: $mode) {
            fileTab
                .tag(InputMode.file)
                .tabItem { Text("File") }
            magnetTab
                .tag(InputMode.magnet)
                .tabItem { Text("Magnet Link") }
        }
        .frame(height: 96)
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    private var fileTab: some View {
        HStack {
            if let url = fileURL {
                Label(url.lastPathComponent, systemImage: "doc.fill")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("No file selected")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button("Choose…") { showFileImporter = true }
        }
        .padding()
    }

    private var magnetTab: some View {
        VStack {
            TextField("magnet:?xt=urn:btih:…", text: $magnetString)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .magnet)
            Spacer(minLength: 0)
        }
        .padding()
    }

    /// Shared options that apply to either source.
    private var optionsForm: some View {
        Form {
            LabeledContent("Destination") {
                TextField("", text: $destination)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .focused($focusedField, equals: .destination)
            }

            TextField("Label (optional)", text: $labelText)
                .focused($focusedField, equals: .label)

            LabeledContent("Priority") {
                Picker("Priority", selection: $priority) {
                    Text("High").tag(TorrentPriority.high)
                    Text("Normal").tag(TorrentPriority.normal)
                    Text("Low").tag(TorrentPriority.low)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            Toggle("Start when added", isOn: $startWhenAdded)
        }
        .formStyle(.grouped)
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
            label: labelText.isEmpty ? nil : labelText,
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
}

#Preview("Magnet") {
    AddTorrentSheet(isPresented: .constant(true), initialMagnetMode: true)
        .environment(TorrentStore(service: MockTorrentService()))
}
