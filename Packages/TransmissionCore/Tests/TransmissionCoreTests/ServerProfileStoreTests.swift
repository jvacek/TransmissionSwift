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
                OpenMapping(name: "Finder", template: "file:///Volumes/transmission/{folder}"),
                OpenMapping(
                    name: "Web", template: "https://{host}/downloads/{folder}/",
                    applicationBundleID: "com.google.Chrome"),
            ])
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(ServerProfile.self, from: data)
        #expect(decoded == profile)
        #expect(decoded.mappings.count == 2)
        #expect(decoded.mappings[1].applicationBundleID == "com.google.Chrome")
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
}
