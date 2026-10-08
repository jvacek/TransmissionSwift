# TransmissionSwift — Architecture

A native SwiftUI remote control for the [Transmission](https://transmissionbt.com) BitTorrent daemon, in the spirit of [transgui](https://github.com/transmission-remote-gui/transgui) but native to Apple platforms.

This document captures the architectural decisions made up front. Treat it as load-bearing — revisit and update when reality diverges.

---

## 1. Platforms

- **Primary target:** macOS only.
- **Minimum deployment:** macOS 26.
- **Architectures:** Universal binary — Apple Silicon + Intel.
- **Future-proofing:** Code outside the app target must not import `AppKit`. Keep `TransmissionRPC` and `TransmissionCore` platform-agnostic so iOS/iPadOS can be added later as a separate app target without restructuring.

## 2. Module layout

Use **local Swift Packages** in the same repo (analogous to a monorepo with separate libraries). The package boundary is enforced by the compiler, which prevents views from reaching into URLSession and keeps testing simple.

```
TransmissionSwift/                          ← Xcode project root
├── TransmissionSwift.xcodeproj
├── TransmissionSwift/                      ← app target (SwiftUI views, view models)
├── TransmissionSwiftTests/
├── TransmissionSwiftUITests/
└── Packages/
    ├── TransmissionRPC/                    ← wire protocol, no UI
    │   ├── Package.swift
    │   ├── Sources/TransmissionRPC/
    │   └── Tests/TransmissionRPCTests/
    └── TransmissionCore/                   ← domain models, storage, services
        ├── Package.swift
        ├── Sources/TransmissionCore/
        ├── Sources/TransmissionTestSupport/  ← mocks/fixtures, not in the product
        └── Tests/TransmissionCoreTests/
```

**Layering rules:**
- `TransmissionRPC` depends on **Foundation only** (plus `OSLog` for logging — fine, it's platform-agnostic). No SwiftUI, no AppKit, no SwiftData.
- `TransmissionCore` depends on `TransmissionRPC` + Foundation + (optionally) SwiftData/Security for storage. The package also builds a second, non-product target, `TransmissionTestSupport`, holding the mocks/fixtures; only tests and previews link it.
- The app target depends on both packages (and `TransmissionTestSupport`, for previews). It holds SwiftUI views and view models, plus thin app-only services that don't belong in Core — connection coordination, crash reporting, favicon/tag stores, App Intents.

**Why three layers:**
- `TransmissionRPC` is a pure protocol implementation — testable without a UI, swappable, mockable via protocol.
- `TransmissionCore` is the "service layer" — server profiles, credentials, polling orchestration, the things every UI surface will need.
- The app target stays thin: views observe view models, view models call into core, core calls into RPC.

### Store layer

`TorrentStore` (TransmissionCore) is the single `@Observable` object the app
injects into the environment. It is a coordinator, not a god object: it owns the
connection state machine and the poll loop, and composes focused collaborators
that each own one concern.

| Collaborator | Concern |
|---|---|
| `list` (`TorrentListModel`) | torrents, facets, visible rows, selection, search, filters, sort |
| `session` (`SessionModel`) | session settings, turtle speed, free space, version, stats, port |
| `inspector` (`InspectorModel`) | inspector detail, visibility, tab |
| `actions` (`TorrentActionModel`) | every torrent mutation + the staged removal |
| `ui` (`TorrentSheetState`) | sheet presentation state |

Views read `store.<collaborator>.<member>`; the poll loop distributes snapshots
to the models. User-action failures funnel through the coordinator's
`lastActionError`. The split is tracked in `doc/torrentstore-split.md`.

The services behind the store are split by capability: `TorrentReading` (always
available) and `TorrentMutating` (live and mock services only). Callers resolve
the optional mutation half with `TorrentReading.mutations` rather than a
repeated `as?` downcast. A read-only source (snapshot replay) implements only
`TorrentReading`; `EmptyTorrentService` is the production no-server placeholder.

Choosing *which* service to install is app-only and lives in
`ConnectionCoordinator` (app target), not the view: it reads the Keychain off
the main actor, builds the service and drives `TorrentStore` plus the shared
`AppEnvironment` that App Intents read.

## 3. RPC client design

### Wire protocol notes worth knowing

- Transmission's RPC is **JSON-RPC-ish over HTTP**. One endpoint, request body has `{ "method": "...", "arguments": {...}, "tag": N }`.
- **Two protocols exist since Transmission 4.1**: the legacy bespoke envelope above (kebab-case keys) and a JSON-RPC 2.0 variant (snake_case). The legacy protocol is deprecated upstream but supported by **every** daemon version; JSON-RPC 2.0 only by ≥ 4.1. **We speak the legacy protocol** for maximum reach (the transgui model). Both specs are cached under `reference/`. Revisit when pre-4.1 daemons stop mattering.
- **Session-ID handshake:** the first request gets rejected with **HTTP 409** and an `X-Transmission-Session-Id` response header. Subsequent requests must echo it. If the server restarts, the ID changes and a single 409 is expected — the client must transparently retry once.
- **Auth:** HTTP Basic.
- **No push.** Polling-only.

### Client shape

- Public `protocol TransmissionClient` so the app and core layers depend on the interface, not the implementation. Mocks become trivial.
- A concrete `URLSessionTransmissionClient` actor that:
  - Owns the current session ID (mutable state — actor isolation handles this cleanly).
  - On `409`, captures the new session ID from the response header and retries the request **once**.
  - Surfaces typed errors (`TransmissionError.unauthorized`, `.network(URLError)`, `.decoding`, `.serverError(message)`).
- Codable request/response types per RPC method. Generated by hand, not from a schema — keeps types tight.
- No third-party RPC library. (`mogeko/transmission-rpc` was evaluated and rejected — 0 stars, 13 commits, single contributor, unclear maintenance, unclear 409 handling. We'll write our own thin client.)

## 4. Concurrency

- **`async`/`await` throughout.** No Combine.
- View models are `@Observable` (the macro, not `ObservableObject`).
- SwiftUI lifecycle driven by `.task { }` modifiers.
- The RPC client is an `actor` to serialize session-ID state.
- The app target builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so
  views, view models and app services are main-actor by default. Pure logic
  (the table row/selection/sort/menu helpers, process checks) is marked
  `nonisolated` so it can be unit-tested without the main actor.

## 5. Polling strategy

- **Default interval: 5 seconds**, while the relevant UI is visible.
- **Adaptive** based on visibility:
  - When the window is in the foreground and the torrent list is visible → 5s.
  - When the window is backgrounded or the user is on a non-list screen (settings, etc.) → slow down or pause.
- Implement as an `AsyncStream` driven by a `Task` that loops with `Task.sleep`. The poller belongs in `TransmissionCore`, started/stopped by view models via `.task { }` lifecycles.
- Future: scale the rate based on whether torrents are actively transferring vs. all idle.

## 6. Storage

What we persist locally — the daemon owns everything else.

| Data | Where | Why |
|---|---|---|
| Server profiles (host, port, RPC path, username, label) | JSON file in App Support | Plain config, easy to back up |
| Server passwords | **Keychain** | Non-negotiable — never plain text |
| UI preferences (column order/widths, sort, inspector width, sidebar expansion) | `@AppStorage` / `UserDefaults` | Standard for prefs |
| Last selected server ID | `@AppStorage` | Restore-on-launch |
| Torrent list cache | Not persisted (yet) | Live data — refetch on launch |

The table's sort preference is read and written through a
`TablePreferencesStoring` seam over `UserDefaults`, so the list model can be
tested without the shared defaults.

**Remove from default template:** the boilerplate `Item.swift` model and the `ModelContainer` setup in `TransmissionSwiftApp.swift`. We are not using SwiftData on day one.

## 7. Multi-server support

- The app **must support multiple Transmission server profiles** with a switcher (the transgui model).
- Design implication: types like `ServerProfile`, `TransmissionClient`, and the polling service all take a `ServerProfile` (or are scoped per-profile). Never have a singleton "the server."
- UI implication: a menu / toolbar control to switch the active server; settings UI to manage the profile list.

## 8. Testing

- **Framework:** Swift Testing (`@Test`, `#expect`). XCUIAutomation for UI.
- **RPC layer:** canned HTTP responses via a custom `URLProtocol` stub — 409-then-retry handshake, auth failure, malformed JSON.
- **Core layer:** the `TransmissionClient` protocol injects a fake client for service-level tests, and the store's main collaborators each have a direct suite. Mocks/fixtures live in the `TransmissionTestSupport` target.
- **App layer:** pure logic extracted from the views (table row store, selection, sort, row-menu spec, cell-content builder, formatters) is unit-tested directly in `TransmissionSwiftTests`, as is `ConnectionCoordinator` with an injected Keychain reader, service builder and `AppEnvironment`. Views themselves are covered by previews and UI tests.
- **UI:** a daemon-free snapshot-replay test (`just test-snapshot`) and an opt-in E2E golden path (`TEST_RUNNER_TRANSMISSION_E2E=1`, needs a live local daemon).
- Package tests run with `-warnings-as-errors` (see the decision log).
- **Known gaps:** `session-get` and `torrent-add` fixtures are captured from a live daemon; `torrent-get` (list + inspector), `torrent-set`, `torrent-start/stop/remove` and `free-space` are still hand-made JSON in the tests. Recapture from the dev daemon when the RPC surface is next touched.
- The E2E XCUITest suite (`TEST_RUNNER_TRANSMISSION_E2E=1`) has not been re-run against the live daemon since the RPC layer landed; only `testAddServerAndTestConnection` is daemon-gated today.

## 9. Open questions (decide as they come up)

- Whether to expose `URLSession` configuration (timeouts, proxies, certificate trust for self-signed daemons) in server profiles. Likely yes, eventually.
- Optional offline torrent list cache (SwiftData) — defer until there's a real reason.

---

## Decision log

| Date | Decision | Status |
|---|---|---|
| 2026-06-10 | macOS-only, min macOS 26, universal binary | Active |
| 2026-06-10 | Three-layer module split via local Swift Packages | Active |
| 2026-06-10 | Hand-rolled RPC client; reject mogeko/transmission-rpc dependency | Active |
| 2026-06-10 | async/await + `@Observable`, no Combine | Active |
| 2026-06-10 | Adaptive polling, default 5s | Active |
| 2026-06-10 | Multi-server first-class; switcher in UI | Active |
| 2026-06-10 | Keychain for passwords, JSON file for profiles | Active |
| 2026-06-10 | Drop SwiftData scaffolding from the default template | Active |
| 2026-06-10 | Speak the legacy RPC protocol, not 4.1's JSON-RPC 2.0 — works against every daemon version | Active |
| 2026-06-10 | ATS exception `NSAllowsArbitraryLoads` — users connect to arbitrary LAN daemons over plain HTTP | Active |
| 2026-06-10 | App sandbox kept, with `com.apple.security.network.client` entitlement | Active |
| 2026-08-21 | User-selected file access upgraded to read-write (`ENABLE_USER_SELECTED_FILES = readwrite`) so the Developer pane's snapshot save panel can write | Active |
| 2026-06-10 | warnings-as-errors enforced via CI flags, not Package.swift (conflicts with Xcode's `-suppress-warnings` for package deps) | Active |
| 2026-06-10 | E2E golden-path XCUITest, opt-in via `TEST_RUNNER_TRANSMISSION_E2E=1` (needs a live local daemon) | Active |
| 2026-06-11 | Mock-first UI buildout: views consume `protocol TorrentService` (TransmissionCore), built against `MockTorrentService` first; `RPCTorrentService` swaps in last with zero view changes | Done |
| 2026-06-0? | Split RPC client files per method group | Active |
| 2026-10-08 | `TorrentStore` is a coordinator over focused `@Observable` collaborators (`list`/`session`/`inspector`/`actions`/`ui`), not a god object; plan + progress in `doc/torrentstore-split.md` | Active |
| 2026-10-08 | `TorrentService` split into `TorrentReading` + `TorrentMutating`; callers resolve the mutation half via `TorrentReading.mutations` | Active |
| 2026-10-08 | Connect flow extracted from `ContentView` into an app-target `ConnectionCoordinator` (Keychain + factory + `AppEnvironment`), with injected dependencies | Active |
| 2026-10-08 | Table sort persists through a `TablePreferencesStoring` seam; the persisted value is the single source of truth | Active |
| 2026-10-08 | Mocks/fixtures moved out of `TransmissionCore` into a `TransmissionTestSupport` target; `EmptyTorrentService` is the production no-server placeholder | Active |
| 2026-10-08 | AppKit decomposition: the cell view and the table `Coordinator` split into focused files and pure types; plan in `doc/appkit-decomposition.md` | Active |
