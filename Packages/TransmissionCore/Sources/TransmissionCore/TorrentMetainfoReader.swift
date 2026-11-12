// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import TorrentMetainfo

/// What the Add Torrent sheet shows for a user-picked `.torrent` file before it
/// is sent to the daemon.
public struct TorrentAddPreview: Equatable, Sendable {
    /// The torrent's display name (`info.name`).
    public let name: String
    /// The torrent's files in `info.files` order, with the indices the daemon's
    /// `files-wanted` and priority arguments expect.
    public let files: [TorrentAddFile]
}

/// Reads a user-picked `.torrent` file's metadata for display before it's added
/// to the daemon.
///
/// Kept in Core so the app target doesn't have to link `TorrentMetainfo`
/// directly — the format package stays an implementation detail of Core.
public enum TorrentMetainfoReader {
    /// Largest `.torrent` file the reader and the add path accept.
    public static let maximumSize = TorrentMetainfo.maximumSize

    /// The torrent's name and files, or `nil` when the file can't be read or
    /// decoded.
    public static func preview(at url: URL) -> TorrentAddPreview? {
        guard let metainfo = metainfo(at: url) else { return nil }
        let files = metainfo.files.enumerated().map { index, file in
            TorrentAddFile(index: index, path: file.path, length: file.length)
        }
        return TorrentAddPreview(name: metainfo.name, files: files)
    }

    private static func metainfo(at url: URL) -> TorrentMetainfo? {
        // `.fileImporter` hands back a security-scoped URL; reading it without
        // claiming access fails even outside the sandbox.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try? TorrentMetainfo(contentsOf: url)
    }
}
