import AppKit
import TransmissionCore

/// Resolves a mapping's URL and hands it to macOS, sharing the logic between
/// the torrent list's context menu and the inspector's file context menu.
@MainActor
enum MappingOpener {
    static func open(
        _ mapping: OpenMapping,
        torrent: Torrent,
        file: TorrentFile?,
        profile: ServerProfile,
        store: TorrentStore
    ) {
        // The password lives in the Keychain, not on the profile. Reading it is
        // a user-initiated action, so a transient keychain prompt is acceptable.
        let password = (try? KeychainStore().password(for: profile.id)) ?? nil
        guard
            let url = MappingTemplate.expand(
                mapping.template,
                torrent: torrent,
                server: profile,
                password: password,
                defaultDownloadDirectory: store.downloadDirectory,
                file: file)
        else {
            store.lastActionError = .failed(message: "Could not build a URL from “\(mapping.template)”")
            return
        }
        if let bundleID = mapping.applicationBundleID, !bundleID.isEmpty {
            openInApp(bundleID: bundleID, url: url, store: store)
        } else if !NSWorkspace.shared.open(url) {
            store.lastActionError = .failed(message: "Could not open \(url.absoluteString)")
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
