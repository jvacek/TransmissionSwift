# First Slice — End-to-end `session-get`

**Goal:** Prove the entire stack works by getting one RPC call — `session-get` — to render its result in the app. After this slice, every later feature is just more of the same shape.

**Success criteria:**
1. App launches, shows a settings screen to enter one server profile (host, port, username, password).
2. Password is stored in Keychain; profile metadata in a JSON file.
3. A "Test connection" button calls `session-get` against the real Transmission daemon.
4. The Transmission daemon's reported version appears in the UI.
5. The 409 session-ID handshake is handled automatically — verified by a unit test.
6. Universal binary builds (arm64 + x86_64) on macOS 26.

**Out of scope for this slice:** torrent list, polling, multi-server switching UI, error UX polish, anything that resembles the real app. We're proving the wiring.

---

## Step 0 — Clean the template

- [ ] Delete `TransmissionSwift/Item.swift`.
- [ ] In `TransmissionSwiftApp.swift`: remove the `ModelContainer`, `Schema`, `SwiftData` import.
- [ ] In `ContentView.swift`: strip the `@Query`, `@Environment(\.modelContext)`, `addItem`, `deleteItems`. Leave a placeholder `Text("TransmissionSwift")` for now.
- [ ] Build — confirm a clean app launches with nothing useful in it.

## Step 1 — Create the `TransmissionRPC` package

- [ ] Create `Packages/TransmissionRPC/` with `Package.swift` (platform: macOS 26, products: library `TransmissionRPC`).
- [ ] Add the package to the Xcode project as a local package dependency. Link `TransmissionRPC` to the app target.
- [ ] In `Sources/TransmissionRPC/`:
  - `TransmissionClient.swift` — the `protocol TransmissionClient` with `func sessionGet() async throws -> SessionInfo`.
  - `TransmissionError.swift` — typed errors (`unauthorized`, `network`, `decoding`, `serverError`).
  - `SessionInfo.swift` — Codable struct mapping the fields we care about today (`version`, `rpcVersion`, `rpcVersionMinimum`). More fields later.
  - `URLSessionTransmissionClient.swift` — `actor` conforming to `TransmissionClient`. Holds `var sessionId: String?`. Implements:
    - Build request: POST to `{baseURL}/transmission/rpc`, body `{"method": "session-get", "arguments": {}}`, headers include Basic auth + `X-Transmission-Session-Id` if known.
    - On 409: capture the new session ID from `X-Transmission-Session-Id` response header, retry **once**.
    - On 401: `throw .unauthorized`.
    - On 2xx: decode the envelope `{ "arguments": {...}, "result": "success" }`.
- [ ] Configure in `init(baseURL:credentials:urlSession:)`. Pass URLSession explicitly so tests can inject.

## Step 2 — Test the 409 handshake

- [ ] In `Tests/TransmissionRPCTests/`, add a `URLProtocol` stub.
- [ ] Test cases:
  - `sessionGet returns version on first 200` — happy path with session ID pre-known.
  - `sessionGet retries once on 409 with new session ID` — first response is 409 + header, second is 200. Verify both requests were made and second included the header.
  - `sessionGet throws unauthorized on 401`.
  - `sessionGet throws decoding error on malformed JSON`.
- [ ] Run tests. They should pass before moving on.

## Step 3 — Create the `TransmissionCore` package

- [ ] Create `Packages/TransmissionCore/` with `Package.swift` (depends on `TransmissionRPC`).
- [ ] Add to Xcode project. Link to app target.
- [ ] In `Sources/TransmissionCore/`:
  - `ServerProfile.swift` — Codable struct: `id: UUID`, `label: String`, `host: String`, `port: Int`, `rpcPath: String` (default `/transmission/rpc`), `username: String?`, `useHTTPS: Bool`. Computed `baseURL`.
  - `KeychainStore.swift` — small wrapper over `Security` framework: `getPassword(for: UUID)`, `setPassword(_:for:)`, `deletePassword(for:)`.
  - `ServerProfileStore.swift` — `@Observable` class. Loads/saves profiles to `Application Support/TransmissionSwift/servers.json`. Exposes `profiles: [ServerProfile]`, `add`, `update`, `remove`.
  - `ConnectionService.swift` — `@Observable` class. Given a `ServerProfile`, builds a `URLSessionTransmissionClient` and exposes `func testConnection() async -> Result<SessionInfo, TransmissionError>`. This is what the UI button calls.
- [ ] No tests for `KeychainStore` (touches system state). One test for `ServerProfileStore` round-trip serialization.

## Step 4 — Minimal app UI

- [ ] `TransmissionSwiftApp.swift`: instantiate a single `ServerProfileStore` and pass into environment.
- [ ] `ContentView.swift`: NavigationSplitView with two states:
  - **No profile yet** → "Add server" form (label, host, port, username, password).
  - **Profile exists** → a status panel showing the profile + a "Test connection" button + a result area.
- [ ] On submit: persist profile to JSON, password to Keychain, switch to status panel.
- [ ] On "Test connection": call `ConnectionService.testConnection()`. Render either `"Connected to Transmission \(info.version) (RPC \(info.rpcVersion))"` or the error.

## Step 5 — Validate end-to-end

- [ ] Run a local Transmission daemon (`brew install transmission-cli && transmission-daemon`, or the macOS app). Default URL: `http://localhost:9091/transmission/rpc`.
- [ ] Launch the app, add a profile, hit Test. Confirm the version string shows up.
- [ ] Force a 409 by restarting `transmission-daemon` while the app holds an old session ID — confirm the next test still works (the retry kicks in).
- [ ] Check **both** Apple Silicon and Intel builds compile (Build Settings → Architectures = Standard, run a release build).

## Step 6 — Wrap up

- [ ] Update `ARCHITECTURE.md` "Decision log" with anything that changed during implementation.
- [ ] Commit. (Only on explicit request — per personal preferences in CLAUDE.md.)

---

## Risks / things that may surprise

- **Adding a local Swift Package to an existing Xcode project** is a UI dance, not a CLI one. Likely needs the user (Jonas) to do it via Xcode's "Add Package Dependencies… → Add Local…" flow. I can prep the package on disk but the Xcode integration step may be manual.
- **Keychain access on first run** may prompt for permission depending on entitlements. May need to add the Keychain Sharing capability or a custom access group.
- **Self-signed certs** — defer. If the user's daemon uses HTTPS with a self-signed cert, we'll punt that to a later slice.
- **Sandbox network access** — the macOS app sandbox requires `com.apple.security.network.client` entitlement for outbound HTTP. The Xcode template usually sets this for new apps but worth confirming on first run.
