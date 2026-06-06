# dockja — Per-App Window Bar (Design Spec)

**Date:** 2026-06-06
**Status:** Approved, pre-implementation
**Platform:** macOS (native Swift + AppKit)

## 1. Problem

macOS aggregates all windows of an app under one Dock icon. Clicking the icon
raises an arbitrary window (usually the most recent), not the one wanted. The
only precise path is right-click → pick from a menu. This is slow for apps with
many windows (browser, editor, notes).

## 2. Goal

A small macOS utility that, for a user-selected set of apps, shows a floating
bar listing **only** the windows of the currently-focused enabled app — one
entry per window, nothing more. Clicking an entry raises and focuses that exact
window. Result: fast, direct navigation between windows of the same app.

## 3. Behavior

- The app is a **menu-bar agent** with no Dock icon of its own (`LSUIElement`).
- A single **contextual bar** follows focus:
  - Frontmost app is **enabled** and has ≥1 window → bar shows that app's
    windows. (No suppression for the 1-window case — avoids show/hide flicker.)
  - Frontmost app is **not enabled** → bar **hides**.
- Each entry shows `[app icon | truncated window title]`. Untitled windows get
  a fallback label (e.g. `Untitled`, or index `#2`).
- The currently-active window of the app is **highlighted**.
- **Click** an entry → raise + focus that window (see §6).
- The bar is **floating and draggable**; its position is remembered across
  launches.
- The bar panel is **non-activating**: interacting with it never steals focus
  from the target app, so clicking an entry can correctly raise another app's
  window.

## 4. Tech stack

Native **Swift + AppKit**, built with Xcode.
- Menu-bar agent via `NSStatusItem`, `LSUIElement = YES`.
- Window enumeration/control via the **Accessibility API** (`AXUIElement`).
- Bar = non-activating floating `NSPanel` hosting a SwiftUI view.
- Preferences = SwiftUI window.

Rationale: only stack with first-class window control; smallest, fastest,
single distributable `.app`. No screen-recording permission needed.

## 5. Architecture / components

Each unit has one job, a clear interface, and is independently testable.

| Component | Responsibility | Depends on |
|-----------|----------------|------------|
| `AccessibilityProvider` (protocol) | Wraps every `AXUIElement` call. Real impl + fake impl for tests. | macOS AX API |
| `WindowEnumerator` | App AX element → `[WindowInfo]` (axRef, title, isMinimized, isActive). | `AccessibilityProvider` |
| `WindowRaiser` | `raise(WindowInfo)`: unminimize → activate app → AXRaise → set main/focused. | `AccessibilityProvider` |
| `FocusObserver` | Emits "frontmost app changed" + "window list/title/focus changed" events, debounced. | `NSWorkspace`, AX observers |
| `BarPanelController` | Owns the floating non-activating `NSPanel`; renders entries; drag-to-move; persists frame. | SwiftUI, `SettingsStore` |
| `PreferencesController` | SwiftUI checklist of running/installed apps + "Add app…" picker; toggles enabled set. | `SettingsStore` |
| `StatusItemController` | Menu-bar icon + menu: Preferences, Accessibility status, Quit. | AppKit |
| `SettingsStore` | Persists enabled bundle IDs + bar frame (JSON in Application Support). | Foundation |
| `AppCoordinator` | Wires the above; the only place with cross-component glue. | all |

### Data model

```
WindowInfo {
  axRef: AXUIElement          // opaque handle to the window
  title: String               // may be empty → fallback label at render
  isMinimized: Bool
  isActive: Bool              // is this the app's focused/main window
}

AppConfig {
  bundleID: String
  displayName: String
  enabled: Bool
  // Future: logoRules: [{ titlePattern: String, imagePath: String }]
}

Persisted (JSON):
  enabledBundleIDs: [String]
  barFrame: { x, y, w, h }
```

### Data flow

```
NSWorkspace.didActivateApplication
        │
        ▼
frontmost bundleID ∈ enabledSet ?
  ── no ──▶ BarPanelController.hide()
  ── yes ─▶ WindowEnumerator.windows(for: app)
                 │
                 ▼
            BarPanelController.show(entries)
            FocusObserver.attach(to: app)   // live updates
                 │
   AX events (created/destroyed/title/focus)
                 ▼
            re-enumerate → BarPanelController.update(entries)

User clicks entry ──▶ WindowRaiser.raise(window)
```

## 6. Window control mechanics (the core)

Enumerate: `AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute)`;
title via `kAXTitleAttribute`; minimized via `kAXMinimizedAttribute`;
active window via the app's `kAXFocusedWindowAttribute` / `kAXMainWindowAttribute`.

Raise a specific window:
1. If `kAXMinimizedAttribute == true` → set it `false` (unminimize).
2. `NSRunningApplication(processIdentifier:).activate(options:)` to bring the
   app forward.
3. `AXUIElementPerformAction(win, kAXRaiseAction)`.
4. Set `kAXMainAttribute = true` (and focused) on the window.

This targets one window precisely, unlike a Dock click.

## 7. Permissions & lifecycle

- Requires **Accessibility** permission only.
- On launch: `AXIsProcessTrustedWithOptions([prompt: true])`.
- If untrusted: menu-bar menu and Preferences show a **"Grant Accessibility"**
  button that opens the relevant System Settings pane. Poll trust status; once
  granted, start `FocusObserver` and enable the bar.
- No screen-recording permission (entries are icon + text, not thumbnails).

## 8. Edge cases

- **Minimized windows**: listed (visually dimmed); raising unminimizes.
- **Other Spaces**: raising a window on another Space switches to it (accepted).
- **Untitled / empty title**: fallback label.
- **Apps exposing no AX windows** (some non-standard/Electron): bar shows empty
  or hides; documented limitation.
- **Rapid app switching**: `FocusObserver` debounces updates.
- **The agent's own panel**: never appears in any list (agent has no normal
  window; panel is excluded by design).
- **Full-screen target window**: AX raise resolves within its Space.

## 9. Out of scope (MVP) — designed to allow later

- **Per-window custom logo images** (primary long-term goal): map a window
  (by title pattern) to a user-linked image used in place of the app icon.
  Data model reserves `AppConfig.logoRules` for this.
- Vertical bar orientation.
- Keyboard-driven window switching.
- Close / minimize actions from the bar.

## 10. Testing

- **Unit** (AX faked via `AccessibilityProvider`):
  - `WindowEnumerator`: AX values → `WindowInfo` mapping, active/minimized flags.
  - `SettingsStore`: round-trip persistence.
  - Title fallback logic.
  - Enabled-set filtering (show/hide decision).
  - `FocusObserver` debounce.
- **Manual / integration**:
  - Accessibility permission flow (untrusted → granted).
  - Raise correctness: normal, minimized, across Spaces, full-screen.
  - Drag bar → position persists across relaunch.
  - Live update when target app opens/closes a window or retitles one.
