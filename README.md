# dockja

A per-window dock bar for macOS. Instead of one icon per app, dockja shows one
slot per open window, with a customizable name and icon for each — plus Apple
Dock styling, app groups, auto-hide, and edge snapping.

> ⚠️ Early release (v0.1). Works, but rough edges remain.

## Features

- **Per-window slots** — every open window gets its own entry; click to raise it.
- **Per-window customization** — rename a window and give it a custom icon.
- **App groups** — merge several apps into a single combined section, with an
  original-app badge on custom icons.
- **Apple Dock styling** — magnification and look inspired by the macOS Dock.
- **Auto-hide** — peek-on-approach or click-to-pin, with a configurable delay;
  stays put while an edit/preferences popover is open.
- **Edge snapping** — the bar snaps to a screen edge.

## Requirements

- macOS 14.0 or later
- [Swift toolchain](https://www.swift.org/install/) (ships with Xcode / Command
  Line Tools)

## Build & run

dockja is distributed as source — you build it locally. No prebuilt binary is
shipped.

```bash
git clone https://github.com/Ojajajajaja/dockja.git
cd dockja
./scripts/bundle.sh          # builds and signs dockja.app
open dockja.app
```

### Grant Accessibility permission

dockja reads and raises other apps' windows through the macOS Accessibility
API, so it needs permission:

**System Settings → Privacy & Security → Accessibility → enable `dockja`.**

Without this grant the bar stays empty.

### A note on signing

`bundle.sh` signs the app with whatever code-signing identity it finds in your
keychain, falling back to an **ad-hoc** signature. With an ad-hoc signature the
Accessibility grant resets on every rebuild (you re-grant once). To make the
grant survive rebuilds, create a stable self-signed identity first:

```bash
./scripts/dev-cert.sh        # run once
```

See `scripts/dev-cert.sh` for details.

## Run the tests

```bash
swift test
```

## License

[MIT](LICENSE) — provided "as is", without warranty of any kind.
