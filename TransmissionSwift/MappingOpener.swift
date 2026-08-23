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
        profileStore: ServerProfileStore
    ) async {
        // The password lives in the Keychain, not on the profile. Reading it is
        // a user-initiated action, so a transient keychain prompt is acceptable.
        let password = (try? KeychainStore().password(for: profile.id)) ?? nil
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
                defaultDownloadDirectory: store.downloadDirectory,
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
        // an earlier Allow prompt). Activate its scope for the duration of the
        // open so LaunchServices accepts the URL.
        if let scopeURL = resolveBookmark(mapping.accessBookmark) {
            let accessing = scopeURL.startAccessingSecurityScopedResource()
            defer { if accessing { scopeURL.stopAccessingSecurityScopedResource() } }
            dispatch(url, mapping: mapping, store: store)
            return
        }

        switch mapping.action {
        case .finder:
            revealInFinder(url, store: store)
        case .open:
            promptForAccess(to: url, mapping: mapping, profile: profile, store: store, profileStore: profileStore)
        }
    }

    /// Reveal in Finder, or open with the default handler (or the mapping's app).
    private static func dispatch(_ url: URL, mapping: OpenMapping, store: TorrentStore) {
        switch mapping.action {
        case .finder:
            revealInFinder(url, store: store)
        case .open:
            if let bundleID = mapping.applicationBundleID, !bundleID.isEmpty {
                openInApp(bundleID: bundleID, url: url, store: store)
            } else if !NSWorkspace.shared.open(url) {
                store.lastActionError = .failed(message: "Could not open \(url.absoluteString)")
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
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Resolves a stored security-scoped bookmark back to a folder URL, or nil.
    private static func resolveBookmark(_ data: Data?) -> URL? {
        guard let data else { return nil }
        var isStale = false
        return try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale)
    }

    /// No bookmark yet, so the user must grant access to the folder once.
    /// Persist the grant as a security-scoped bookmark on the mapping, then
    /// retry the open with the scope active.
    private static func promptForAccess(
        to url: URL,
        mapping: OpenMapping,
        profile: ServerProfile,
        store: TorrentStore,
        profileStore: ServerProfileStore
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
                updated.accessBookmark = try granted.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil)
                try profileStore.replaceMapping(updated, inProfile: profile.id)
                let accessing = granted.startAccessingSecurityScopedResource()
                defer { if accessing { granted.stopAccessingSecurityScopedResource() } }
                dispatch(url, mapping: mapping, store: store)
            } catch {
                store.lastActionError = .failed(
                    message: "Could not save the access permission: \(error.localizedDescription)")
            }
        }
    }

    private static func openInApp(bundleID: String, url: URL, store: TorrentStore) {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            store.lastActionError = .failed(message: "Could not find the app for “\(bundleID)”")
            return
        }
        // Route the URL to the specific app via LaunchServices; the app receives
        // it exactly like a normal open. Errors arrive on the completion handler.
        NSWorkspace.shared.open(
            [url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration()
        ) { _, error in
            if let error {
                Task { @MainActor in
                    store.lastActionError = .failed(message: error.localizedDescription)
                }
            }
        }
    }
}
