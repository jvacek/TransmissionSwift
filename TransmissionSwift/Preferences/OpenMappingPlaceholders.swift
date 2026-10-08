import SwiftUI
import TransmissionCore

/// The template placeholder catalog and preset templates, shared by the
/// sheet's insert menu, its reference popover and its preset menu. Kept in
/// one place so the two placeholder surfaces cannot drift apart.
enum OpenMappingPlaceholders {
    /// Single source of truth for the template placeholders: drives both the
    /// "Insert placeholder" menu and the reference popover, so the two can't
    /// drift apart.
    static let groups: [PlaceholderGroup] = [
        PlaceholderGroup(
            title: "File",
            items: [
                PlaceholderItem(
                    token: "{file}",
                    summary:
                        "The file or folder being opened, relative to the folder the torrent is saved under."
                ),
                PlaceholderItem(
                    token: "{fileAbsolute}",
                    summary:
                        "Same as {file}, but prefixed with the torrent's full download folder (absolute path)."
                ),
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

    static let presets:
        [(label: String, defaultName: String, template: String, action: OpenMappingAction, explanation: String)] = [
            (
                "Reveal in Finder (from local daemon)",
                "Finder",
                "file:///{download-dir}/{folder}/{file}",
                .finder,
                "The daemon runs on this Mac — reveal the torrent's file or folder in Finder."
            ),
            (
                "Reveal in Finder (mounted volume)",
                "Finder",
                "file:///Volumes/transmission/{folder}/{file}",
                .finder,
                "The daemon's download folder is mounted on this Mac — reveal the file or folder in Finder."
            ),
            (
                "Open with default app",
                "Default app",
                "file:///{fileAbsolute}",
                .open,
                "Open the file with its default macOS app (e.g. Music for mp3, TextEdit for txt)."
            ),
            (
                "Open in Cyberduck",
                "Cyberduck",
                "sftp://{user}@{host}/{fileAbsolute}",
                .open,
                "Open the file or download folder over SFTP in Cyberduck."
            ),
            (
                "Open in Swizzin web",
                "Swizzin Web",
                "https://{user}:{password-encoded}@{host}/transmission.downloads/{folder}/{file}",
                .open,
                "Open the file in swizzin's web downloads view (basic auth)."
            ),
        ]
}

/// One selectable template placeholder with its one-line documentation.
struct PlaceholderItem: Identifiable, Hashable {
    let token: String
    let summary: String
    var id: String { token }
}

/// A group of placeholders shown together in the insert menu and reference.
struct PlaceholderGroup: Identifiable {
    let title: String
    let items: [PlaceholderItem]
    var id: String { title }
}

/// Compact, scrollable reference for the template placeholders, shown from a
/// popover so it doesn't consume the sheet's limited vertical space.
struct PlaceholderReferenceView: View {
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
                    Text("{fileAbsolute} is the same path, prefixed with the torrent's download folder.")
                }
                .font(.caption)
            }
            .padding(12)
        }
        .frame(width: 340, height: 380)
        .textSelection(.enabled)
    }
}
