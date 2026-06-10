# TransmissionSwift — Agent Instructions

A native SwiftUI macOS app that acts as a remote control for the Transmission BitTorrent daemon — a native equivalent to [transgui](https://github.com/transmission-remote-gui/transgui).

This file gives AI coding agents (Claude, Cursor, Codex, Aider, etc.) the persistent context they need to be useful in this repo. Keep it concise.

## Read first

- `ARCHITECTURE.md` — durable architectural decisions and the rationale behind them.
- `doc/first-slice.md` — the current implementation plan (a thin end-to-end `session-get` slice).

If anything in this file contradicts `ARCHITECTURE.md`, treat `ARCHITECTURE.md` as the source of truth and propose updating this file.

## Project shape (summary)

- **Platforms:** macOS only, min macOS 26, universal binary (arm64 + x86_64).
- **Module layout:** local Swift Packages under `Packages/`.
  - `TransmissionRPC` — wire protocol, Foundation only. No SwiftUI, no AppKit.
  - `TransmissionCore` — domain models, storage, services. Depends on `TransmissionRPC`.
  - App target (`TransmissionSwift/`) — SwiftUI views and view models only.
- **Concurrency:** `async`/`await` + `@Observable` macro. No Combine.
- **Storage:** JSON file for server profiles, Keychain for passwords, `@AppStorage` for UI prefs. No SwiftData on day one.

## Build & test commands

```bash
# Format Swift sources in-place (uses bundled swift-format).
swift format --in-place --recursive .

# Format lint (CI-style — no writes, exits non-zero on diff).
swift format lint --strict --recursive .

# Build & test individual packages (fast).
cd Packages/TransmissionRPC && swift test
cd Packages/TransmissionCore && swift test

# Build the macOS app target (slow; prefer xcode-tools MCP `BuildProject`).
xcodebuild -project TransmissionSwift.xcodeproj -scheme TransmissionSwift build | xcbeautify

# Run the macOS app's tests.
xcodebuild -project TransmissionSwift.xcodeproj -scheme TransmissionSwift test | xcbeautify

# Run all pre-commit hooks across the repo (uses prek).
prek run --all-files
```

When invoked from inside Xcode via Claude Code: prefer the `xcode-tools` MCP server (`BuildProject`, `XcodeRefreshCodeIssuesInFile`, `RunSomeTests`) over raw `xcodebuild`. The MCP tools pre-parse output and save context.

## Conventions

- **Style:** enforced by `swift-format`. Config in `.swift-format`. Don't argue with it; run it.
- **Indentation:** 4 spaces (set by `.swift-format`).
- **Naming:** `PascalCase` for types, `camelCase` for properties/methods.
- **Types:** strong types, no force-unwrapping. Prefer typed errors over `Error` strings.
- **Comments:** rare. Only when *why* is non-obvious. No "what" comments next to self-explanatory code.
- **Tests:** Swift Testing framework (`@Test`, `#expect`). XCUIAutomation for UI tests.
- **Compiler strictness:** each `Package.swift` should enable `-warnings-as-errors` and `-strict-concurrency=complete`.

## Architectural layering (compiler-enforced)

```
App target  ──depends on──>  TransmissionCore  ──depends on──>  TransmissionRPC  ──depends on──>  Foundation
```

If you need to add a dependency that crosses these boundaries the wrong direction, stop and propose a refactor instead.

## Local reference material & dev daemon

- `reference/` (gitignored) caches the upstream RPC specs — both the legacy protocol (4.0.6, **the one we implement**) and the JSON-RPC 2.0 protocol (4.1+). See `reference/README.md` to re-fetch.
- Local dev daemon: `transmission-daemon -g ~/.transmission-dev -t -u dev -v devpass -p 9091 -w /tmp/transmission-dev-downloads` (installed via `brew install transmission-cli`).
- RPC test fixtures in `Packages/TransmissionRPC/Tests/TransmissionRPCTests/Fixtures/` were captured from a real daemon with `curl` — recapture rather than hand-edit when the protocol surface grows.
- Opt-in E2E UI test (needs the daemon above): `TEST_RUNNER_TRANSMISSION_E2E=1 xcodebuild test -project TransmissionSwift.xcodeproj -scheme TransmissionSwift -only-testing:TransmissionSwiftUITests`.

## Working efficiently in this repo

- **Adding files to a Swift package**: just create the file under `Sources/<package>/`. SPM picks it up automatically — no project file edits.
- **Adding files to the app target**: the project uses filesystem-synchronized groups (Xcode 16+ format), so new files under `TransmissionSwift/` are picked up from disk automatically — no pbxproj edits needed for sources. Structural pbxproj edits (linking packages, entitlements) are manageable; keep them small and build immediately after.
- **Multiplatform-friendliness**: even though we're macOS-only, avoid `import AppKit` outside the app target. Keeps the door open to iOS later.

## Pre-commit / DX

- The repo uses `prek` (a Rust drop-in replacement for `pre-commit`). Install once: `brew install prek` then `prek install`.
- Hooks live in `.pre-commit-config.yaml`. They auto-format `.swift` files via `swift-format` and run standard hygiene checks.
- CI mirrors the local hooks plus a build/test pass — see `.github/workflows/ci.yml`.

## Don't

- Don't reintroduce SwiftData unless there's a documented reason in `ARCHITECTURE.md`.
- Don't add Combine.
- Don't add third-party Swift package dependencies without checking maintenance status (stars, last commit, contributors). We rejected `mogeko/transmission-rpc` for this reason.
- Don't add files to the app target without confirming with a human.
- Don't make commits or create branches unless explicitly asked.

## Personal preferences (Jonas)

These are also captured in `~/.claude/CLAUDE.md`, repeated here for non-Claude agents:

- Web backend background, new to native Apple/SwiftUI development — frame native concepts using backend analogues when helpful.
- Don't make commits on the user's behalf unless asked.
- Don't create new branches unless asked.
- For larger plans, prioritise a cross-stack slice for validation.
- If a plan won't fit one session, save it as a markdown file under `doc/` and track progress there.
