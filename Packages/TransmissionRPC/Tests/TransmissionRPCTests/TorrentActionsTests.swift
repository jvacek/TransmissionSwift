import Foundation
import Testing

@testable import TransmissionRPC

// MARK: - Helpers

private func fixture(named name: String) throws -> Data {
    let url = try #require(
        Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

private struct RPCResponse<T: Decodable>: Decodable {
    let result: String
    let arguments: T
}

// MARK: - SessionInfo.altSpeedEnabled

@Suite("SessionInfo.altSpeedEnabled")
struct SessionInfoAltSpeedTests {
    @Test("alt-speed-enabled decodes from session-get fixture")
    func decodeAltSpeedEnabled() throws {
        let data = try fixture(named: "session-get-success")
        let response = try JSONDecoder().decode(RPCResponse<SessionInfo>.self, from: data)
        #expect(response.arguments.altSpeedEnabled == false)
    }
}

// MARK: - TorrentAddResponse decode

@Suite("TorrentAddResponse decode")
struct TorrentAddResponseTests {
    @Test("torrent-added branch decodes id, name, hashString")
    func decodeTorrentAdded() throws {
        let data = try fixture(named: "torrent-add-success")
        let response = try JSONDecoder().decode(RPCResponse<TorrentAddResponse>.self, from: data)
        let added = try #require(response.arguments.torrentAdded)
        #expect(added.id == 42)
        #expect(added.name == "My Test Torrent")
        #expect(added.hashString == "abc123def456abc123def456abc123def456abc123")
        #expect(response.arguments.torrentDuplicate == nil)
    }

    @Test("torrent-duplicate branch decodes and torrentAdded is nil")
    func decodeTorrentDuplicate() throws {
        let data = try fixture(named: "torrent-add-duplicate")
        let response = try JSONDecoder().decode(RPCResponse<TorrentAddResponse>.self, from: data)
        let dup = try #require(response.arguments.torrentDuplicate)
        #expect(dup.id == 42)
        #expect(dup.name == "My Test Torrent")
        #expect(response.arguments.torrentAdded == nil)
    }
}

// MARK: - TorrentSetArguments encode

@Suite("TorrentSetArguments encode")
struct TorrentSetArgumentsEncodeTests {
    private func encoded(_ args: TorrentSetArguments) throws -> [String: Any] {
        let data = try JSONEncoder().encode(args)
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    @Test("nil optional fields are absent from the encoded JSON")
    func nilFieldsAbsent() throws {
        var args = TorrentSetArguments(ids: [1])
        args.downloadLimit = 500
        let json = try encoded(args)
        #expect(json["downloadLimit"] as? Int == 500)
        #expect(json["uploadLimit"] == nil)
        #expect(json["files-wanted"] == nil)
        #expect(json["files-unwanted"] == nil)
        #expect(json["priority-high"] == nil)
    }

    @Test("file-index arrays use kebab-case keys")
    func fileIndexKeyCasing() throws {
        var args = TorrentSetArguments(ids: [7])
        args.filesWanted = [0, 1, 2]
        args.priorityHigh = [0]
        let json = try encoded(args)
        #expect(json["files-wanted"] as? [Int] == [0, 1, 2])
        #expect(json["priority-high"] as? [Int] == [0])
        // camelCase keys should not appear for kebab fields
        #expect(json["filesWanted"] == nil)
        #expect(json["priorityHigh"] == nil)
    }

    @Test("peer-limit uses kebab-case key")
    func peerLimitKey() throws {
        var args = TorrentSetArguments(ids: [3])
        args.peerLimit = 80
        let json = try encoded(args)
        #expect(json["peer-limit"] as? Int == 80)
        #expect(json["peerLimit"] == nil)
    }

    @Test("empty arrays are never emitted for file-index fields")
    func noEmptyArraysForFileIndexFields() throws {
        // A nil [Int]? must not encode to []. Build args with only ids set.
        let args = TorrentSetArguments(ids: [1])
        let json = try encoded(args)
        for key in [
            "files-wanted", "files-unwanted", "priority-high", "priority-normal",
            "priority-low",
        ] {
            let val = json[key]
            if let arr = val as? [Any] {
                Issue.record("Key \(key) was encoded as \(arr) — expected absent")
            }
        }
    }
}

// MARK: - TorrentAddArguments encode

@Suite("TorrentAddArguments encode")
struct TorrentAddArgumentsEncodeTests {
    private func encoded(_ args: TorrentAddArguments) throws -> [String: Any] {
        let data = try JSONEncoder().encode(args)
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    @Test("startWhenAdded:true encodes as paused:false")
    func startWhenAddedTrue() throws {
        let args = TorrentAddArguments(filename: "magnet:?xt=test", paused: false)
        let json = try encoded(args)
        #expect(json["paused"] as? Bool == false)
    }

    @Test("startWhenAdded:false encodes as paused:true")
    func startWhenAddedFalse() throws {
        let args = TorrentAddArguments(filename: "magnet:?xt=test", paused: true)
        let json = try encoded(args)
        #expect(json["paused"] as? Bool == true)
    }

    @Test("download-dir uses kebab-case key")
    func downloadDirKey() throws {
        let args = TorrentAddArguments(filename: "magnet:?xt=test", downloadDir: "/tmp/downloads")
        let json = try encoded(args)
        #expect(json["download-dir"] as? String == "/tmp/downloads")
        #expect(json["downloadDir"] == nil)
    }

    @Test("nil fields are absent — metainfo omitted when filename is set")
    func nilFieldsAbsent() throws {
        let args = TorrentAddArguments(filename: "magnet:?xt=test")
        let json = try encoded(args)
        #expect(json["filename"] as? String == "magnet:?xt=test")
        #expect(json["metainfo"] == nil)
        #expect(json["labels"] == nil)
        #expect(json["paused"] == nil)
    }
}
