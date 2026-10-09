import Foundation
import Observation
import TransmissionCore

/// Field state for one Add/Edit session of the mapping editor. A new instance
/// is created on every open and seeded from the mapping being edited, so the
/// sheet's fields never carry stale values from a previous presentation.
@Observable
final class MappingEditorModel: Identifiable {
    let id = UUID()
    /// The mapping being edited, if any; nil when adding a new one.
    let existing: OpenMapping?
    var name: String
    var template: String
    var action: OpenMappingAction
    var applicationBundleID: String?
    /// Which servers this mapping applies to.
    var scope: MappingServerScope
    /// Persisted so editing a mapping doesn't drop its file-access grants; also
    /// the test/preview never touches them.
    var accessBookmarks: [Data]
    var testMessage: String?
    var testFailed = false

    init(existing: OpenMapping?) {
        self.existing = existing
        name = existing?.name ?? ""
        template = existing?.template ?? ""
        action = existing?.action ?? .open
        applicationBundleID = existing?.applicationBundleID
        scope = existing?.scope ?? .all
        accessBookmarks = existing?.accessBookmarks ?? []
    }

    func resetTestState() {
        testMessage = nil
        testFailed = false
    }

    /// The folders stored access bookmarks point at, for display. Resolving
    /// decodes the bookmark data and needs no active scope.
    var accessGrantedPaths: [String] {
        accessBookmarks.compactMap { MappingLauncher.resolveBookmark($0)?.path }
    }
}
