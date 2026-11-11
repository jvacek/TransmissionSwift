import Foundation
import Testing

@testable import TorrentMetainfo

// MARK: - Bencode builders (test-only)

private func bstr(_ string: String) -> String {
    "\(string.utf8.count):\(string)"
}

private func bint(_ value: Int) -> String {
    "i\(value)e"
}

private func torrentInfo(
    name: String,
    nameUTF8: String? = nil,
    length: Int? = nil,
    files: [(path: String, length: Int)]? = nil
) -> Data {
    var info = "d"
    if let files {
        info += bstr("files")
        info += "l"
        for file in files {
            info +=
                "d" + bstr("length") + bint(file.length) + bstr("path") + "l"
                + file.path.split(separator: "/").map { bstr(String($0)) }.joined() + "ee"
        }
        info += "e"
    }
    if let length {
        info += bstr("length") + bint(length)
    }
    info += bstr("name") + bstr(name)
    if let nameUTF8 {
        info += bstr("name.utf-8") + bstr(nameUTF8)
    }
    info += "e"

    let root = "d" + bstr("announce") + bstr("http://tracker.invalid/announce") + bstr("info") + info + "e"
    return Data(root.utf8)
}

/// One `info.files` entry, with an optional `path.utf-8` list.
private func fileEntry(
    path: [String],
    length: Int,
    utf8Path: [String]? = nil
) -> String {
    var entry =
        "d" + bstr("length") + bint(length) + bstr("path") + "l"
        + path.map(bstr).joined() + "e"
    if let utf8Path {
        entry += bstr("path.utf-8") + "l" + utf8Path.map(bstr).joined() + "e"
    }
    return entry + "e"
}

/// A multi-file torrent around pre-built `info.files` entries.
private func multiFileTorrent(name: String = "root", entries: [String]) -> Data {
    let info =
        "d" + bstr("files") + "l" + entries.joined() + "e" + bstr("name") + bstr(name) + "e"
    return Data(("d" + bstr("info") + info + "e").utf8)
}

// MARK: - Fixtures

@Suite("Real .torrent fixtures")
struct TorrentMetainfoFixtureTests {
    @Test("decodes a single-file torrent")
    func singleFile() throws {
        let url = try #require(
            Bundle.module.url(forResource: "single-file", withExtension: "torrent", subdirectory: "Fixtures"))
        let metainfo = try TorrentMetainfo(contentsOf: url)

        #expect(metainfo.name == "hello world.txt")
        #expect(metainfo.isMultiFile == false)
        #expect(metainfo.files.map(\.pathString) == ["hello world.txt"])
        #expect(metainfo.files.map(\.length) == [6])
        #expect(metainfo.totalSize == 6)
    }

    @Test("decodes a multi-file torrent")
    func multiFile() throws {
        let url = try #require(
            Bundle.module.url(forResource: "multi-file", withExtension: "torrent", subdirectory: "Fixtures"))
        let metainfo = try TorrentMetainfo(contentsOf: url)

        #expect(metainfo.name == "My Torrent Data")
        #expect(metainfo.isMultiFile)
        #expect(metainfo.files.map(\.pathString).sorted() == ["alpha.txt", "gamma gamma.txt", "sub/beta.bin"])
        #expect(metainfo.totalSize == 6 + 18 + 5)
    }

    @Test("reads a torrent from a file URL")
    func contentsOfURL() throws {
        let url = try #require(
            Bundle.module.url(forResource: "single-file", withExtension: "torrent", subdirectory: "Fixtures"))
        #expect(try TorrentMetainfo(contentsOf: url).name == "hello world.txt")
    }
}

// MARK: - Decoding

@Suite("Decoding")
struct TorrentMetainfoDecodingTests {
    @Test("single-file info yields one synthesized file path")
    func singleFile() throws {
        let metainfo = try TorrentMetainfo(decoding: torrentInfo(name: "file.bin", length: 11))

        #expect(metainfo.name == "file.bin")
        #expect(metainfo.isMultiFile == false)
        #expect(metainfo.files.map(\.pathString) == ["file.bin"])
        #expect(metainfo.totalSize == 11)
    }

    @Test("multi-file info preserves path components")
    func multiFile() throws {
        let data = torrentInfo(name: "root", files: [("a.txt", 1), ("dir/b.bin", 2)])
        let metainfo = try TorrentMetainfo(decoding: data)

        #expect(metainfo.isMultiFile)
        #expect(metainfo.files.map(\.path) == [["a.txt"], ["dir", "b.bin"]])
        #expect(metainfo.totalSize == 3)
    }

