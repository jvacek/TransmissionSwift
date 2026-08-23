import AppKit
import Observation
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

    /// Created fresh on every Add/Edit click. Presenting a non-nil model shows
    /// the sheet; the sheet content receives the model directly (via
    /// `sheet(item:)`), so the fields are always seeded from the mapping being
    /// edited.
    @State private var editingModel: MappingEditorModel?

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
                        editingModel = MappingEditorModel(existing: mapping)
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
                editingModel = MappingEditorModel(existing: nil)
            } label: {
                Label("Add Mapping…", systemImage: "plus")
            }
            .buttonStyle(.borderless)
        }
        .sheet(item: $editingModel) { model in
            MappingEditorSheet(
                model: model,
                onCancel: { editingModel = nil },
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
                    editingModel = nil
                }
            )
        }
    }
}

// MARK: - Add / Edit sheet

/// Field state for one Add/Edit session of the mapping editor. A new instance
/// is created on every open and seeded from the mapping being edited, so the
/// sheet's fields never carry stale values from a previous presentation.
@Observable
final class MappingEditorModel: Identifiable {
    let id = UUID()
    /// The mapping being edited, if any; nil when adding a new one.
    let existing: OpenMapping?
    var name: String
    var template: String
    var applicationBundleID: String?
    var testMessage: String?
    var testFailed = false

    init(existing: OpenMapping?) {
        self.existing = existing
        name = existing?.name ?? ""
        template = existing?.template ?? ""
        applicationBundleID = existing?.applicationBundleID
    }

    func resetTestState() {
        testMessage = nil
        testFailed = false
    }
}

private struct MappingEditorSheet: View {
    /// The live field state for this session.
    @Bindable var model: MappingEditorModel
    /// Dismisses the sheet (nils out the presenting item).
    let onCancel: () -> Void
    let sampleServer: ServerProfile
    let sampleTorrent: Torrent?
    let samplePassword: String
    let sampleDownloadDir: String?
    /// Resolves the password actually used for Test: the typed field, else the
    /// stored Keychain secret. Resolved on demand so the Keychain isn't read
    /// during view rendering.
    let resolveSamplePassword: () -> String
    let onSave: (OpenMapping) -> Void

    @FocusState private var templateFocused: Bool
    /// Whether the placeholder reference popover is visible.
    @State private var showPlaceholderHelp = false

    /// Single source of truth for the template placeholders: drives both the
    /// "Insert placeholder" menu and the reference popover, so the two can't
    /// drift apart.
    private static let placeholderGroups: [PlaceholderGroup] = [
        PlaceholderGroup(
            title: "File",
            items: [
                PlaceholderItem(
                    token: "{file}",
                    summary:
                        "The file or folder being opened, relative to the folder the torrent is saved under."
                )
            ]
        ),
        PlaceholderGroup(
            title: "Torrent",
            items: [
                PlaceholderItem(
                    token: "{folder}",
                    summary:
                        "The folder the torrent is saved under, relative to the daemon's default download folder."
                ),
                PlaceholderItem(token: "{path}", summary: "The torrent's full download folder."),
            ]
        ),
        PlaceholderGroup(
            title: "Server",
            items: [
                PlaceholderItem(token: "{host}", summary: "Server host."),
                PlaceholderItem(token: "{port}", summary: "Server port."),
                PlaceholderItem(token: "{user}", summary: "Server username (empty when unset)."),
                PlaceholderItem(
                    token: "{password}",
                    summary:
                        "Raw password; avoid when it can contain / or %. Prefer {password-encoded}."),
                PlaceholderItem(
                    token: "{password-encoded}",
                    summary: "Percent-encoded password, safe to embed for basic auth."),
                PlaceholderItem(
                    token: "{download-dir}", summary: "The daemon's default download folder."),
            ]
        ),
    ]

    private static let presets: [(name: String, template: String, explanation: String)] = [
        (
            "Finder / local mount",
            "file:///Volumes/transmission/{folder}/{file}",
            "The daemon's download folder is mounted on this Mac."
        ),
        (
            "Local daemon (Finder)",
            "file:///{download-dir}/{folder}/{file}",
            "The daemon runs on this Mac — open the torrent's file or folder in Finder."
        ),
        (
            "Swizzin Web",
            "https://{user}:{password-encoded}@{host}/transmission.downloads/{folder}/{file}",
            "Open the file in swizzin's web downloads view (basic auth)."
        ),
        (
            "Cyberduck / SFTP",
            "sftp://{user}@{host}/{download-dir}/{folder}/{file}",
            "Open the file or download folder over SFTP in Cyberduck."
        ),
    ]

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
            model.template,
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
            model.template,
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
        if let bundleID = model.applicationBundleID {
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
        let trimmed = model.template.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = trimmed.range(of: "://") {
            return String(trimmed[..<range.lowerBound]).lowercased()
        }
        return trimmed.hasPrefix("/") ? "file" : nil
    }

