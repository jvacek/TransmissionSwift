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
| **Get Servers** (`GetServersIntent`) | shipped | — | `[ServerEntity]` |
| **Get Torrents** (`GetTorrentsIntent`) | shipped | Server, Status (default All), Label, Tracker, Search (all optional, AND) | `[TorrentEntity]` |
| **Add Torrent File** (`AddTorrentFileIntent`) | shipped | Torrent File (required), Server, Add Paused, Destination Folder, Labels, Priority (default Normal) | dialog |
| **Add Magnet Link** (`AddMagnetLinkIntent`) | shipped | Magnet Link (required), Server, Add Paused, Destination Folder, Labels, Priority (default Normal) | dialog |
| **Open Torrent** (`OpenTorrentIntent`) | shipped | Torrent (required) | deep-links the app to the torrent |
| **Pause Torrents** (`PauseTorrentsIntent`) | shipped | Server, Torrents (empty = all) | dialog |
| **Resume Torrents** (`ResumeTorrentsIntent`) | shipped | Server, Torrents (empty = all) | dialog |
| **Remove Torrents** (`RemoveTorrentsIntent`) | shipped | Server, Torrents, Also Delete Downloaded Data | dialog (confirms first) |
| **Verify Torrents** (`VerifyTorrentsIntent`) | shipped | Server, Torrents (required) | dialog |
| **Re-announce Torrents** (`ReannounceTorrentsIntent`) | shipped | Server, Torrents (required) | dialog |
| **Get Server Info** (`GetServerStatsIntent`) | shipped | Server (optional) | `ServerStatsEntity` (transient: counts, speeds, free space, turtle state) + dialog |
| **Get Torrent Stats** (`GetTorrentStatsIntent`) | shipped | Server, Torrent (required) | `TorrentStatsEntity` (transient) + dialog |
| **Set Turtle Mode** (`SetTurtleModeIntent`) | shipped | Server, Enabled | dialog |
| **Set Server Speed Limits** (`SetServerSpeedLimitsIntent`) | shipped | Server, download/upload limit + enable | dialog |
| **Set Torrent Speed Limits** (`SetTorrentSpeedLimitsIntent`) | shipped | Server, Torrents (required), download/upload limit + enable | dialog |
| Server (`ServerEntity`) | shipped | — | entity, indexed in Spotlight |
| Torrent (`TorrentEntity`) | shipped | — | entity (id/name/status/progress/speeds/ratio/size/labels/tracker/limits), indexed in Spotlight, URL-representable |
| `ServerStatsEntity` | shipped | — | transient result entity (server id/label, counts, speeds, free space, turtle) |
| `TorrentStatsEntity` | shipped | — | transient result entity (one torrent) |
| `TorrentStatusOption` | shipped | — | enum, the `Status` filter on Get Torrents (includes `All`) |

Free space is part of **Get Server Info** rather than its own action; the
`Get free space` Siri phrase still resolves to `GetServerStatsIntent`.

