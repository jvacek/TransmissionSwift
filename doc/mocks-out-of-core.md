# Getting the mocks out of the production library

Status: **complete.** `MockFixtures` and `MockTorrentService` now live in a
dedicated `TransmissionTestSupport` target; `TransmissionCore` no longer
contains or exports them. This is item 3 of the senior review's leftovers.

## Progress

| Slice | State |
|---|---|
| Production `EmptyTorrentService` + use it for the no-server placeholder | done |
| Move `MockFixtures` / `MockTorrentService` into `TransmissionTestSupport` | done |
| Product code stops referencing the mock fixture (`OpenMappingEditor` fallback) | done |

## Why

`MockFixtures.swift` (~490 lines) and `MockTorrentService.swift` (~325 lines)
were `public` sources of `TransmissionCore`: test and preview infrastructure
shipped in the product library, widening its API and inviting production use
(which had already happened — the no-server placeholder was
`MockTorrentService(initial: [])`).

## Why Option B, not `#if DEBUG`

The obvious fix — gate the two files on `#if DEBUG` — does not work under
Xcode. The app target's `SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG` does **not**
propagate to the package dependency in the Test action: `build-for-testing`
compiles `TransmissionCore` in a "Testing" configuration with no `-DDEBUG`
(verified in the build log), while the app target *does* define `DEBUG`. So the
app's previews compiled their `#if DEBUG` branch and referenced mocks the
package had omitted — `cannot find 'MockTorrentService' in scope`. Gating on
`DEBUG` assumes the app and its package dependency agree, and they don't.

A dedicated target sidesteps this: it is linked in every configuration, so the
app and test targets always see the same module.

## What was done

- `Packages/TransmissionCore/Package.swift` gained a `TransmissionTestSupport`
  library product/target that depends on `TransmissionCore`; the package's test
  target depends on it.
- `MockFixtures.swift` / `MockTorrentService.swift` moved to
  `Sources/TransmissionTestSupport/` and `import TransmissionCore`.
- The package test files, the app's preview files and `AppIntentTests` gained
  `import TransmissionTestSupport`.
- The app target links the product in `TransmissionSwift.xcodeproj`. The app
  **unit test target does not** declare it: it inherits the module through the
  app target. Declaring it there links a second `TransmissionCore` and splits
  the `TorrentReading` / `TorrentMutating` protocol types, so the intents saw a
  read-only service.
- `OpenMappingEditor.previewTorrent` no longer uses `Torrent.sample`; it builds
  a placeholder `Torrent` inline, so product code has no fixture dependency.

The app release binary still links `TransmissionTestSupport` (previews are in the
app target), but the *library* is clean, which is the stated goal. A future
cleanup could move the previews' mock usage to app-local data if the app binary
size ever matters.

## Verification

`just test-packages-strict` (317 tests), a Debug **and** a Release app build
(the Release build is what would catch an unguarded preview), app unit tests and
`just test-snapshot` all pass.
