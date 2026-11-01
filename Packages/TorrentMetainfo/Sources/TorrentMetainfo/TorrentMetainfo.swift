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

    /// Decodes `.torrent` metainfo.
    ///
    /// - Throws: `TorrentMetainfoError` when `data` isn't a bencoded dictionary
    ///   with an `info` dictionary carrying a name.
    public init(decoding data: Data) throws {
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
        self.name = name

        if let entries = info["files"]?.list {
            self.isMultiFile = true
            self.files = try entries.map(Self.file(from:))
        } else if let length = info["length"]?.integer {
            self.isMultiFile = false
            self.files = [File(path: [name], length: Int64(length))]
        } else {
            throw TorrentMetainfoError.missingFileList
        }
    }

    /// Reads and decodes a `.torrent` file.
    ///
    /// Propagates file-system errors from `Data(contentsOf:)`; throws
    /// `TorrentMetainfoError` when the contents aren't valid metainfo.
    public init(contentsOf url: URL) throws {
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
        guard let bytes = (info["name.utf-8"] ?? info["name"])?.bytes,
            let name = string(from: bytes),
            !name.isEmpty
        else { return nil }
        return name
    }

    private static func file(from value: Bencode) throws -> File {
        guard let entry = value.dictionary,
            let rawPath = (entry["path.utf-8"] ?? entry["path"])?.list
        else { throw TorrentMetainfoError.malformedFileEntry }

        let path = try rawPath.map { component -> String in
            guard let bytes = component.bytes, let part = string(from: bytes) else {
                throw TorrentMetainfoError.malformedFileEntry
            }
            return part
        }
        guard let length = entry["length"]?.integer else {
            throw TorrentMetainfoError.malformedFileEntry
        }
        return File(path: path, length: Int64(length))
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
    /// Not valid bencode (truncated, bad token, or trailing bytes).
    case malformedBencode
    /// The top-level dictionary has no `info` dictionary.
    case missingInfoDictionary
    /// `info` has neither a `files` list nor a `length`.
    case missingFileList
    /// `info` has no usable `name`.
    case missingName
    /// A `files` entry is missing its `path` or `length`.
    case malformedFileEntry
}
