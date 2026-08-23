import Foundation
import Testing

@testable import TransmissionCore

@Suite("MappingTemplate")
struct MappingTemplateTests {

    private func makeTorrent(
        downloadFolder: String,
        name: String = "My Torrent",
        files: [TorrentFile] = []
    ) -> Torrent {
        Torrent(
            id: 1,
            name: name,
            hash: "abc",
            size: 0,
            status: .seeding,
            progress: 1,
            primaryTracker: "tracker.example.com",
            downloadFolder: downloadFolder,
            addedAt: Date(),
            pieces: 0,
            pieceSize: 1024,
            havePieces: 0,
            files: files)
    }

    private func expand(
        _ template: String,
        downloadFolder: String,
        name: String = "My Torrent",
        server: ServerProfile,
        password: String? = nil,
        defaultDownloadDirectory: String? = nil,
        files: [TorrentFile] = [],
        file: TorrentFile? = nil
    ) -> URL? {
        MappingTemplate.expand(
            template,
            torrent: makeTorrent(downloadFolder: downloadFolder, name: name, files: files),
            server: server,
            password: password,
            defaultDownloadDirectory: defaultDownloadDirectory,
            file: file)
    }

    @Test("scheme-less path template expands to a file URL")
    func noSchemePath() {
        let server = ServerProfile(label: "x", host: "nas.local", port: 9091)
        #expect(
            expand(
                "/Volumes/transmission/{folder}", downloadFolder: "/Volumes/transmission/My Torrent", server: server)?
                .absoluteString
                == "file:///Volumes/transmission/My%20Torrent")
    }

    @Test("explicit file:// template with {folder}")
    func explicitFile() {
        let server = ServerProfile(label: "x", host: "nas.local", port: 9091)
        #expect(
            expand(
                "file:///Volumes/transmission/{folder}", downloadFolder: "/Volumes/transmission/My Torrent",
                server: server)?
                .absoluteString
                == "file:///Volumes/transmission/My%20Torrent")
    }

    @Test("https template substitutes host and folder with a trailing slash")
    func httpsFancyindex() {
        let server = ServerProfile(label: "x", host: "nas.local", port: 9091)
        #expect(
            expand(
                "https://{host}/downloads/{folder}/", downloadFolder: "/srv/transmission/My Torrent", server: server)?
                .absoluteString
                == "https://nas.local/downloads/My%20Torrent/")
    }

    @Test("full {path} keeps its slash separators and encodes each segment")
    func pathPlaceholder() {
        let server = ServerProfile(label: "x", host: "nas.local")
        #expect(
            expand("https://{host}/dl{path}", downloadFolder: "/mnt/nas/torrents/Sub Dir", server: server)?
                .absoluteString
                == "https://nas.local/dl/mnt/nas/torrents/Sub%20Dir")
    }

    @Test("unicode and spaces in folder are percent-encoded")
    func unicodeAndSpaces() {
        let server = ServerProfile(label: "x", host: "nas.local")
        #expect(
            expand(
                "file:///Volumes/transmission/{folder}", downloadFolder: "/Volumes/transmission/Torrents 下载",
                server: server)?
                .absoluteString
                == "file:///Volumes/transmission/Torrents%20%E4%B8%8B%E8%BD%BD")
    }

    @Test("? and # in a folder name are encoded as path, not query/fragment")
    func reservedCharactersInFolder() {
        let server = ServerProfile(label: "x", host: "nas.local")
        #expect(
            expand(
                "file:///Volumes/transmission/{folder}", downloadFolder: "/Volumes/transmission/Question? #mark",
                server: server)?
                .absoluteString
                == "file:///Volumes/transmission/Question%3F%20%23mark")
    }

    @Test("nil username substitutes as an empty user")
    func nilUser() {
        let server = ServerProfile(label: "x", host: "nas.local", username: nil)
        #expect(
            expand("sftp://{user}@{host}/~/{folder}/", downloadFolder: "/home/dev/torrents/My Torrent", server: server)?
                .absoluteString
                == "sftp://@nas.local/~/My%20Torrent/")
    }

    @Test("username with a value round-trips through the authority")
    func userWithValue() {
        let server = ServerProfile(label: "x", host: "nas.local", username: "casey")
        #expect(
            expand("sftp://{user}@{host}/~/{folder}/", downloadFolder: "/home/dev/torrents/My Torrent", server: server)?
                .absoluteString
                == "sftp://casey@nas.local/~/My%20Torrent/")
    }

    @Test("bracketed IPv6 host and port expand correctly")
    func ipv6Host() {
        let server = ServerProfile(label: "x", host: "[::1]", port: 9091)
        #expect(
            expand("https://{host}:{port}/downloads/{folder}/", downloadFolder: "/dl/My Torrent", server: server)?
                .absoluteString
                == "https://[::1]:9091/downloads/My%20Torrent/")
    }

    @Test("template with no path produces a host-only URL")
    func emptyPath() {
        let server = ServerProfile(label: "x", host: "nas.local")
        #expect(
            expand("https://{host}", downloadFolder: "/dl", server: server)?.absoluteString
                == "https://nas.local")
    }

    @Test("static template with no placeholders is used as-is")
    func staticTemplate() {
        let server = ServerProfile(label: "x", host: "nas.local")
        #expect(
            expand("https://example.com/downloads/", downloadFolder: "/dl", server: server)?.absoluteString
                == "https://example.com/downloads/")
    }

    @Test("invalid templates expand to nil")
    func invalidTemplates() {
        let server = ServerProfile(label: "x", host: "nas.local")
        #expect(expand("hello world", downloadFolder: "/dl", server: server) == nil)
        #expect(expand("", downloadFolder: "/dl", server: server) == nil)
        #expect(expand("   ", downloadFolder: "/dl", server: server) == nil)
    }

    @Test("raw {password} substitutes the literal password")
    func rawPassword() {
        let server = ServerProfile(label: "x", host: "nas.local", username: "admin")
        #expect(
            expand(
                "https://{user}:{password}@{host}/dl/{folder}",
                downloadFolder: "/dl/My Torrent",
                server: server,
                password: "secret"
            )?.absoluteString
                == "https://admin:secret@nas.local/dl/My%20Torrent")
    }

    @Test("{password-encoded} percent-encodes special characters for basic auth")
    func encodedPassword() {
        let server = ServerProfile(label: "x", host: "nas.local", username: "admin")
        #expect(
            expand(
                "https://{user}:{password-encoded}@{host}/dl/{folder}",
                downloadFolder: "/dl/My Torrent",
                server: server,
                password: "p@ss:word"
            )?.absoluteString
                == "https://admin:p%40ss:word@nas.local/dl/My%20Torrent")
    }

    @Test("{password-encoded} survives a slash that would break a raw password")
    func encodedPasswordWithSlash() {
        let server = ServerProfile(label: "x", host: "nas.local", username: "admin")
        #expect(
            expand(
                "https://{user}:{password-encoded}@{host}/dl",
                downloadFolder: "/dl",
                server: server,
                password: "p/ss word"
            )?.absoluteString
                == "https://admin:p%2Fss%20word@nas.local/dl")
    }

    @Test("nil password substitutes as empty for both password placeholders")
    func nilPassword() {
        let server = ServerProfile(label: "x", host: "nas.local", username: "admin")
        #expect(
            expand(
                "https://{user}:{password}@{host}/dl",
                downloadFolder: "/dl",
                server: server
            )?.absoluteString
                == "https://admin:@nas.local/dl")
        #expect(
            expand(
                "https://{user}:{password-encoded}@{host}/dl",
                downloadFolder: "/dl",
                server: server
            )?.absoluteString
                == "https://admin:@nas.local/dl")
    }

    @Test("{download-dir} substitutes the daemon's default download directory")
    func downloadDirectory() {
        let server = ServerProfile(label: "x", host: "nas.local")
        let files = [TorrentFile(id: 0, name: "ubuntu-24.04.iso", size: 1, progress: 1)]
        #expect(
            expand(
                "https://{host}/{download-dir}/{folder}/{file}",
                downloadFolder: "~/transmission/downloads/Ubuntu",
                name: "ubuntu-24.04.iso",
                server: server,
                defaultDownloadDirectory: "~/transmission/downloads",
                files: files
            )?.absoluteString
                == "https://nas.local/~/transmission/downloads/Ubuntu/ubuntu-24.04.iso")
    }

    @Test("unknown {download-dir} substitutes as empty")
    func downloadDirectoryUnknown() {
        let server = ServerProfile(label: "x", host: "nas.local")
        #expect(
            expand(
                "https://{host}/{download-dir}/{folder}",
                downloadFolder: "/srv/downloads/Ubuntu",
                server: server
            )?.absoluteString
                == "https://nas.local/Ubuntu")
    }

    @Test("{folder} is relative to the default download directory when inside it")
    func folderRelativeToDefaultDir() {
        let server = ServerProfile(label: "x", host: "nas.local")
        let files = [TorrentFile(id: 0, name: "ep01.mkv", size: 1, progress: 1)]
        #expect(
            expand(
                "https://{host}/{download-dir}/{folder}/{file}",
                downloadFolder: "~/transmission/downloads/SomeShow/Season 1",
                name: "ep01.mkv",
                server: server,
                defaultDownloadDirectory: "~/transmission/downloads",
                files: files
            )?.absoluteString
                == "https://nas.local/~/transmission/downloads/SomeShow/Season%201/ep01.mkv")
    }

    @Test("a torrent directly in the default dir yields an empty folder segment")
    func folderEqualDefaultDir() {
        let server = ServerProfile(label: "x", host: "nas.local")
        #expect(
            expand(
                "https://{host}/{download-dir}/{folder}",
                downloadFolder: "~/transmission/downloads",
                server: server,
                defaultDownloadDirectory: "~/transmission/downloads"
            )?.absoluteString
                == "https://nas.local/~/transmission/downloads/")
    }

    @Test("{folder} falls back to the basename outside the default dir")
    func folderOutsideDefaultDir() {
        let server = ServerProfile(label: "x", host: "nas.local")
        #expect(
            expand(
                "https://{host}/{download-dir}/{folder}",
                downloadFolder: "/mnt/other/torrents/Show",
                server: server,
                defaultDownloadDirectory: "~/transmission/downloads"
            )?.absoluteString
                == "https://nas.local/~/transmission/downloads/Show")
    }

    @Test("{file} is the torrent's own folder with a trailing slash for multi-file torrents")
    func fileMultiFile() {
        // Real Transmission reports downloadFolder = the folder the torrent is
        // saved under; file names carry the torrent-named folder prefix.
        let server = ServerProfile(label: "x", host: "nas.local", username: "dev")
        let files = [
            TorrentFile(id: 0, name: "TV Show/ep1.mkv", size: 1, progress: 1),
            TorrentFile(id: 1, name: "TV Show/ep2.mkv", size: 1, progress: 1),
        ]
        #expect(
            expand(
                "sftp://{user}@{host}/{download-dir}/{folder}/{file}",
                downloadFolder: "~/transmission/downloads",
                name: "TV Show",
                server: server,
                defaultDownloadDirectory: "~/transmission/downloads",
                files: files
            )?.absoluteString
                == "sftp://dev@nas.local/~/transmission/downloads/TV%20Show/")
    }

    @Test("{file} is the file itself for a single-file torrent")
    func fileSingleFile() {
        let server = ServerProfile(label: "x", host: "nas.local", username: "dev")
        let files = [TorrentFile(id: 0, name: "ubuntu.iso", size: 1, progress: 1)]
        #expect(
            expand(
                "sftp://{user}@{host}/{download-dir}/{folder}/{file}",
                downloadFolder: "~/transmission/downloads/ISO",
                name: "ubuntu.iso",
                server: server,
                defaultDownloadDirectory: "~/transmission/downloads",
                files: files
            )?.absoluteString
                == "sftp://dev@nas.local/~/transmission/downloads/ISO/ubuntu.iso")
    }

    @Test("{file} treats an unknown file list as the torrent's folder")
    func fileUnknownFiles() {
        let server = ServerProfile(label: "x", host: "nas.local", username: "dev")
        #expect(
            expand(
                "sftp://{user}@{host}/{download-dir}/{folder}/{file}",
                downloadFolder: "~/transmission/downloads",
                name: "TV Show",
                server: server,
                defaultDownloadDirectory: "~/transmission/downloads"
            )?.absoluteString
                == "sftp://dev@nas.local/~/transmission/downloads/TV%20Show/")
    }

    @Test("{file} expands a selected file's path, prefixed with the torrent folder")
    func fileInContext() {
        let server = ServerProfile(label: "x", host: "nas.local", username: "dev")
        let files = [
            TorrentFile(id: 0, name: "TV Show/Season 1/ep01.mkv", size: 1, progress: 1),
            TorrentFile(id: 1, name: "TV Show/Season 1/ep02.mkv", size: 1, progress: 1),
        ]
        let file = TorrentFile(id: 0, name: "TV Show/Season 1/ep01.mkv", size: 1, progress: 1)
        #expect(
            expand(
                "sftp://{user}@{host}/{download-dir}/{folder}/{file}",
                downloadFolder: "~/transmission/downloads",
                server: server,
                defaultDownloadDirectory: "~/transmission/downloads",
                files: files,
                file: file
            )?.absoluteString
                == "sftp://dev@nas.local/~/transmission/downloads/TV%20Show/Season%201/ep01.mkv")
    }

    @Test("an empty {folder} collapses to a single slash in the URL")
    func emptyFolderCollapses() {
        let server = ServerProfile(label: "x", host: "nas.local", username: "dev")
        let files = [TorrentFile(id: 0, name: "ubuntu.iso", size: 1, progress: 1)]
        #expect(
            expand(
                "sftp://{user}@{host}/{download-dir}/{folder}/{file}",
                downloadFolder: "~/transmission/downloads",
                name: "ubuntu.iso",
                server: server,
                defaultDownloadDirectory: "~/transmission/downloads",
                files: files
            )?.absoluteString
                == "sftp://dev@nas.local/~/transmission/downloads/ubuntu.iso")
    }

    @Test("{fileAbsolute} is {file} prefixed with the download folder (single file)")
    func fileAbsoluteSingleFile() {
        let server = ServerProfile(label: "x", host: "nas.local", username: "dev")
        let files = [TorrentFile(id: 0, name: "myfile.txt", size: 1, progress: 1)]
        #expect(
            expand(
                "sftp://{user}@{host}/{fileAbsolute}",
                downloadFolder: "/srv/downloads/TV",
                name: "myfile.txt",
                server: server,
                files: files
            )?.absoluteString
                == "sftp://dev@nas.local/srv/downloads/TV/myfile.txt")
    }

    @Test("{fileAbsolute} includes the torrent's own folder for multi-file torrents")
    func fileAbsoluteMultiFile() {
        let server = ServerProfile(label: "x", host: "nas.local", username: "dev")
        let files = [
            TorrentFile(id: 0, name: "Series1/Episode1", size: 1, progress: 1),
            TorrentFile(id: 1, name: "Series1/Episode2", size: 1, progress: 1),
        ]
        #expect(
            expand(
                "sftp://{user}@{host}/{fileAbsolute}",
                downloadFolder: "/srv/downloads/TV",
                name: "Series1",
                server: server,
                files: files
            )?.absoluteString
                == "sftp://dev@nas.local/srv/downloads/TV/Series1/")
    }

    @Test("{fileAbsolute} resolves a selected file to its absolute path")
    func fileAbsoluteInContext() {
        let server = ServerProfile(label: "x", host: "nas.local", username: "dev")
        let files = [
            TorrentFile(id: 0, name: "Series1/Episode1", size: 1, progress: 1),
            TorrentFile(id: 1, name: "Series1/Episode2", size: 1, progress: 1),
        ]
        let file = TorrentFile(id: 0, name: "Series1/Episode1", size: 1, progress: 1)
        #expect(
            expand(
                "sftp://{user}@{host}/{fileAbsolute}",
                downloadFolder: "/srv/downloads/TV",
                server: server,
                files: files,
                file: file
            )?.absoluteString
                == "sftp://dev@nas.local/srv/downloads/TV/Series1/Episode1")
    }

    @Test("{fileAbsolute} keeps a home-relative download folder as ~")
    func fileAbsoluteTilde() {
        let server = ServerProfile(label: "x", host: "nas.local", username: "dev")
        let files = [
            TorrentFile(id: 0, name: "Series1/Episode1", size: 1, progress: 1),
            TorrentFile(id: 1, name: "Series1/Episode2", size: 1, progress: 1),
        ]
        #expect(
            expand(
                "sftp://{user}@{host}/{fileAbsolute}",
                downloadFolder: "~/transmission/downloads/TV",
                name: "Series1",
                server: server,
                files: files
            )?.absoluteString
                == "sftp://dev@nas.local/~/transmission/downloads/TV/Series1/")
    }

    @Test("file scheme expands a leading tilde to the local home directory")
    func fileSchemeExpandsTilde() {
        let server = ServerProfile(label: "x", host: "nas.local")
        let home = NSHomeDirectory()
        #expect(
            expand(
                "file:///{download-dir}/{folder}",
                downloadFolder: "~/transmission/downloads/TV Show",
                server: server,
                defaultDownloadDirectory: "~/transmission/downloads"
            )?.absoluteString
                == "file://\(home)/transmission/downloads/TV%20Show")
    }

    @Test("remote schemes keep a tilde literal")
    func remoteSchemeKeepsTilde() {
        let server = ServerProfile(label: "x", host: "nas.local", username: "dev")
        #expect(
            expand(
                "https://{host}/{download-dir}/{folder}",
                downloadFolder: "~/transmission/downloads/TV Show",
                server: server,
                defaultDownloadDirectory: "~/transmission/downloads"
            )?.absoluteString
                == "https://nas.local/~/transmission/downloads/TV%20Show")
    }
}

