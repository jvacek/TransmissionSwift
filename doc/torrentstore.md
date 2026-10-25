# TorrentStore layout

`TorrentStore` (`TransmissionCore`) is the single `@Observable` object the app
injects into the environment. It owns wiring, not state:

- the backing service and the poll tasks (`streamTask`, `freeSpaceTask`)
- the connection state machine, `isConnected`, `actionsEnabled`
- `lastActionError`, the one alert channel
- the `open*` sheet entry points, `torrentForOpening`, `captureSnapshot`

Everything else lives in one of five collaborators:

| Collaborator | Owns |
|---|---|
| `list` | torrents, facets, visible rows, selection, search, filters, sort |
| `session` | session settings, turtle speed, free space, version, stats, port |
| `inspector` | the selected torrent's detail, visibility, tab |
| `actions` | every torrent mutation and the staged removal |
| `ui` | sheet presentation state |

Views read `store.<collaborator>.<member>` and bind with
`@Bindable var list = store.list`. Sub-models never hold a reference back to the
coordinator: cross-cutting effects go through the list model (selection prune)
or the inspector model (refresh after a mutation), and errors through the
coordinator's `onError` sink.

## Poll wiring

The poll loop is the only writer of snapshots: `list.setTorrents(...)`,
`session.load`/`poll`, and `inspector.poll()` per tick. The selected torrent's
detail is a separate fetch in `InspectorModel.fetch`, because the list snapshot
carries no files or peers.

## Tests

Each collaborator has its own suite (`TorrentListModelTests`,
`SessionModelTests`, `InspectorModelTests`, `TorrentActionModelTests`);
`TorrentStoreTests` is the coordinator and wiring suite.
