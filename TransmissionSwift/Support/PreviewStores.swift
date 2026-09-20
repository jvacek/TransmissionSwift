import TransmissionCore

/// Shared store for `#Preview`s that need a populated torrent list (the sheets,
/// which derive their "known folders" from the torrents).
///
/// A store built inside a preview closure is rebuilt on every body evaluation,
/// so its async mock stream never settles and the view renders with an empty
/// torrent list — no facets, no known folders. A file-scope store is created
/// once and persists, so the mock data is there when the preview draws.
///
/// Previews run on the main actor, so building the `@MainActor` store at file
/// scope is safe.
let previewTorrentStore: TorrentStore = {
    let store = TorrentStore(service: MockTorrentService())
    store.seedTorrents(MockFixtures.torrents())
    store.simulateConnection(.connected)
    return store
}()
