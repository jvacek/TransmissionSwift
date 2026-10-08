import Testing
import TransmissionCore

@testable import TransmissionSwift

/// The row context-menu enablement matrix. The `Coordinator` maps this spec to
/// `NSMenuItem`s, so the capability rules are pinned here without a window.
@Suite("TorrentRowMenu")
struct TorrentRowMenuTests {
    private func menuItems(
        ids: [Torrent.ID] = [1],
        priorities: [TorrentPriority] = [.normal],
        actionsEnabled: Bool = true,
        labelsSupported: Bool = true,
        mappings: [OpenMapping] = []
    ) -> [TorrentRowMenuItem] {
        TorrentRowMenu.items(
            ids: ids,
            priorities: priorities,
            actionsEnabled: actionsEnabled,
            labelsSupported: labelsSupported,
            mappings: mappings)
    }

    private func enabled(
        _ items: [TorrentRowMenuItem], _ kind: TorrentRowMenuItem.Kind
    ) -> Bool? {
        items.first { $0.kind == kind }?.isEnabled
    }

    private func isMapping(_ item: TorrentRowMenuItem) -> Bool {
        if case .mapping = item.kind { return true }
        return false
    }

    @Test func rowMenu_disablesActionsWithoutTargets() {
        let items = menuItems(ids: [])
        #expect(enabled(items, .resume) == false)
        #expect(enabled(items, .pause) == false)
        #expect(enabled(items, .verify) == false)
        #expect(enabled(items, .remove) == false)
        #expect(enabled(items, .removeAndDeleteData) == false)
    }

    @Test func rowMenu_disablesActionsWhenMutationsAreOff() {
        let items = menuItems(actionsEnabled: false)
        #expect(enabled(items, .resume) == false)
        #expect(enabled(items, .setLocation) == false)
    }

    @Test func rowMenu_gatesEditLabelsOnLabelSupport() {
        #expect(enabled(menuItems(labelsSupported: false), .editLabels) == false)
        #expect(enabled(menuItems(labelsSupported: true), .editLabels) == true)
    }

    @Test func rowMenu_singleTargetGatesRenameAndMappings() {
        let mapping = OpenMapping(name: "Cyberduck", template: "sftp://{host}/{file}")
        let single = menuItems(ids: [1], mappings: [mapping])
        #expect(enabled(single, .rename) == true)
        #expect(enabled(single, .mapping(mapping)) == true)

        let multi = menuItems(ids: [1, 2], priorities: [.normal, .normal], mappings: [mapping])
        #expect(enabled(multi, .rename) == false)
        #expect(enabled(multi, .mapping(mapping)) == false)
    }

    @Test func rowMenu_onlyListsMappingsWhenPresent() {
        #expect(!menuItems(mappings: []).contains(where: isMapping))
        let mapping = OpenMapping(name: "Finder", template: "file:///{file}", action: .finder)
        #expect(menuItems(mappings: [mapping]).contains(where: isMapping))
    }

    @Test func rowMenu_checksTheUniformPriorityOnly() {
        let uniform = menuItems(ids: [1, 2], priorities: [.high, .high])
        #expect(uniform.first { $0.kind == .priority(.high) }?.isChecked == true)
        #expect(uniform.first { $0.kind == .priority(.low) }?.isChecked == false)

        let mixed = menuItems(ids: [1, 2], priorities: [.high, .low])
        #expect(
            !mixed.contains {
                if case .priority = $0.kind { return $0.isChecked } else { return false }
            })
    }
}
