# App Intents (Shortcuts actions)

TransmissionSwift exposes Shortcuts / Siri / Spotlight actions through Apple's
App Intents framework. This document is the durable reference: what the feature
is, how it is wired, how to add or fix an intent, and the environment gotchas
that will otherwise cost you an afternoon.

If you are here to **change or debug an intent**, read
[Adding an intent](#adding-an-intent) and
[Troubleshooting playbook](#troubleshooting-playbook) first.

---

## Current surface

| Action | Status | Parameters | Returns |
|---|---|---|---|
| **Get Server Stats** (`GetServerStatsIntent`) | shipped | Server (optional) | `String` summary + dialog |
| Server (`ServerEntity`) | shipped | — | entity used by the Server picker |

Planned but **not implemented** (the rest of the original catalogue): Add Torrent,
Pause/Resume, Turtle toggle, Get Torrent Stats, per-torrent selection, Siri
phrases (`AppShortcutsProvider`). See [Status / what's left](#status--whats-left).

---

## File map

Everything App-Intents-specific lives under `TransmissionSwift/Intents/` in the
**app target** (filesystem-synchronized group — adding a file needs no pbxproj
edit).

| File | Responsibility |
|---|---|
| `TransmissionSwift/Intents/AppEnvironment.swift` | Process-wide shared state the intents resolve against (server list + service). The spine of the feature. |
| `TransmissionSwift/Intents/ServerEntity.swift` | `ServerEntity` + `ServerEntityQuery` — the Shortcuts "Server" picker. |
| `TransmissionSwift/Intents/GetServerStatsIntent.swift` | The one shipped action. |
| `TransmissionSwift/Intents/IntentError.swift` | `IntentError`, a user-facing error whose message shows verbatim in Shortcuts. |
| `TransmissionSwift/Intents/` (new files) | One file per intent, by convention. |

Supporting pieces elsewhere:

| File | Change |
|---|---|
| `Packages/TransmissionCore/Sources/TransmissionCore/TransmissionServiceFactory.swift` | Builds a `TorrentService` from a profile (Keychain + URLSession client). Shared by the app and intents. |
| `Packages/TransmissionCore/Sources/TransmissionCore/ServerProfileStore.swift` | `readProfiles(from:)` and `defaultFileURL()` are `nonisolated` so intents can read profiles off the main actor. |
| `Packages/TransmissionCore/Sources/TransmissionCore/RPCTorrentService.swift` | `isAlternativeSpeedEnabled()` / `add()` warm a cold `cachedSession` before reading it. |
| `TransmissionSwift/TransmissionSwiftApp.swift` | Creates and registers the `AppEnvironment` at launch. |
| `TransmissionSwift/ContentView.swift` | Publishes the live connected service into the `AppEnvironment`. |
| `TransmissionSwiftUITests/AppIntentsUITests.swift` | `AppIntentsTesting` integration tests. |
| `Packages/TransmissionCore/Tests/TransmissionCoreTests/AppIntentSupportTests.swift` | Unit tests for the core glue. |

---

## Runtime model (why it is shaped like this)

App Intents on macOS run **in the app's process, but outside the SwiftUI object
graph**. Key consequences:

1. **No view state.** An intent cannot see `TorrentStore`, `ServerProfileStore`,
   or anything in `@State`/`.environment`. It must resolve state itself — that is
   what `AppEnvironment` is for.
2. **Headless.** Every intent sets `openAppWhenRun = false`. The system launches
   the app process in the background with no window to service the intent. Never
   assume a window exists.
3. **One-shot RPC only.** `RPCTorrentService` starts its polling loop only inside
   `torrentsStream()`. Intents call one-shot methods (`torrents()`, `add()`,
   `start()`, `sessionStats()`, …) and must **never** call `torrentsStream()` —
   otherwise they leave a poll task and mutate UI-ish state.
4. **Discovery is automatic.** No Info.plist keys and no extension target. The
   system indexes `AppIntent` conformers in the app binary and the build emits
   `Contents/Resources/Metadata.appintents/`. That is also why the types live in
   the app target rather than in an SPM package.
5. **`TransmissionCore` stays AppIntents-free.** The package remains
   platform-agnostic (`ARCHITECTURE.md`) and its `swift test` stays clean. All
   `AppIntent` / `AppEntity` / `AppEnum` wrappers live in the app target.

---

## The shared state: `AppEnvironment`

`AppEnvironment` is a small, `nonisolated`, `Sendable` class registered
process-wide. Intents read it via `AppEnvironment.current`.

```swift
nonisolated final class AppEnvironment: Sendable {
    enum Mode { case live, snapshot }

    let mode: Mode
    let profileFileURL: URL        // the app's ServerProfileStore file
    let snapshotFileURL: URL?      // set under --snapshot

    func setConnected(_ service: (any TorrentService)?, for profile: ServerProfile)
    func profiles() -> (profiles: [ServerProfile], activeProfileID: UUID?)
    func resolve(_ server: ServerEntity?) -> ServerProfile?   // chosen, else active, else first
    func service(for profile: ServerProfile) -> (any TorrentService)?

    static func register(_ environment: AppEnvironment)       // called from App.init
    static var current: AppEnvironment? { get }
}
```

Rules the implementation encodes:

- `service(for:)` returns, in order: the app's live connected service (when it
  matches the profile), the frozen `SnapshotTorrentService` (in `.snapshot`
  mode), or a fresh `TransmissionServiceFactory.make(for:)`. The factory fallback
  is what makes closed-app Shortcuts work.
- Registration happens once in `TransmissionSwiftApp.init`. Because intents run
  in the app process, `current` is populated by the time any intent runs.
- `ContentView.connectToProfile` calls `setConnected(_:for:)` after connecting so
  a matching intent reuses the live connection (no second Keychain read).
- Mutability is guarded by a `Synchronization.Mutex`, keeping the class
  `Sendable` without going through a MainActor.

**Why the profile file URL, not the store?** In `--snapshot` / `--ephemeral`
modes the app uses an ephemeral `servers.json`. Intents must read the *same*
file, so the environment carries the URL and reads it via the `nonisolated`
`ServerProfileStore.readProfiles(from:)`. This is also what makes AppIntentsTesting
deterministic (see [Testing](#testing)).

**Intentionally not a full `AppModel`.** `AppEnvironment` holds no UI state —
subscription, selection, filters and polling all stay in `TorrentStore` in the
view layer. Consequence: an intent run while the window is open won't update the
window until its next poll. That is fine for these actions.

---

## Server selection

Every action takes the same optional parameter:

```swift
@Parameter(title: "Server")
var server: ServerEntity?
```

- `ServerEntity.id` is the profile's UUID string; `label` is its display name.
- `ServerEntityQuery.suggestedEntities()` lists all profiles;
  `defaultResult()` returns the active profile, so leaving Server blank behaves
  like the app after launch.
- `resolve(_:)` in `AppEnvironment` maps the chosen entity back to a profile. A
  nil result means "no servers configured" — throw `IntentError` for that.

---

## Core glue (in `TransmissionCore`)

- **`TransmissionServiceFactory`** — the single service-construction path, used
  by both `ContentView` and intents.

  ```swift
  // App path: credentials already resolved off-main.
  static func make(for profile: ServerProfile, credentials: Credentials?) -> (any TorrentService)?
  // Intent path: reads the Keychain synchronously.
  static func make(for profile: ServerProfile, keychain: KeychainStore = KeychainStore()) -> (any TorrentService)?
  ```

  Returns nil when the profile's host/path don't form a valid RPC URL.

- **`ServerProfileStore.readProfiles(from:)`** — `nonisolated` JSON read reused by
  both the store's `init` and the intents. Do not re-implement profile decoding.

- **Cold session cache.** A freshly built `RPCTorrentService` has
  `cachedSession == nil`. `isAlternativeSpeedEnabled()` and `add()` now warm it
  from a fresh `session-get` before reading, mirroring `sessionSettings()`. If you
  add a method that reads session-derived state, follow the same pattern or it
  will silently misbehave for intents (which never run the connect flow).

---

## Adding an intent

1. **Pick the surface.** If it mutates, check `service.supportsActions` or handle
   `SnapshotError.replayReadOnly` — snapshot replay is read-only.
2. **Create `TransmissionSwift/Intents/<Name>Intent.swift`.** Minimal shape:

   ```swift
   import AppIntents
   import TransmissionCore

   struct PauseEverythingIntent: AppIntent {
       static let title: LocalizedStringResource = "Pause All Torrents"
       static let openAppWhenRun = false

       @Parameter(title: "Server")
       var server: ServerEntity?

       func perform() async throws -> some IntentResult & ProvidesDialog {
           guard let environment = AppEnvironment.current else {
               throw IntentError(message: "TransmissionSwift isn't ready.")
           }
           guard let profile = environment.resolve(server) else {
               throw IntentError(message: "No Transmission servers are configured.")
           }
           guard let service = environment.service(for: profile) else {
               throw IntentError(message: "The server “\(profile.label)” has an invalid RPC address.")
           }
           let ids = try await service.torrents().map(\.id)
           try await service.stop(ids)
           return .result(dialog: "Paused \(ids.count) torrents on \(profile.label).")
       }
   }
   ```

3. **Concurrency rule (easy to get wrong).** The app target defaults to
   `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Helpers you call from an intent's
   `nonisolated` `perform()` must themselves be `nonisolated` — `AppEnvironment`
   (whole class + extension), `GetServerStatsIntent.summary`, and the
   `ColumnFormatters` enum are marked so. If you hit "main actor-isolated … cannot
   be called from outside of the actor", mark the callee `nonisolated`.
4. **Returning data.** A `String` result (with `ProvidesDialog`) is usable in
   Shortcuts. Structured values need `TransientAppEntity`; only add it if field
   chaining in Shortcuts is actually wanted.
5. **Entities/enums.** To add a selectable value (e.g. torrent priority), define
   an app-target `AppEnum`/`AppEntity` — do **not** make `TransmissionCore` types
   conform, that would drag AppIntents into the package.
6. **Build and verify discovery:**

   ```bash
   just build
   strings <DerivedData>/.../TransmissionSwift.app/Contents/Resources/Metadata.appintents/extract.actionsdata \
     | grep -o "<YourIntentName>" | head -1
   ```

Adding files under `TransmissionSwift/Intents/` is picked up automatically.

### Per-torrent selection (not built yet)

Selecting specific torrents needs a `TorrentEntity` whose query hits
`service.torrents()` on the *selected* server. The query learns the server via
`@IntentParameterDependency<Intent>(\.$server)`; because that ties a query to one
intent, either use a small per-intent query type or a shared resolver. Until then,
operate on "all torrents on the server".

---

## Testing

Three layers, from cheapest to most real:

### 1. Core unit tests (always run, no signing)

`Packages/TransmissionCore/Tests/TransmissionCoreTests/AppIntentSupportTests.swift`
covers `TransmissionServiceFactory`, `ServerProfileStore.readProfiles`, and the
`RPCTorrentService` cold-cache fix. `just test-core` / `just check`.

### 2. AppIntentsTesting (real, but needs signing — opt-in)

`TransmissionSwiftUITests/AppIntentsUITests.swift` boots the app on
`--snapshot` and runs `GetServerStatsIntent` / `ServerEntityQuery` through the
real App Intents stack (out-of-process, no mocks, no `@testable import`). Requires
macOS 27 (`@available(macOS 27.0, *)`).

```bash
just test-appintents <YOUR_TEAM_ID>     # sets the opt-in env var + DEVELOPMENT_TEAM
```

Determinism comes from `AppEnvironment`: in `--snapshot` mode the intents resolve
against the frozen fixture instead of the network.

**Two things must both be true to run it** — see
[Troubleshooting](#troubleshooting-playbook): a code-signing team, and a single
current app install.

### 3. Manual Shortcuts smoke test

Build, install to `/Applications`, open Shortcuts, add the action, confirm the
Server dropdown lists profiles with the active one preselected, and run it. This
is the only way to verify the actual Shortcuts UX.

### The opt-in environment-variable convention (important)

`xcodebuild` forwards shell environment variables prefixed `TEST_RUNNER_` to the
test runner **with the prefix stripped**. So:

```
shell:  TEST_RUNNER_TRANSMISSION_APPINTENTS=1 xcodebuild …
runner: ProcessInfo.processInfo.environment["TRANSMISSION_APPINTENTS"] == "1"
```

Tests must read the **stripped** name. (This was previously wrong here, which
silently skipped both opt-in lanes for a long time. Do not reintroduce the
prefixed form in test code; only the shell/justfile sets the prefixed name.)

---

## Troubleshooting playbook

| Symptom | Cause | Fix |
|---|---|---|
| Shortcuts: **"Could not communicate with app"** | Ad-hoc-signed app (no team) and/or the bundle id resolves to a stale install without App Intents metadata. | Sign app + test runner with the same `DEVELOPMENT_TEAM`; install one current build to `/Applications`; remove duplicate registrations. |
| AppIntentsTesting: `AppIntentsServicesSecurityErrorDomain Code=800 "Your app does not have permission to perform this."` | Same root cause: no signing team. | Set `DEVELOPMENT_TEAM` on the Debug app + UI test targets (needs a `Mac Development` cert). |
| AppIntentsTesting: `AppIntentsServicesMetadataErrorDomain … "<bundle id> is not present"` | The system resolved the bundle id to a copy without intent metadata (e.g. a stale `/Applications` app), or nothing registered yet. | Ensure the current build is the installed one; run it once; `lsregister -gc` to drop stale copies. |
| Opt-in test **silently skips** | Reading `TEST_RUNNER_<X>` instead of the stripped `<X>` in test code. | Read the stripped name; keep the prefix only in the shell/justfile. |
| Intent appears in Shortcuts but does nothing / errors immediately | `AppEnvironment.current` is nil, no profiles, or `service(for:)` returned nil. | Check the thrown `IntentError` message; verify `register` runs in `App.init` and a profile exists. |
| "main actor-isolated … cannot be called from outside of the actor" | Target default isolation is MainActor; a helper called from a `nonisolated` intent member isn't. | Mark the helper `nonisolated`. |

**Diagnostics:**

```bash
codesign -dv --verbose=4 /path/to/TransmissionSwift.app        # Signature=adhoc / TeamIdentifier
ls /path/TransmissionSwift.app/Contents/Resources/Metadata.appintents   # must exist
lsregister -dump | grep -A2 "TransmissionSwift.app"            # look for duplicate registrations
security find-identity -v -p codesigning                       # is there a usable cert?
```

---

## Environment requirements & gotchas

- **Code signing is mandatory.** App Intents require the app and any invoking
  process (Shortcuts, the AppIntentsTesting runner) to share a development team.
  Ad-hoc builds fail with the security error above. The Debug app config has no
  `DEVELOPMENT_TEAM` (only Release does); add one on machines with a cert.
- **One install per bundle id.** `jvacek.TransmissionSwift` should resolve to a
  single, current app (ideally in `/Applications`). DerivedData, temp, and trash
  copies all register under the same id and confuse resolution.
- **`AppIntentsTesting` needs macOS 27** and a UI Testing bundle signed with the
  same team. The app itself still targets macOS 26.
- **Sandbox is fine.** Intents run in the app's sandbox:
  `com.apple.security.network.client` covers RPC; Keychain and the container
  `Application Support` are the same as in-app.
- **Snapshot mode is read-only and stateless.** `SnapshotTorrentService` returns
  nil for `sessionStats()` and throws `SnapshotError.replayReadOnly` for
  mutations. `GetServerStatsIntent` therefore falls back to aggregating
  `torrents()` when `session-stats` is unavailable. Any new read intent should do
  the same; any write intent should surface a clear error in replay.
- **First background Keychain read may prompt** when the app is launched cold for
  an intent. Expected; test the closed-app path.

---

## Status / what's left

Shipped: the `AppEnvironment` spine, `ServerEntity`/query, `GetServerStatsIntent`,
core factory + profile reader + cache-warm fix, and the AppIntentsTesting bundle
(signing-gated).

Not built: `GetTorrentStatsIntent`, `PauseTorrentsIntent` / `ResumeTorrentsIntent`,
`SetTurtleModeIntent`, `AddTorrentIntent`, per-torrent `TorrentEntity`, and Siri
phrases (`AppShortcutsProvider`). None of them require new architecture — each is
`AppEnvironment.resolve` + `service(for:)` + a service call, following
[Adding an intent](#adding-an-intent).
