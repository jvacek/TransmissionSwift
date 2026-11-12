import Foundation

/// The metadata a `.torrent` file carries: its display name and file list.
///
/// A `.torrent` is a bencoded dictionary; this type exposes the handful of
/// fields the UI needs and hides the encoding. Decode-only for now — writing
/// (`torrent-create`) can be added later without changing this surface.
public struct TorrentMetainfo: Equatable, Sendable {
    /// The torrent's display name: `info.name.utf-8` when present, otherwise
    /// `info.name`.
    public let name: String

    /// Whether the torrent is a directory of files (`info.files`) rather than a
    /// single file (`info.length`).
    public let isMultiFile: Bool

    /// The torrent's files in `info.files` order. A single-file torrent yields
    /// exactly one entry whose path is `[name]`.
    public let files: [File]

    /// Total size of every file in the torrent, in bytes.
    public var totalSize: Int64 {
        files.reduce(0) { $0 + $1.length }
    }

    /// Largest `.torrent` this reader accepts. Real files are a few KB per
    /// thousand entries; the cap keeps a hostile or accidentally huge file from
    /// being copied into memory several times before it is rejected.
    public static let maximumSize = 16 * 1024 * 1024

    /// Decodes `.torrent` metainfo.
    ///
    /// - Throws: `TorrentMetainfoError` when `data` isn't a bencoded dictionary
    ///   with an `info` dictionary carrying a name, or is larger than
    ///   `maximumSize`.
    public init(decoding data: Data) throws {
        guard data.count <= Self.maximumSize else {
            throw TorrentMetainfoError.fileTooLarge
        }
        let root: Bencode
        do {
            root = try BencodeDecoder.decode(data)
        } catch {
            throw TorrentMetainfoError.malformedBencode
        }
        guard let info = root["info"]?.dictionary else {
            throw TorrentMetainfoError.missingInfoDictionary
        }
        guard let name = Self.name(in: info) else {
            throw TorrentMetainfoError.missingName
        }

        let isMultiFile: Bool
        let files: [File]
        if let entries = info["files"]?.list {
            guard !entries.isEmpty else {
                throw TorrentMetainfoError.missingFileList
            }
            isMultiFile = true
            files = try entries.map(Self.file(from:))
        } else if let length = info["length"]?.integer {
            isMultiFile = false
            files = [File(path: [name], length: Int64(length))]
        } else {
            throw TorrentMetainfoError.missingFileList
        }
        _ = try Self.checkedTotalSize(files)

        self.name = name
        self.isMultiFile = isMultiFile
        self.files = files
    }

    /// Reads and decodes a `.torrent` file.
    ///
    /// Propagates file-system errors from `Data(contentsOf:)`; throws
    /// `TorrentMetainfoError` when the contents aren't valid metainfo.
    public init(contentsOf url: URL) throws {
        // Check the on-disk size first so an oversized file is never loaded.
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
            size > Self.maximumSize
        {
            throw TorrentMetainfoError.fileTooLarge
        }
        try self.init(decoding: Data(contentsOf: url))
    }
}

extension TorrentMetainfo {
    /// One file inside a torrent.
    public struct File: Equatable, Sendable {
        /// Path components relative to the torrent root, e.g.
        /// `["Season 1", "Episode 1.mkv"]`.
        public let path: [String]

        /// Size in bytes.
        public let length: Int64

        /// The path components joined with `/`.
        public var pathString: String {
            path.joined(separator: "/")
        }
    }
}

// MARK: - Parsing helpers

extension TorrentMetainfo {
    private static func name(in info: [String: Bencode]) -> String? {
        // A malformed name.utf-8 must not hide a usable name.
        for key in ["name.utf-8", "name"] {
            if let bytes = info[key]?.bytes, let name = string(from: bytes), !name.isEmpty {
                return name
            }
        }
        return nil
    }

    private static func file(from value: Bencode) throws -> File {
        guard let entry = value.dictionary else {
            throw TorrentMetainfoError.malformedFileEntry
        }
        // A malformed `path.utf-8` must not hide a usable `path`, matching the
        // `name.utf-8` fallback above.
        let path: [String]
        if let utf8Path = entry["path.utf-8"]?.list, let parsed = Self.path(from: utf8Path) {
            path = parsed
        } else if let rawPath = entry["path"]?.list, let parsed = Self.path(from: rawPath) {
            path = parsed
        } else {
            throw TorrentMetainfoError.malformedFileEntry
        }
        guard let length = entry["length"]?.integer else {
            throw TorrentMetainfoError.malformedFileEntry
        }
        return File(path: path, length: Int64(length))
    }

    /// Decodes a bencoded path list, or nil when any component is not a
    /// non-empty string.
    private static func path(from components: [Bencode]) -> [String]? {
        var path: [String] = []
        path.reserveCapacity(components.count)
        for component in components {
            guard let bytes = component.bytes, let part = string(from: bytes), !part.isEmpty else {
                return nil
            }
            path.append(part)
        }
        return path.isEmpty ? nil : path
    }

    /// Rejects negative lengths and sums that would overflow `Int64`. The
    /// computed `totalSize` and the add sheet's selected-size sum are only
    /// safe because this runs once at decode time.
    private static func checkedTotalSize(_ files: [File]) throws -> Int64 {
        var total: Int64 = 0
        for file in files {
            guard file.length >= 0 else { throw TorrentMetainfoError.invalidFileLength }
            let (sum, overflow) = total.addingReportingOverflow(file.length)
            guard !overflow else { throw TorrentMetainfoError.invalidFileLength }
            total = sum
        }
        return total
    }

    /// Bencode strings are byte strings. Modern torrents are UTF-8; older ones
    /// carry whatever the creating client's local encoding was. Latin-1 can
    /// represent every byte, so it's the lossless-enough fallback.
    private static func string(from bytes: [UInt8]) -> String? {
        String(bytes: bytes, encoding: .utf8) ?? String(bytes: bytes, encoding: .isoLatin1)
    }
}

/// Why a byte sequence isn't usable `.torrent` metainfo.
public enum TorrentMetainfoError: Error, Equatable, Sendable {
    /// Not valid bencode (truncated, bad token, duplicate key, or trailing
    /// bytes).
    case malformedBencode
    /// Larger than `TorrentMetainfo.maximumSize`.
    case fileTooLarge
    /// The top-level dictionary has no `info` dictionary.
    case missingInfoDictionary
    /// `info` has no usable file list: neither `files` nor `length`, or an empty
    /// `files` list.
    case missingFileList
    /// `info` has no usable `name`.
    case missingName
    /// A `files` entry is missing its path or length.
    case malformedFileEntry
    /// A file length is negative, or the total would overflow `Int64`.
    case invalidFileLength
}
