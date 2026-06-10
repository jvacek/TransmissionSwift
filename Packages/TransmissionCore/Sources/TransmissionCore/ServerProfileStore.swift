import Foundation
import Observation

/// Owns the list of server profiles, persisted as JSON. Analogous to a tiny
/// repository over a config file — every mutation writes through to disk.
@MainActor
@Observable
public final class ServerProfileStore {
    public private(set) var profiles: [ServerProfile] = []

    private let fileURL: URL

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
        self.profiles = (try? Self.read(from: fileURL)) ?? []
    }

    public func add(_ profile: ServerProfile) throws {
        profiles.append(profile)
        try persist()
    }

    public func update(_ profile: ServerProfile) throws {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index] = profile
        try persist()
    }

    public func remove(id: UUID) throws {
        profiles.removeAll { $0.id == id }
        try persist()
    }

    private static func read(from fileURL: URL) throws -> [ServerProfile] {
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([ServerProfile].self, from: data)
    }

    private func persist() throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(profiles).write(to: fileURL, options: .atomic)
    }
}
