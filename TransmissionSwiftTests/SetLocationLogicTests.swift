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
}

/// Mirrors `FolderFilter.defaultFolderName` — the empty relative path that marks
/// torrents sitting directly in the default download directory.
private let folderSentinel = ""
