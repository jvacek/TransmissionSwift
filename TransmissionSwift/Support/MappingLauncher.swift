import AppKit

/// The sandbox-aware plumbing behind an `OpenMapping`: revealing a URL in
/// Finder, opening it with a specific app or the default handler, resolving a
/// stored security-scoped bookmark, and naming a bundle.
///
/// Shared by the runtime opener (`MappingOpener`, used from the torrent context
/// menu) and the editor's Test button, so both reach LaunchServices the same
/// way.
@MainActor
enum MappingLauncher {
    enum OpenOutcome: Sendable {
        case opened
        case failed(message: String)
    }

    /// Selects `url` in a Finder window. Needs no bookmark — the powerbox
    /// handles any access prompt.
    static func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Opens `url`, optionally in the app with `applicationBundleID`; the empty
    /// or nil case goes to the scheme's default handler. The app route reports
    /// errors asynchronously, so the outcome always arrives via `completion`.
    static func open(
        url: URL,
        applicationBundleID: String?,
        completion: @MainActor @escaping (OpenOutcome) -> Void
    ) {
        guard let bundleID = applicationBundleID, !bundleID.isEmpty else {
            if NSWorkspace.shared.open(url) {
                completion(.opened)
            } else {
                completion(.failed(message: "No app handles \(url.scheme ?? "this") links."))
            }
            return
        }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else {
            completion(.failed(message: "Could not find the app for “\(bundleID)”."))
            return
        }
        NSWorkspace.shared.open(
            [url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration()
        ) { _, error in
            Task { @MainActor in
                if let error {
                    completion(.failed(message: error.localizedDescription))
                } else {
                    completion(.opened)
                }
            }
        }
    }

    /// Resolves a stored security-scoped bookmark back to its URL, or nil.
    /// Nonisolated: pure Foundation, callable from non-main contexts.
    nonisolated static func resolveBookmark(_ data: Data?) -> URL? {
        guard let data else { return nil }
        var isStale = false
        return try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale)
    }

    /// Human-readable name for a bundle ID, for menus and labels.
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
