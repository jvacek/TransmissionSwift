# TransmissionSwift — Agent Instructions

Native SwiftUI macOS remote control for the Transmission BitTorrent daemon (native equivalent of [transgui](https://github.com/transmission-remote-gui/transgui)). macOS-only, min macOS 26, universal binary.

**Read `ARCHITECTURE.md` first** — durable architectural decisions. If anything here contradicts it, `ARCHITECTURE.md` wins; propose updating this file.

## Build, test, run

Use `just <recipe>`; `just --list` shows all. The justfile wraps the common commands, including the Xcode `DEVELOPER_DIR` that package tests need (the CLT `swift` lacks the `Testing` module). Key recipes: `build`, `test` (packages + app), `test-packages` (fast: RPC + Core), `test-snapshot` (daemon-free UI test), `daemon`, `format`, `lint`.

Inside Xcode, prefer the `xcode` MCP tools (`BuildProject`, `RunSomeTests`, `XcodeRefreshCodeIssuesInFile`) over raw `xcodebuild` — they pre-parse output and save context.

## Conventions

- **Style:** swift-format owns it (`.swift-format`, 4 spaces). Run it; don't argue.
- Strong types, no force-unwrapping, typed errors over `Error` strings.
- Comments only when *why* is non-obvious; no "what" comments.
- Tests: Swift Testing (`@Test`, `#expect`); XCUIAutomation for UI.
- Packages use `.swiftLanguageMode(.v6)` (strict concurrency). `-warnings-as-errors` runs in CI (`swift test -Xswiftc -warnings-as-errors`), not in `Package.swift` — it conflicts with Xcode's `-suppress-warnings` for package deps. Don't add it to manifests.

## Architecture

Layering is compiler-enforced: app target → `TransmissionCore` → `TransmissionRPC` → Foundation. A dependency crossing it the wrong way means a refactor, not a workaround. Keep `TransmissionRPC`/`TransmissionCore` free of `AppKit` and SwiftUI (keeps an iOS target possible). Details in `ARCHITECTURE.md`.

## Development notes

- `reference/` (gitignored) caches both RPC specs: legacy 4.0.6 (**the protocol we implement**) and JSON-RPC 2.0 (4.1+). See `reference/README.md` to re-fetch.
- RPC fixtures in `Packages/TransmissionRPC/Tests/TransmissionRPCTests/Fixtures/` were captured from a real daemon with `curl`; recapture rather than hand-edit.
- Opt-in E2E UI test (needs the dev daemon): `TEST_RUNNER_TRANSMISSION_E2E=1 xcodebuild test -project TransmissionSwift.xcodeproj -scheme TransmissionSwift -only-testing:TransmissionSwiftUITests`.
- New files in a Swift package: create under `Sources/<package>/`; SPM picks them up.
- New files in the app target: filesystem-synchronized groups pick them up from disk, so no pbxproj edit for sources. Structural pbxproj edits are fine — keep them small and build immediately.

## Snapshot capture & replay

Reproduce a real-daemon bug with no daemon: Settings → Developer → **Capture Snapshot…** (redacts, then leak-checks), then replay read-only off the committed fixture:

```bash
open Build/Products/Debug/TransmissionSwift.app --args --snapshot TransmissionSwiftUITests/Fixtures/snapshot-10-torrents.json
```

Debug builds carry a read-only `/` sandbox exception, so this works from the repo; Release is sandboxed to `~/Downloads`. `--snapshot` forces ephemeral profiles (never written to `servers.json`). Design and remaining gotchas: `doc/snapshot-replay.md`.

## Working efficiently

Sessions default to a mid-tier model on purpose:

- Delegate broad exploration ("where is X handled?") to a cheap subagent (Claude Code: `Explore`/`Agent` on `haiku`) instead of reading many files in the main loop.
- Orient from `doc/appkit-decomposition.md` before reading source; don't re-read files already in context; don't dump raw `xcodebuild` output.
- If a task stalls (architecture change, concurrency debugging, RPC design), say so and suggest a stronger model (`/model opus`) instead of grinding.
- Jonas is a web-backend dev new to SwiftUI: frame native concepts with backend analogues when useful. Prefer a cross-stack slice for validating larger plans; save plans that won't fit one session under `doc/`.

## Tooling & Git

- `prek` (pre-commit drop-in): `brew install prek && prek install`. Hooks auto-format `.swift` and run hygiene checks; CI mirrors them plus build/test (`.github/workflows/ci.yml`).
- Don't commit or create branches unless asked.

## Don't

- Don't reintroduce SwiftData without a documented reason in `ARCHITECTURE.md`.
- Don't add Combine.
- Don't add third-party Swift packages without checking maintenance (stars, last commit, contributors) — we rejected `mogeko/transmission-rpc`.
- Don't add files to the app target without confirming with a human.