Siri phrases for Get Servers / Server Info / Pause / Resume are provided by
`TransmissionSwiftShortcuts` (`AppShortcutsProvider`). See
[Spotlight, structured results, Siri](#spotlight-structured-results-siri).

### Deep links

`TorrentEntity` conforms to `URLRepresentableEntity`, so the system can refer to
a torrent as a URL and open it:

```
transmissionswift://<serverUUID>/<torrentID>
```

The scheme is registered in `TransmissionSwift/Info.plist` (`CFBundleURLTypes`,
alongside `magnet`). `TransmissionSwiftApp`'s `.onOpenURL` routes a matching URL
to `OpenRequest(deepLink:)`, which drops an `OpenRequest` on `OpenRequestBus` —
the same path `OpenTorrentIntent.perform()` uses. The torrent's server UUID is
baked into its identifier (`<serverUUID>/<torrentID>`), so
`TorrentEntityQuery.entities(for:)` resolves an identifier against its own
server rather than the active one; that is what lets `Open Torrent` accept a
torrent from `Get Torrents` instead of falling back to a picker.

---

## File map

Everything App-Intents-specific lives under `TransmissionSwift/Intents/` in the
**app target** (filesystem-synchronized group — adding a file needs no pbxproj
edit).

| File | Responsibility |
|---|---|
| `TransmissionSwift/Intents/AppEnvironment.swift` | Process-wide shared state the intents resolve against (server list + service). The spine of the feature. |
| `TransmissionSwift/Intents/ServerEntity.swift` | `ServerEntity` + `ServerEntityQuery` — the Shortcuts "Server" picker. |
| `TransmissionSwift/Intents/GetServerStatsIntent.swift` | "Get Server Info" action; `ServerStatsEntity` (counts, speeds, free space, turtle) lives here. |
| `TransmissionSwift/Intents/AddTorrentIntent.swift` | `AddTorrentFileIntent` + `AddMagnetLinkIntent` and their shared add path. |
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
    func requireService(_ server: ServerEntity?) throws -> (profile: ServerProfile, service: any TorrentService)

    static func register(_ environment: AppEnvironment)       // called from App.init
    static var current: AppEnvironment? { get }
    static func require() throws -> AppEnvironment            // current or a user-facing error
}
```

Rules the implementation encodes:

- `service(for:)` returns, in order: the app's live connected service (when it
  matches the profile), the frozen `SnapshotTorrentService` (in `.snapshot`
  mode), or a fresh `TransmissionServiceFactory.make(for:)`. The factory fallback
  is what makes closed-app Shortcuts work.
- Registration happens once in `TransmissionSwiftApp.init`. Because intents run
  in the app process, `current` is populated by the time any intent runs.
- `ConnectionCoordinator.connect(to:)` (driven from `ContentView`) calls
  `setConnected(_:for:)` after connecting so a matching intent reuses the live
  connection (no second Keychain read).
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
   (whole class + extension), `ColumnFormatters`, and anything else reached from
   a query's `nonisolated` methods are marked so. If you hit "main actor-isolated
   … cannot be called from outside of the actor", mark the callee `nonisolated`.
4. **Returning data.** Return a `TransientAppEntity` when the result has more
   than one field a shortcut might chain (`ServerStatsEntity`, `TorrentStatsEntity`);
   the transient entity's `@Property` fields become selectable
   in Shortcuts. A plain `String` result is only usable as an opaque string, so
   avoid it for anything a shortcut should compute on. Every read intent also
   provides a dialog — that is what Siri speaks, and what Shortcuts' per-action
   "Show When Run" toggle displays (or suppresses).
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

### Per-torrent selection

`TorrentEntity` / `TorrentEntityQuery` exist; one shared query learns the selected
server from whichever carrying intent is being configured, through one
`@IntentParameterDependency<…>(\.$server)` per intent (see `TorrentEntityQuery`).
A torrent's identifier is `<serverUUID>/<torrentID>`, and
`TorrentEntityQuery.entities(for:)` parses the server out of the identifier, so a
selection resolves against its own server no matter which profile is active.

Required vs. optional `Torrents` is deliberate:

- `VerifyTorrentsIntent`, `ReannounceTorrentsIntent` and
  `SetTorrentSpeedLimitsIntent` take a **required** `[TorrentEntity]`. Blanket
  operations against a whole library can stall the daemon, so they must be
  explicit.
- `PauseTorrentsIntent` / `ResumeTorrentsIntent` / `RemoveTorrentsIntent` /
  `GetTorrentStatsIntent` still treat an empty selection as "every torrent"
  (replaceable, and `Remove` confirms first).

When you add an intent with a `Torrents` parameter, register its dependency in
`TorrentEntityQuery` so its picker scopes to the chosen server.

---

## Spotlight, structured results, Siri

- **Spotlight (`IndexedEntity`).** `ServerEntity` and `TorrentEntity` conform to
  `IndexedEntity`; `SpotlightIndexer` donates them via
  `CSSearchableIndex.default().indexAppEntities(_:)`. Servers are indexed once at
  launch (`ContentView`); torrents are donated by `GetTorrentsIntent`.
  `OpenTorrentIntent` (`OpenIntent`) is the tap target — it drops an `OpenRequest`
  on `OpenRequestBus` and activates the app; `MainWindow` switches server,
  selects the torrent, and reveals the inspector. Torrents are indexed on demand,
  not on every poll (they change constantly). Each donation prunes torrents that
  dropped out of the set, and `RemoveTorrentsIntent` deletes the ones it removed;
  app-UI removals are pruned on the next donation.
- **Structured results (`TransientAppEntity`).** Read intents return structured
  entities so a shortcut can chain individual fields instead of parsing a string.
  `ServerStatsEntity` = a server's id/label, torrent counts, transfer speeds,
  free space and turtle state (`GetServerStatsIntent`, presented as "Get Server
  Info"); `TorrentStatsEntity` = one torrent's progress/speeds/ratio
  (`GetTorrentStatsIntent`, which requires a torrent — the server-wide aggregate
  is `GetServerStatsIntent`). `GetTorrentsIntent` returns `[TorrentEntity]`, whose
  `@Property` fields (name, status, progress, speeds, ratio, size, labels,
  tracker, per-torrent download/upload limits with their `… Limited` flags) are
  chainable.
- **Filtering torrents.** `GetTorrentsIntent` takes optional `Status`
  (`TorrentStatusOption`, default `All`), `Label`, `Tracker` and `Search`
  parameters and narrows the list with AND semantics, reusing the core
  `TorrentFilterSelection`. The server-scoped torrent picker stays unfiltered.
- **Deep links.** `TorrentEntity` is `URLRepresentableEntity`; the URL is
  `transmissionswift://<serverUUID>/<torrentID>`, registered in Info.plist and
  routed through `.onOpenURL` → `OpenRequestBus` (see [Deep links](#deep-links)).
- **Siri (`AppShortcutsProvider`).** `TransmissionSwiftShortcuts` publishes phrases
  for a few parameterless actions. Phrases must contain `\(.applicationName)` and
  be unique; prefer intents with no required parameters.

---

## Testing

Three layers, from cheapest to most real:

### 1. Core unit tests (always run, no signing)

`Packages/TransmissionCore/Tests/TransmissionCoreTests/AppIntentSupportTests.swift`
covers `TransmissionServiceFactory`, `ServerProfileStore.readProfiles`, and the
`RPCTorrentService` cold-cache fix. `just test-core` / `just check`.

### 2. AppIntentsTesting (real, but needs signing — signing-gated)

`TransmissionSwiftUITests/AppIntentsUITests.swift` boots the app on
`--snapshot` and runs `GetServerStatsIntent` / `ServerEntityQuery` through the
real App Intents stack (out-of-process, no mocks, no `@testable import`). The
whole file is wrapped in `#if canImport(AppIntentsTesting)`, so it compiles out on
toolchains without the framework (the framework ships only in the **macOS 27 SDK /
Xcode 27**). Runtime availability is additionally guarded by
`@available(macOS 27.0, *)`. A `macos-26` CI runner is fine — it just skips the
file. (The framework's dylib is built for 26.4, so the UI test target links with a
harmless "built for newer version" warning.)

```bash
just test-appintents <YOUR_TEAM_ID>     # sets the signing guard env var + DEVELOPMENT_TEAM
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

### 4. CI lane (the `App Intents tests` step)

`.github/workflows/ci.yml` runs the AppIntentsTesting lane in the `App Intents
tests` step of the `build-app` job, on the `xcode-27` leg (macOS 27 image, arm64
only). It **always runs on that leg** — no repository variable or manual opt-in.
The release pipeline does not run it. It is enforced on main pushes; PRs run it
too, and the whole `xcode-27` leg is `continue-on-error` on `pull_request` only
because that image is a public preview.

Everything below is required — App Intents reject an unsigned (ad-hoc) app with
`Code=800`, so there is no signing-free shortcut:

- **Runner:** `xcode-27` (the macOS 27 SDK is the only place `AppIntentsTesting`
  exists).
- **Secrets:** `APP_INTENTS_CERT_P12_BASE64`, `APP_INTENTS_CERT_PASSWORD`,
  `APP_INTENTS_KEYCHAIN_PASSWORD` — a base64-encoded Apple Development `.p12`
  (with its private key) and its password.
- **Team id:** set inline as `DEVELOPMENT_TEAM` in the job; keep it in sync with
  the certificate.
- The job passes `-allowProvisioningUpdates` so Xcode can fetch the profile the
  app-groups entitlement needs. If signing still fails, add an App Store Connect
  API key and pass `-authenticationKeyPath` / `-authenticationKeyID` /
  `-authenticationKeyIssuerID`.

To produce the `.p12`: Xcode → Settings → Accounts → Manage Certificates (Apple
Development), or Keychain Access → export the identity. Without a certificate you
cannot run this lane anywhere — not locally and not in CI.

### Known gaps

- **MainWindow open-request handling** (server switch → select → reveal, from
  `OpenTorrentIntent`) is covered only at the bus level
  (`AppIntentTests.openTorrentRequestsNavigation`). The view-side application
  needs a UI test (including `viewAnnotations()`).
- **`RemoveTorrentsIntent`'s confirmation** is framework-driven, so it isn't
  unit-tested; it needs the integration lane or a manual run.
- **`SpotlightIndexer`** is thin (`CSSearchableIndex.indexAppEntities`, errors
  swallowed) and untested — verifying actual indexing needs Spotlight.
- **`AppShortcutsProvider` phrases** are validated by Xcode at build time, not by
  a test.
- Value-returning intents (`GetServers`/`GetTorrents`, `GetServerStats`,
  `GetTorrentStats`) assert their contract through `AppIntentsUITests`; plain unit
  tests can't read an `AppIntent`'s opaque result. Headless intents resolve via
  `AppEnvironment`, so `AppIntentTests` covers them with a `MockTorrentService`.

### The signing-gate environment-variable convention (important)

`xcodebuild` forwards shell environment variables prefixed `TEST_RUNNER_` to the
test runner **with the prefix stripped**. So:

```
shell:  TEST_RUNNER_TRANSMISSION_APPINTENTS=1 xcodebuild …
runner: ProcessInfo.processInfo.environment["TRANSMISSION_APPINTENTS"] == "1"
```

Tests must read the **stripped** name. (This was previously wrong here, which
silently skipped both signed lanes for a long time. Do not reintroduce the
prefixed form in test code; only the shell/justfile sets the prefixed name.)

---

## Troubleshooting playbook

| Symptom | Cause | Fix |
|---|---|---|
| Shortcuts: **"Could not communicate with app"** | Ad-hoc-signed app (no team) and/or the bundle id resolves to a stale install without App Intents metadata. | Sign app + test runner with the same `DEVELOPMENT_TEAM`; install one current build to `/Applications`; remove duplicate registrations. |
| Shortcuts: server picker empty / **"No Transmission servers are configured"** in a *downloaded* build, while the app shows profiles | The released app is ad-hoc signed (no `TeamIdentifier`), so App Intents can't reach it (`AppIntentsServicesSecurityErrorDomain Code=800`); the app's own profiles are invisible to Shortcuts. | Team-sign the release. The pipeline now signs with the Apple Development cert and `verify_artifact` fails on ad-hoc zips. |
| AppIntentsTesting: `AppIntentsServicesSecurityErrorDomain Code=800 "Your app does not have permission to perform this."` | Same root cause: no signing team. | Set `DEVELOPMENT_TEAM` on the Debug app + UI test targets (needs a `Mac Development` cert). |
| AppIntentsTesting: `AppIntentsServicesMetadataErrorDomain … "<bundle id> is not present"` | The system resolved the bundle id to a copy without intent metadata (e.g. a stale `/Applications` app), or nothing registered yet. | Ensure the current build is the installed one; run it once; `lsregister -gc` to drop stale copies. |
| Signing-gated test **silently skips** | Reading `TEST_RUNNER_<X>` instead of the stripped `<X>` in test code. | Read the stripped name; keep the prefix only in the shell/justfile. |
| CI: `Unable to resolve module dependency: 'AppIntentsTesting'` | CI Xcode/SDK predates macOS 27 — the framework only exists in Xcode 27. | Keep the test file `#if canImport(AppIntentsTesting)`-guarded (compiles out), or bump the runner to a macOS 27 image if you want CI to compile it. |
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

- **Code signing is mandatory, including for the shipped build.** App Intents
  require the app to carry a team identity, so an ad-hoc release has a Shortcuts
  surface that is silently dead: the server picker is empty and actions report
  "No Transmission servers are configured" even though the app itself is full of
  profiles. The release pipeline imports the Apple Development certificate (the
  same `APP_INTENTS_*` secrets the AppIntentsTesting lane uses) and signs with
  it, and `verify_artifact` fails the run if the zipped app still reports
  `TeamIdentifier=not set`. The Debug app config has no `DEVELOPMENT_TEAM`
  (only Release does); add one on machines with a cert.
- **One install per bundle id.** `jvacek.TransmissionSwift` should resolve to a
  single, current app (ideally in `/Applications`). DerivedData, temp, and trash
  copies all register under the same id and confuse resolution.
- **`AppIntentsTesting` needs the macOS 27 SDK (Xcode 27)** and a UI Testing
  bundle signed with the same team. The file is `#if canImport`-guarded, so older
  toolchains (e.g. a `macos-26` CI runner) compile it out instead of failing. The
  app itself still targets macOS 26.
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

Shipped: Get Servers/Torrents, Add Torrent File / Add Magnet Link, Open Torrent,
Pause/Resume, Remove, Verify, Re-announce, Get Server Info, Get Torrent Stats,
Set Turtle Mode, Set Server/Torrent Speed Limits, torrent deep links — plus the
`AppEnvironment` spine, `ServerEntity`/`TorrentEntity`/`TorrentStatsEntity`,
Spotlight indexing, Siri phrases, the core factory/profile reader/cache-warm fix,
and the AppIntentsTesting bundle (signing-gated).

Possible next: per-file wanted/priority; setting labels and priority from
shortcuts; session queue/seed-ratio/network intents; a single "Set Server Limits"
umbrella; macOS Control Center controls; and IndexedEntity indexing on torrent
change rather than only on `GetTorrentsIntent`.
