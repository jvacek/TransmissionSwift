# Changelog

**Versions under 0.6.2 need to be updated manually.** Please check the [release page](https://github.com/jvacek/TransmissionSwift/releases).

## 0.7.4

14th November 2026

- New
  - Drag torrents out of the table as magnet links
  - Type to jump to a torrent in the list
  - Use the inspector's file list with the keyboard and VoiceOver
  - Ask before removing a server, and delete its saved password too
- Fixes
  - Show a Reconnecting label, and recover on your own after a daemon restart, sleep or network change
  - Show clearer errors, and give up on stalled requests sooner
  - Fix Edit Labels erasing labels that only some of the selected torrents had
  - Fix Cancel still applying a change
  - Fix actions and open sheets targeting the wrong server after switching
  - Fix server settings being lost when the settings file is damaged
  - Keep the torrent list when the main window is closed and reopened
  - Clear the Dock badge when the window closes, and remove deleted servers from Spotlight
  - Fix tag colours after switching between light and dark mode
  - Blend the torrent list's column header into the toolbar, like Finder
  - Drop the status bar's frosted background and divider so it sits flush with the window
  - Draw tags as flat colour pills, like Finder
  - Use the system row height in the torrent list, so it's as compact as Finder's
  - Label the inspector toolbar button Show or Hide Inspector, and have VoiceOver read the server switcher as the server's name
  - Fit the Peers tab to the inspector: client and flags sit under the address, and download and upload speeds share a column
  - Sort the inspector's file list from a Sort By menu, and show how many files the torrent has
  - Fix quick clicks on a column header only flipping the sort every other time
  - Use the same title and bottom buttons in every sheet, including Add Torrent
  - Restyle the Add Torrent options like a system form, so labels no longer clip at larger text sizes
  - Only warn about a slash when renaming a torrent
  - Use the standard empty-state layout while connecting and for searches with no results, and stop showing the disconnected labels in red
  - List servers in Settings like mappings, and edit each one in its own sheet
  - Add a details button to server and mapping rows, with Duplicate and Remove in the editor
  - Ask before removing a mapping, and only enable Save once something changed
  - Make the inspector a native column like Xcode's, with the show/hide button above the column and the tabs at its top, the system divider, and resizing that works
  - Show the torrent's name in the inspector's Metadata, with Rename next to it
  - Search from a magnifier button that opens into a field on click or ⌘F
  - Show the server's name on the toolbar's server switcher, and keep the toolbar buttons in separate groups
  - Keep the sidebar button in the toolbar in Icon and Text mode, and caption the server switcher "Server"
  - Animate the sidebar when it's shown or hidden from the View menu
  - Stop the window from clipping the sidebar and inspector when it's narrow
- Performance
  - Lower memory use, smoother sorting and less work while idle on large lists
- Requirements
  - macOS 26.1 or later

## 0.7.3

11th November 2026

- Choose which files a `.torrent` downloads when adding it, with per-file priority
  - Filter the file list
  - Bulk prio/download changes
- Add URL support to Magnet's add tab.
- Add some menu actions and keyboard shortcuts
  - resume, pause, start/stop selected and all, remove, remove with data, copy magnet link, copy name, edit labels, set location, rename, find, inspector and sidebar toggles
- Improve GeoIP DB handling, cutting down RAM usage by ~90 MB

## 0.7.2

3rd Nov 2026

- Modify trackers from torrent inspector (add, remove, move, change)

## 0.7.1

25th Oct 2026

- Fix Inspector's file progress and tracker stats not updating
- Add an incremental refresh interval, move the full refresh default to 15 seconds
- Show a country flag next to each peer in the torrent inspector
  - Local lookups against cached DB
  - Refresh toggle in settings

## 0.7.0

9th Oct 2026

- Add App Intents support
  - Adds TransmissionSwift to Shortcuts.app
    - Get server stats
    - Manage torrents (adding, removing, verifying, re-announcing)
    - Change speed limits server/torrent-wide
  - Allows control from Spotlight and non-AI Siri
- Fix definiton of "Active" status
- Add opt-in for crash reporting
- Fix Favicon cache behaviour to an actual request cache
- Move file mappings to Application settings as app-wide entries
  - Each mapping can apply to all servers, all local servers, all remote servers, or only selected ones
  - Existing per-server mappings are migrated on first launch; identical ones merge into one entry scoped to the servers they were on, or all servers
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
