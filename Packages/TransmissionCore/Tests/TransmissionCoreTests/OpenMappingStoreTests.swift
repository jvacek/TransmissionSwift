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
        for scope in [MappingServerScope.all, .only([first, second])] {
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

    @Test("mappings(for:) includes .all and matching .only, in order")
    @MainActor
    func scopeFilter() throws {
        let urls = tempURLs()
        defer { try? FileManager.default.removeItem(at: urls.directory) }
        let serverA = UUID()
        let serverB = UUID()
        let store = OpenMappingStore(fileURL: urls.mappings)
        try store.add(OpenMapping(name: "everywhere", template: "a", scope: .all))
        try store.add(OpenMapping(name: "a-only", template: "b", scope: .only([serverA])))
        try store.add(OpenMapping(name: "nobody", template: "c", scope: .only([])))

        #expect(store.mappings(for: serverA).map(\.name) == ["everywhere", "a-only"])
        #expect(store.mappings(for: serverB).map(\.name) == ["everywhere"])
    }

    @Test("first run imports per-server mappings scoped to their server")
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
        #expect(store.mappings[0].scope == .only([profileID]))
        #expect(store.mappings(for: profileID).count == 1)

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
        #expect(store.mappings[0].scope == .only([profileID]))
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
