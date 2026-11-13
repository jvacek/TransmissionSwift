// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Observation

/// Owns the list of server profiles, persisted as JSON. Analogous to a tiny
/// repository over a config file — every mutation writes through to disk.
@MainActor
@Observable
public final class ServerProfileStore {
    public private(set) var profiles: [ServerProfile] = []
    public private(set) var activeProfileID: UUID?

    private let fileURL: URL

    /// The active profile, falling back to the first profile when no explicit
    /// active ID is set.
    public var activeProfile: ServerProfile? {
        if let id = activeProfileID, let match = profiles.first(where: { $0.id == id }) {
            return match
        }
        return profiles.first
    }

    public nonisolated static func defaultFileURL() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        return
            appSupport
            .appendingPathComponent("TransmissionSwift", isDirectory: true)
            .appendingPathComponent("servers.json")
    }

    /// Reads the profile list and active selection straight from disk, without
    /// constructing the `@MainActor` store. Used by App Intents, which run
    /// outside the SwiftUI object graph. A missing or corrupt file yields an
    /// empty list — same as a fresh install.
    public nonisolated static func readProfiles(from fileURL: URL) -> (
        profiles: [ServerProfile], activeProfileID: UUID?
    ) {
        guard let stored = try? Self.read(from: fileURL) else { return ([], nil) }
        return (stored.profiles, stored.activeProfileID)
    }

    /// - Parameter fileURL: injectable so tests can point at a temp file.
    public init(fileURL: URL) {
        self.fileURL = fileURL
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let stored = try Self.read(from: fileURL)
            self.profiles = stored.profiles
            self.activeProfileID = stored.activeProfileID
        } catch {
            // A corrupt or newer-schema file must not become an empty profile
            // list: the next mutation would atomically overwrite it. Move it
            // aside so the user can recover it, then start fresh.
            Self.quarantine(fileURL)
        }
    }

    public func add(_ profile: ServerProfile) throws {
        try persistMutation {
            profiles.append(profile)
            if activeProfileID == nil { activeProfileID = profile.id }
        }
    }

    public func update(_ profile: ServerProfile) throws {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        try persistMutation {
            profiles[index] = profile
        }
    }

    public func remove(id: UUID) throws {
        try persistMutation {
            profiles.removeAll { $0.id == id }
            if activeProfileID == id {
                activeProfileID = profiles.first?.id
            }
        }
    }

    public func setActive(_ id: UUID) throws {
        guard profiles.contains(where: { $0.id == id }) else { return }
        try persistMutation {
            activeProfileID = id
        }
    }

    /// Creates a copy of the profile with a fresh ID, appends it, and persists.
    /// Returns the new profile, or nil when no profile has that id.
    @discardableResult
    public func duplicate(id: UUID) throws -> ServerProfile? {
        guard let original = profiles.first(where: { $0.id == id }) else { return nil }
        let copy = ServerProfile(
            id: UUID(),
            label: "\(original.label) (Copy)",
            host: original.host,
            port: original.port,
            rpcPath: original.rpcPath,
            username: original.username,
            useHTTPS: original.useHTTPS)
        try persistMutation {
            profiles.append(copy)
        }
        return copy
    }

    // MARK: - Persistence

    private struct PersistedData: Codable {
        var profiles: [ServerProfile]
        var activeProfileID: UUID?
        var schemaVersion: Int

        init(profiles: [ServerProfile], activeProfileID: UUID?) {
            self.profiles = profiles
            self.activeProfileID = activeProfileID
            self.schemaVersion = 1
        }

        enum CodingKeys: String, CodingKey {
            case profiles, activeProfileID, schemaVersion
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            profiles = try container.decode([ServerProfile].self, forKey: .profiles)
            activeProfileID = try container.decodeIfPresent(UUID.self, forKey: .activeProfileID)
            schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        }
    }

    private nonisolated static func read(from fileURL: URL) throws -> PersistedData {
        let data = try Data(contentsOf: fileURL)
        // Prefer the new envelope; fall back to the legacy flat array.
        if let persisted = try? JSONDecoder().decode(PersistedData.self, from: data) {
            // A newer build may have written fields this version would drop on
            // the next save. Refuse it rather than silently downgrading.
            guard persisted.schemaVersion <= 1 else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return persisted
        }
        let profiles = try JSONDecoder().decode([ServerProfile].self, from: data)
        return PersistedData(profiles: profiles, activeProfileID: nil)
    }

    /// Applies an in-memory mutation and writes it, restoring the previous
    /// state when the write fails so the UI never shows a change that did not
    /// reach disk.
    private func persistMutation(_ body: () -> Void) throws {
        let previousProfiles = profiles
        let previousActiveID = activeProfileID
        body()
        do {
            try persist()
        } catch {
            profiles = previousProfiles
            activeProfileID = previousActiveID
            throw error
        }
    }

    private nonisolated static func quarantine(_ fileURL: URL) {
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backup = fileURL.deletingLastPathComponent()
            .appendingPathComponent("\(fileURL.lastPathComponent).corrupt-\(stamp)")
        try? FileManager.default.moveItem(at: fileURL, to: backup)
    }

    private func persist() throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = PersistedData(profiles: profiles, activeProfileID: activeProfileID)
        try encoder.encode(data).write(to: fileURL, options: .atomic)
    }
}
