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

    public static func defaultFileURL() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        return
            appSupport
            .appendingPathComponent("TransmissionSwift", isDirectory: true)
            .appendingPathComponent("servers.json")
    }

    /// - Parameter fileURL: injectable so tests can point at a temp file.
    public init(fileURL: URL) {
        self.fileURL = fileURL
        let stored = (try? Self.read(from: fileURL)) ?? PersistedData()
        self.profiles = stored.profiles
        self.activeProfileID = stored.activeProfileID
    }

    public func add(_ profile: ServerProfile) throws {
        profiles.append(profile)
        if activeProfileID == nil { activeProfileID = profile.id }
        try persist()
    }

    public func update(_ profile: ServerProfile) throws {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index] = profile
        try persist()
    }

    public func remove(id: UUID) throws {
        profiles.removeAll { $0.id == id }
        if activeProfileID == id {
            activeProfileID = profiles.first?.id
        }
        try persist()
    }

    public func setActive(_ id: UUID) throws {
        guard profiles.contains(where: { $0.id == id }) else { return }
        activeProfileID = id
        try persist()
    }

    // MARK: - Persistence

    private struct PersistedData: Codable {
        var profiles: [ServerProfile] = []
        var activeProfileID: UUID? = nil
    }

    private static func read(from fileURL: URL) throws -> PersistedData {
        let data = try Data(contentsOf: fileURL)
        // Prefer the new envelope; fall back to the legacy flat array.
        if let persisted = try? JSONDecoder().decode(PersistedData.self, from: data) {
            return persisted
        }
        let profiles = try JSONDecoder().decode([ServerProfile].self, from: data)
        return PersistedData(profiles: profiles, activeProfileID: nil)
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
