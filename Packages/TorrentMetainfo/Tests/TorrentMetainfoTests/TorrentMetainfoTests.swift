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
}
