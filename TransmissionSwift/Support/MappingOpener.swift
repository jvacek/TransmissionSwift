import AppKit
import TransmissionCore

/// Resolves a mapping's URL and hands it to macOS, sharing the logic between
/// the torrent list's context menu and the inspector's file context menu.
///
/// Opening a `file://` URL from a sandboxed app requires sandbox read access to
/// the file: folder entitlements cover the app's own I/O but not LaunchServices'
/// "open" check, so handing a local path to another app (default handler or a
/// chosen app) is denied unless the user has granted access. The first time an
/// `.open` mapping targets a local file, we ask once via an `NSOpenPanel` and
/// persist a security-scoped bookmark on the mapping; later opens reuse it.
/// `.finder` (Reveal in Finder) needs no bookmark — `activateFileViewerSelecting`
/// self-prompts via powerbox.
@MainActor
enum MappingOpener {
    static func open(
        _ mapping: OpenMapping,
        torrent: Torrent,
        file: TorrentFile?,
        profile: ServerProfile,
        store: TorrentStore,
        mappingStore: OpenMappingStore
    ) async {
        // The password lives in the Keychain, not on the profile. Reading it is
        // a user-initiated action, so a transient keychain prompt is acceptable.
        // Only fail the whole open when the template actually needs it — a locked
        // Keychain shouldn't block a password-less mapping.
        let password: String?
        do {
            password = try KeychainStore().password(for: profile.id)
        } catch {
            if MappingTemplate.needsPassword(mapping.template) {
                store.lastActionError = .failed(
                    message: "Couldn't read the saved password from the Keychain.")
                return
            }
            password = nil
        }
        // From the torrent list the file list isn't fetched; `{file}` needs it
        // to tell a single-file torrent (open the file) from a multi-file one
        // (open the folder), so resolve it on demand.
        let resolved = await store.torrentForOpening(torrent)
        guard
            let url = MappingTemplate.expand(
                mapping.template,
                torrent: resolved,
                server: profile,
                password: password,
                defaultDownloadDirectory: store.list.downloadDirectory,
                file: file)
        else {
            store.lastActionError = .failed(message: "Could not build a URL from “\(mapping.template)”")
            return
        }

        guard url.scheme == "file" else {
            // Remote schemes are routed by LaunchServices by scheme; no file
            // access needed.
            dispatch(url, mapping: mapping, store: store)
            return
        }

        // A stored bookmark grants access to the mapped folder (persisted from
        // an earlier Allow prompt). A mapping may span servers whose files live
        // in different folders, so trust only the bookmark whose folder contains
        // the target; activate its scope for the duration of the open. Otherwise
        // fall through and prompt.
        if let scopeURL = grantedScopeURL(for: url, bookmarks: mapping.accessBookmarks) {
            let accessing = scopeURL.startAccessingSecurityScopedResource()
            defer { if accessing { scopeURL.stopAccessingSecurityScopedResource() } }
            dispatch(url, mapping: mapping, store: store)
            return
        }

        switch mapping.action {
        case .finder:
            revealInFinder(url, store: store)
        case .open:
            promptForAccess(to: url, mapping: mapping, store: store, mappingStore: mappingStore)
        }
    }

    /// Reveal in Finder, or open with the default handler (or the mapping's app).
    private static func dispatch(_ url: URL, mapping: OpenMapping, store: TorrentStore) {
        switch mapping.action {
        case .finder:
            revealInFinder(url, store: store)
        case .open:
            MappingLauncher.open(url: url, applicationBundleID: mapping.applicationBundleID) {
                outcome in
                if case .failed(let message) = outcome {
                    store.lastActionError = .failed(message: message)
                }
            }
        }
    }

    /// Finder has no "open" registration for directories, so a generic
    /// `NSWorkspace.open` can fail for `file://` URLs. Revealing through
    /// `activateFileViewerSelecting` always routes to Finder and self-prompts
    /// for access when the app lacks it.
    private static func revealInFinder(_ url: URL, store: TorrentStore) {
        guard url.scheme == "file" else {
            store.lastActionError = .failed(
                message: "“Reveal in Finder” needs a file:// URL, got \(url.scheme ?? "none").")
            return
        }
        MappingLauncher.revealInFinder(url)
    }

    /// The stored bookmark whose folder contains `url`, if any. Activating a
    /// bookmark only grants its own subtree, so a mapping that spans servers
    /// must check the target against each grant before trusting one.
    private static func grantedScopeURL(for url: URL, bookmarks: [Data]) -> URL? {
        let target = url.standardizedFileURL.path
        for data in bookmarks {
            guard let scopeURL = MappingLauncher.resolveBookmark(data) else { continue }
            let folder = scopeURL.standardizedFileURL.path
            let prefix = folder.hasSuffix("/") ? folder : folder + "/"
            if target == folder || target.hasPrefix(prefix) {
                return scopeURL
            }
        }
        return nil
    }

    /// No bookmark covers `url` yet, so the user must grant access to the folder
    /// once. Append the grant to the mapping's bookmarks, then retry the open
    /// with the scope active.
    private static func promptForAccess(
        to url: URL,
        mapping: OpenMapping,
        store: TorrentStore,
        mappingStore: OpenMappingStore
    ) {
        let folder = url.deletingLastPathComponent()
        let panel = NSOpenPanel()
        panel.title = "Allow Access"
        panel.message =
            "“\(mapping.name)” opens files in \(folder.path). Choose the folder to allow access."
        panel.prompt = "Allow"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = folder
        panel.begin { response in
            guard response == .OK, let granted = panel.url else { return }
            do {
                var updated = mapping
                let bookmark = try granted.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil)
                if !updated.accessBookmarks.contains(bookmark) {
                    updated.accessBookmarks.append(bookmark)
                }
                try mappingStore.replace(updated)
                let accessing = granted.startAccessingSecurityScopedResource()
                defer { if accessing { granted.stopAccessingSecurityScopedResource() } }
                dispatch(url, mapping: mapping, store: store)
            } catch {
                store.lastActionError = .failed(
                    message: "Could not save the access permission: \(error.localizedDescription)")
            }
        }
    }
}
