import Foundation
import Testing

@testable import TransmissionCore

@Suite("ServerProfileStore")
struct ServerProfileStoreTests {

    private func tempFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ServerProfileStoreTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("servers.json")
    }

    @Test("profiles round-trip through the JSON file")
    @MainActor
    func roundTrip() throws {
        let fileURL = tempFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let profile = ServerProfile(
            label: "Home NAS", host: "nas.local", port: 9091,
            username: "dev", useHTTPS: false)

        let store = ServerProfileStore(fileURL: fileURL)
        try store.add(profile)

        let reloaded = ServerProfileStore(fileURL: fileURL)
        #expect(reloaded.profiles == [profile])

        var renamed = profile
        renamed.label = "Office"
        try reloaded.update(renamed)
        #expect(ServerProfileStore(fileURL: fileURL).profiles == [renamed])

        try reloaded.remove(id: profile.id)
        #expect(ServerProfileStore(fileURL: fileURL).profiles.isEmpty)
    }

    @Test("duplicate copies the profile and its mappings with fresh IDs")
    @MainActor
    func duplicate() throws {
        let fileURL = tempFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let original = ServerProfile(
            label: "Home NAS", host: "nas.local", port: 9092,
            rpcPath: "/transmission/rpc", username: "dev", useHTTPS: true,
            mappings: [
                OpenMapping(
                    name: "Finder", template: "file:///Volumes/transmission/{folder}",
                    action: .finder),
                OpenMapping(
                    name: "Web", template: "https://{host}/downloads/{folder}/",
                    applicationBundleID: "com.google.Chrome"),
            ])

        let store = ServerProfileStore(fileURL: fileURL)
        try store.add(original)

        guard let copy = try store.duplicate(id: original.id) else {
            Issue.record("duplicate returned nil")
            return
        }

        #expect(copy.id != original.id)
        #expect(copy.label == "Home NAS (Copy)")
        #expect(copy.host == original.host)
        #expect(copy.port == original.port)
        #expect(copy.rpcPath == original.rpcPath)
        #expect(copy.username == original.username)
        #expect(copy.useHTTPS == original.useHTTPS)

        #expect(copy.mappings.count == original.mappings.count)
        #expect(copy.mappings[0].name == "Finder")
        #expect(copy.mappings[0].template == "file:///Volumes/transmission/{folder}")
        #expect(copy.mappings[0].action == .finder)
        #expect(copy.mappings[1].action == .open)
        #expect(copy.mappings[1].applicationBundleID == "com.google.Chrome")
        #expect(copy.mappings[0].id != original.mappings[0].id)
        #expect(copy.mappings[1].id != original.mappings[1].id)

        #expect(store.profiles.count == 2)
        #expect(store.profiles.contains(copy))
        #expect(ServerProfileStore(fileURL: fileURL).profiles.contains(copy))

        #expect(try store.duplicate(id: UUID()) == nil)
    }

    @Test("missing file yields an empty profile list")
    @MainActor
    func missingFile() {
        let store = ServerProfileStore(fileURL: tempFileURL())
        #expect(store.profiles.isEmpty)
    }

    @Test("rpcURL is assembled from profile fields")
    func rpcURL() {
        let profile = ServerProfile(
            label: "x", host: "example.com", port: 9092, rpcPath: "transmission/rpc",
            useHTTPS: true)
        #expect(profile.rpcURL?.absoluteString == "https://example.com:9092/transmission/rpc")
    }

    @Test("profiles without a mappings key decode to empty mappings (backward compat)")
    func backwardCompatibleDecode() throws {
        let json = """
            {
              "id": "\(UUID().uuidString)",
              "label": "Legacy",
              "host": "nas.local",
              "port": 9091,
              "rpcPath": "/transmission/rpc",
              "username": "dev",
              "useHTTPS": false
            }
            """
        let profile = try JSONDecoder().decode(
            ServerProfile.self, from: Data(json.utf8))
        #expect(profile.mappings.isEmpty)
        #expect(profile.host == "nas.local")
    }

    @Test("mappings round-trip through JSON encoding")
    func mappingsRoundTrip() throws {
        let profile = ServerProfile(
            label: "x", host: "nas.local",
            mappings: [
                OpenMapping(
                    name: "Finder", template: "file:///Volumes/transmission/{folder}",
                    action: .finder),
                OpenMapping(
                    name: "Web", template: "https://{host}/downloads/{folder}/",
                    applicationBundleID: "com.google.Chrome"),
            ])
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(ServerProfile.self, from: data)
        #expect(decoded == profile)
        #expect(decoded.mappings.count == 2)
        #expect(decoded.mappings[0].action == .finder)
        #expect(decoded.mappings[1].action == .open)
        #expect(decoded.mappings[1].applicationBundleID == "com.google.Chrome")
    }

    @Test("mappings without an action key decode to .open (backward compat)")
    func mappingActionBackwardCompatibleDecode() throws {
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
        #expect(mapping.name == "Finder")
    }

    @Test("mappings without an applicationBundleID key decode to nil (backward compat)")
    func mappingBackwardCompatibleDecode() throws {
        let json = """
            {
              "id": "\(UUID().uuidString)",
              "name": "Finder",
              "template": "file:///Volumes/transmission/{folder}"
            }
            """
        let mapping = try JSONDecoder().decode(OpenMapping.self, from: Data(json.utf8))
        #expect(mapping.applicationBundleID == nil)
        #expect(mapping.name == "Finder")
    }

    @Test("mapping accessBookmark round-trips through JSON")
    func mappingBookmarkRoundTrip() throws {
        let mapping = OpenMapping(
            name: "VLC", template: "file:///{download-dir}/{file}",
            applicationBundleID: "org.videolan.vlc",
            accessBookmark: Data([0xDE, 0xAD, 0xBE, 0xEF]))
        let data = try JSONEncoder().encode(mapping)
        let decoded = try JSONDecoder().decode(OpenMapping.self, from: data)
        #expect(decoded == mapping)
        #expect(decoded.accessBookmark == Data([0xDE, 0xAD, 0xBE, 0xEF]))
    }

    @Test("mappings without an accessBookmark key decode to nil (backward compat)")
    func mappingBookmarkBackwardCompatibleDecode() throws {
        let json = """
            {
              "id": "\(UUID().uuidString)",
              "name": "VLC",
              "template": "file:///{download-dir}/{file}",
              "action": "open"
            }
            """
        let mapping = try JSONDecoder().decode(OpenMapping.self, from: Data(json.utf8))
        #expect(mapping.accessBookmark == nil)
        #expect(mapping.applicationBundleID == nil)
    }

    @Test("replaceMapping updates and persists a single mapping")
    @MainActor
    func replaceMapping() throws {
        let fileURL = tempFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let profile = ServerProfile(
            label: "Home NAS", host: "nas.local", port: 9091,
            mappings: [
                OpenMapping(name: "Finder", template: "file:///{download-dir}", action: .finder),
                OpenMapping(name: "VLC", template: "file:///{download-dir}/{file}"),
            ])
        let store = ServerProfileStore(fileURL: fileURL)
        try store.add(profile)

        var updated = profile.mappings[1]
        updated.accessBookmark = Data([0x00, 0x01, 0x02])
        try store.replaceMapping(updated, inProfile: profile.id)

        let reloaded = ServerProfileStore(fileURL: fileURL)
        #expect(reloaded.profiles.first?.mappings[1].accessBookmark == Data([0x00, 0x01, 0x02]))
        #expect(reloaded.profiles.first?.mappings[0].accessBookmark == nil)
    }
}