    @Test("prefers name.utf-8 over name")
    func utf8NamePreferred() throws {
        let data = torrentInfo(name: "fallback", nameUTF8: "Café", length: 1)
        #expect(try TorrentMetainfo(decoding: data).name == "Café")
    }

    @Test("falls back to Latin-1 when name isn't UTF-8")
    func latin1Name() throws {
        // "Café" in Latin-1 ends in 0xE9, which is not a valid UTF-8 sequence.
        let prefix = Array("d4:infod6:lengthi1e4:name4:".utf8)
        let nameBytes: [UInt8] = [0x43, 0x61, 0x66, 0xE9]
        let data = Data(prefix + nameBytes + Array("ee".utf8))

        #expect(try TorrentMetainfo(decoding: data).name == "Café")
    }

    @Test("files win when a length is also present")
    func filesPrecedeLength() throws {
        let data = torrentInfo(name: "root", length: 99, files: [("a.txt", 1)])
        let metainfo = try TorrentMetainfo(decoding: data)

        #expect(metainfo.isMultiFile)
        #expect(metainfo.files.map(\.pathString) == ["a.txt"])
        #expect(metainfo.totalSize == 1)
    }

    @Test("prefers path.utf-8 over path")
    func utf8PathPreferred() throws {
        let data = multiFileTorrent(entries: [
            fileEntry(path: ["old"], length: 1, utf8Path: ["new"])
        ])

        #expect(try TorrentMetainfo(decoding: data).files.map(\.path) == [["new"]])
    }

    @Test("falls back to path when path.utf-8 is malformed")
    func malformedUTF8PathFallsBack() throws {
        let entry =
            "d" + bstr("length") + bint(1) + bstr("path") + "l" + bstr("old") + "e"
            + bstr("path.utf-8") + bint(1) + "e"
        let data = multiFileTorrent(entries: [entry])

        #expect(try TorrentMetainfo(decoding: data).files.map(\.path) == [["old"]])
    }

    @Test("falls back to Latin-1 when a path component isn't UTF-8")
    func latin1Path() throws {
        var data = Data("d4:infod5:filesld6:lengthi1e4:pathl4:".utf8)
        data.append(contentsOf: [0x43, 0x61, 0x66, 0xE9])
        data.append(contentsOf: Array("eee4:name4:rootee".utf8))

        #expect(try TorrentMetainfo(decoding: data).files.map(\.path) == [["Café"]])
    }
}

// MARK: - Malformed input

@Suite("Malformed input throws")
struct TorrentMetainfoMalformedTests {
    @Test("truncated bencode")
    func truncated() {
        #expect(throws: TorrentMetainfoError.malformedBencode) {
            try TorrentMetainfo(decoding: Data("d4:info".utf8))
        }
    }

    @Test("trailing bytes after the top-level value")
    func trailingBytes() {
        #expect(throws: TorrentMetainfoError.malformedBencode) {
            try TorrentMetainfo(decoding: Data("dejunk".utf8))
        }
    }

    @Test("unterminated list")
    func unterminatedList() {
        #expect(throws: TorrentMetainfoError.malformedBencode) {
            try TorrentMetainfo(decoding: Data("d4:infoli1e".utf8))
        }
    }

    @Test("string length exceeding the remaining bytes")
    func oversizedString() {
        #expect(throws: TorrentMetainfoError.malformedBencode) {
            try TorrentMetainfo(decoding: Data("d4:info99:short".utf8))
        }
    }

    @Test("no info dictionary")
    func noInfo() {
        #expect(throws: TorrentMetainfoError.missingInfoDictionary) {
            try TorrentMetainfo(decoding: Data("de".utf8))
        }
    }

    @Test("info dictionary without a name")
    func noName() {
        #expect(throws: TorrentMetainfoError.missingName) {
            try TorrentMetainfo(decoding: Data("d4:infod6:lengthi1eee".utf8))
        }
    }

    @Test("info dictionary without files or length")
    func noFileList() {
        #expect(throws: TorrentMetainfoError.missingFileList) {
            try TorrentMetainfo(decoding: Data("d4:infod4:name4:testee".utf8))
        }
    }

    @Test("files entry missing its length")
    func malformedFileEntry() {
        let root = "d4:infod4:name4:root5:filesld4:pathl1:aeeeee"
        #expect(throws: TorrentMetainfoError.malformedFileEntry) {
            try TorrentMetainfo(decoding: Data(root.utf8))
        }
    }

    @Test("invalid bencode token")
    func invalidToken() {
        #expect(throws: TorrentMetainfoError.malformedBencode) {
            try TorrentMetainfo(decoding: Data("x".utf8))
        }
    }

    @Test("invalid integer")
    func invalidInteger() {
        #expect(throws: TorrentMetainfoError.malformedBencode) {
            try TorrentMetainfo(decoding: Data("i1xe".utf8))
        }
    }

    @Test("integer larger than Int")
    func integerOverflow() {
        #expect(throws: TorrentMetainfoError.malformedBencode) {
            try TorrentMetainfo(decoding: Data("i999999999999999999999999e".utf8))
        }
    }

    @Test("dictionary key is not UTF-8")
    func invalidDictionaryKey() {
        let data = Data([0x64, 0x31, 0x3A, 0xFF, 0x69, 0x31, 0x65, 0x65])
        #expect(throws: TorrentMetainfoError.malformedBencode) {
            try TorrentMetainfo(decoding: data)
        }
    }

    @Test("info is not a dictionary")
    func infoNotDictionary() {
        #expect(throws: TorrentMetainfoError.missingInfoDictionary) {
            try TorrentMetainfo(decoding: Data("d4:infoli1eee".utf8))
        }
    }

    @Test("absurd nesting is rejected")
    func tooDeep() {
        let data = Data(String(repeating: "l", count: 65).utf8)
        #expect(throws: TorrentMetainfoError.malformedBencode) {
            try TorrentMetainfo(decoding: data)
        }
    }
}

