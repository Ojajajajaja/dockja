# dockja — Per-Window Customization + Apple Dock Mode (Design Spec)

**Date:** 2026-06-06
**Status:** Approved, pre-implementation
**Builds on:** the per-app window bar MVP (already on `develop`)

## 1. Goal

Two related features sharing one per-window override model:

1. **Right-click edit** of a bar entry: change its display **name** and **icon**
   (load any image via browse, with a persistent grid of **recent icons**
   always offered).
2. A second display mode, **Apple Dock**, that mimics the macOS Dock: large
   icons, no titles, edge-snapped, horizontal or vertical, with an active-window
   indicator dot, hover tooltip, and hover magnification. The existing layout is
   renamed **Compact**.

## 2. Context / constraints

- The user's window titles are **unstable** (Warp varies by activity; Brave does
  not expose the profile/path). So customizations **cannot** be keyed by title.
- Therefore per-window overrides are keyed by **`CGWindowID`** (already on
  `WindowInfo.id`), which is stable for the window's lifetime. Overrides are
  **session-scoped**: they live as long as the window and are lost when the app
  (or window) closes. There is **no cross-restart persistence of overrides**.
- The **recent-icons library is persisted**, so re-applying after a restart is
  one click.

## 3. Feature A — Right-click edit popover

- Right-click a bar entry → an **NSPopover** anchored to that entry, hosting a
  SwiftUI `EditView`. On open, `NSApp.activate(ignoringOtherApps: true)` so the
  name field can take keyboard focus (the bar itself is non-activating and can't).
- `EditView` contents:
  - **Name** text field (display-only override; we do not rename the real macOS
    window — most apps ignore `kAXTitleAttribute` writes).
  - **Recent icons** grid — clicking one applies it immediately.
  - **Browse…** → `NSOpenPanel` with `allowedContentTypes = [.image]` (png, jpg,
    heic, tiff, gif, icns, pdf, …).
  - **Reset** — clears this window's override.
- Editing writes to the in-memory `WindowOverrideStore` keyed by `CGWindowID`.
- Display resolution for every entry (both modes):
  - name = `override.customName` (if non-empty) else `window.displayLabel`
  - icon = image at `override.iconPath` (if set & loadable) else the app icon

## 4. Feature B — Recent-icons library (persisted)

- **Browse…** copies the chosen image into
  `~/Library/Application Support/dockja/icons/` (so deleting the original never
  breaks an override), returning the copied path.
- That path is added to the recents list: **most-recent-first, de-duplicated,
  capped at 12**. The list is persisted in settings.
- The recents grid always shows the current list (plus the Browse button).

## 5. Feature C — Display modes

Global mode, toggled from the **menu-bar menu** (`Compact ✓ / Apple Dock`),
persisted as `displayMode`.

### Compact (existing, unchanged)
Free-floating, draggable, **horizontal** fixed-size chips (icon + centered
name). Position remembered via `barFrame`. **No edge-snapping.**

### Apple Dock (new)
- **Large icons (~48 pt), no title.** Icon = custom override icon, else app icon.
- **Hover tooltip** showing the window name.
- **Active-window dot** on the side facing the screen interior:
  bottom edge → dot above the icon, top edge → below, left edge → right, right
  edge → left.
- **Hover magnification** (macOS-Dock style): icons scale up near the cursor.
  This is the heaviest piece; a reduced version (scale the hovered icon + its
  immediate neighbors) is an acceptable first cut.
- **Auto-snap to nearest screen edge** on drag end: top/bottom → **horizontal**
  layout, left/right → **vertical** layout. Persisted as `dockEdge` + a parallel
  offset (position along the edge). Snapping applies **only** in this mode.

Switching modes repositions the bar: Compact restores `barFrame`; Apple Dock
restores `dockEdge` + parallel offset (or snaps to a default edge first time).

## 6. Architecture

### DockjaCore (new, unit-tested — no AppKit)
- `DisplayMode` enum: `.compact`, `.appleDock` (Codable).
- `DockEdge` enum: `.top`, `.bottom`, `.left`, `.right` (Codable); `isHorizontal`.
- `OverrideResolver`: `resolve([WindowInfo], overrides: [CGWindowID: WindowOverride]) -> [DisplayWindow]`.
  - `WindowOverride { customName: String?; iconPath: String? }`
  - `DisplayWindow { window: WindowInfo; name: String; iconPath: String? }`
  - name/icon resolution per §3; icon image loading stays in the view layer.
- `RecentIcons` (Codable): `paths: [String]`, `mutating func add(_:)` =
  move-to-front + dedup + cap(12).
- `EdgeSnapper` (pure geometry, screens passed as `CGRect`):
  - `nearestEdge(barCenter: CGPoint, screen: CGRect) -> DockEdge`
  - `origin(for edge: DockEdge, size: CGSize, parallel: CGFloat, screen: CGRect) -> CGPoint`
    (flush to edge, parallel coordinate clamped within screen).

### dockja executable (AppKit/SwiftUI glue)
- `WindowOverrideStore` — in-memory `[CGWindowID: WindowOverride]`; get/set
  name, set icon, reset. Not persisted.
- `IconLibrary` — copies a picked image into App Support/icons/, returns the
  path, updates `RecentIcons`, persists via `SettingsStore`.
- `EditPopoverController` — builds/shows the `NSPopover` + `EditView` for a given
  entry rect and `CGWindowID`.
- `BarView` — two layouts:
  - Compact: existing fixed-size chips (icon + centered name), now name/icon from
    `DisplayWindow`.
  - Apple Dock: orientation-aware `HStack`/`VStack` of large icons, with tooltip,
    active dot (placed per `dockEdge`), and magnification.
  - Right-click on an entry → callback into `EditPopoverController` (via a small
    `NSViewRepresentable` that catches `rightMouseDown`).
- `BarPanelController` — mode-aware positioning: Compact = free drag (current);
  Apple Dock = on drag end compute `nearestEdge`, set orientation, re-fit, snap
  origin via `EdgeSnapper`, persist `dockEdge` + parallel offset.
- `StatusItemController` — add the `Compact / Apple Dock` mode items.
- `SettingsStore` — add `displayMode`, `dockEdge`, `dockParallel`, `recentIcons`
  (all Codable; existing fields unchanged).
- `AppCoordinator` — pass `displayMode` + resolved `DisplayWindow`s to the bar;
  own the `WindowOverrideStore` + `IconLibrary`; prune overrides whose window id
  disappears (optional housekeeping).

## 7. Data / persistence

- **Persisted** (`settings.json`): existing (`enabledBundleIDs`, `barFrame`) plus
  `displayMode`, `dockEdge`, `dockParallel`, `recentIcons` (array of paths).
  Image files copied under `App Support/dockja/icons/`.
- **Ephemeral** (in memory only): per-window overrides keyed by `CGWindowID`.

## 8. Testing

- **Unit (DockjaCore, faked/no AppKit):**
  - `OverrideResolver`: name fallback, custom name wins, icon path passthrough,
    empty custom name ignored.
  - `RecentIcons`: add moves to front, dedups, caps at 12.
  - `EdgeSnapper`: nearest edge for points near each edge; origin flush + parallel
    clamp for each edge; horizontal/vertical mapping.
  - `DockEdge.isHorizontal`, Codable round-trips for new settings fields.
- **Manual:**
  - Right-click → popover; rename; browse + apply; click a recent; reset.
  - Recents persist across relaunch; an override is lost when the target app
    restarts; the icon file remains for one-click re-apply.
  - Toggle Compact ↔ Apple Dock from the menu.
  - Apple Dock: snap to each of the 4 edges; layout flips H/V; active dot on the
    correct side; tooltip on hover; magnification near cursor.
  - Compact still free-floats (no snap).

## 9. Out of scope

- Cross-restart persistence of per-window overrides (titles too unstable).
- Per-app display mode (mode is global for now).
- Renaming the actual macOS window via AX.
