import Foundation
import Testing

@testable import TransmissionCore

@Suite("TorrentMetainfoReader")
struct TorrentMetainfoReaderTests {
    @Test("files keep info order and carry their index, path, and length")
    func filesInOrder() throws {
        let url = try writeTorrent(
            name: "root", files: [("a.txt", 1), ("dir/b.bin", 2), ("dir/c.bin", 3)])
        defer { try? FileManager.default.removeItem(at: url) }

        let files = try #require(TorrentMetainfoReader.files(at: url))

        #expect(files.map(\.index) == [0, 1, 2])
        #expect(files.map(\.pathString) == ["a.txt", "dir/b.bin", "dir/c.bin"])
        #expect(files.map(\.path) == [["a.txt"], ["dir", "b.bin"], ["dir", "c.bin"]])
        #expect(files.map(\.length) == [1, 2, 3])
        #expect(files.allSatisfy { $0.wanted })
        #expect(files.allSatisfy { $0.priority == .normal })
    }

    @Test("a single-file torrent yields one file named after the torrent")
    func singleFile() throws {
        let url = try writeSingleFileTorrent(name: "hello.txt", length: 6)
        defer { try? FileManager.default.removeItem(at: url) }

        let files = try #require(TorrentMetainfoReader.files(at: url))

        #expect(files.count == 1)
        #expect(files[0].index == 0)
        #expect(files[0].pathString == "hello.txt")
        #expect(files[0].length == 6)
    }

    @Test("displayName still reads the info name")
    func displayName() throws {
        let url = try writeTorrent(name: "My Torrent", files: [("a.txt", 1)])
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(TorrentMetainfoReader.displayName(at: url) == "My Torrent")
    }

    @Test("undecodable data returns nil instead of throwing")
    func malformed() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("reader-tests-\(UUID().uuidString).torrent")
        try Data("not bencode".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(TorrentMetainfoReader.files(at: url) == nil)
        #expect(TorrentMetainfoReader.displayName(at: url) == nil)
    }
}

// MARK: - Helpers

private func writeTorrent(name: String, files: [(path: String, length: Int)]) throws -> URL {
    var info = "d5:filesl"
    for file in files {
        info += "d6:lengthi\(file.length)e4:pathl"
        info += file.path.split(separator: "/").map { "\($0.utf8.count):\($0)" }.joined()
        info += "ee"
    }
    info += "e4:name\(name.utf8.count):\(name)e"
    return try write(Data("d4:info\(info)e".utf8))
}

private func writeSingleFileTorrent(name: String, length: Int) throws -> URL {
    let info = "d6:lengthi\(length)e4:name\(name.utf8.count):\(name)e"
    return try write(Data("d4:info\(info)e".utf8))
}

private func write(_ data: Data) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("reader-tests-\(UUID().uuidString).torrent")
    try data.write(to: url)
    return url
}
