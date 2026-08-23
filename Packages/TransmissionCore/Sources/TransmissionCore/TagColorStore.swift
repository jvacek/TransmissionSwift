import Foundation
import Observation

/// Local, per-tag colour assignments (Finder-style tag colours). Persisted as a
/// JSON `[String: TagColor]` blob in `UserDefaults` — a UI preference, exactly
/// like `TablePreferences`. Keys are tag names as reported by the daemon,
/// whitespace-normalized so " Media" and "Media" can't diverge.
///
/// Colour is assigned by tag name, not by torrent, so the same tag keeps its
/// colour across servers and across torrents. "No colour" is an absent entry.
@MainActor
@Observable
public final class TagColorStore {
    public private(set) var colors: [String: TagColor] = [:]

    private let userDefaults: UserDefaults
    private static let storageKey = "tagColors"

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        load()
    }

    /// The colour assigned to `label`, or nil when the tag is uncoloured.
    public func color(for label: String) -> TagColor? {
        colors[Self.normalized(label)]
    }

    /// Assign a colour to `label`, or clear it when `color` is nil.
    public func setColor(_ color: TagColor?, for label: String) {
        let key = Self.normalized(label)
        guard !key.isEmpty else { return }
        if let color {
            colors[key] = color
        } else {
            colors.removeValue(forKey: key)
        }
        save()
    }

    /// All tags that currently have a colour, sorted by name. Lets the Tags
    /// settings pane show pre-coloured tags even when no torrent uses them.
    public var coloredLabels: [String] {
        colors.keys.sorted()
    }

    /// Replaces the in-memory assignments without persisting — used to seed the
    /// store from a snapshot's captured colours on replay. The user's own
    /// `UserDefaults` prefs stay untouched until they actually edit a colour
    /// (at which point `setColor` persists the merged set, as usual).
    public func seed(_ colors: [String: TagColor]) {
        self.colors = colors
    }

    private func load() {
        guard let data = userDefaults.data(forKey: Self.storageKey),
            let decoded = try? JSONDecoder().decode([String: TagColor].self, from: data)
        else { return }
        colors = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(colors) else { return }
        userDefaults.set(data, forKey: Self.storageKey)
    }

    private static func normalized(_ label: String) -> String {
        label.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
