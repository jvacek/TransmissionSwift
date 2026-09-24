# Changelog

All notable changes to TransmissionSwift.

## 0.5.6

24th Sept 2026

- Add a button and menu item to open a new github issue with the versions pre-filled
- Fix the seedcount column

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
