// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

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

    @Test("duplicate copies the profile with a fresh ID")
    @MainActor
    func duplicate() throws {
        let fileURL = tempFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let original = ServerProfile(
            label: "Home NAS", host: "nas.local", port: 9092,
            rpcPath: "/transmission/rpc", username: "dev", useHTTPS: true)

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

    @Test("a corrupt profile file is quarantined, not overwritten")
    @MainActor
    func corruptFileQuarantined() throws {
        let fileURL = tempFileURL()
        let directory = fileURL.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: fileURL)

        let store = ServerProfileStore(fileURL: fileURL)
        #expect(store.profiles.isEmpty)

        let backups = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("servers.json.corrupt-") }
        #expect(backups.count == 1)
        let backup = try #require(backups.first)
        #expect(store.loadError == .quarantined(backupName: backup))
        #expect(store.loadError?.localizedDescription.contains(backup) == true)

        store.acknowledgeLoadError()
        #expect(store.loadError == nil)

        // The next write starts a fresh, valid file.
        try store.add(ServerProfile(label: "New", host: "nas.local"))
        #expect(ServerProfileStore(fileURL: fileURL).profiles.count == 1)
    }

    @Test("a corrupt file that cannot be moved aside is never overwritten")
    @MainActor
    func unmovableCorruptFileBlocksWrites() throws {
        let fileURL = tempFileURL()
        let directory = fileURL.deletingLastPathComponent()
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let corrupt = Data("{ not json".utf8)
        try corrupt.write(to: fileURL)
        // A read-only folder lets the file be read but not renamed.
        try manager.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        defer {
            try? manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
            try? manager.removeItem(at: directory)
        }

        let store = ServerProfileStore(fileURL: fileURL)
        #expect(store.profiles.isEmpty)
        #expect(store.loadError == .unreadableNotMoved(fileName: "servers.json"))

        store.acknowledgeLoadError()
        #expect(throws: ServerProfileLoadError.unreadableNotMoved(fileName: "servers.json")) {
            try store.add(ServerProfile(label: "New", host: "nas.local"))
        }
        #expect(store.profiles.isEmpty)
        #expect(try Data(contentsOf: fileURL) == corrupt)
    }

    @Test("a failed write restores the previous profile list")
    @MainActor
    func failedWriteRollsBack() throws {
        let fileURL = tempFileURL()
        let directory = fileURL.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: directory) }
        // A file where the parent directory should be makes createDirectory fail.
        try Data().write(to: directory)

        let store = ServerProfileStore(fileURL: fileURL)
        do {
            try store.add(ServerProfile(label: "New", host: "nas.local"))
            Issue.record("add should have thrown")
        } catch {
            // expected
        }
        #expect(store.profiles.isEmpty)
    }

    @Test("rpcURL is assembled from profile fields")
    func rpcURL() {
        let profile = ServerProfile(
            label: "x", host: "example.com", port: 9092, rpcPath: "transmission/rpc",
            useHTTPS: true)
        #expect(profile.rpcURL?.absoluteString == "https://example.com:9092/transmission/rpc")
    }

    @Test("a legacy servers.json carrying mappings still decodes the profile")
    @MainActor
    func legacyMappingsKeyIsIgnored() throws {
        let id = UUID()
        let json = """
            {
              "profiles": [
                {
                  "id": "\(id.uuidString)",
                  "label": "Legacy",
                  "host": "nas.local",
                  "port": 9091,
                  "rpcPath": "/transmission/rpc",
                  "username": "dev",
                  "useHTTPS": false,
                  "mappings": [
                    { "id": "\(UUID().uuidString)", "name": "Finder",
                      "template": "file:///{download-dir}", "action": "finder" }
                  ]
                }
              ]
            }
            """
        let fileURL = tempFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(json.utf8).write(to: fileURL)

        let store = ServerProfileStore(fileURL: fileURL)
        #expect(store.profiles.first?.id == id)
        #expect(store.profiles.first?.host == "nas.local")
    }
}
