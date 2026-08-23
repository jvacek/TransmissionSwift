# Changelog

All notable changes to TransmissionSwift.

## 0.4.0

23rd August 2026

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
