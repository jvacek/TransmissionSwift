import AppKit
import SwiftUI
import TransmissionCore
import UniformTypeIdentifiers

/// Editable list of file mappings for one server profile. Rendered inside the
/// `ServerProfileForm`'s "File Mappings" section; each row becomes an
/// "Open with…" item in the torrent context menu.
struct OpenMappingEditor: View {
    @Binding var mappings: [OpenMapping]
    /// Live form context (host/port/username) used for the preview and Test.
    var sampleServer: ServerProfile
    /// The torrent the preview/Test act on (inspector selection, else first in
    /// the list). Nil when there are no torrents.
    var sampleTorrent: Torrent?
    /// The password currently entered in the form, used for preview/Test.
    var samplePassword: String
    /// Resolves the effective password for Test (typed field, else Keychain).
    var resolveSamplePassword: () -> String
    /// The daemon's default download directory (when connected), for the
    /// `{download-dir}` placeholder in preview/Test.
    var sampleDownloadDir: String?

    @State private var editingMapping: OpenMapping?
    @State private var showEditor = false
    /// Bumped on every Add/Edit click. The sheet content is keyed by it so each
    /// presentation gets a fresh identity (and therefore fresh `@State`) —
    /// otherwise SwiftUI reuses the previous open's field values.
    @State private var editSessionID = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(
                "A mapping describes how this server's download folders are reachable from this Mac, so a torrent's context menu can open them in an external app. Mappings are stored with the server — changes apply when you click Save Changes below."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            ForEach($mappings) { $mapping in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mapping.name)
                            .fontWeight(.medium)
                        Text(mapping.template)
                            .font(.caption)
                            .monospaced()
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let bundleID = mapping.applicationBundleID {
                            Text("Opens in \(HandlerApp.displayName(for: bundleID) ?? bundleID)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                    Button {
                        editingMapping = mapping
                        editSessionID = UUID()
                        showEditor = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)
                    .help("Edit mapping")
                    Button {
                        mappings.removeAll { $0.id == mapping.id }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Delete mapping")
                }
            }

            Button {
                editingMapping = nil
                editSessionID = UUID()
                showEditor = true
            } label: {
                Label("Add Mapping…", systemImage: "plus")
            }
            .buttonStyle(.borderless)
        }
        .sheet(isPresented: $showEditor) {
            MappingEditorSheet(
                isPresented: $showEditor,
                existing: editingMapping,
                sampleServer: sampleServer,
                sampleTorrent: sampleTorrent,
                samplePassword: samplePassword,
                sampleDownloadDir: sampleDownloadDir,
                resolveSamplePassword: resolveSamplePassword,
                onSave: { mapping in
                    if let index = mappings.firstIndex(where: { $0.id == mapping.id }) {
                        mappings[index] = mapping
                    } else {
                        mappings.append(mapping)
                    }
                }
            )
            .id(editSessionID)
        }
    }
}

// MARK: - Add / Edit sheet

private struct MappingEditorSheet: View {
    @Binding var isPresented: Bool
    let existing: OpenMapping?
    let sampleServer: ServerProfile
    let sampleTorrent: Torrent?
    let samplePassword: String
    let sampleDownloadDir: String?
    /// Resolves the password actually used for Test: the typed field, else the
    /// stored Keychain secret. Resolved on demand so the Keychain isn't read
    /// during view rendering.
    let resolveSamplePassword: () -> String
    let onSave: (OpenMapping) -> Void

    @State private var name: String
    @State private var template: String
    @State private var applicationBundleID: String?
    @State private var testMessage: String?
    @State private var testFailed = false
    @FocusState private var templateFocused: Bool

    private static let placeholderGroups: [(title: String, items: [String])] = [
        ("Torrent", ["{name}", "{folder}", "{path}"]),
        ("File", ["{filePath}"]),
        (
            "Server",
            ["{host}", "{port}", "{user}", "{password}", "{password-encoded}", "{download-dir}"]
        ),
        ("Cyberduck", ["{trailingSlash}"]),
    ]

    private static let placeholders: [String] = placeholderGroups.flatMap(\.items)

    private static let presets: [(name: String, template: String, explanation: String)] = [
        (
            "Finder / local mount",
            "file:///Volumes/transmission/{folder}",
            "The daemon's download folder is mounted on this Mac."
        ),
        (
            "Local daemon (Finder)",
            "file:///{path}",
            "The daemon runs on this Mac — open the torrent's folder in Finder."
        ),
        (
            "Swizzin Web",
            "https://{user}:{password-encoded}@{host}/transmission.downloads/{folder}/{name}",
            "Open the file in swizzin's web downloads view (basic auth)."
        ),
        (
            "Cyberduck / SFTP",
            "sftp://{user}@{host}/{download-dir}/{folder}/{name}/",
            "Open the download folder over SFTP in Cyberduck."
        ),
    ]

