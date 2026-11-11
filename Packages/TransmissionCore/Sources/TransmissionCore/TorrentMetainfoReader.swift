import Foundation
import TorrentMetainfo

/// Reads a user-picked `.torrent` file's metadata for display before it's added
/// to the daemon.
///
/// Kept in Core so the app target doesn't have to link `TorrentMetainfo`
/// directly — the format package stays an implementation detail of Core.
public enum TorrentMetainfoReader {
    /// Largest `.torrent` file the reader and the add path accept.
    public static let maximumSize = TorrentMetainfo.maximumSize

    /// The torrent's display name (`info.name`), or `nil` when the file can't be
    /// read or decoded.
    public static func displayName(at url: URL) -> String? {
        metainfo(at: url)?.name
    }

    /// The torrent's files in `info.files` order, or `nil` when the file can't
    /// be read or decoded. The array offsets are the indices the daemon's
    /// `files-wanted` and priority arguments expect.
    public static func files(at url: URL) -> [TorrentAddFile]? {
        guard let metainfo = metainfo(at: url) else { return nil }
        return metainfo.files.enumerated().map { index, file in
            TorrentAddFile(index: index, path: file.path, length: file.length)
        }
    }

    private static func metainfo(at url: URL) -> TorrentMetainfo? {
        // `.fileImporter` hands back a security-scoped URL; reading it without
        // claiming access fails even outside the sandbox.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try? TorrentMetainfo(contentsOf: url)
    }
}
