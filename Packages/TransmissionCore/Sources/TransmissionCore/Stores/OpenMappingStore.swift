import Foundation
import Observation

/// Owns the app-wide "Open with…" mappings, persisted as JSON. Unlike the
/// per-server arrangement this replaced, each mapping carries a
/// `MappingServerScope` saying which servers it applies to.
@MainActor
@Observable
public final class OpenMappingStore {
    public private(set) var mappings: [OpenMapping] = []

    private let fileURL: URL

    public nonisolated static func defaultFileURL() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        return
            appSupport
            .appendingPathComponent("TransmissionSwift", isDirectory: true)
            .appendingPathComponent("mappings.json")
    }

    /// Loads the store, or an empty list when the file doesn't exist yet.
    /// Migration is explicit (see the convenience init) so a test pointing at a
    /// temp file never reads the real `servers.json`.
    public init(fileURL: URL) {
        self.fileURL = fileURL
        mappings = (try? Self.read(from: fileURL)) ?? []
    }

    /// First-run migration: when `mappings.json` doesn't exist yet, import every
    /// per-server mapping from `legacyServersURL`, scoped to its server so
    /// behaviour is unchanged, and write the file (even when empty) so this runs
    /// once and never resurrects stale per-server data.
    public convenience init(fileURL: URL, migratingFrom legacyServersURL: URL) {
        let firstRun = !FileManager.default.fileExists(atPath: fileURL.path)
        self.init(fileURL: fileURL)
        guard firstRun else { return }
        mappings = Self.importLegacy(from: legacyServersURL)
        try? persist()
    }

    /// The mappings that apply to `server`, in order.
    public func mappings(for server: ServerProfile) -> [OpenMapping] {
        mappings.filter { $0.scope.includes(server) }
    }

    public func add(_ mapping: OpenMapping) throws {
        mappings.append(mapping)
        try persist()
    }

    public func update(_ mapping: OpenMapping) throws {
        guard let index = mappings.firstIndex(where: { $0.id == mapping.id }) else { return }
        mappings[index] = mapping
        try persist()
    }

    public func remove(id: UUID) throws {
        mappings.removeAll { $0.id == id }
        try persist()
    }

    /// Replaces a single mapping (used when a mapping gains a file-access
    /// bookmark during an open) and persists. No-op when it can't be found.
    public func replace(_ mapping: OpenMapping) throws {
        guard let index = mappings.firstIndex(where: { $0.id == mapping.id }) else { return }
        mappings[index] = mapping
        try persist()
    }

    // MARK: - Persistence

    /// Merges every profile's mappings. Identical mappings (same name, template,
    /// action, app and file-access grants) collapse into one entry scoped to
    /// every server that carried it; when that is every server, the scope is
    /// `.all` rather than listing them. Each entry gets a fresh id so an id
    /// reused across profiles can't collide app-wide.
    private nonisolated static func importLegacy(from fileURL: URL) -> [OpenMapping] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        // Envelope first, then the pre-envelope flat array — same fallback as
        // ServerProfileStore.read(from:).
        let profiles =
            (try? decoder.decode(LegacyEnvelope.self, from: data))?.profiles
            ?? (try? decoder.decode([LegacyProfile].self, from: data))
            ?? []
        let allServerIDs = Set(profiles.map(\.id))

        // Insertion-ordered identities, with the servers each was seen on.
        var order: [MappingIdentity] = []
        var firstByID: [MappingIdentity: OpenMapping] = [:]
        var serversByID: [MappingIdentity: Set<UUID>] = [:]

        for profile in profiles {
            for legacy in profile.mappings ?? [] {
                let identity = MappingIdentity(legacy)
                if firstByID[identity] == nil {
                    order.append(identity)
                    firstByID[identity] = legacy
                    serversByID[identity] = []
                }
                serversByID[identity]?.insert(profile.id)
            }
        }

        return order.compactMap { identity in
            guard var mapping = firstByID[identity], let servers = serversByID[identity]
            else { return nil }
            mapping.id = UUID()
            mapping.scope = (!allServerIDs.isEmpty && servers == allServerIDs) ? .all : .only(servers)
            return mapping
        }
    }

    private nonisolated static func read(from fileURL: URL) throws -> [OpenMapping] {
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([OpenMapping].self, from: data)
    }

    private func persist() throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(mappings).write(to: fileURL, options: .atomic)
    }
}

/// Only the fields migration needs; the current `ServerProfile` no longer
/// carries mappings, so this reads the legacy shape without re-encoding it.
/// File-scope (not nested in the `@MainActor` store) so the nonisolated import
/// can use it.
private struct LegacyEnvelope: Decodable { var profiles: [LegacyProfile] }
private struct LegacyProfile: Decodable {
    var id: UUID
    var mappings: [OpenMapping]?
}

/// A mapping's content, ignoring `id` and `scope`, so identical mappings on
/// different servers collapse into one entry during migration.
private struct MappingIdentity: Hashable {
    var name: String
    var template: String
    var action: OpenMappingAction
    var applicationBundleID: String?
    var accessBookmarks: [Data]

    init(_ mapping: OpenMapping) {
        name = mapping.name
        template = mapping.template
        action = mapping.action
        applicationBundleID = mapping.applicationBundleID
        accessBookmarks = mapping.accessBookmarks
    }
}