    init(
        isPresented: Binding<Bool>,
        existing: OpenMapping?,
        sampleServer: ServerProfile,
        sampleTorrent: Torrent?,
        samplePassword: String,
        sampleDownloadDir: String?,
        resolveSamplePassword: @escaping () -> String,
        onSave: @escaping (OpenMapping) -> Void
    ) {
        self._isPresented = isPresented
        self.existing = existing
        self.sampleServer = sampleServer
        self.sampleTorrent = sampleTorrent
        self.samplePassword = samplePassword
        self.sampleDownloadDir = sampleDownloadDir
        self.resolveSamplePassword = resolveSamplePassword
        self.onSave = onSave
        _name = State(initialValue: existing?.name ?? "")
        _template = State(initialValue: existing?.template ?? "")
        _applicationBundleID = State(initialValue: existing?.applicationBundleID)
    }

    /// The torrent the preview + Test act on. Prefers the real torrent passed
    /// in (inspector selection, else first in the list); when there are none,
    /// substitutes the placeholders with their literal names so the preview
    /// still shows the URL shape.
    private var previewTorrent: Torrent {
        if let sampleTorrent { return sampleTorrent }
        var fallback = Torrent.sample
        fallback.downloadFolder = "/folder"
        fallback.name = "name"
        return fallback
    }

    private var previewURL: URL? {
        MappingTemplate.expand(
            template,
            torrent: previewTorrent,
            server: sampleServer,
            // The preview never exposes a real password — mask a typed one,
            // and a stored-only secret isn't read during rendering.
            password: samplePassword.isEmpty ? "" : "xxxx",
            // Fall back to the literal placeholder name so the preview stays
            // legible when the daemon's default download dir is unknown.
            defaultDownloadDirectory: sampleDownloadDir ?? "download-dir")
    }

    /// The URL the Test button actually opens, using the effective password
    /// (typed field, else the stored Keychain secret).
    private var testURL: URL? {
        MappingTemplate.expand(
            template,
            torrent: previewTorrent,
            server: sampleServer,
            password: resolveSamplePassword(),
            defaultDownloadDirectory: sampleDownloadDir ?? "download-dir")
    }

