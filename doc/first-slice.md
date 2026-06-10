# First Slice — End-to-end `session-get`

**Status: ✅ COMPLETE (2026-06-10).** See "Result notes" at the bottom for what diverged from the plan.

**Goal:** Prove the entire stack works by getting one RPC call — `session-get` — to render its result in the app. After this slice, every later feature is just more of the same shape.

**Success criteria:**
1. ✅ App launches, shows a settings screen to enter one server profile (host, port, username, password).
2. ✅ Password is stored in Keychain; profile metadata in a JSON file.
3. ✅ A "Test connection" button calls `session-get` against the real Transmission daemon.
4. ✅ The Transmission daemon's reported version appears in the UI.
5. ✅ The 409 session-ID handshake is handled automatically — verified by unit tests (and live).
6. ✅ Universal binary builds (arm64 + x86_64) on macOS 26 — verified with `lipo -info` on a Release build.

**Out of scope for this slice:** torrent list, polling, multi-server switching UI, error UX polish, anything that resembles the real app. We're proving the wiring.

---

## Step -1 — Reference cache & live daemon (added during execution)

- [x] `reference/` dir (gitignored) with the upstream RPC specs — see `reference/README.md`.
- [x] `brew install transmission-cli`; dev daemon: `transmission-daemon -g ~/.transmission-dev -t -u dev -v devpass -p 9091 -w /tmp/transmission-dev-downloads` (Transmission 4.1.2).
- [x] Real responses captured as test fixtures in `Packages/TransmissionRPC/Tests/TransmissionRPCTests/Fixtures/` (409 with headers, 401, successful `session-get`).

## Step 0 — Clean the template

- [x] Delete `TransmissionSwift/Item.swift`.
- [x] In `TransmissionSwiftApp.swift`: remove the `ModelContainer`, `Schema`, `SwiftData` import.
- [x] In `ContentView.swift`: strip the `@Query`, `@Environment(\.modelContext)`, `addItem`, `deleteItems`.
- [x] Build — confirmed clean.

## Step 1 — Create the `TransmissionRPC` package

- [x] `Packages/TransmissionRPC/` with `Package.swift` (macOS 26, Swift language mode 6).
- [x] Added to the Xcode project + linked to the app target (pbxproj edited directly — worked fine, see notes).
- [x] `TransmissionClient.swift`, `TransmissionError.swift`, `SessionInfo.swift`, `URLSessionTransmissionClient.swift` (actor; 409 retry-once; Basic auth; typed throws).
- [x] `init(rpcURL:credentials:urlSession:)` with injectable URLSession.

## Step 2 — Test the 409 handshake

- [x] `URLProtocol` stub (host-routed so parallel Swift Testing runs don't share state).
- [x] 8 tests: happy path, 409-retry-once (header echo verified), session-ID reuse across calls, 401, Basic-auth header, malformed JSON, non-`success` result, persistent 409.
- [x] All passing (`swift test`).

## Step 3 — Create the `TransmissionCore` package

- [x] `Packages/TransmissionCore/` depending on `TransmissionRPC`.
- [x] `ServerProfile.swift` (+ computed `rpcURL`), `KeychainStore.swift`, `ServerProfileStore.swift` (`@Observable`, write-through JSON), `ConnectionService.swift`.
- [x] 3 tests: profile round-trip, missing file, URL assembly. Passing.

## Step 4 — Minimal app UI

- [x] `TransmissionSwiftApp.swift`: single `ServerProfileStore` in the environment (+ `--ephemeral-profiles` launch arg for UI tests).
- [x] `ContentView.swift` switches: `AddServerForm` ↔ `ServerStatusView` (simple two-state view; NavigationSplitView deferred until there's something to navigate).
- [x] Submit persists profile JSON + Keychain password; Test connection renders version or error.

## Step 5 — Validate end-to-end

- [x] Live daemon on `localhost:9091` with auth — version string renders. Proven by an opt-in XCUITest (`TEST_RUNNER_TRANSMISSION_E2E=1 xcodebuild test …`), which fills the form, saves, tests, and asserts "Connected to Transmission…" appears.
- [x] 409 handshake live: every fresh client does the initial 409→retry against the real daemon (the E2E test exercises it); stale-ID-after-restart covered by unit test.
- [x] Universal binary: Release build with `ONLY_ACTIVE_ARCH=NO` → `x86_64 arm64`.
- [x] `swift format lint --strict` and `prek run --all-files` clean.

## Step 6 — Wrap up

- [x] `ARCHITECTURE.md` decision log updated.
- [x] `AGENTS.md` updated (reference cache, dev daemon, fixtures, E2E test).
- [ ] Commit — left to Jonas (per CLAUDE.md, no commits unless asked).

---

## Result notes (what diverged from the plan)

- **Legacy vs new RPC protocol.** Transmission 4.1 introduced JSON-RPC 2.0 with snake_case keys and deprecated the bespoke `{"method", "arguments"}` envelope. We implement the **legacy protocol** (works against every daemon version incl. 4.x; same choice as transgui). Specs for both are cached in `reference/`. Revisit when old daemons stop mattering.
- **pbxproj editing was fine.** The Xcode 26 project format (objectVersion 77, filesystem-synchronized groups) made both package linking and adding app-target files painless — no manual Xcode dance needed. New app-target source files are picked up from disk automatically.
- **App Transport Security.** ATS exempts loopback, so localhost worked, but real remote daemons over plain HTTP were blocked. Added `NSAppTransportSecurity → NSAllowsArbitraryLoads` via a partial `TransmissionSwift/Info.plist` (merged into the generated one).
- **Sandbox entitlement.** Outbound network needed `ENABLE_OUTGOING_NETWORK_CONNECTIONS = YES` (`com.apple.security.network.client`) — the template did not include it.
- **warnings-as-errors.** `.treatAllWarnings(as: .error)` in Package.swift conflicts with the `-suppress-warnings` Xcode passes to package dependencies. Enforced in CI via `swift test -Xswiftc -warnings-as-errors` instead.
- **CI runners** bumped `macos-15` → `macos-26` (the project needs the macOS 26 SDK).
- **SwiftUI + XCUITest gotchas:** form fields need explicit `.accessibilityIdentifier(...)`; a SwiftUI `Label`/`Text` exposes its string as the element's `value`, not `label`.
