import Foundation
import Testing

@testable import TransmissionCore

@Suite("TagColorStore")
struct TagColorStoreTests {
    @MainActor
    private func makeStore() -> (TagColorStore, UserDefaults) {
        let suite = "tag-color-store-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (TagColorStore(userDefaults: defaults), defaults)
    }

    @Test("starts empty and returns nil for unknown tags")
    @MainActor
    func startsEmpty() {
        let (store, _) = makeStore()
        #expect(store.color(for: "Linux") == nil)
        #expect(store.coloredLabels.isEmpty)
    }

    @Test("setColor stores and color(for:) reads back")
    @MainActor
    func setAndRead() {
        let (store, _) = makeStore()
        store.setColor(.blue, for: "Linux")
        #expect(store.color(for: "Linux") == .blue)
        #expect(store.coloredLabels == ["Linux"])
    }

    @Test("setting nil clears the colour")
    @MainActor
    func clear() {
        let (store, _) = makeStore()
        store.setColor(.blue, for: "Linux")
        store.setColor(nil, for: "Linux")
        #expect(store.color(for: "Linux") == nil)
        #expect(store.coloredLabels.isEmpty)
    }

    @Test("keys are whitespace-normalized")
    @MainActor
    func whitespaceNormalization() {
        let (store, _) = makeStore()
        store.setColor(.green, for: "  Media ")
        #expect(store.color(for: "Media") == .green)
        #expect(store.color(for: "  Media ") == .green)
    }

    @Test("empty or blank keys are ignored")
    @MainActor
    func blankKeysIgnored() {
        let (store, _) = makeStore()
        store.setColor(.red, for: "   ")
        #expect(store.colors.isEmpty)
    }

    @Test("colours persist across store instances sharing the same defaults")
    @MainActor
    func persistence() {
        let suite = "tag-color-store-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let first = TagColorStore(userDefaults: defaults)
        first.setColor(.orange, for: "Linux")
        first.setColor(.purple, for: "Media")

        let second = TagColorStore(userDefaults: defaults)
        #expect(second.color(for: "Linux") == .orange)
        #expect(second.color(for: "Media") == .purple)

        defaults.removePersistentDomain(forName: suite)
    }

    @Test("multiple tags can carry different colours")
    @MainActor
    func multipleColours() {
        let (store, _) = makeStore()
        store.setColor(.red, for: "Linux")
        store.setColor(.blue, for: "3D")
        store.setColor(.yellow, for: "Media")
        #expect(store.color(for: "Linux") == .red)
        #expect(store.color(for: "3D") == .blue)
        #expect(store.color(for: "Media") == .yellow)
        #expect(store.coloredLabels == ["3D", "Linux", "Media"])
    }

    @Test("seed replaces the in-memory map without persisting")
    @MainActor
    func seedReplacesWithoutPersisting() {
        let (store, defaults) = makeStore()
        store.setColor(.red, for: "Linux")
        store.seed(["Media": .blue, "3D": .green])

        #expect(store.color(for: "Media") == .blue)
        #expect(store.color(for: "3D") == .green)
        #expect(store.color(for: "Linux") == nil)
        // The seed wrote nothing: defaults still hold exactly the pre-seed state.
        let persisted =
            defaults.data(forKey: "tagColors")
            .flatMap { try? JSONDecoder().decode([String: TagColor].self, from: $0) }
        #expect(persisted == ["Linux": .red])
    }
}
