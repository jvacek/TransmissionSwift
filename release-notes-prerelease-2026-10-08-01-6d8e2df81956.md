# Changelog

All notable changes to TransmissionSwift.

---

**Versions on or below 0.6.1 need to be manually updated to 0.6.2 or above**. There was a bug in the updater, and you will need to work around it yourself. My sincere apoologies for the inconvenience.

Please visit the [release page](https://github.com/jvacek/TransmissionSwift/releases), download TransmissionSwift and replace the current install.

---

## 0.7.0

8th Oct 2026

- Add App Intents support
  - Adds support for Shortcuts.app
    - Get Servers
    - Get Server Stats
    - Get Server Free space
    - Add torrent to server
  - Allows control from Spotlight and non-AI Siri
- Add opt-in for crash reporting
- Fix Favicon cache not being re-used on startup
- Add donation link to the status bar
  - Add option to hide it (and also the bug report link)
- Major refactor behind the scenes
- Thin down the release binaries

## 0.6.4

3rd Oct 2026

- Add option to remove .torrent files after deletion
- Persist the .torrent delete option from settings and have the add sheet read from it

## 0.6.3

3rd Oct 2026

- Label the universal binary release
- Separate appcasts for universal and arm64 releases
  - **If you used the auto-updater from an arm64 release, it installed the universal over it, just FYI**

## 0.6.2

1st Oct 2026

- Fix in-app updates failing to install on sandboxed builds (Sparkle's Installer XPC service was never enabled).
  - Note: **versions ≤ 0.6.1 must update to this release manually once**; automatic updates resume after that.

## 0.6.1

25th septh 2026

- Implement torrent renaming

## 0.6.0

24th septh 2026

- Split settings page into two: Application and server settings
- Implement server settings
- Fix UI bugs in settings pages

## 0.5.6

24th Sept 2026

- Add a button and menu item to open a new github issue with the versions pre-filled
- Fix the seedcount column
- Preserve inspector closed/open state
- Fix the "Hide this column" function

## 0.5.5

23 Sept 2026

- Group the items in the column menu
- Add a bunch of new columns
  - Dates & Time (existing: Added)
    - Completed
    - Started
    - Last Active
    - Download Time
    - Seeding Time
  - Totals (new group)
    - Total DL
    - Total UL
    - Remaining
    - Size When Done
  - Limits (new group)
    - DL Limit
    - UL Limit
    - Ratio Limit
    - Idle Limit
    - Peer Limit

## 0.5.4

20th September 2026

- Fix torrent-table column restore logic
- Fix missed sentinel value in ratio column
- Fix "Known folders" in Set Location modal
- Add "Known folders" dropdown to the "Add torrent" modal
- Move known folders to drop-down
- Try simplify UX for the relative path in set location field
- Handle Add exceptions

## 0.5.3

- Fix the signature of the thinned ARM-only release

## 0.5.2

- Add "Set Location" to change a torrent's download location on the daemon (single + bulk via the table context menu, inspector, and toolbar), with a "Move data" option and a full-path preview
- Paths in "Set Location" are relative to the daemon's default download dir (or absolute from `/`); `..`/`.` are resolved, and known folders are suggested
- Add favicons to tracker inspector
- Wire up the RPC for comment, creator, dateCreated, isPrivate, downloadedEver, uploadedEver, activityDate, magnetLink.
- Add the above to the torrent inspector
- Add server stats under the (i) popover

## 0.5.1

25th August 2026

- Redesign Torrent add menu
- Make CMD+O open the Add torrent sheet
- Fix colours that wouldn't change when triggering dark/light modes
- Show active speed limits on the bottom status bar
- Remove turtle mode toggle from the top nav
- Move turtle mode toggle closer to the limits

## 0.5.0

24th August 2026

- Redesign of the settings page
- Implement RPC calls for controlling the daemon's config (via settings)
  - Speed controls
  - Seeding controld
  - Networking + Port checking
  - Blocklist Updating
- Big reorg in the source

## 0.4.1

24th August 2026

- Add support for setting torrent priorities
- Add support for setting file-level priorities
- Add a "no label" section under labels
- Fix a bug where if filtering on a torrent/label/folder, removing the last instance of aforementioned would get you stuck in a filter impossible to get out of.

## 0.4.0

24th August 2026

- **Implement file mapping via URI patterns**
  - Presets for Locally hosted daemons, Cyberduck, Swizzin files, SSHFS/rsync
  - Works via URIs so you can choose whatever protocol you want
  - Option to override the default app that would receive the URI (e.g. to VLC for http:// or sftp:// addresses)
  - Placeholder substitution system so you can make your mappings dynamic
    - Options for encoding your credentials for HTTP basic auth
    - Help with explanations available next to the placeholder dropdown
- Allow duplicating server profiles
- Redesign the file list in the inspector
- Add action for updating the tracker

## 0.3.0

23rd August 2026

- Allow multiple tags to be set on a torrent
- Add colour-coding to the tags
- Adjust background colour of progress bar

## 0.2.2

23rd August 2026

- Change build version numbering to allow multiple releases on same day
- Simplify release flow

## 0.2.1

23rd August 2026

- Fix favicons not fetching
- Show entire changelog in sparkle

## 0.2.0

23rd August 2026

- Major rewrite of the main table to NSTableView directly instead of using the SwiftUI table due to perf and stability
- Fetching favicons for trackers for the sidebar
- Testing suite improvements
- Links in tracker messages are clickable in inspector
- Add snapshot feature to help with troubleshooting
- Do a quick refresh after start/pause to get a quicker refresh on the rows
- Add Apple Silicon-only builds
- Add little about view + page

## 0.1.0

11th July 2026

This is basically the first stable release. These are some of the things that work at this point:

- Adding torrents
  - Using torrent file, or magnet link
  - Handling .torrent file registrations
  - Drag and drop
  - Add paused
  - Set priority and destination folder
  - Add Label
- Filtering torrents
  - Select multiple criteria for subfilter
  - Favicons on torrent lists
  - Download paths relative to default path
  - Collapsable sections
- Store multiple servers
- Free space check
- Turtle mode
- Torrent list
  - Search
  - Start/stop torrents
  - Torrent inspector
    - View details only
  - Verify local data
  - Delete (with or without data)

# Changes since prerelease-2026-10-07-04-aad2cfa1be2a

6d8e2df Update CHANGELOG.md
c018764 ci(release): strip the shipped binary and drop release coverage
ca74cfb test(app): cover the connection branches and the mutations accessor
ca2ed3f refactor(app): inject ConnectionCoordinator dependencies
2f2ea59 test(app): split table logic tests into per-unit suites
b3a8e98 refactor(core): inject the table preference store into TorrentListModel
7116946 docs: mark the AppKit decomposition complete
a1115a7 refactor(app): split OpenMappingEditor into focused files
6c733a3 chore(xcode): canonicalise the package product dependency order
049c324 docs: mark the AppKit decomposition complete
792a519 refactor(app): extract the row context-menu spec
aa44c1f docs: record the mocks-out-of-core outcome
9dc0baa refactor(app): build the mapping-editor fallback torrent inline
70afd63 refactor(core): move mocks into a TransmissionTestSupport target
c6e58a4 docs: add plan for moving the mocks out of TransmissionCore
3466e7c refactor(core): add EmptyTorrentService for the no-server placeholder
fc0b3dd refactor(intents): resolve the mutating service half via TorrentReading.mutations
529a15f refactor(core): make persisted table preferences the single sort source
9c9e03d refactor(app): extract ConnectionCoordinator from ContentView
d360c99 docs: record AppKit decomposition progress
fade607 fix(app): make CrashReporting logger nonisolated
236bb05 refactor(app): extract table row, selection and sort logic
e8dfc32 test(app): cover TorrentCellContent.make
8091772 refactor(app): split TorrentTableCellView into focused files
00f76f0 docs: add plan for decomposing the large AppKit files
9d0c238 refactor(app): use os.Logger instead of NSLog
54fd478 fix(app): avoid force cast when tinting the tag menu image
4abc44f fix(core): keep last-known-good session cache on transient failure
4bffd5a docs: record the TorrentStore coordinator split
14055f0 refactor(core): extract TorrentSheetState from TorrentStore (phase 5)
c8c2105 refactor(core): extract TorrentActionModel from TorrentStore (phase 4)
f98141a refactor(core): extract InspectorModel from TorrentStore (phase 3)
eb9be53 refactor(core): extract SessionModel from TorrentStore (phase 2)
4e34ae8 refactor(core): extract TorrentListModel from TorrentStore (phase 1)
15f9cf4 fix date
5eee988 docs: add plan for splitting TorrentStore
794907a refactor(app): extract MappingLauncher for shared URL launching
a67f7bd refactor(core): split TorrentService into read and mutate capabilities
e315946 refactor: centralize UserDefaults keys in PreferenceKeys
7eb2932 refactor(core): remove unused ConnectionService
f9317e0 ci(codeql): drop Swift analysis
5fee516 ci(intents): run App Intents tests in CI, drop the release lane
83ff5d4 ci(codeql): replace default setup with a scoped Swift build
810b7d7 Update project.pbxproj
03b7729 fix: stop swallowing Keychain failures at the other credential reads
506e4a8 ci(pages): key the uv cache to the build script
e70638b fix(intents): surface keychain failures instead of a blank password
c4b8445 ci(pages): redeploy when the site build script changes
19ec174 fix(site): build the changelog page from the latest release
a3a514a fix(intents): expire an open-torrent request that never lands
70fe9c7 refactor(core): reuse sessionWarmingCache in sessionSettings
de2906a fix(crash-reporting): tag reports with environment and full release
a392022 refactor(core): centralise the prefs TorrentStore reads
9f20fad fix(intents): persist the Spotlight donation log across launches
b902d1a fix(intents): scope torrent entity ids to their server
531e24a fix(ci): pin setup-uv to v10.2.0
da81e59 style(site): flatten screenshots and pin the footer to the bottom
a593308 feat(site): render the Pages site from Jinja templates
93ccc79 docs(intents): correct torrent-picker and derived-stats notes
26889de fix(intents): forget the live service on disconnect
b712391 docs(crash): correct the local-build DSN claim
23f225f chore(favicons): drop the dead forceRevalidate path
e7da6f5 fix(intents): prune removed torrents from Spotlight
ea97b7c fix(intents): stage and clean up Add Torrent uploads safely
3f0eb30 test(core): cover batched speed limits and label verification
61ff957 fix(core): fail add() when label support can't be verified
d5abed6 perf(intents): set torrent speed limits in a single torrent-set
e9cf877 fix(intents): report an unreachable server instead of "no matches"
19d5c50 style(site): show download steps as numbered cards
9035832 feat(site): add a dedicated download page
3db1e15 Update CrashReporting.swift
50e3758 Add donation to the app, add toggles to hide it
9efaa0f Prek Unit tests on push only when relevant
52d5cbb Fix copy, make subtitle
d98329d feat(snapshot): replay the file's server name in the title bar
6de34aa Update main.png
