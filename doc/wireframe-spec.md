# TransmissionSwift — Wireframe Spec (v0)

Brief to hand to a wireframing tool (e.g. Claude Design). Response format at the bottom is structured so we can re-parse it into SwiftUI scaffolding.

## Context for the designer
- Native **macOS** app, target **macOS 26** (Liquid Glass era). No iOS layouts.
- Power-user remote control for the **Transmission BitTorrent daemon**, modelled on [transgui](https://github.com/transmission-remote-gui/transgui).
- Polling-only (no push). **Multi-server is first-class** — there is no "the server."
- Today only one screen exists (`ServerStatusView` showing daemon version after a `session-get` ping). Everything below is greenfield.

## Conventions to follow
- `NavigationSplitView` shape: **sidebar · list · inspector** (inspector via `.inspector(isPresented:content:)`).
- Toolbar for primary actions; bottom status bar for global stats.
- Dense, tabular, sortable. Resizable/reorderable columns.
- Sheets for transient flows (add torrent, edit profile). Preferences window for persistent settings.
- No tab bars, no fullscreen modals where a sheet works.

## Liquid Glass conformance (macOS 26)
The wireframes must respect Apple's Liquid Glass guidance — the system applies the material automatically when we use standard components, so the wireframe's job is to *not* fight it.

- **Use system components only.** `NavigationSplitView`, `Table`, `Form(.grouped)`, `Toolbar`, `Inspector`, `Sheet`, `Settings`. No custom backgrounds on toolbars, sidebars, or split views.
- **Toolbar groupings.** Items must be grouped by purpose, with `ToolbarSpacer` between groups (not a flat strip). See S1 below for groupings.
- **Color discipline.** Default to monochromatic. Color is reserved for:
  - status indicators (reachability dot, per-torrent status icon, error banner);
  - the *single* primary CTA per screen, styled `.glassProminent` (e.g. the "Add server" button in S5 onboarding, the "Add" button in S2);
  - nothing else. Toolbar buttons stay monochrome.
- **Liquid Glass variant: `regular`** everywhere. We have no media-rich backgrounds, so `clear` does not apply.
- **No custom `glassEffect` modifiers** in the wireframes — let the system supply the material.
- **Section headers** use title-style capitalization (e.g. "Bandwidth Limits", not "BANDWIDTH LIMITS").
- **Accessibility labels** required on every icon-only toolbar item and status indicator.
- **Scroll edge effect** is automatic on the table — don't sketch any custom top fade.
- **Reduced-transparency / reduced-motion** should still be legible: the wireframe should work with all chrome rendered as opaque.

## Screens to wireframe

### S1 — Main window
**Sidebar (top → bottom):**
- Server switcher (popup or selectable rows; shows label + reachability dot).
- Filters list: All, Downloading, Seeding, Active, Paused, Finished, Error.
- Dynamic groups: Labels, Trackers, Folders. Counts on the right.

**Center — torrent table:**
- Columns: status icon, name, size, progress bar, ↓ speed, ↑ speed, ETA, ratio, seeds/peers, added, tracker.
- Multi-select. Right-click menu (Start, Pause, Remove, Remove+data, Verify, Reannounce, Copy magnet, Set location).

**Inspector (right, toggleable):**
- Tabs: General · Trackers · Peers · Files (tree, per-file priority) · Options (per-torrent limits).

**Toolbar (grouped, separated by `ToolbarSpacer(.fixed)`):**
- Group 1 — *Add*: split-button (file / magnet).
- Group 2 — *Selection actions*: Start, Pause, Remove.
- `ToolbarSpacer(.flexible)`
- Group 3 — *Search*: search field (`.searchable`).
- Group 4 — *View toggles*: inspector toggle, alt-speed toggle.

No toolbar button is colored. The Add split-button is the most prominent action but stays monochrome — emphasis comes from position (leading edge), not color.

**Bottom status bar:** global ↓/↑, free space on download dir, torrent count, active server label.

### S2 — Add torrent sheet
- Segmented control: **From file** / **From magnet or URL**.
- File-tree preview with per-file checkboxes + priority.
- Fields: download location (with recents), label, bandwidth priority, start-paused checkbox.
- Cancel / Add.

### S3 — Server profile management
- Currently lives at `AddServerForm.swift` (single profile only). Needs to become a list.
- List of profiles (label, host:port, reachability).
- Add / Edit / Remove. Edit form: label, host, port, HTTPS toggle, username, password (Keychain), optional RPC path.
- **Test connection** button (renders version on success, typed error on failure — mirror existing `ServerStatusView` behavior).

### S4 — Preferences window
- General · Servers (S3 embedded) · Bandwidth (alt-speed schedule + limits) · Advanced (timeouts, self-signed cert handling).

### S5 — Empty & error states
- No servers → onboarding card centered in window. "Add server" CTA uses `.buttonStyle(.glassProminent)` with the app accent color — this is the one place a colored Liquid Glass background is correct.
- Server unreachable → top banner with Retry. Banner uses a system warning color on text/icon, not on a glass background.
- Auth failure → inline error in edit form, monochrome with a red status icon.

## Interactions to annotate
- Drag-drop `.torrent` / magnet URL onto window → S2 prefilled.
- Keyboard: space (toggle pause), delete (remove), ⌘N (add), ⌘F (focus search), ⌘I (inspector).
- Adaptive polling: visible torrent list = 5s, background = paused. Surface a "live / paused" hint somewhere in S1.

## What we want back from Claude Design
For **each screen**, produce both:
1. A wireframe image (low-fi, grayscale, annotated).
2. A structured block in this exact shape so we can re-parse it:

```yaml
screen: S1
window: { minWidth: 960, minHeight: 600 }
regions:
  - id: sidebar
    control: NavigationSplitView.sidebar
    children:
      - { id: serverSwitcher, control: Picker, items: [...] }
      - { id: filters,        control: List,   items: [...] }
  - id: content
    control: Table
    columns: [status, name, size, progress, downSpeed, upSpeed, eta, ratio, peers, added, tracker]
  - id: inspector
    control: NavigationSplitView.detail
    tabs: [General, Trackers, Peers, Files, Options]
toolbar:
  - group: [add]                              # split-button: file / magnet
  - group: [start, pause, remove]             # selection actions
  - spacer: flexible
  - group: [search]                           # .searchable
  - group: [inspectorToggle, altSpeed]        # view toggles
toolbarStyle: { labels: iconOnly, prominent: none, customBackgrounds: false }
statusBar: [globalDown, globalUp, freeSpace, torrentCount, activeServer]
shortcuts: { space: togglePause, delete: remove, "⌘N": add, "⌘F": search, "⌘I": inspector }
```

Mapping controls to native names (`Table`, `NavigationSplitView`, `Picker`, etc.) lets us drop them straight into SwiftUI.

## Out of scope (this round)
- Visual polish, color, icon design.
- About box, help, onboarding tour.
- iOS/iPadOS layouts.
