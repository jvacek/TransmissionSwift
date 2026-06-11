import SwiftUI
import TransmissionCore
import UniformTypeIdentifiers

/// Sheet presented from the main window — covers file-based and magnet-link
/// add flows behind a single segmented control.
struct AddTorrentSheet: View {
    @Environment(TorrentStore.self) private var store
    @Binding var isPresented: Bool

    var initialMagnetMode: Bool = false
    var prefilledURL: URL? = nil

    enum InputMode: Hashable { case file, magnet }

    @State private var mode: InputMode = .file
    @State private var fileURL: URL?
    @State private var magnetString: String = ""
    @State private var destination: String = "~/Downloads"
    @State private var labelText: String = ""
    @State private var priority: TorrentPriority = .normal
    @State private var startWhenAdded: Bool = true
    @State private var verifyLocalData: Bool = false
    @State private var showFileImporter: Bool = false
    @State private var isAdding: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            formSection
            filesPlaceholder
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
        }
    }

    // MARK: - Sections

    private var formSection: some View {
        Form {
            Section {
                Picker("", selection: $mode) {
                    Text("File").tag(InputMode.file)
                    Text("Magnet Link").tag(InputMode.magnet)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Section {
                if mode == .file {
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
                } else {
                    TextField("magnet:?xt=urn:btih:…", text: $magnetString)
                        .font(.monospaced(.body)())
                }

                LabeledContent("Destination") {
                    Text(destination)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Label") {
                    TextField("None", text: $labelText)
                }

                LabeledContent("Priority") {
                    Picker("Priority", selection: $priority) {
                        Text("High").tag(TorrentPriority.high)
                        Text("Normal").tag(TorrentPriority.normal)
                        Text("Low").tag(TorrentPriority.low)
                    }
                    .labelsHidden()
                    .frame(maxWidth: 120)
                }

                Toggle("Start when added", isOn: $startWhenAdded)
                Toggle("Verify local data", isOn: $verifyLocalData)
            }
        }
        .formStyle(.grouped)
    }

    private var filesPlaceholder: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Files")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)

            Divider()

            ContentUnavailableView {
                Label("No Preview Available", systemImage: "doc.questionmark")
            } description: {
                Text("Select a .torrent file to preview its contents.")
            }
            .frame(height: 120)
        }
    }

    private var footerBar: some View {
        HStack(spacing: 12) {
            Text("Destination: \(destination)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
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