    private var trimmedName: String {
        model.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedTemplate: String {
        model.template.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && !trimmedTemplate.isEmpty && previewURL != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.existing == nil ? "Add Mapping" : "Edit Mapping")
                .font(.headline)

            TextField("Name", text: $model.name, prompt: Text("e.g. Finder"))
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 6) {
                TextField(
                    "Template",
                    text: $model.template,
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
                        ForEach(Array(Self.placeholderGroups.enumerated()), id: \.element.id) {
                            index, group in
                            if index > 0 { Divider() }
                            Text(group.title)
                            ForEach(group.items) { item in
                                Button(item.token) { insertPlaceholder(item.token) }
                                    .help(item.summary)
                            }
                        }
                    }
                    .controlSize(.small)

                    Button {
                        showPlaceholderHelp.toggle()
                    } label: {
                        Image(systemName: "questionmark.circle")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help("Placeholder reference")
                    .popover(isPresented: $showPlaceholderHelp, arrowEdge: .top) {
                        PlaceholderReferenceView(groups: Self.placeholderGroups)
                    }

                    Spacer()
                }
            }

            HStack(spacing: 10) {
                Picker("Open with", selection: $model.applicationBundleID) {
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

            HStack(spacing: 10) {
                Button("Test") { test() }
                    .disabled(testURL == nil || trimmedTemplate.isEmpty)
                    .help("Opens the preview URL in the chosen app")
                if let message = model.testMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(
                            model.testFailed ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                }
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button(model.existing == nil ? "Add" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func applyPreset(_ preset: (name: String, template: String, explanation: String)) {
        if trimmedName.isEmpty {
            model.name = preset.name
        }
        model.template = preset.template
        // A preset changes the scheme, so the previously picked app may no
        // longer be a candidate — fall back to the system default.
        model.applicationBundleID = nil
        model.resetTestState()
    }

    private func insertPlaceholder(_ placeholder: String) {
        model.resetTestState()
        // Insert at the text caret when the template field is the first
        // responder; fall back to appending otherwise.
        if templateFocused, let editor = NSApp.keyWindow?.firstResponder as? NSTextView {
            editor.insertText(placeholder, replacementRange: editor.selectedRange())
            model.template = editor.string
        } else {
            model.template += placeholder
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
            model.applicationBundleID = bundleID
            model.resetTestState()
        }
    }

    private func test() {
        model.resetTestState()
        guard let url = testURL else { return }
        if let bundleID = model.applicationBundleID, !bundleID.isEmpty {
            guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
                model.testMessage = "Could not find the app for “\(bundleID)”."
                model.testFailed = true
                return
            }
            NSWorkspace.shared.open(
                [url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration()
            ) { _, error in
                Task { @MainActor in
                    if let error {
                        model.testMessage = "Could not open — \(error.localizedDescription)"
                        model.testFailed = true
                    } else {
                        model.testMessage = "Opened."
                        model.testFailed = false
                    }
                }
            }
        } else if NSWorkspace.shared.open(url) {
            model.testMessage = "Opened in the default app."
            model.testFailed = false
        } else {
            model.testMessage = "Could not open — no app handles \(url.scheme ?? "this") links."
            model.testFailed = true
        }
    }

    private func save() {
        onSave(
            OpenMapping(
                id: model.existing?.id ?? UUID(),
                name: trimmedName,
                template: trimmedTemplate,
                applicationBundleID: model.applicationBundleID))
        onCancel()
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

/// One selectable template placeholder with its one-line documentation.
private struct PlaceholderItem: Identifiable, Hashable {
    let token: String
    let summary: String
    var id: String { token }
}

/// A group of placeholders shown together in the insert menu and reference.
private struct PlaceholderGroup: Identifiable {
    let title: String
    let items: [PlaceholderItem]
    var id: String { title }
}

/// Compact, scrollable reference for the template placeholders, shown from a
/// popover so it doesn't consume the sheet's limited vertical space.
private struct PlaceholderReferenceView: View {
    let groups: [PlaceholderGroup]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(group.title)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        ForEach(group.items) { item in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(item.token)
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(minWidth: 88, alignment: .leading)
                                Text(item.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 5) {
                    Text("How {file} resolves")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Torrent list · single file → the file itself, e.g. myfile.txt")
                    Text("Torrent list · multi-file → the torrent's folder, e.g. Series1/")
                    Text("Files tab · one file selected → that file, e.g. Series1/Episode1")
                }
                .font(.caption)
            }
            .padding(12)
        }
        .frame(width: 340, height: 380)
        .textSelection(.enabled)
    }
}
