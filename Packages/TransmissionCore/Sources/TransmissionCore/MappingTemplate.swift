import Foundation

/// Expands an `OpenMapping.template` into a concrete URL for one torrent.
///
/// The template is split on `://` **before** substitution so that a `?`, `#`
/// or other reserved character inside a substituted value (folder name, path)
/// is not misread as a query/fragment. Substituted values are inserted raw and
/// the result is assembled via `URLComponents`, which percent-encodes path
/// segments automatically while preserving `/` separators from `{path}`.
///
/// Placeholders:
/// - `{file}`  — the torrent's content relative to the folder it's saved
///   under (`{folder}`). A specific file (file-list selection) resolves to
///   that file's path (e.g. `Series1/Episode1`); a single-file torrent
///   resolves to the file itself (e.g. `myfile.txt`); a multi-file torrent
///   resolves to its folder with a trailing `/` (e.g. `Series1/`). An empty
///   file list (fetch failed) falls back to the folder (`name/`).
/// - `{folder}` — the directory the torrent is saved under, relative to the
///   daemon's default download directory (e.g. `TV`; empty when the torrent
///   sits directly in it). Falls back to the folder's basename when the
///   default directory is unknown or the torrent lives outside it.
/// - `{path}`   — full `torrent.downloadFolder` (keeps its `/`)
/// - `{download-dir}` — the daemon's default download directory (empty when
///   unknown), e.g. `~/transmission/downloads`
/// - `{host}`   — server host
/// - `{port}`   — server port
/// - `{user}`   — server username (empty string when nil)
/// - `{password}` — raw password (empty string when nil). Avoid if the
///   password can contain `/` or a malformed `%` — those break the authority.
/// - `{password-encoded}` — percent-encoded password, safe to embed in a
///   `user:password@host` userinfo for HTTP basic auth.
///
/// A template without `://` must start with `/` and is treated as a `file://`
/// path; anything else is invalid and expands to `nil`.
///
/// For `file://` URLs, a leading `~` in a substituted value (daemon-reported
/// home-relative paths, common for local daemons) is expanded to this Mac's
/// home directory; remote schemes keep `~` literal.
public enum MappingTemplate {
    public static func expand(
        _ template: String,
        torrent: Torrent,
        server: ServerProfile,
        password: String? = nil,
        defaultDownloadDirectory: String? = nil,
        file: TorrentFile? = nil
    ) -> URL? {
        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let scheme: String
        var authority: String
        var path: String
        if let schemeRange = trimmed.range(of: "://") {
            scheme = String(trimmed[..<schemeRange.lowerBound])
            let afterScheme = trimmed[schemeRange.upperBound...]
            if let slash = afterScheme.firstIndex(of: "/") {
                authority = String(afterScheme[..<slash])
                path = String(afterScheme[slash...])
            } else {
                authority = String(afterScheme)
                path = ""
            }
        } else if trimmed.hasPrefix("/") {
            scheme = "file"
            authority = ""
            path = trimmed
        } else {
            return nil
        }

        let encodedPassword =
            (password ?? "")
            .addingPercentEncoding(withAllowedCharacters: Self.urlUnreserved) ?? ""
        authority =
            authority
            .replacingOccurrences(of: "{host}", with: server.host)
            .replacingOccurrences(of: "{port}", with: String(server.port))
            .replacingOccurrences(of: "{user}", with: server.username ?? "")
            .replacingOccurrences(of: "{password}", with: password ?? "")
            .replacingOccurrences(of: "{password-encoded}", with: encodedPassword)

        let folder = Self.folderComponent(
            of: torrent.downloadFolder, defaultDownloadDirectory: defaultDownloadDirectory)
        let openedFile = Self.fileComponent(of: torrent, file: file)
        path =
            path
            .replacingOccurrences(of: "{folder}", with: folder)
            .replacingOccurrences(of: "{path}", with: torrent.downloadFolder)
            .replacingOccurrences(of: "{download-dir}", with: defaultDownloadDirectory ?? "")
            .replacingOccurrences(of: "{file}", with: openedFile)

        var components = URLComponents()
        components.scheme = scheme
        guard let authorityComponents = URLComponents(string: "x://" + authority) else {
            return nil
        }
        components.user = authorityComponents.user
        components.password = authorityComponents.password
        components.host = authorityComponents.host
        components.port = authorityComponents.port
        components.path = Self.expandTildeIfNeeded(
            scheme: scheme, path: Self.collapseDuplicateSlashes(path))
        return components.url
    }

    /// For `file://` URLs the path refers to this Mac's filesystem, so a
    /// leading `~` (a home-relative daemon path, common for local daemons)
    /// resolves to the current user's home directory. Remote schemes keep `~`
    /// literal, since there it means the daemon's home.
    private static func expandTildeIfNeeded(scheme: String, path: String) -> String {
        guard scheme == "file", !path.isEmpty else { return path }
        let home = NSHomeDirectory()
        if path == "~" || path == "/~" { return home }
        if path.hasPrefix("~/") { return home + path.dropFirst(1) }
        if path.hasPrefix("/~/") { return home + "/" + path.dropFirst(3) }
        return path
    }

    /// RFC 3986 unreserved characters — the safe alphabet for embedding a
    /// value in any URL component.
    private static let urlUnreserved: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    /// `{folder}` = the torrent's download folder relative to the daemon's
    /// default download directory; basename when that's not computable.
    private static func folderComponent(
        of downloadFolder: String, defaultDownloadDirectory: String?
    ) -> String {
        guard let defaultDir = defaultDownloadDirectory,
            let relative = relativePath(of: downloadFolder, from: defaultDir)
        else {
            return (downloadFolder as NSString).lastPathComponent
        }
        return relative
    }

    /// `{file}` = the torrent's content relative to the folder it's saved under
    /// (`{folder}`). A specific file wins; a single-file torrent resolves to
    /// the file itself; a multi-file torrent resolves to its folder with a
    /// trailing `/` (per Cyberduck URI rules a trailing `/` denotes a
    /// directory). An empty file list (unknown) treats the torrent as a
    /// folder.
    private static func fileComponent(of torrent: Torrent, file: TorrentFile?) -> String {
        if let file {
            return file.name
        }
        if torrent.files.count == 1 {
            return torrent.files.first?.name ?? torrent.name
        }
        return torrent.name + "/"
    }

    /// Collapses runs of `/` so an empty `{folder}` (torrent directly in the
    /// default download dir) between literal template slashes yields one slash
    /// instead of `//`. Daemon paths are POSIX, so a leading `//` never
    /// carries meaning here.
    private static func collapseDuplicateSlashes(_ path: String) -> String {
        var collapsed = ""
        var lastWasSlash = false
        for character in path {
            if character == "/" {
                if !lastWasSlash { collapsed.append("/") }
                lastWasSlash = true
            } else {
                collapsed.append(character)
                lastWasSlash = false
            }
        }
        return collapsed
    }

    /// Path `path` expressed relative to `base`, or nil when it is not inside
    /// `base`. Compares path components so `~/downloads2` is not treated as
    /// inside `~/downloads`, and trailing slashes are ignored.
    private static func relativePath(of path: String, from base: String) -> String? {
        let baseParts = pathParts(base)
        let targetParts = pathParts(path)
        guard targetParts.count >= baseParts.count,
            targetParts.prefix(baseParts.count).elementsEqual(baseParts)
        else { return nil }
        return targetParts.dropFirst(baseParts.count).joined(separator: "/")
    }

    private static func pathParts(_ path: String) -> [String] {
        path.split(separator: "/").map(String.init)
    }
}