// MARK: - Length and name validation

@Suite("Length and name validation")
struct TorrentMetainfoValidationTests {
    @Test("a non-string name.utf-8 falls back to name")
    func nameUTF8Fallback() throws {
        let data = Data("d4:infod10:name.utf-8i1e4:name4:test6:lengthi1eee".utf8)
        #expect(try TorrentMetainfo(decoding: data).name == "test")
    }

    @Test("an empty name.utf-8 falls back to name")
    func emptyUTF8NameFallback() throws {
        let data = Data("d4:infod10:name.utf-80:4:name4:test6:lengthi1eee".utf8)
        #expect(try TorrentMetainfo(decoding: data).name == "test")
    }

    @Test("a negative single-file length is rejected")
    func negativeSingleFileLength() {
        #expect(throws: TorrentMetainfoError.invalidFileLength) {
            try TorrentMetainfo(decoding: torrentInfo(name: "file", length: -1))
        }
    }

    @Test("a negative file length is rejected")
    func negativeFileLength() {
        let data = multiFileTorrent(entries: [fileEntry(path: ["a"], length: -1)])
        #expect(throws: TorrentMetainfoError.invalidFileLength) {
            try TorrentMetainfo(decoding: data)
        }
    }

    @Test("a total size that overflows Int64 is rejected")
    func overflowingTotalSize() {
        let data = multiFileTorrent(entries: [
            fileEntry(path: ["a"], length: Int.max),
            fileEntry(path: ["b"], length: Int.max),
        ])
        #expect(throws: TorrentMetainfoError.invalidFileLength) {
            try TorrentMetainfo(decoding: data)
        }
    }

    @Test("an empty files list is rejected")
    func emptyFilesList() {
        #expect(throws: TorrentMetainfoError.missingFileList) {
            try TorrentMetainfo(decoding: multiFileTorrent(entries: []))
        }
    }

    @Test("a file without a path is rejected")
    func missingPath() {
        let entry = "d" + bstr("length") + bint(1) + "e"
        #expect(throws: TorrentMetainfoError.malformedFileEntry) {
            try TorrentMetainfo(decoding: multiFileTorrent(entries: [entry]))
        }
    }

    @Test("a file path with an empty component is rejected")
    func emptyPathComponent() {
        let data = multiFileTorrent(entries: [fileEntry(path: ["", "a"], length: 1)])
        #expect(throws: TorrentMetainfoError.malformedFileEntry) {
            try TorrentMetainfo(decoding: data)
        }
    }

    @Test("zero-length files are valid")
    func zeroLengthFile() throws {
        #expect(try TorrentMetainfo(decoding: torrentInfo(name: "empty", length: 0)).totalSize == 0)
    }
}