    /// Apps that can handle the preview URL's scheme, plus the currently
    /// selected app (so the picker always reflects the saved value even when
    /// the scheme changed). Sorted by display name. Falls back to a
    /// scheme-only probe so an incomplete template (empty host, etc.) still
    /// lists candidates.
    private var handlerApps: [(bundleID: String, name: String)] {
        var apps: [(bundleID: String, name: String)] = []
        if let bundleID = applicationBundleID {
            apps.append((bundleID, HandlerApp.displayName(for: bundleID) ?? bundleID))
        }
        let probe = previewURL ?? templateScheme.flatMap { URL(string: "\($0)://probe") }
        if let url = probe {
            for appURL in NSWorkspace.shared.urlsForApplications(toOpen: url) {
                guard let bundle = Bundle(url: appURL), let bundleID = bundle.bundleIdentifier
                else { continue }
                if apps.contains(where: { $0.bundleID == bundleID }) { continue }
                let name =
                    (bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String)
                    ?? bundle.infoDictionary?["CFBundleName"] as? String
                    ?? appURL.deletingPathExtension().lastPathComponent
                apps.append((bundleID, name))
            }
        }
        return apps.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// The URL scheme of the current template, used to probe for candidate apps
    /// when the full preview URL can't be built.
    private var templateScheme: String? {
        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = trimmed.range(of: "://") {
            return String(trimmed[..<range.lowerBound]).lowercased()
        }
        return trimmed.hasPrefix("/") ? "file" : nil
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedTemplate: String {
        template.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && !trimmedTemplate.isEmpty && previewURL != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(existing == nil ? "Add Mapping" : "Edit Mapping")
                .font(.headline)

            TextField("Name", text: $name, prompt: Text("e.g. Finder"))
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 6) {
                TextField(
                    "Template",
                    text: $template,
                    prompt: Text("e.g. file:///Volumes/transmission/{folder}")
                )
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .focused($templateFocused)

                HStack(spacing: 12) {
                    Menu {
                        ForEach(Self.presets, id: \.name) { preset in
                            Button {
                                applyPreset(preset)
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(preset.name)
                                    Text(preset.explanation)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } label: {
                        Text("Presets")
                    }
                    .controlSize(.small)

                    Menu("Insert placeholder") {
                        ForEach(Array(Self.placeholderGroups.enumerated()), id: \.element.title) {
                            index, group in
                            if index > 0 { Divider() }
                            Text(group.title)
                            ForEach(group.items, id: \.self) { placeholder in
                                Button(placeholder) { insertPlaceholder(placeholder) }
                            }
                        }
                    }
                    .controlSize(.small)

                    Spacer()
                }
            }

            HStack(spacing: 10) {
                Picker("Open with", selection: $applicationBundleID) {
                    Text("Default app").tag(String?.none)
                    if !handlerApps.isEmpty {
                        Divider()
                        ForEach(handlerApps, id: \.bundleID) { app in
                            Text(app.name).tag(Optional(app.bundleID))
                        }
                    }
                }
                .pickerStyle(.menu)
                .help("Which app receives the URL; the system default when unset")
                Button("Choose App…") { chooseApp() }
                    .controlSize(.small)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Preview")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let url = previewURL {
                    Text(url.absoluteString)
                        .font(.caption)
                        .monospaced()
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                } else if trimmedTemplate.isEmpty {
                    Text("Enter a template to see a preview.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(
                        "This template can't form a valid URL. Check the placeholders and the scheme (e.g. \("{host}") is required for \("https://")."
                    )
                    .font(.caption)
                    .foregroundStyle(.red)
                }
            }

            Text("Placeholders: \(Self.placeholders.joined(separator: "  "))")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            HStack(spacing: 10) {
                Button("Test") { test() }
                    .disabled(testURL == nil || trimmedTemplate.isEmpty)
                    .help("Opens the preview URL in the chosen app")
                if let message = testMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(testFailed ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                }
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button(existing == nil ? "Add" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear {
            // The sheet's @State persists across presentations (SwiftUI reuses
            // the content view's identity), so init's initial values only apply
            // on the very first open. Re-sync from the mapping on every appear.
            name = existing?.name ?? ""
            template = existing?.template ?? ""
            applicationBundleID = existing?.applicationBundleID
            testMessage = nil
            testFailed = false
        }
    }

    private func applyPreset(_ preset: (name: String, template: String, explanation: String)) {
        if trimmedName.isEmpty {
            name = preset.name
        }
        template = preset.template
        // A preset changes the scheme, so the previously picked app may no
        // longer be a candidate — fall back to the system default.
        applicationBundleID = nil
        testMessage = nil
    }

    private func insertPlaceholder(_ placeholder: String) {
        testMessage = nil
        // Insert at the text caret when the template field is the first
        // responder; fall back to appending otherwise.
        if templateFocused, let editor = NSApp.keyWindow?.firstResponder as? NSTextView {
            editor.insertText(placeholder, replacementRange: editor.selectedRange())
            template = editor.string
        } else {
            template += placeholder
        }
    }

    /// Lets the user pick any installed app (e.g. Chrome) even when automatic
    /// scheme detection found no candidates. User-selected file access
    /// (ENABLE_USER_SELECTED_FILES) covers reading the app's bundle ID.
    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.title = "Choose an App"
        panel.prompt = "Choose"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.begin { response in
            guard response == .OK, let url = panel.url,
                let bundleID = Bundle(url: url)?.bundleIdentifier
            else { return }
            applicationBundleID = bundleID
            testMessage = nil
        }
    }

    private func test() {
        testMessage = nil
        guard let url = testURL else { return }
        if let bundleID = applicationBundleID, !bundleID.isEmpty {
            guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
                testMessage = "Could not find the app for “\(bundleID)”."
                testFailed = true
                return
            }
            NSWorkspace.shared.open(
                [url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration()
            ) { _, error in
                Task { @MainActor in
                    if let error {
                        testMessage = "Could not open — \(error.localizedDescription)"
                        testFailed = true
                    } else {
                        testMessage = "Opened."
                        testFailed = false
                    }
                }
            }
        } else if NSWorkspace.shared.open(url) {
            testMessage = "Opened in the default app."
            testFailed = false
        } else {
            testMessage = "Could not open — no app handles \(url.scheme ?? "this") links."
            testFailed = true
        }
    }

    private func save() {
        onSave(
            OpenMapping(
                id: existing?.id ?? UUID(),
                name: trimmedName,
                template: trimmedTemplate,
                applicationBundleID: applicationBundleID))
        isPresented = false
    }
}

/// Resolves a bundle ID to a human-readable app name for display.
private enum HandlerApp {
    static func displayName(for bundleID: String) -> String? {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
            let bundle = Bundle(url: appURL)
        else { return nil }
        return
            (bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String)
            ?? bundle.infoDictionary?["CFBundleDisplayName"] as? String
            ?? bundle.infoDictionary?["CFBundleName"] as? String
    }
}
