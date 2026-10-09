import Foundation
import Testing

@testable import TransmissionCore

@Suite("OpenMapping codable")
struct OpenMappingCodableTests {
    @Test("a minimal legacy mapping decodes with defaults")
    func minimalDecode() throws {
        let json = """
            {
              "id": "\(UUID().uuidString)",
              "name": "Finder",
              "template": "file:///Volumes/transmission/{folder}"
            }
            """
        let mapping = try JSONDecoder().decode(OpenMapping.self, from: Data(json.utf8))
        #expect(mapping.action == .open)
        #expect(mapping.applicationBundleID == nil)
        #expect(mapping.scope == .all)
        #expect(mapping.accessBookmarks.isEmpty)
    }

    @Test("scope round-trips through JSON")
    func scopeRoundTrip() throws {
        let first = UUID()
        let second = UUID()
        for scope in [
            MappingServerScope.all, .local, .remote, .only([first, second]),
        ] {
            let mapping = OpenMapping(name: "x", template: "file:///", scope: scope)
            let decoded = try JSONDecoder().decode(
                OpenMapping.self, from: JSONEncoder().encode(mapping))
            #expect(decoded.scope == scope)
            #expect(decoded == mapping)
        }
    }

    @Test("an unrecognized scope widens to .all")
    func unknownScope() throws {
        let json = """
            { "id": "\(UUID().uuidString)", "name": "x", "template": "file:///",
              "scope": "nonsense" }
            """
        let mapping = try JSONDecoder().decode(OpenMapping.self, from: Data(json.utf8))
        #expect(mapping.scope == .all)
    }

    @Test("the legacy single accessBookmark folds into accessBookmarks")
    func legacyBookmark() throws {
        let bookmark = Data([0xDE, 0xAD, 0xBE, 0xEF]).base64EncodedString()
        let json = """
            { "id": "\(UUID().uuidString)", "name": "V", "template": "file:///",
              "accessBookmark": "\(bookmark)" }
            """
        let mapping = try JSONDecoder().decode(OpenMapping.self, from: Data(json.utf8))
        #expect(mapping.accessBookmarks == [Data([0xDE, 0xAD, 0xBE, 0xEF])])

        // Re-encoding drops the legacy key; the current key replaces it.
        let reencoded = String(decoding: try JSONEncoder().encode(mapping), as: UTF8.self)
        #expect(!reencoded.contains("\"accessBookmark\""))
        #expect(reencoded.contains("\"accessBookmarks\""))
    }

    @Test("accessBookmarks round-trips through JSON")
    func bookmarksRoundTrip() throws {
        let mapping = OpenMapping(
            name: "VLC", template: "file:///{download-dir}/{file}",
            applicationBundleID: "org.videolan.vlc",
            accessBookmarks: [Data([0x01, 0x02]), Data([0x03])])
        let decoded = try JSONDecoder().decode(
            OpenMapping.self, from: JSONEncoder().encode(mapping))
        #expect(decoded == mapping)
        #expect(decoded.accessBookmarks.count == 2)
    }
}

@Suite("OpenMappingStore")
struct OpenMappingStoreTests {
    /// A fresh temp directory holding both files, so migration can be exercised.
    private func tempURLs() -> (mappings: URL, servers: URL, directory: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenMappingStoreTests-\(UUID().uuidString)", isDirectory: true)
        return (
            directory.appendingPathComponent("mappings.json"),
            directory.appendingPathComponent("servers.json"),
            directory
        )
    }

    private func writeServers(_ json: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(json.utf8).write(to: url)
    }

