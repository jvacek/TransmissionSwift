// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import TransmissionCore

/// The template placeholder catalog and preset templates, shared by the
/// sheet's insert menu, its reference popover and its preset menu. Kept in
/// one place so the two placeholder surfaces cannot drift apart.
enum OpenMappingPlaceholders {
    /// Single source of truth for the template placeholders: drives both the
    /// "Insert placeholder" menu and the reference popover, so the two can't
    /// drift apart.
    static var groups: [PlaceholderGroup] {
        [
            PlaceholderGroup(
                title: L10n.text("File"),
                items: [
                    PlaceholderItem(
                        token: "{file}",
                        summary:
                            L10n.text(
                                "The file or folder being opened, relative to the folder the torrent is saved under.")
                    ),
                    PlaceholderItem(
                        token: "{fileAbsolute}",
                        summary:
                            L10n.text(
                                "Same as {file}, but prefixed with the torrent's full download folder (absolute path).")
                    ),
                ]
            ),
            PlaceholderGroup(
                title: L10n.text("Torrent"),
                items: [
                    PlaceholderItem(
                        token: "{folder}",
                        summary:
                            L10n.text(
                                "The folder the torrent is saved under, relative to the daemon's default download folder."
                            )
                    ),
                    PlaceholderItem(token: "{path}", summary: L10n.text("The torrent's full download folder.")),
                ]
            ),
            PlaceholderGroup(
                title: L10n.text("Server"),
                items: [
                    PlaceholderItem(token: "{host}", summary: L10n.text("Server host.")),
                    PlaceholderItem(token: "{port}", summary: L10n.text("Server port.")),
                    PlaceholderItem(token: "{user}", summary: L10n.text("Server username (empty when unset).")),
                    PlaceholderItem(
                        token: "{password}",
                        summary:
                            L10n.text("Raw password; avoid when it can contain / or %. Prefer {password-encoded}.")),
                    PlaceholderItem(
                        token: "{password-encoded}",
                        summary: L10n.text("Percent-encoded password, safe to embed for basic auth.")),
                    PlaceholderItem(
                        token: "{download-dir}", summary: L10n.text("The daemon's default download folder.")),
                ]
            ),
        ]
    }

    static var presets:
        [(label: String, defaultName: String, template: String, action: OpenMappingAction, explanation: String)]
    {
        [
            (
                L10n.text("Reveal in Finder (from local daemon)"),
                L10n.text("Finder"),
                "file:///{download-dir}/{folder}/{file}",
                .finder,
                L10n.text("The daemon runs on this Mac — reveal the torrent's file or folder in Finder.")
            ),
            (
                L10n.text("Reveal in Finder (mounted volume)"),
                L10n.text("Finder"),
                "file:///Volumes/transmission/{folder}/{file}",
                .finder,
                L10n.text("The daemon's download folder is mounted on this Mac — reveal the file or folder in Finder.")
            ),
            (
                L10n.text("Open with default app"),
                L10n.text("Default app"),
                "file:///{fileAbsolute}",
                .open,
                L10n.text("Open the file with its default macOS app (e.g. Music for mp3, TextEdit for txt).")
            ),
            (
                L10n.text("Open in Cyberduck"),
                L10n.text("Cyberduck"),
                "sftp://{user}@{host}/{fileAbsolute}",
                .open,
                L10n.text("Open the file or download folder over SFTP in Cyberduck.")
            ),
            (
                L10n.text("Open in Swizzin web"),
                L10n.text("Swizzin Web"),
                "https://{user}:{password-encoded}@{host}/transmission.downloads/{folder}/{file}",
                .open,
                L10n.text("Open the file in swizzin's web downloads view (basic auth).")
            ),
        ]
    }
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
                    Text(L10n.text("How {file} resolves"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(L10n.text("Torrent list · single file → the file itself, e.g. myfile.txt"))
                    Text(L10n.text("Torrent list · multi-file → the torrent's folder, e.g. Series1/"))
                    Text(L10n.text("Files tab · one file selected → that file, e.g. Series1/Episode1"))
                    Text(L10n.text("{fileAbsolute} is the same path, prefixed with the torrent's download folder."))
                }
                .font(.caption)
            }
            .padding(12)
        }
        .frame(width: 340, height: 380)
        .textSelection(.enabled)
    }
}
