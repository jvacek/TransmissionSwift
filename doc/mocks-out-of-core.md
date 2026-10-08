# Getting the mocks out of the production library

Status: **plan — the safe first slice has landed; the relocation is not started.**
This is item 3 of the senior review's maintainability leftovers.

## Progress

| Slice | State |
|---|---|
| Production `EmptyTorrentService` + use it for the no-server placeholder | done (`refactor(core): add EmptyTorrentService…`) |
| Relocate `MockFixtures` / `MockTorrentService` out of `TransmissionCore` | not started |

The app no longer uses `MockTorrentService` outside previews, so the production
dependency is gone. What remains is that the mocks are still compiled and public
in the `TransmissionCore` release build.

## Why

`MockFixtures.swift` (~490 lines) and `MockTorrentService.swift` (~325 lines)
live in `Packages/TransmissionCore/Sources/` and are `public`. They are test and
preview infrastructure, not product code: they bloat the shipped library, widen
its public API, and invite accidental production use (which already happened —
the no-server placeholder used to be `MockTorrentService(initial: [])`).

## What depends on them

| Consumer | Needs them | Notes |
|---|---|---|
| `TransmissionCoreTests` (most suites) | yes | `swift test` = Debug |
| `TransmissionSwiftTests` (`AppIntentTests`) | yes | Debug |
| App `#Preview`s (~12 files) | yes | compiled in **all** configurations |
| `Support/PreviewStores.swift` | yes | file-scope preview store |
| `OpenMappingEditor.previewTorrent` | `Torrent.sample` **in production code** | fallback when no torrent is available |
| `TransmissionSwiftApp` | no longer | now `EmptyTorrentService` |

## Option A — `#if DEBUG` around the mocks (recommended)

Wrap `MockFixtures.swift` and `MockTorrentService.swift` in `#if DEBUG`. Verified
that Xcode passes `-DDEBUG` to the `TransmissionCore` package target in Debug
(grepped the build log: `TransmissionCore-t.build … -DDEBUG`), and SwiftPM's
`swift test`/`swift build` debug configs do too.

Steps:

1. Wrap the two files' contents in `#if DEBUG` … `#endif`.
2. Replace the production `Torrent.sample` fallback in
   `OpenMappingEditor.previewTorrent` with an inline constructed `Torrent`
   (production code must not reach into fixtures).
3. Guard every app-target mock usage with `#if DEBUG`:
   - `Inspector/InspectorView.swift`
   - `Inspector/InspectorPeersTab.swift`, `InspectorTrackersTab.swift`,
     `InspectorOptionsTab.swift`, `InspectorFilesTab.swift`,
     `InspectorGeneralTab.swift`
   - `Preferences/PrefsShared.swift`, `Preferences/TagsPrefsPane.swift`
   - `Sheets/EditLabelsSheet.swift`, `Sheets/RenameTorrentSheet.swift`
   - `Support/PreviewStores.swift`
   - `MainWindow.swift`
4. Verify with **both** a Debug and a Release app build
   (`xcodebuild … -configuration Debug build` and `… Release build`); the Release
   build is what catches an unguarded preview. Then the package tests, app unit
   tests and snapshot test as usual.

Trade-off: `swift test -c release` would no longer compile the mock-dependent
suites. Nobody runs that today (`just test-packages-strict` is Debug; CI is
Debug), but it is worth a note in the test target if it ever matters.

This fully removes the mocks from the release library **and** the release app.

## Option B — a separate `TransmissionTestSupport` target

Add a second library target/product to `Packages/TransmissionCore/Package.swift`,
move the two files there, and have `TransmissionCoreTests`, the app target and
the app test targets depend on it. No preview guards needed.

Trade-offs: requires linking the new product in `TransmissionSwift.xcodeproj`
(the app and its test targets), and the mocks are still linked into the app's
release binary — the "production library" is clean, but the app is not. More
moving parts for a weaker result than Option A.

## Recommendation

Option A. It is more edits but purely mechanical, removes the code from every
release artifact, and needs no pbxproj or package-graph changes; the Release
build in step 4 verifies it directly.

## Also outstanding (separate, optional)

- **Item 1 / Slice B4** — extract the table row context-menu enablement into a
  pure `TorrentRowMenu` spec (see `doc/appkit-decomposition.md`). Highest
  behavioural risk of the item-1 work, lowest structural gain.
- **Item 1 / Slice C** — mechanical split of `OpenMappingEditor.swift`.