    @Test("mappings(for:) matches all, local, remote and the selected set, in order")
    @MainActor
    func scopeFilter() throws {
        let urls = tempURLs()
        defer { try? FileManager.default.removeItem(at: urls.directory) }
        let local = ServerProfile(label: "NAS", host: "192.168.1.2")
        let remote = ServerProfile(label: "Seedbox", host: "seedbox.example.com")
        let store = OpenMappingStore(fileURL: urls.mappings)
        try store.add(OpenMapping(name: "everywhere", template: "a", scope: .all))
        try store.add(OpenMapping(name: "locally", template: "b", scope: .local))
        try store.add(OpenMapping(name: "remotely", template: "c", scope: .remote))
        try store.add(OpenMapping(name: "nas-only", template: "d", scope: .only([local.id])))
        try store.add(OpenMapping(name: "nobody", template: "e", scope: .only([])))

        #expect(
            store.mappings(for: local).map(\.name)
                == ["everywhere", "locally", "nas-only"])
        #expect(
            store.mappings(for: remote).map(\.name)
                == ["everywhere", "remotely"])
    }

    @Test("isLocal classifies loopback, private, link-local and .local hosts")
    func hostClassification() {
        for host in [
            "localhost", "127.0.0.1", "::1", "10.0.0.5", "172.16.4.1", "172.31.255.1",
            "192.168.1.2", "169.254.0.1", "nas.local", "fe80::1",
        ] {
            #expect(ServerProfile(label: "x", host: host).isLocal, "\(host) should be local")
        }
        for host in [
            "seedbox.example.com", "8.8.8.8", "172.32.0.1", "192.169.1.1", "203.0.113.9",
        ] {
            #expect(!ServerProfile(label: "x", host: host).isLocal, "\(host) should be remote")
        }
    }

    @Test("first run imports a mapping present on every server as .all")
    @MainActor
    func migratesFromEnvelope() throws {
        let urls = tempURLs()
        defer { try? FileManager.default.removeItem(at: urls.directory) }
        let profileID = UUID()
        try writeServers(
            """
            {
              "profiles": [
                { "id": "\(profileID.uuidString)", "label": "NAS", "host": "nas",
                  "port": 9091, "rpcPath": "/transmission/rpc", "useHTTPS": false,
                  "mappings": [
                    { "id": "\(UUID().uuidString)", "name": "Finder",
                      "template": "file:///Volumes/transmission/{folder}", "action": "finder" }
                  ] }
              ]
            }
            """, to: urls.servers)

        let store = OpenMappingStore(fileURL: urls.mappings, migratingFrom: urls.servers)
        #expect(store.mappings.count == 1)
        #expect(store.mappings[0].name == "Finder")
        #expect(store.mappings[0].action == .finder)
        #expect(store.mappings[0].scope == .all)
        #expect(store.mappings(for: ServerProfile(id: profileID, label: "NAS", host: "nas")).count == 1)

        // Written to disk, and given a fresh id.
        #expect(FileManager.default.fileExists(atPath: urls.mappings.path))
        let reloaded = OpenMappingStore(fileURL: urls.mappings)
        #expect(reloaded.mappings == store.mappings)
    }

    @Test("first run imports from the pre-envelope flat array too")
    @MainActor
    func migratesFromFlatArray() throws {
        let urls = tempURLs()
        defer { try? FileManager.default.removeItem(at: urls.directory) }
        let profileID = UUID()
        try writeServers(
            """
            [
              { "id": "\(profileID.uuidString)", "label": "NAS", "host": "nas",
                "port": 9091, "rpcPath": "/transmission/rpc", "useHTTPS": false,
                "mappings": [
                  { "id": "\(UUID().uuidString)", "name": "Web",
                    "template": "https://{host}/d/{folder}/" }
                ] }
            ]
            """, to: urls.servers)

        let store = OpenMappingStore(fileURL: urls.mappings, migratingFrom: urls.servers)
        #expect(store.mappings.count == 1)
        #expect(store.mappings[0].scope == .all)
    }

    @Test("identical mappings across servers collapse and select those servers")
    @MainActor
    func collapsesIdenticalMappings() throws {
        let urls = tempURLs()
        defer { try? FileManager.default.removeItem(at: urls.directory) }
        let a = UUID()
        let b = UUID()
        let c = UUID()
        // Same name + template; "Everywhere" is on all three, "Web" on A+B,
        // "Finder" on A+C, "VLC" on B.
        let everywhere = #""name": "Everywhere", "template": "https://{host}/x/{file}""#
        let web = #""name": "Web", "template": "https://{host}/d/{file}""#
        let finder = #""name": "Finder", "template": "file:///{file}""#
        let vlc = #""name": "VLC", "template": "file:///{file}", "applicationBundleID": "org.videolan.vlc""#
        try writeServers(
            """
            { "profiles": [
              { "id": "\(a.uuidString)", "label": "A", "host": "a",
                "port": 9091, "rpcPath": "/transmission/rpc", "useHTTPS": false,
                "mappings": [
                  { "id": "\(UUID().uuidString)", \(everywhere) },
                  { "id": "\(UUID().uuidString)", \(web) },
                  { "id": "\(UUID().uuidString)", \(finder) }
                ] },
              { "id": "\(b.uuidString)", "label": "B", "host": "b",
                "port": 9091, "rpcPath": "/transmission/rpc", "useHTTPS": false,
                "mappings": [
                  { "id": "\(UUID().uuidString)", \(everywhere) },
                  { "id": "\(UUID().uuidString)", \(web) },
                  { "id": "\(UUID().uuidString)", \(vlc) }
                ] },
              { "id": "\(c.uuidString)", "label": "C", "host": "c",
                "port": 9091, "rpcPath": "/transmission/rpc", "useHTTPS": false,
                "mappings": [
                  { "id": "\(UUID().uuidString)", \(everywhere) },
                  { "id": "\(UUID().uuidString)", \(finder) }
                ] }
            ] }
            """, to: urls.servers)

        let store = OpenMappingStore(fileURL: urls.mappings, migratingFrom: urls.servers)
        #expect(store.mappings.map(\.name) == ["Everywhere", "Web", "Finder", "VLC"])
        #expect(store.mappings[0].scope == .all)
        #expect(store.mappings[1].scope == .only([a, b]))
        #expect(store.mappings[2].scope == .only([a, c]))
        #expect(store.mappings[3].scope == .only([b]))
    }

    @Test("migration runs once and never resurrects servers.json state")
    @MainActor
    func migratesOnce() throws {
        let urls = tempURLs()
        defer { try? FileManager.default.removeItem(at: urls.directory) }
        try writeServers(
            """
            { "profiles": [ { "id": "\(UUID().uuidString)", "label": "NAS", "host": "nas",
              "port": 9091, "rpcPath": "/transmission/rpc", "useHTTPS": false,
              "mappings": [ { "id": "\(UUID().uuidString)", "name": "Old",
                "template": "file:///old" } ] } ] }
            """, to: urls.servers)

        let first = OpenMappingStore(fileURL: urls.mappings, migratingFrom: urls.servers)
        #expect(first.mappings.map(\.name) == ["Old"])
        try first.remove(id: first.mappings[0].id)
        try first.add(OpenMapping(name: "New", template: "file:///new"))

        let second = OpenMappingStore(fileURL: urls.mappings, migratingFrom: urls.servers)
        #expect(second.mappings.map(\.name) == ["New"])
    }

    @Test("a missing servers.json writes an empty store and doesn't re-run")
    @MainActor
    func missingServersFile() throws {
        let urls = tempURLs()
        defer { try? FileManager.default.removeItem(at: urls.directory) }

        let store = OpenMappingStore(fileURL: urls.mappings, migratingFrom: urls.servers)
        #expect(store.mappings.isEmpty)
        #expect(FileManager.default.fileExists(atPath: urls.mappings.path))
    }

    @Test("replace rewrites a single mapping and persists")
    @MainActor
    func replace() throws {
        let urls = tempURLs()
        defer { try? FileManager.default.removeItem(at: urls.directory) }
        let store = OpenMappingStore(fileURL: urls.mappings)
        try store.add(OpenMapping(name: "VLC", template: "file:///{download-dir}/{file}"))

        var updated = store.mappings[0]
        updated.accessBookmarks = [Data([0x00, 0x01])]
        try store.replace(updated)

        let reloaded = OpenMappingStore(fileURL: urls.mappings)
        #expect(reloaded.mappings.first?.accessBookmarks == [Data([0x00, 0x01])])
    }

    @Test("update and remove persist")
    @MainActor
    func updateRemove() throws {
        let urls = tempURLs()
        defer { try? FileManager.default.removeItem(at: urls.directory) }
        let store = OpenMappingStore(fileURL: urls.mappings)
        try store.add(OpenMapping(name: "a", template: "x"))
        var changed = store.mappings[0]
        changed.name = "b"
        try store.update(changed)
        #expect(OpenMappingStore(fileURL: urls.mappings).mappings.map(\.name) == ["b"])

        try store.remove(id: changed.id)
        #expect(OpenMappingStore(fileURL: urls.mappings).mappings.isEmpty)
    }
}