// MARK: - Expected outputs against the mock fixtures

/// Expands the Cyberduck preset template against the shipped mock torrents
/// (`Torrent.samples`) so the exact per-context outputs are visible for review.
@Suite("MappingTemplate — expected outputs with the mock fixtures")
struct MappingTemplateMockOutputsTests {
    private let server = ServerProfile(label: "x", host: "nas.local", username: "dev")
    private let cyberduck = "sftp://{user}@{host}/{fileAbsolute}"
    private let downloads = "/srv/downloads"

    /// Percent-decoded full URL, for readable assertions (keeps the trailing
    /// slash that `URL.path` normalizes away).
    private func expandedURL(
        _ template: String, torrent: Torrent, defaultDownloadDirectory: String? = nil,
        file: TorrentFile? = nil
    ) -> String {
        MappingTemplate.expand(
            template, torrent: torrent, server: server,
            defaultDownloadDirectory: defaultDownloadDirectory, file: file)?
            .absoluteString.removingPercentEncoding ?? ""
    }

    @Test("single-file torrent (Ubuntu) opens the file itself")
    func ubuntuSingleFile() {
        let ubuntu = Torrent.samples[0]
        #expect(
            expandedURL(cyberduck, torrent: ubuntu, defaultDownloadDirectory: downloads)
                == "sftp://dev@nas.local/Linux ISOs/ubuntu-24.04.2-desktop-amd64.iso")
        #expect(
            MappingTemplate.expand(
                cyberduck, torrent: ubuntu, server: server, defaultDownloadDirectory: downloads)?
                .absoluteString
                == "sftp://dev@nas.local/Linux%20ISOs/ubuntu-24.04.2-desktop-amd64.iso")
    }

    @Test("multi-file torrent (Debian) opens the torrent's own folder")
    func debianMultiFile() {
        let debian = Torrent.samples[4]
        #expect(
            expandedURL(cyberduck, torrent: debian, defaultDownloadDirectory: downloads)
                == "sftp://dev@nas.local/Linux ISOs/Debian 12.6 — netinst (multi-arch) collection/")
    }

    @Test("a file selected in the inspector opens within the torrent folder")
    func debianInspectorFile() {
        let debian = Torrent.samples[4]
        let file = debian.files[0]
        #expect(
            expandedURL(cyberduck, torrent: debian, defaultDownloadDirectory: downloads, file: file)
                == "sftp://dev@nas.local/Linux ISOs/Debian 12.6 — netinst (multi-arch) collection/debian-12.6.0-amd64-netinst.iso"
        )
    }
}
