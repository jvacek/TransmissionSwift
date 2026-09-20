import Foundation

/// Known-folder suggestions for a server-side destination path. `known` is the
/// torrent folder rollup from `FilterFacets` — relative folder names, where the
/// empty string is the sentinel for torrents sitting directly in the default
/// download directory. That sentinel names the default folder itself, not a
/// destination worth jumping to, so it is dropped. The result is deliberately
/// independent of any typed path: every known folder stays one click away.
func knownFolderSuggestions(_ known: [String]) -> [String] {
    known.filter { !$0.isEmpty }
}
