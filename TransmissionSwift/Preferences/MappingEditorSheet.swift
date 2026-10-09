import AppKit
import Observation
import SwiftUI
import TransmissionCore
import UniformTypeIdentifiers

struct MappingEditorSheet: View {
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

    /// The servers the "Selected Servers" checklist offers.
    @Environment(ServerProfileStore.self) private var profileStore

    @FocusState private var templateFocused: Bool
    /// Whether the placeholder reference popover is visible.
    @State private var showPlaceholderHelp = false
    /// Whether the save-time "allow file access?" alert is visible.
    @State private var showAccessAlert = false

    /// The torrent the preview + Test act on. Prefers the real torrent passed
    /// in (inspector selection, else first in the list); when there are none,
    /// substitutes the placeholders with their literal names so the preview
    /// still shows the URL shape.
    private var previewTorrent: Torrent {
        if let sampleTorrent { return sampleTorrent }
        // A placeholder so the preview URL renders when no torrent is selected.
        // Built inline rather than reusing a test fixture: the mocks are
        // Debug-only and product code must not reference them.
        return Torrent(
            id: -1,
            name: "name",
            hash: "",
            size: 0,
            status: .downloading,
            progress: 0,
            primaryTracker: "",
            downloadFolder: "/folder",
            addedAt: Date(),
            pieces: 0,
            pieceSize: 0,
            havePieces: 0)
    }

    private var previewURL: URL? {
        MappingTemplate.expand(
            maskedTemplate,
            torrent: previewTorrent,
            server: sampleServer,
            // Password placeholders are masked with readable tokens below, so a
            // real password never reaches the preview (and a stored-only secret
            // isn't read during rendering).
            password: "",
            // Fall back to the literal placeholder name so the preview stays
            // legible when the daemon's default download dir is unknown.
            defaultDownloadDirectory: sampleDownloadDir ?? "download-dir")
    }

    /// `{password}` / `{password-encoded}` are swapped for `<password>` /
    /// `<encoded-password>` so the preview shows exactly where each lands —
    /// more informative than a shared `xxxx` mask, and still no real secret.
    private var maskedTemplate: String {
        model.template
            .replacingOccurrences(of: "{password-encoded}", with: "<encoded-password>")
            .replacingOccurrences(of: "{password}", with: "<password>")
    }

