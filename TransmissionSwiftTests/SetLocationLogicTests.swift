import Testing

@testable import TransmissionSwift

/// Unit coverage for the Set Location sheet's pure logic: the daemon-side path
/// resolver and the "Known folders" suggestion filter. Neither needs a window
/// or a live daemon, so they live here rather than in the UI test suite.
struct SetLocationLogicTests {
    // MARK: - resolveServerPath

    @Test func resolve_normalizes_absolute_paths() {
        #expect(resolveServerPath("/data/torrents", relativeTo: "/downloads") == "/data/torrents")
        #expect(resolveServerPath("/data//torrents/", relativeTo: "/downloads") == "/data/torrents")
        #expect(resolveServerPath("/", relativeTo: "/downloads") == "/")
    }

    @Test func resolve_joins_relative_paths_onto_a_rooted_base() {
        #expect(resolveServerPath("Movies", relativeTo: "/downloads") == "/downloads/Movies")
        // Empty input resolves to the base itself, keeping the leading slash.
        #expect(resolveServerPath("", relativeTo: "/downloads") == "/downloads")
    }

    @Test func resolve_dot_segments() {
        #expect(resolveServerPath("./Sub", relativeTo: "/downloads") == "/downloads/Sub")
        #expect(resolveServerPath("../Music", relativeTo: "/downloads/Movies") == "/downloads/Music")
    }

    @Test func resolve_cannot_climb_above_root() {
        #expect(resolveServerPath("../../..", relativeTo: "/downloads") == "/")
        #expect(resolveServerPath("/..", relativeTo: "/downloads") == "/")
    }

    @Test func resolve_without_base_keeps_relative_input_relative() {
        #expect(resolveServerPath("Movies", relativeTo: nil) == "Movies")
    }

    // MARK: - knownFolderSuggestions

    @Test func suggestions_drop_the_default_folder_sentinel() {
        #expect(knownFolderSuggestions([folderSentinel, "Archive"]) == ["Archive"])
    }

    @Test func suggestions_are_not_filtered_by_the_typed_path() {
        // The list is static — no path argument at all, so every known folder
        // stays offered no matter what the field contains.
        let result = knownFolderSuggestions([folderSentinel, "Archive", "Movies", "Music"])
        #expect(result == ["Archive", "Movies", "Music"])
    }

    @Test func suggestions_are_empty_when_no_other_folder_is_known() {
        #expect(knownFolderSuggestions([folderSentinel]).isEmpty)
    }

    // MARK: - initialServerPath

    @Test func initial_nested_path_shows_relative() {
        #expect(initialServerPath(existing: "/downloads/Movies", relativeTo: "/downloads") == "Movies")
    }

    @Test func initial_default_dir_shows_empty() {
        #expect(initialServerPath(existing: "/downloads", relativeTo: "/downloads") == "")
        // Trailing slashes and whitespace don't change the outcome.
        #expect(initialServerPath(existing: "/downloads/", relativeTo: "/downloads") == "")
        #expect(initialServerPath(existing: "  /downloads  ", relativeTo: "/downloads") == "")
    }

    @Test func initial_outside_base_stays_absolute() {
        #expect(initialServerPath(existing: "/other/path", relativeTo: "/downloads") == "/other/path")
    }

    @Test func initial_without_existing_or_base_is_empty() {
        #expect(initialServerPath(existing: nil, relativeTo: "/downloads") == "")
        #expect(initialServerPath(existing: "/downloads/Movies", relativeTo: nil) == "/downloads/Movies")
    }

    // MARK: - isSubmittableServerPath

    @Test func submittable_empty_needs_a_base() {
        #expect(isSubmittableServerPath("", relativeTo: "/downloads"))
        #expect(!isSubmittableServerPath("", relativeTo: nil))
        #expect(!isSubmittableServerPath("   ", relativeTo: "  "))
    }

    @Test func submittable_nonempty_always_submits() {
        #expect(isSubmittableServerPath("Movies", relativeTo: "/downloads"))
        #expect(isSubmittableServerPath("Movies", relativeTo: nil))
        #expect(isSubmittableServerPath("/other/path", relativeTo: nil))
    }

    // MARK: - serverPathClimbsAboveBase

    @Test func climb_relative_inside_base_is_not_a_climb() {
        #expect(!serverPathClimbsAboveBase("Movies", relativeTo: "/downloads"))
        #expect(!serverPathClimbsAboveBase("Movies/../Music", relativeTo: "/downloads"))
        #expect(!serverPathClimbsAboveBase("", relativeTo: "/downloads"))
    }

    @Test func climb_relative_escaping_base_is_a_climb() {
        #expect(serverPathClimbsAboveBase("../Music", relativeTo: "/downloads"))
        #expect(serverPathClimbsAboveBase("../../etc", relativeTo: "/downloads"))
    }

    @Test func climb_absolute_only_on_excess_dotdot() {
        #expect(!serverPathClimbsAboveBase("/other/path", relativeTo: "/downloads"))
        #expect(serverPathClimbsAboveBase("/../etc", relativeTo: "/downloads"))
        #expect(serverPathClimbsAboveBase("/data/../../..", relativeTo: "/downloads"))
    }

    // MARK: - serverPathIsNewFolder

    @Test func newFolder_base_and_known_are_not_new() {
        #expect(!serverPathIsNewFolder(resolved: "/downloads", relativeTo: "/downloads", folders: []))
        #expect(
            !serverPathIsNewFolder(
                resolved: "/downloads/Movies", relativeTo: "/downloads", folders: ["Movies"]))
        #expect(!serverPathIsNewFolder(resolved: "/", relativeTo: "/downloads", folders: []))
    }

    @Test func newFolder_unknown_subtree_is_new() {
        #expect(
            serverPathIsNewFolder(
                resolved: "/downloads/Fresh", relativeTo: "/downloads", folders: ["Movies"]))
        #expect(
            serverPathIsNewFolder(
                resolved: "/media/torrents", relativeTo: "/downloads", folders: ["Movies"]))
    }

    // MARK: - setLocationInitialState

    @Test func initialState_single_folder_prefills_relative() {
        let state = setLocationInitialState(
            folders: ["/downloads/Movies"], relativeTo: "/downloads")
        #expect(state.path == "Movies")
        #expect(state.distinctCount == 1)
    }

    @Test func initialState_mixed_folders_starts_empty() {
        let state = setLocationInitialState(
            folders: ["/downloads/Movies", "/downloads/Music"], relativeTo: "/downloads")
        #expect(state.path.isEmpty)
        #expect(state.distinctCount == 2)
    }

    @Test func initialState_no_folders_starts_empty() {
        let state = setLocationInitialState(folders: [], relativeTo: "/downloads")
        #expect(state.path.isEmpty)
        #expect(state.distinctCount == 0)
    }
}

/// Mirrors `FolderFilter.defaultFolderName` — the empty relative path that marks
/// torrents sitting directly in the default download directory.
private let folderSentinel = ""