    /// `previewURL` percent-encodes the angle brackets in the password tokens
    /// (`%3C`/`%3E`); undo that just for those tokens so the preview reads as
    /// `<password>` / `<encoded-password>`.
    private var previewDisplayString: String? {
        guard let url = previewURL else { return nil }
        return
            url.absoluteString
            .replacingOccurrences(of: "%3Cencoded-password%3E", with: "<encoded-password>")
            .replacingOccurrences(of: "%3Cpassword%3E", with: "<password>")
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
            apps.append((bundleID, MappingLauncher.displayName(for: bundleID) ?? bundleID))
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

    /// The scheme's default handler, resolved via LaunchServices, so the editor
    /// can reason about which app would actually receive the URL.
    private var defaultHandlerBundleID: String? {
        guard let url = previewURL ?? templateScheme.flatMap({ URL(string: "\($0)://probe") }),
            let appURL = NSWorkspace.shared.urlForApplication(toOpen: url)
        else { return nil }
        return Bundle(url: appURL)?.bundleIdentifier
    }

    /// Warns when the template embeds credentials (`{password}` /
    /// `{password-encoded}`) and Safari — explicitly chosen or the scheme's
    /// default handler — would open it. Safari mishandles basic auth in URLs
    /// (it re-prompts for credentials instead of using the embedded ones).
    private var safariBasicAuthWarning: String? {
        guard
            model.template.contains("{password}")
                || model.template.contains("{password-encoded}")
        else { return nil }
        let effectiveBundleID = model.applicationBundleID ?? defaultHandlerBundleID
        guard effectiveBundleID == "com.apple.Safari" else { return nil }
        return
            "Safari doesn't handle basic-auth URLs correctly and will re-prompt for credentials. Pick a different app (e.g. Chrome)."
    }

    private var trimmedName: String {
        model.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedTemplate: String {
        model.template.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && !trimmedTemplate.isEmpty && previewURL != nil && scopeIsValid
    }

    /// A "Selected Servers" mapping must target at least one server; "All
    /// Servers" is always valid.
    private var scopeIsValid: Bool {
        if case .only(let ids) = model.scope { return !ids.isEmpty }
        return true
    }

    private enum ScopeChoice: Hashable { case all, selected }

    private var scopeChoice: Binding<ScopeChoice> {
        Binding(
            get: {
                if case .only = model.scope { return .selected }
                return .all
            },
            set: { choice in
                switch choice {
                case .all:
                    model.scope = .all
                case .selected:
                    if case .only = model.scope { return }
                    // Seed with every current server so unchecking one is one
                    // click; servers added later won't be included.
                    model.scope = .only(Set(profileStore.profiles.map(\.id)))
                }
            })
    }

    private func serverToggle(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: {
                if case .only(let ids) = model.scope { return ids.contains(id) }
                return true
            },
            set: { on in
                guard case .only(var ids) = model.scope else { return }
                if on { ids.insert(id) } else { ids.remove(id) }
                model.scope = .only(ids)
            })
    }

    @ViewBuilder
    private var scopeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Applies to")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Applies to", selection: scopeChoice) {
                Text("All Servers").tag(ScopeChoice.all)
                Text("Selected Servers").tag(ScopeChoice.selected)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if case .only = model.scope {
                if profileStore.profiles.isEmpty {
                    Text("No servers configured yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(profileStore.profiles) { profile in
                            Toggle(isOn: serverToggle(profile.id)) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(profile.label)
                                    Text("\(profile.host):\(profile.port)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .monospaced()
                                }
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                    if !scopeIsValid {
                        Text("Select at least one server.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
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
                        ForEach(OpenMappingPlaceholders.presets, id: \.label) { preset in
                            Button {
                                applyPreset(preset)
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(preset.label)
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
                        ForEach(Array(OpenMappingPlaceholders.groups.enumerated()), id: \.element.id) {
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
                        PlaceholderReferenceView(groups: OpenMappingPlaceholders.groups)
                    }

                    Spacer()
                }
            }

            HStack(spacing: 10) {
                Picker("Action", selection: $model.action) {
                    Text("Reveal in Finder").tag(OpenMappingAction.finder)
                    Text("Open").tag(OpenMappingAction.open)
                }
                .pickerStyle(.menu)
                .help(
                    "Reveal selects the item in Finder; Open hands the URL to the system's protocol handler or a chosen app"
                )
                Spacer()
            }

            if model.action == .open {
                HStack(spacing: 10) {
                    Picker("Open with", selection: $model.applicationBundleID) {
                        Text("Let the system handle it").tag(String?.none)
                        if !handlerApps.isEmpty {
                            Divider()
                            ForEach(handlerApps, id: \.bundleID) { app in
                                Text(app.name).tag(Optional(app.bundleID))
                            }
                        }
                    }
                    .pickerStyle(.menu)
                    .help("Which app receives the URL; the system default for the scheme when unset")
                    Button("Choose App…") { chooseApp() }
                        .controlSize(.small)
                    Spacer()
                }
                if model.action == .open && templateScheme == "file" {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("File access")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            let paths = model.accessGrantedPaths
                            if paths.isEmpty {
                                Text("macOS needs permission to hand local files to another app.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(paths, id: \.self) { path in
                                    Text("Access granted to \(path)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        Spacer()
                        Button(model.accessBookmarks.isEmpty ? "Pre-approve directory…" : "Add directory…") {
                            chooseAccessFolder()
                        }
                        .controlSize(.small)
                    }
                }
            }

            scopeSection

            if let warning = safariBasicAuthWarning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Preview")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let url = previewURL {
                    Text(previewDisplayString ?? url.absoluteString)
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
        .alert("Allow access to local files?", isPresented: $showAccessAlert) {
            Button("Pre-approve directory…") {
                chooseAccessFolder {
                    commitSave()
                }
            }
            Button("Save without access") {
                commitSave()
            }
        } message: {
            Text(accessPromptMessage)
        }
    }

    private func applyPreset(
        _ preset: (label: String, defaultName: String, template: String, action: OpenMappingAction, explanation: String)
    ) {
        if trimmedName.isEmpty {
            model.name = preset.defaultName
        }
        model.template = preset.template
        model.action = preset.action
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

    /// Lets the user pre-approve a folder for this mapping up-front (default
    /// download dir is the suggested starting point). Creating the bookmark
    /// must go through the powerbox panel — a path the app can't reach yet has
    /// no bookmark to record.
    private func chooseAccessFolder(then completion: (() -> Void)? = nil) {
        let panel = NSOpenPanel()
        panel.title = "Allow Access"
        panel.message =
            "Choose a folder that “\(model.name)” may open files from. Pre-approving it now means no prompt when you open a file."
        panel.prompt = "Allow"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if let dir = sampleDownloadDir, !dir.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: dir, isDirectory: true)
        }
        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    let bookmark = try url.bookmarkData(
                        options: .withSecurityScope,
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil)
                    if !model.accessBookmarks.contains(bookmark) {
                        model.accessBookmarks.append(bookmark)
                    }
                } catch {
                    model.testMessage = "Could not save access permission: \(error.localizedDescription)"
                    model.testFailed = true
                }
            }
            completion?()
        }
    }

    /// An `.open` mapping that targets local files has no permission yet — ask
    /// up-front (default download dir) instead of surprising the user at first
    /// use. `.finder` needs no bookmark, so it never prompts.
    private var shouldPromptForAccess: Bool {
        model.action == .open && templateScheme == "file" && model.accessBookmarks.isEmpty
    }

    private var accessPromptMessage: String {
        if let dir = sampleDownloadDir, !dir.isEmpty {
            return
                "This mapping opens local files. Allow access to the download folder \(dir) so macOS can hand files to another app? You can pre-approve a different folder, or skip and the app will ask on first use."
        }
        return
            "This mapping opens local files. macOS needs permission to hand them to another app. You can pre-approve a folder now, or the app will ask on first use."
    }

    private func test() {
        model.resetTestState()
        guard let url = testURL else { return }
        switch model.action {
        case .finder:
            guard url.scheme == "file", FileManager.default.fileExists(atPath: url.path) else {
                model.testMessage =
                    "Nothing to reveal at \(url.path) — Reveal in Finder only works for files that exist on this Mac (a local daemon or mounted volume)."
                model.testFailed = true
                return
            }
            MappingLauncher.revealInFinder(url)
            model.testMessage = "Revealed in Finder."
            model.testFailed = false
        case .open:
            let hasApp = !(model.applicationBundleID ?? "").isEmpty
            MappingLauncher.open(url: url, applicationBundleID: model.applicationBundleID) {
                outcome in
                switch outcome {
                case .opened:
                    model.testMessage = hasApp ? "Opened." : "Opened in the default app."
                    model.testFailed = false
                case .failed(let message):
                    model.testMessage = "Could not open — \(message)"
                    model.testFailed = true
                }
            }
        }
    }

    private func save() {
        if shouldPromptForAccess {
            showAccessAlert = true
        } else {
            commitSave()
        }
    }

    private func commitSave() {
        onSave(
            OpenMapping(
                id: model.existing?.id ?? UUID(),
                name: trimmedName,
                template: trimmedTemplate,
                action: model.action,
                applicationBundleID: model.applicationBundleID,
                scope: model.scope,
                accessBookmarks: model.accessBookmarks))
        onCancel()
    }
}
