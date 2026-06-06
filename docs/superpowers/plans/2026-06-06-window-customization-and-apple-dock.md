# Per-Window Customization + Apple Dock Mode — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add right-click editing of a bar entry's name/icon (with a persistent recent-icons library) and a second display mode, "Apple Dock" (large edge-snapped icons, no titles, active dot, tooltip, magnification), alongside the existing "Compact" mode.

**Architecture:** New pure logic in `DockjaCore` (display-mode + dock-edge enums, override resolution, recent-icons list management, edge-snap geometry) is unit-tested with no AppKit. The `dockja` executable adds the AppKit/SwiftUI glue: in-memory per-window override store, icon file library, an NSPopover editor, a two-layout `BarView`, mode-aware panel positioning, and menu wiring.

**Tech Stack:** Swift 6.2, AppKit, SwiftUI, ApplicationServices, Swift Package Manager. macOS 14+. Tests via XCTest (`swift test`).

---

## File Structure

```
Sources/DockjaCore/
  DisplayMode.swift            # NEW: DisplayMode enum
  DockEdge.swift               # NEW: DockEdge enum (+ isHorizontal)
  WindowOverride.swift         # NEW: WindowOverride, DisplayWindow, OverrideResolver
  WindowOverrideStore.swift    # NEW: in-memory CGWindowID -> override store
  RecentIcons.swift            # NEW: recent-icon list (add/dedup/cap)
  EdgeSnapper.swift            # NEW: nearestEdge + origin geometry
  SettingsStore.swift          # MODIFY: add displayMode/dockEdge/dockParallel/recentIcons
Sources/dockja/
  IconLibrary.swift            # NEW: copy image into App Support, update recents
  EditPopoverController.swift  # NEW: NSPopover + EditView
  BarView.swift                # MODIFY: BarModel + dispatcher + Compact layout + right-click catcher
  DockBarView.swift            # NEW: Apple Dock layout (icons, dot, tooltip, magnification)
  BarPanelController.swift     # MODIFY: mode-aware positioning + edge snapping
  StatusItemController.swift   # MODIFY: Compact / Apple Dock menu items
  AppCoordinator.swift         # MODIFY: override store + icon library + resolver + wiring
Tests/DockjaCoreTests/
  DisplayModeTests.swift       # NEW
  DockEdgeTests.swift          # NEW
  OverrideResolverTests.swift  # NEW
  WindowOverrideStoreTests.swift # NEW
  RecentIconsTests.swift       # NEW
  EdgeSnapperTests.swift       # NEW
  SettingsStoreTests.swift     # MODIFY: backward-compat decode test
```

---

## Task 1: DisplayMode + DockEdge enums

**Files:**
- Create: `Sources/DockjaCore/DisplayMode.swift`
- Create: `Sources/DockjaCore/DockEdge.swift`
- Test: `Tests/DockjaCoreTests/DisplayModeTests.swift`
- Test: `Tests/DockjaCoreTests/DockEdgeTests.swift`

- [ ] **Step 1: Write the failing tests**

`Tests/DockjaCoreTests/DisplayModeTests.swift`:
```swift
import XCTest
import Foundation
@testable import DockjaCore

final class DisplayModeTests: XCTestCase {
    func testCodableRoundTrip() throws {
        let data = try JSONEncoder().encode(DisplayMode.appleDock)
        XCTAssertEqual(try JSONDecoder().decode(DisplayMode.self, from: data), .appleDock)
    }

    func testRawValuesStable() {
        XCTAssertEqual(DisplayMode.compact.rawValue, "compact")
        XCTAssertEqual(DisplayMode.appleDock.rawValue, "appleDock")
    }
}
```

`Tests/DockjaCoreTests/DockEdgeTests.swift`:
```swift
import XCTest
@testable import DockjaCore

final class DockEdgeTests: XCTestCase {
    func testIsHorizontal() {
        XCTAssertTrue(DockEdge.top.isHorizontal)
        XCTAssertTrue(DockEdge.bottom.isHorizontal)
        XCTAssertFalse(DockEdge.left.isHorizontal)
        XCTAssertFalse(DockEdge.right.isHorizontal)
    }

    func testCodableRoundTrip() throws {
        for edge in [DockEdge.top, .bottom, .left, .right] {
            let data = try JSONEncoder().encode(edge)
            XCTAssertEqual(try JSONDecoder().decode(DockEdge.self, from: data), edge)
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter DisplayModeTests`
Expected: FAIL — `cannot find 'DisplayMode' in scope`.

- [ ] **Step 3: Write the implementations**

`Sources/DockjaCore/DisplayMode.swift`:
```swift
import Foundation

public enum DisplayMode: String, Codable, Equatable {
    case compact
    case appleDock
}
```

`Sources/DockjaCore/DockEdge.swift`:
```swift
import Foundation

public enum DockEdge: String, Codable, Equatable {
    case top
    case bottom
    case left
    case right

    public var isHorizontal: Bool { self == .top || self == .bottom }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter DisplayModeTests; swift test --filter DockEdgeTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/DockjaCore/DisplayMode.swift Sources/DockjaCore/DockEdge.swift Tests/DockjaCoreTests/DisplayModeTests.swift Tests/DockjaCoreTests/DockEdgeTests.swift
git commit -m "Add DisplayMode and DockEdge enums"
```

---

## Task 2: WindowOverride + DisplayWindow + OverrideResolver

**Files:**
- Create: `Sources/DockjaCore/WindowOverride.swift`
- Test: `Tests/DockjaCoreTests/OverrideResolverTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import CoreGraphics
@testable import DockjaCore

final class OverrideResolverTests: XCTestCase {
    private func win(_ id: CGWindowID, _ title: String) -> WindowInfo {
        WindowInfo(ref: WindowRef(), id: id, title: title,
                   isMinimized: false, isActive: false, pid: 1)
    }

    func testUsesTitleWhenNoOverride() {
        let out = OverrideResolver().resolve([win(1, "Gmail")], overrides: [:])
        XCTAssertEqual(out[0].name, "Gmail")
        XCTAssertNil(out[0].iconPath)
        XCTAssertEqual(out[0].window.id, 1)
    }

    func testCustomNameWins() {
        let ov: [CGWindowID: WindowOverride] = [1: WindowOverride(customName: "Build", iconPath: "/a.png")]
        let out = OverrideResolver().resolve([win(1, "Gmail")], overrides: ov)
        XCTAssertEqual(out[0].name, "Build")
        XCTAssertEqual(out[0].iconPath, "/a.png")
    }

    func testEmptyCustomNameFallsBackToTitle() {
        let ov: [CGWindowID: WindowOverride] = [1: WindowOverride(customName: "", iconPath: nil)]
        let out = OverrideResolver().resolve([win(1, "Gmail")], overrides: ov)
        XCTAssertEqual(out[0].name, "Gmail")
    }

    func testUntitledFallback() {
        let out = OverrideResolver().resolve([win(2, "")], overrides: [:])
        XCTAssertEqual(out[0].name, "Untitled")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter OverrideResolverTests`
Expected: FAIL — `cannot find 'OverrideResolver' in scope`.

- [ ] **Step 3: Write `Sources/DockjaCore/WindowOverride.swift`**

```swift
import Foundation
import CoreGraphics

/// A per-window display override. Keyed elsewhere by CGWindowID.
public struct WindowOverride: Equatable {
    public var customName: String?
    public var iconPath: String?

    public init(customName: String? = nil, iconPath: String? = nil) {
        self.customName = customName
        self.iconPath = iconPath
    }

    /// True when there is nothing to remember (used to drop empty entries).
    public var isEmpty: Bool {
        (customName?.isEmpty ?? true) && (iconPath?.isEmpty ?? true)
    }
}

/// A window plus its resolved display name and optional custom icon path.
public struct DisplayWindow {
    public let window: WindowInfo
    public let name: String
    public let iconPath: String?

    public init(window: WindowInfo, name: String, iconPath: String?) {
        self.window = window
        self.name = name
        self.iconPath = iconPath
    }
}

/// Merges raw windows with per-window overrides into display models.
public struct OverrideResolver {
    public init() {}

    public func resolve(_ windows: [WindowInfo],
                        overrides: [CGWindowID: WindowOverride]) -> [DisplayWindow] {
        windows.map { w in
            let o = overrides[w.id]
            let name: String
            if let custom = o?.customName, !custom.isEmpty {
                name = custom
            } else {
                name = w.displayLabel
            }
            let iconPath = (o?.iconPath?.isEmpty == false) ? o?.iconPath : nil
            return DisplayWindow(window: w, name: name, iconPath: iconPath)
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter OverrideResolverTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/DockjaCore/WindowOverride.swift Tests/DockjaCoreTests/OverrideResolverTests.swift
git commit -m "Add WindowOverride, DisplayWindow, OverrideResolver"
```

---

## Task 3: WindowOverrideStore

**Files:**
- Create: `Sources/DockjaCore/WindowOverrideStore.swift`
- Test: `Tests/DockjaCoreTests/WindowOverrideStoreTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import CoreGraphics
@testable import DockjaCore

final class WindowOverrideStoreTests: XCTestCase {
    func testSetNameAndIcon() {
        let store = WindowOverrideStore()
        store.setName("Build", for: 5)
        store.setIcon("/a.png", for: 5)
        XCTAssertEqual(store.override(for: 5).customName, "Build")
        XCTAssertEqual(store.override(for: 5).iconPath, "/a.png")
        XCTAssertEqual(store.overrides()[5]?.customName, "Build")
    }

    func testResetRemoves() {
        let store = WindowOverrideStore()
        store.setName("Build", for: 5)
        store.reset(5)
        XCTAssertTrue(store.overrides().isEmpty)
        XCTAssertNil(store.override(for: 5).customName)
    }

    func testClearingBothFieldsDropsEntry() {
        let store = WindowOverrideStore()
        store.setName("Build", for: 5)
        store.setName(nil, for: 5)   // now empty
        XCTAssertTrue(store.overrides().isEmpty)
    }

    func testPruneKeepsOnlyLiveIDs() {
        let store = WindowOverrideStore()
        store.setName("A", for: 1)
        store.setName("B", for: 2)
        store.prune(keeping: [2])
        XCTAssertNil(store.overrides()[1])
        XCTAssertEqual(store.overrides()[2]?.customName, "B")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter WindowOverrideStoreTests`
Expected: FAIL — `cannot find 'WindowOverrideStore' in scope`.

- [ ] **Step 3: Write `Sources/DockjaCore/WindowOverrideStore.swift`**

```swift
import Foundation
import CoreGraphics

/// In-memory per-window overrides, keyed by CGWindowID (stable for the window's
/// lifetime). Not persisted: overrides are intentionally lost when the window
/// or its app closes.
public final class WindowOverrideStore {
    private var map: [CGWindowID: WindowOverride] = [:]

    public init() {}

    public func overrides() -> [CGWindowID: WindowOverride] { map }

    public func override(for id: CGWindowID) -> WindowOverride { map[id] ?? WindowOverride() }

    public func setName(_ name: String?, for id: CGWindowID) {
        var o = map[id] ?? WindowOverride()
        o.customName = name
        store(o, for: id)
    }

    public func setIcon(_ path: String?, for id: CGWindowID) {
        var o = map[id] ?? WindowOverride()
        o.iconPath = path
        store(o, for: id)
    }

    public func reset(_ id: CGWindowID) { map[id] = nil }

    public func prune(keeping liveIDs: Set<CGWindowID>) {
        map = map.filter { liveIDs.contains($0.key) }
    }

    private func store(_ o: WindowOverride, for id: CGWindowID) {
        map[id] = o.isEmpty ? nil : o
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter WindowOverrideStoreTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/DockjaCore/WindowOverrideStore.swift Tests/DockjaCoreTests/WindowOverrideStoreTests.swift
git commit -m "Add WindowOverrideStore"
```

---

## Task 4: RecentIcons

**Files:**
- Create: `Sources/DockjaCore/RecentIcons.swift`
- Test: `Tests/DockjaCoreTests/RecentIconsTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import DockjaCore

final class RecentIconsTests: XCTestCase {
    func testAddMovesToFront() {
        var r = RecentIcons(paths: ["/a", "/b"])
        r.add("/b")
        XCTAssertEqual(r.paths, ["/b", "/a"])
    }

    func testAddDedups() {
        var r = RecentIcons(paths: ["/a"])
        r.add("/a")
        XCTAssertEqual(r.paths, ["/a"])
    }

    func testAddCaps() {
        var r = RecentIcons()
        for i in 0..<20 { r.add("/\(i)", cap: 12) }
        XCTAssertEqual(r.paths.count, 12)
        XCTAssertEqual(r.paths.first, "/19")
        XCTAssertEqual(r.paths.last, "/8")
    }

    func testCodableRoundTrip() throws {
        let r = RecentIcons(paths: ["/a", "/b"])
        let data = try JSONEncoder().encode(r)
        XCTAssertEqual(try JSONDecoder().decode(RecentIcons.self, from: data), r)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter RecentIconsTests`
Expected: FAIL — `cannot find 'RecentIcons' in scope`.

- [ ] **Step 3: Write `Sources/DockjaCore/RecentIcons.swift`**

```swift
import Foundation

/// Ordered, de-duplicated, capped list of recently used icon file paths.
public struct RecentIcons: Codable, Equatable {
    public private(set) var paths: [String]

    public init(paths: [String] = []) { self.paths = paths }

    public mutating func add(_ path: String, cap: Int = 12) {
        paths.removeAll { $0 == path }
        paths.insert(path, at: 0)
        if paths.count > cap { paths = Array(paths.prefix(cap)) }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter RecentIconsTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/DockjaCore/RecentIcons.swift Tests/DockjaCoreTests/RecentIconsTests.swift
git commit -m "Add RecentIcons list helper"
```

---

## Task 5: EdgeSnapper

**Files:**
- Create: `Sources/DockjaCore/EdgeSnapper.swift`
- Test: `Tests/DockjaCoreTests/EdgeSnapperTests.swift`

Coordinates follow AppKit: origin bottom-left, y increases upward. `screen` is a
visible-frame rectangle.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import CoreGraphics
@testable import DockjaCore

final class EdgeSnapperTests: XCTestCase {
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let snapper = EdgeSnapper()

    func testNearestEdge() {
        XCTAssertEqual(snapper.nearestEdge(barCenter: CGPoint(x: 20, y: 400), screen: screen), .left)
        XCTAssertEqual(snapper.nearestEdge(barCenter: CGPoint(x: 980, y: 400), screen: screen), .right)
        XCTAssertEqual(snapper.nearestEdge(barCenter: CGPoint(x: 500, y: 20), screen: screen), .bottom)
        XCTAssertEqual(snapper.nearestEdge(barCenter: CGPoint(x: 500, y: 780), screen: screen), .top)
    }

    func testOriginBottomIsFlushAndClamped() {
        let o = snapper.origin(for: .bottom, size: CGSize(width: 200, height: 50),
                               parallel: 5000, screen: screen)
        XCTAssertEqual(o.y, 0)            // flush to bottom
        XCTAssertEqual(o.x, 800)          // clamped to maxX - width
    }

    func testOriginTopIsFlush() {
        let o = snapper.origin(for: .top, size: CGSize(width: 200, height: 50),
                               parallel: 100, screen: screen)
        XCTAssertEqual(o.y, 750)          // maxY - height
        XCTAssertEqual(o.x, 100)
    }

    func testOriginLeftIsFlushAndClamped() {
        let o = snapper.origin(for: .left, size: CGSize(width: 50, height: 200),
                               parallel: -100, screen: screen)
        XCTAssertEqual(o.x, 0)            // flush to left
        XCTAssertEqual(o.y, 0)            // clamped to minY
    }

    func testOriginRightIsFlush() {
        let o = snapper.origin(for: .right, size: CGSize(width: 50, height: 200),
                               parallel: 300, screen: screen)
        XCTAssertEqual(o.x, 950)          // maxX - width
        XCTAssertEqual(o.y, 300)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter EdgeSnapperTests`
Expected: FAIL — `cannot find 'EdgeSnapper' in scope`.

- [ ] **Step 3: Write `Sources/DockjaCore/EdgeSnapper.swift`**

```swift
import Foundation
import CoreGraphics

/// Pure geometry for docking the bar to a screen edge. AppKit coordinates
/// (origin bottom-left, y up). `screen` should be a visible-frame rect.
public struct EdgeSnapper {
    public init() {}

    public func nearestEdge(barCenter c: CGPoint, screen s: CGRect) -> DockEdge {
        let dLeft = c.x - s.minX
        let dRight = s.maxX - c.x
        let dBottom = c.y - s.minY
        let dTop = s.maxY - c.y
        let m = min(dLeft, dRight, dBottom, dTop)
        if m == dLeft { return .left }
        if m == dRight { return .right }
        if m == dBottom { return .bottom }
        return .top
    }

    /// Origin that places `size` flush against `edge`, with the parallel axis
    /// (x for top/bottom, y for left/right) set to `parallel`, clamped on-screen.
    public func origin(for edge: DockEdge, size: CGSize,
                       parallel: CGFloat, screen s: CGRect) -> CGPoint {
        switch edge {
        case .bottom:
            return CGPoint(x: clamp(parallel, s.minX, s.maxX - size.width), y: s.minY)
        case .top:
            return CGPoint(x: clamp(parallel, s.minX, s.maxX - size.width), y: s.maxY - size.height)
        case .left:
            return CGPoint(x: s.minX, y: clamp(parallel, s.minY, s.maxY - size.height))
        case .right:
            return CGPoint(x: s.maxX - size.width, y: clamp(parallel, s.minY, s.maxY - size.height))
        }
    }

    private func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        guard hi > lo else { return lo }
        return max(lo, min(hi, v))
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter EdgeSnapperTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/DockjaCore/EdgeSnapper.swift Tests/DockjaCoreTests/EdgeSnapperTests.swift
git commit -m "Add EdgeSnapper geometry"
```

---

## Task 6: Settings additions (display mode, dock edge, recents)

**Files:**
- Modify: `Sources/DockjaCore/SettingsStore.swift`
- Modify: `Tests/DockjaCoreTests/SettingsStoreTests.swift`

The current `Settings` is:
```swift
public struct Settings: Codable, Equatable {
    public var enabledBundleIDs: [String]
    public var barFrame: CGRect?
    public init(enabledBundleIDs: [String] = [], barFrame: CGRect? = nil) { ... }
}
```
New fields must decode from old JSON that lacks them, so add a backward-compatible
`init(from:)` using `decodeIfPresent`.

- [ ] **Step 1: Write the failing test (append to `SettingsStoreTests.swift`)**

Add these methods inside `final class SettingsStoreTests`:
```swift
    func testNewFieldsDefaultWhenDecodingOldJSON() throws {
        // Old settings.json written before these fields existed.
        let json = #"{"enabledBundleIDs":["com.apple.Safari"]}"#
        let s = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
        XCTAssertEqual(s.enabledBundleIDs, ["com.apple.Safari"])
        XCTAssertEqual(s.displayMode, .compact)
        XCTAssertEqual(s.dockEdge, .bottom)
        XCTAssertNil(s.dockParallel)
        XCTAssertEqual(s.recentIcons, [])
    }

    func testNewFieldsRoundTrip() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dockja-test-\(UUID().uuidString)")
        let store = SettingsStore(directory: dir)
        store.update {
            $0.displayMode = .appleDock
            $0.dockEdge = .left
            $0.dockParallel = 120
            $0.recentIcons = ["/a.png", "/b.png"]
        }
        let reloaded = SettingsStore(directory: dir)
        XCTAssertEqual(reloaded.settings.displayMode, .appleDock)
        XCTAssertEqual(reloaded.settings.dockEdge, .left)
        XCTAssertEqual(reloaded.settings.dockParallel, 120)
        XCTAssertEqual(reloaded.settings.recentIcons, ["/a.png", "/b.png"])
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SettingsStoreTests`
Expected: FAIL — `value of type 'Settings' has no member 'displayMode'`.

- [ ] **Step 3: Replace the `Settings` struct in `Sources/DockjaCore/SettingsStore.swift`**

Replace the existing `public struct Settings { ... }` with:
```swift
public struct Settings: Codable, Equatable {
    public var enabledBundleIDs: [String]
    public var barFrame: CGRect?
    public var displayMode: DisplayMode
    public var dockEdge: DockEdge
    public var dockParallel: CGFloat?
    public var recentIcons: [String]

    public init(enabledBundleIDs: [String] = [],
                barFrame: CGRect? = nil,
                displayMode: DisplayMode = .compact,
                dockEdge: DockEdge = .bottom,
                dockParallel: CGFloat? = nil,
                recentIcons: [String] = []) {
        self.enabledBundleIDs = enabledBundleIDs
        self.barFrame = barFrame
        self.displayMode = displayMode
        self.dockEdge = dockEdge
        self.dockParallel = dockParallel
        self.recentIcons = recentIcons
    }

    // Backward-compatible: tolerate JSON written before these fields existed.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabledBundleIDs = try c.decodeIfPresent([String].self, forKey: .enabledBundleIDs) ?? []
        barFrame = try c.decodeIfPresent(CGRect.self, forKey: .barFrame)
        displayMode = try c.decodeIfPresent(DisplayMode.self, forKey: .displayMode) ?? .compact
        dockEdge = try c.decodeIfPresent(DockEdge.self, forKey: .dockEdge) ?? .bottom
        dockParallel = try c.decodeIfPresent(CGFloat.self, forKey: .dockParallel)
        recentIcons = try c.decodeIfPresent([String].self, forKey: .recentIcons) ?? []
    }
}
```
(The synthesized `Encodable` and `CodingKeys` remain valid alongside the custom
`init(from:)`. Leave the rest of `SettingsStore` unchanged.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter SettingsStoreTests`
Expected: PASS (4 tests — 2 existing + 2 new).

- [ ] **Step 5: Run the full DockjaCore suite**

Run: `swift test`
Expected: PASS — all DockjaCore tests green (Tasks 1-6 + pre-existing).

- [ ] **Step 6: Commit**

```bash
git add Sources/DockjaCore/SettingsStore.swift Tests/DockjaCoreTests/SettingsStoreTests.swift
git commit -m "Add displayMode/dockEdge/dockParallel/recentIcons to Settings"
```

---

## Task 7: IconLibrary (copy image + update recents)

**Files:**
- Create: `Sources/dockja/IconLibrary.swift`

Not unit-tested (file IO + AppKit image validation); verified by compilation and
the manual checklist.

- [ ] **Step 1: Write `Sources/dockja/IconLibrary.swift`**

```swift
import AppKit
import DockjaCore

/// Copies chosen images into the app's icon folder and tracks recents.
final class IconLibrary {
    private let dir: URL
    private let settings: SettingsStore

    init(settings: SettingsStore) {
        self.settings = settings
        dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("dockja/icons")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    /// Validate, copy into the library, register in recents. Returns the new path
    /// or nil if the file isn't a readable image / copy failed.
    func importImage(from url: URL) -> String? {
        guard NSImage(contentsOf: url) != nil else { return nil }
        let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension
        let dest = dir.appendingPathComponent(UUID().uuidString + "." + ext)
        do {
            try FileManager.default.copyItem(at: url, to: dest)
        } catch {
            return nil
        }
        var recents = RecentIcons(paths: settings.settings.recentIcons)
        recents.add(dest.path)
        settings.update { $0.recentIcons = recents.paths }
        return dest.path
    }

    var recents: [String] { settings.settings.recentIcons }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: builds with no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/dockja/IconLibrary.swift
git commit -m "Add IconLibrary for importing icons and tracking recents"
```

---

## Task 8: BarView — consume DisplayWindow, add right-click catcher (Compact)

**Files:**
- Modify: `Sources/dockja/BarView.swift`

This rewrites `BarModel` and `BarView` to consume `[DisplayWindow]`, load custom
icons (falling back to the app icon), dispatch on `DisplayMode`, and catch
right-clicks. The Apple Dock layout is added in Task 9; for now its branch shows
the compact layout as a placeholder call to `CompactBar`.

- [ ] **Step 1: Replace `Sources/dockja/BarView.swift` entirely**

```swift
import SwiftUI
import AppKit
import CoreGraphics
import DockjaCore

final class BarModel: ObservableObject {
    @Published var mode: DisplayMode = .compact
    @Published var edge: DockEdge = .bottom
    @Published var appIcon: NSImage?
    @Published var items: [DisplayWindow] = []

    private var iconCache: [String: NSImage] = [:]

    func update(items: [DisplayWindow], appIcon: NSImage?) {
        self.items = items
        self.appIcon = appIcon
    }

    /// Custom icon for the item if set & loadable, else the app icon.
    func image(for item: DisplayWindow) -> NSImage? {
        if let path = item.iconPath {
            if let cached = iconCache[path] { return cached }
            if let img = NSImage(contentsOfFile: path) {
                iconCache[path] = img
                return img
            }
        }
        return appIcon
    }
}

struct BarView: View {
    @ObservedObject var model: BarModel
    let onSelect: (WindowInfo) -> Void
    let onRightClick: (CGWindowID, NSView) -> Void

    var body: some View {
        Group {
            switch model.mode {
            case .compact:
                CompactBar(model: model, onSelect: onSelect, onRightClick: onRightClick)
            case .appleDock:
                DockBar(model: model, onSelect: onSelect, onRightClick: onRightClick)
            }
        }
    }
}

struct CompactBar: View {
    @ObservedObject var model: BarModel
    let onSelect: (WindowInfo) -> Void
    let onRightClick: (CGWindowID, NSView) -> Void

    private let chipWidth: CGFloat = 150
    private let chipHeight: CGFloat = 28
    private let iconSize: CGFloat = 16

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(model.items.enumerated()), id: \.offset) { _, item in
                Button {
                    onSelect(item.window)
                } label: {
                    ZStack {
                        Text(item.name)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, iconSize + 10)
                        HStack {
                            if let icon = model.image(for: item) {
                                Image(nsImage: icon).resizable().frame(width: iconSize, height: iconSize)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.leading, 6)
                    }
                    .frame(width: chipWidth, height: chipHeight)
                    .background(item.window.isActive ? Color.accentColor.opacity(0.3)
                                                     : Color.gray.opacity(0.15))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .opacity(item.window.isMinimized ? 0.5 : 1.0)
                .background(RightClickCatcher { view in onRightClick(item.window.id, view) })
            }
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .fixedSize()
    }
}

/// Transparent overlay that reports right-clicks and exposes its NSView as a
/// popover anchor.
struct RightClickCatcher: NSViewRepresentable {
    let onRightClick: (NSView) -> Void

    func makeNSView(context: Context) -> NSView {
        let v = RightClickView()
        v.onRightClick = onRightClick
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? RightClickView)?.onRightClick = onRightClick
    }

    final class RightClickView: NSView {
        var onRightClick: ((NSView) -> Void)?
        override func rightMouseDown(with event: NSEvent) { onRightClick?(self) }
        // Let normal left-clicks pass through to the SwiftUI button beneath.
        override func hitTest(_ point: NSPoint) -> NSView? {
            // Only intercept right-clicks; return nil for other cases so the
            // button still receives left clicks.
            guard let event = NSApp.currentEvent else { return nil }
            return event.type == .rightMouseDown ? self : nil
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: FAIL — `cannot find 'DockBar' in scope` (added in Task 9). This is
expected; do NOT commit yet. Proceed to Task 9.

---

## Task 9: DockBar — Apple Dock layout

**Files:**
- Create: `Sources/dockja/DockBarView.swift`

Large icons, no titles, orientation by `model.edge`, hover tooltip, active dot on
the interior side, and hover magnification.

- [ ] **Step 1: Write `Sources/dockja/DockBarView.swift`**

```swift
import SwiftUI
import AppKit
import CoreGraphics
import DockjaCore

struct DockBar: View {
    @ObservedObject var model: BarModel
    let onSelect: (WindowInfo) -> Void
    let onRightClick: (CGWindowID, NSView) -> Void

    private let baseSize: CGFloat = 48
    private let spacing: CGFloat = 10
    private let pad: CGFloat = 10
    private let maxBump: CGFloat = 22      // extra pixels at the cursor
    private let sigma: CGFloat = 60        // magnification falloff

    /// Pointer position along the main axis within the strip; nil when not hovering.
    @State private var hover: CGFloat?

    var body: some View {
        let horizontal = model.edge.isHorizontal
        let layout: AnyLayout = horizontal
            ? AnyLayout(HStackLayout(spacing: spacing))
            : AnyLayout(VStackLayout(spacing: spacing))
        layout {
            ForEach(Array(model.items.enumerated()), id: \.offset) { index, item in
                cell(index: index, item: item)
            }
        }
        .padding(pad)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .fixedSize()
        .coordinateSpace(name: "dock")
        .onContinuousHover(coordinateSpace: .named("dock")) { phase in
            switch phase {
            case .active(let p): hover = horizontal ? p.x : p.y
            case .ended: hover = nil
            }
        }
    }

    /// Each cell reserves a fixed square slot (baseSize + maxBump) so magnified
    /// icons never overflow/clip the fixed-size panel; the icon scales inside it.
    private var cellExtent: CGFloat { baseSize + maxBump }

    @ViewBuilder
    private func cell(index: Int, item: DisplayWindow) -> some View {
        let size = baseSize + bump(forCellAt: index)
        ZStack(alignment: dotAlignment) {
            if let icon = model.image(for: item) {
                Image(nsImage: icon).resizable()
                    .frame(width: size, height: size)
            } else {
                RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.3))
                    .frame(width: size, height: size)
            }
            if item.window.isActive {
                Circle().fill(Color.primary).frame(width: 6, height: 6).padding(1)
            }
        }
        .frame(width: cellExtent, height: cellExtent)
        .opacity(item.window.isMinimized ? 0.5 : 1.0)
        .help(item.name)                                   // hover tooltip
        .animation(.easeOut(duration: 0.12), value: hover)
        .onTapGesture { onSelect(item.window) }
        .background(RightClickCatcher { view in onRightClick(item.window.id, view) })
    }

    /// Magnification bump for the cell at `index` based on cursor distance, using
    /// the fixed slot extent for analytic cell centers.
    private func bump(forCellAt index: Int) -> CGFloat {
        guard let hover else { return 0 }
        let center = pad + CGFloat(index) * (cellExtent + spacing) + cellExtent / 2
        let d = hover - center
        return maxBump * exp(-(d * d) / (2 * sigma * sigma))
    }

    /// Active-window dot placed toward the screen interior.
    private var dotAlignment: Alignment {
        switch model.edge {
        case .bottom: return .top
        case .top: return .bottom
        case .left: return .trailing
        case .right: return .leading
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: builds with no errors (Task 8 + Task 9 together compile).

- [ ] **Step 3: Commit (Tasks 8 + 9 together)**

```bash
git add Sources/dockja/BarView.swift Sources/dockja/DockBarView.swift
git commit -m "BarView consumes DisplayWindow; add Apple Dock layout"
```

---

## Task 10: EditPopoverController + EditView

**Files:**
- Create: `Sources/dockja/EditPopoverController.swift`

- [ ] **Step 1: Write `Sources/dockja/EditPopoverController.swift`**

```swift
import AppKit
import SwiftUI
import CoreGraphics
import DockjaCore

@MainActor
final class EditPopoverController {
    private var popover: NSPopover?

    // Wired by AppCoordinator.
    var currentName: (CGWindowID) -> String = { _ in "" }
    var recents: () -> [String] = { [] }
    var onSetName: (CGWindowID, String) -> Void = { _, _ in }
    var onPickIcon: (CGWindowID, String) -> Void = { _, _ in }
    var onBrowse: (CGWindowID) -> Void = { _ in }
    var onReset: (CGWindowID) -> Void = { _ in }

    func show(for id: CGWindowID, relativeTo view: NSView) {
        popover?.close()
        // The bar is non-activating; activate so the name field can take focus.
        NSApp.activate(ignoringOtherApps: true)

        let edit = EditView(
            name: currentName(id),
            recents: recents(),
            onName: { [weak self] in self?.onSetName(id, $0) },
            onPick: { [weak self] in self?.onPickIcon(id, $0); self?.popover?.close() },
            onBrowse: { [weak self] in self?.onBrowse(id); self?.popover?.close() },
            onReset: { [weak self] in self?.onReset(id); self?.popover?.close() }
        )
        let pop = NSPopover()
        pop.behavior = .transient
        pop.contentSize = NSSize(width: 300, height: 240)
        pop.contentViewController = NSHostingController(rootView: edit)
        pop.show(relativeTo: view.bounds, of: view, preferredEdge: .maxY)
        popover = pop
    }
}

private struct EditView: View {
    @State private var name: String
    let recents: [String]
    let onName: (String) -> Void
    let onPick: (String) -> Void
    let onBrowse: () -> Void
    let onReset: () -> Void

    init(name: String, recents: [String],
         onName: @escaping (String) -> Void,
         onPick: @escaping (String) -> Void,
         onBrowse: @escaping () -> Void,
         onReset: @escaping () -> Void) {
        _name = State(initialValue: name)
        self.recents = recents
        self.onName = onName
        self.onPick = onPick
        self.onBrowse = onBrowse
        self.onReset = onReset
    }

    private let cols = [GridItem(.adaptive(minimum: 40), spacing: 6)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Éditer la fenêtre").font(.headline)

            HStack {
                Text("Nom")
                TextField("Nom", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: name) { _, newValue in onName(newValue) }
            }

            Text("Icônes récentes").font(.subheadline).foregroundStyle(.secondary)
            if recents.isEmpty {
                Text("Aucune — utilisez Parcourir…").font(.caption).foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: cols, spacing: 6) {
                    ForEach(recents, id: \.self) { path in
                        if let img = NSImage(contentsOfFile: path) {
                            Image(nsImage: img).resizable().frame(width: 36, height: 36)
                                .cornerRadius(6)
                                .onTapGesture { onPick(path) }
                        }
                    }
                }
            }

            HStack {
                Button("Parcourir…") { onBrowse() }
                Spacer()
                Button("Réinitialiser", role: .destructive) { onReset() }
            }
        }
        .padding()
        .frame(width: 300)
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: builds with no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/dockja/EditPopoverController.swift
git commit -m "Add right-click edit popover (name + recent icons + browse + reset)"
```

---

## Task 11: BarPanelController — mode-aware positioning + edge snap

**Files:**
- Modify: `Sources/dockja/BarPanelController.swift`

Compact stays free-floating (current behavior). Apple Dock snaps to the nearest
edge after a drag settles and restores from `dockEdge` + `dockParallel`. The
panel's `onRightClick` is threaded to `BarView`.

- [ ] **Step 1: Replace `Sources/dockja/BarPanelController.swift` entirely**

```swift
import AppKit
import SwiftUI
import CoreGraphics
import DockjaCore

@MainActor
final class BarPanelController: NSObject, NSWindowDelegate {
    private let panel: NSPanel
    private let model = BarModel()
    private let settings: SettingsStore
    private let snapper = EdgeSnapper()
    private let frameSaveDebouncer = Debouncer(interval: 0.4)
    private var isAdjustingFrame = false

    var onSelect: ((WindowInfo) -> Void)?
    var onRightClick: ((CGWindowID, NSView) -> Void)?

    init(settings: SettingsStore) {
        self.settings = settings
        let initial = Self.sanitizedFrame(settings.settings.barFrame)
        panel = NSPanel(contentRect: initial,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered,
                        defer: false)
        super.init()

        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.delegate = self

        model.mode = settings.settings.displayMode
        model.edge = settings.settings.dockEdge

        let root = BarView(
            model: model,
            onSelect: { [weak self] win in self?.onSelect?(win) },
            onRightClick: { [weak self] id, view in self?.onRightClick?(id, view) }
        )
        let host = FirstMouseHostingView(rootView: root)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
    }

    // MARK: - Appearance

    func setAppearance(mode: DisplayMode, edge: DockEdge) {
        model.mode = mode
        model.edge = edge
        // Defer so SwiftUI relayouts for the new mode/orientation before we read
        // fittingSize to position the panel.
        DispatchQueue.main.async { [weak self] in self?.repositionForMode() }
    }

    func show(items: [DisplayWindow], appIcon: NSImage?) {
        model.update(items: items, appIcon: appIcon)
        resizeAndPlace()
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func update(items: [DisplayWindow], appIcon: NSImage?) {
        model.update(items: items, appIcon: appIcon)
        resizeAndPlace()
    }

    func hide() {
        if panel.isVisible { panel.orderOut(nil) }
    }

    // MARK: - Positioning

    /// Compact: just fit content (free position). Apple Dock: fit + snap to edge.
    private func resizeAndPlace() {
        guard let host = panel.contentView else { return }
        let fitting = host.fittingSize
        guard fitting.width > 1, fitting.height > 1 else { return }

        switch model.mode {
        case .compact:
            placeFreeFloating(size: fitting)
        case .appleDock:
            placeDocked(size: fitting)
        }
    }

    /// Free-floating with top-left anchored (compact mode).
    private func placeFreeFloating(size: CGSize) {
        var frame = panel.frame
        if abs(frame.width - size.width) < 0.5, abs(frame.height - size.height) < 0.5 { return }
        let topY = frame.origin.y + frame.size.height
        frame.size = size
        frame.origin.y = topY - size.height
        setFrameProgrammatically(frame)
    }

    /// Snap flush to the current edge using the saved parallel offset.
    private func placeDocked(size: CGSize) {
        let screen = (panel.screen ?? NSScreen.main)?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let parallel = settings.settings.dockParallel ?? defaultParallel(for: model.edge, size: size, screen: screen)
        let origin = snapper.origin(for: model.edge, size: size, parallel: parallel, screen: screen)
        setFrameProgrammatically(CGRect(origin: origin, size: size))
    }

    private func defaultParallel(for edge: DockEdge, size: CGSize, screen: CGRect) -> CGFloat {
        edge.isHorizontal ? screen.midX - size.width / 2 : screen.midY - size.height / 2
    }

    /// Called when the mode changes; positions immediately for the new mode.
    private func repositionForMode() {
        resizeAndPlace()
    }

    // MARK: - Dragging

    func windowDidMove(_ notification: Notification) {
        guard !isAdjustingFrame else { return }
        frameSaveDebouncer.call { [weak self] in
            guard let self else { return }
            switch self.model.mode {
            case .compact:
                self.settings.update { $0.barFrame = self.panel.frame }
            case .appleDock:
                self.snapToNearestEdge()
            }
        }
    }

    /// After a drag settles in Apple Dock mode: choose nearest edge, relayout,
    /// snap flush, and persist edge + parallel offset.
    private func snapToNearestEdge() {
        let screen = (panel.screen ?? NSScreen.main)?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let center = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        let edge = snapper.nearestEdge(barCenter: center, screen: screen)
        model.edge = edge   // flips H/V layout

        // Let SwiftUI relayout for the new orientation, then snap to the size.
        DispatchQueue.main.async { [weak self] in
            guard let self, let host = self.panel.contentView else { return }
            let size = host.fittingSize
            // Parallel coordinate from the current drag position.
            let parallel = edge.isHorizontal ? self.panel.frame.origin.x : self.panel.frame.origin.y
            let origin = self.snapper.origin(for: edge, size: size, parallel: parallel, screen: screen)
            self.setFrameProgrammatically(CGRect(origin: origin, size: size))
            self.settings.update {
                $0.dockEdge = edge
                $0.dockParallel = parallel
            }
        }
    }

    private func setFrameProgrammatically(_ frame: CGRect) {
        isAdjustingFrame = true
        panel.setFrame(frame, display: true)
        isAdjustingFrame = false
    }

    // MARK: - Helpers

    private static func sanitizedFrame(_ saved: CGRect?) -> NSRect {
        let fallback = NSRect(x: 200, y: 200, width: 320, height: 64)
        guard let saved, saved.width > 0, saved.height > 0 else { return fallback }
        let onScreen = NSScreen.screens.contains { $0.frame.intersects(saved) }
        return onScreen ? saved : fallback
    }
}

/// Hosting view that responds to the first click even when its window is not key.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: FAIL — `AppCoordinator` still calls the old `bar.show(icon:windows:)`
signature. Expected; fixed in Task 13. Do NOT commit yet.

---

## Task 12: StatusItemController — display-mode menu

**Files:**
- Modify: `Sources/dockja/StatusItemController.swift`

Add a "Compact" / "Apple Dock" pair (with a checkmark on the active one) above
Preferences. The controller asks for the current mode and reports changes.

- [ ] **Step 1: Replace `Sources/dockja/StatusItemController.swift` entirely**

```swift
import AppKit
import DockjaCore

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let item: NSStatusItem
    private let isTrusted: () -> Bool
    private let currentMode: () -> DisplayMode
    private let onSetMode: (DisplayMode) -> Void
    private let onOpenPreferences: () -> Void
    private let onGrantAccessibility: () -> Void

    init(isTrusted: @escaping () -> Bool,
         currentMode: @escaping () -> DisplayMode,
         onSetMode: @escaping (DisplayMode) -> Void,
         onOpenPreferences: @escaping () -> Void,
         onGrantAccessibility: @escaping () -> Void) {
        self.isTrusted = isTrusted
        self.currentMode = currentMode
        self.onSetMode = onSetMode
        self.onOpenPreferences = onOpenPreferences
        self.onGrantAccessibility = onGrantAccessibility
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        item.button?.image = NSImage(systemSymbolName: "rectangle.stack",
                                     accessibilityDescription: "dockja")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if !isTrusted() {
            let grant = NSMenuItem(title: "Grant Accessibility…",
                                   action: #selector(grant), keyEquivalent: "")
            grant.target = self
            menu.addItem(grant)
            menu.addItem(.separator())
        }

        let mode = currentMode()
        let compact = NSMenuItem(title: "Compact", action: #selector(setCompact), keyEquivalent: "")
        compact.target = self
        compact.state = (mode == .compact) ? .on : .off
        menu.addItem(compact)

        let dock = NSMenuItem(title: "Apple Dock", action: #selector(setAppleDock), keyEquivalent: "")
        dock.target = self
        dock.state = (mode == .appleDock) ? .on : .off
        menu.addItem(dock)

        menu.addItem(.separator())

        let prefs = NSMenuItem(title: "Preferences…",
                               action: #selector(openPrefs), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit dockja",
                              action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func setCompact() { onSetMode(.compact) }
    @objc private func setAppleDock() { onSetMode(.appleDock) }
    @objc private func grant() { onGrantAccessibility() }
    @objc private func openPrefs() { onOpenPreferences() }
    @objc private func quit() { NSApp.terminate(nil) }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: FAIL — `AppCoordinator` still constructs `StatusItemController` with the
old initializer. Expected; fixed in Task 13. Do NOT commit yet.

---

## Task 13: AppCoordinator — wire overrides, icons, modes

**Files:**
- Modify: `Sources/dockja/AppCoordinator.swift`

- [ ] **Step 1: Replace `Sources/dockja/AppCoordinator.swift` entirely**

```swift
import AppKit
import ApplicationServices
import CoreGraphics
import DockjaCore

@MainActor
final class AppCoordinator {
    private let provider = AXAccessibilityProvider()
    private let enumerator: WindowEnumerator
    private let raiser: WindowRaiser
    private let settings: SettingsStore
    private let frontmost = FrontmostAppObserver()
    private let bar: BarPanelController
    private let refreshDebouncer = Debouncer(interval: 0.1)
    private var orderStabilizer = WindowOrderStabilizer()
    private let overrides = WindowOverrideStore()
    private let resolver = OverrideResolver()
    private let icons: IconLibrary
    private let editPopover = EditPopoverController()
    private var statusItem: StatusItemController?
    private var refreshTimer: Timer?
    private var trustTimer: Timer?
    private var currentApp: NSRunningApplication?

    init() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("dockja")
        settings = SettingsStore(directory: appSupport)
        enumerator = WindowEnumerator(provider: provider)
        raiser = WindowRaiser(provider: provider)
        icons = IconLibrary(settings: settings)
        bar = BarPanelController(settings: settings)
        bar.onSelect = { [weak self] window in self?.raiser.raise(window) }
        bar.onRightClick = { [weak self] id, view in
            self?.editPopover.show(for: id, relativeTo: view)
        }
        wireEditPopover()
    }

    func start() {
        statusItem = StatusItemController(
            isTrusted: { AXIsProcessTrusted() },
            currentMode: { [weak self] in self?.settings.settings.displayMode ?? .compact },
            onSetMode: { [weak self] mode in self?.setMode(mode) },
            onOpenPreferences: { [weak self] in
                guard let self else { return }
                PreferencesController.shared.show(settings: self.settings)
            },
            onGrantAccessibility: { Self.promptAccessibility() }
        )
        bar.setAppearance(mode: settings.settings.displayMode, edge: settings.settings.dockEdge)
        frontmost.onChange = { [weak self] app in self?.handleFrontmost(app) }
        frontmost.start()
        handleFrontmost(NSWorkspace.shared.frontmostApplication)
        startTrustPollingIfNeeded()
    }

    static func promptAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    // MARK: - Edit popover wiring

    private func wireEditPopover() {
        editPopover.currentName = { [weak self] id in self?.overrides.override(for: id).customName ?? "" }
        editPopover.recents = { [weak self] in self?.icons.recents ?? [] }
        editPopover.onSetName = { [weak self] id, name in
            self?.overrides.setName(name.isEmpty ? nil : name, for: id)
            self?.refresh()
        }
        editPopover.onPickIcon = { [weak self] id, path in
            self?.overrides.setIcon(path, for: id)
            self?.refresh()
        }
        editPopover.onReset = { [weak self] id in
            self?.overrides.reset(id)
            self?.refresh()
        }
        editPopover.onBrowse = { [weak self] id in
            guard let self else { return }
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.image]
            panel.allowsMultipleSelection = false
            NSApp.activate(ignoringOtherApps: true)
            guard panel.runModal() == .OK, let url = panel.url,
                  let path = self.icons.importImage(from: url) else { return }
            self.overrides.setIcon(path, for: id)
            self.refresh()
        }
    }

    private func setMode(_ mode: DisplayMode) {
        settings.update { $0.displayMode = mode }
        bar.setAppearance(mode: mode, edge: settings.settings.dockEdge)
        refresh()
    }

    // MARK: - Refresh

    private func handleFrontmost(_ app: NSRunningApplication?) {
        currentApp = app
        stopTimer()
        refreshDebouncer.call { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
    }

    private func refresh() {
        guard AXIsProcessTrusted(),
              let app = currentApp,
              let bundleID = app.bundleIdentifier else {
            bar.hide(); stopTimer(); return
        }
        let windows = orderStabilizer.stableOrder(
            pid: app.processIdentifier,
            windows: enumerator.windows(forPID: app.processIdentifier))
        switch barState(frontmostBundleID: bundleID,
                        enabled: settings.enabledSet,
                        windowCount: windows.count) {
        case .hidden:
            bar.hide(); stopTimer()
        case .visible:
            bar.show(items: displayWindows(windows), appIcon: app.icon)
            startTimer()
        }
    }

    private func startTimer() {
        guard refreshTimer == nil else { return }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshEntriesOnly() }
        }
    }

    private func stopTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func refreshEntriesOnly() {
        guard let app = currentApp else { return }
        let windows = orderStabilizer.stableOrder(
            pid: app.processIdentifier,
            windows: enumerator.windows(forPID: app.processIdentifier))
        if windows.isEmpty {
            bar.hide(); stopTimer(); return
        }
        bar.update(items: displayWindows(windows), appIcon: app.icon)
    }

    /// Resolve overrides into display models and prune dead window ids.
    private func displayWindows(_ windows: [WindowInfo]) -> [DisplayWindow] {
        overrides.prune(keeping: Set(windows.map { $0.id }))
        return resolver.resolve(windows, overrides: overrides.overrides())
    }

    // MARK: - Trust polling

    private func startTrustPollingIfNeeded() {
        guard !AXIsProcessTrusted() else { return }
        trustTimer?.invalidate()
        trustTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                guard AXIsProcessTrusted() else { return }
                self.trustTimer?.invalidate()
                self.trustTimer = nil
                self.refresh()
            }
        }
    }
}
```

- [ ] **Step 2: Build the whole app**

Run: `swift build`
Expected: builds with no errors (Tasks 11, 12, 13 now resolve together).

- [ ] **Step 3: Run the full test suite**

Run: `swift test`
Expected: PASS — all DockjaCore tests green (existing + Tasks 1-6), nothing broken.

- [ ] **Step 4: Commit**

```bash
git add Sources/dockja/BarPanelController.swift Sources/dockja/StatusItemController.swift Sources/dockja/AppCoordinator.swift
git commit -m "Wire per-window overrides, icon library, and display modes"
```

---

## Task 14: Bundle + manual verification

- [ ] **Step 1: Build the signed bundle**

Run: `./scripts/bundle.sh`
Expected: prints `Signed with identity: …` (your Apple Development identity) and
`Built dockja.app`.

- [ ] **Step 2: Manual checklist** (GUI + Accessibility; can't be automated)

1. `open dockja.app`; grant Accessibility if needed (existing grant should hold —
   same signing identity).
2. Focus an enabled multi-window app → Compact bar shows (unchanged).
3. **Right-click** an entry → popover opens; type a name → entry updates live.
4. Popover **Parcourir…** → pick an image → entry icon changes; reopen popover →
   that icon appears in **recent icons**.
5. Click a **recent icon** in the popover → applied. **Réinitialiser** → back to
   title + app icon.
6. Quit + relaunch dockja → recents still listed; the per-window override is gone
   (expected) but re-applying from recents is one click.
7. Menu-bar icon → **Apple Dock** → bar switches to large icons, no titles;
   checkmark moves.
8. Drag the dock near each screen edge → it snaps; **left/right** make it
   vertical; the **active-window dot** sits on the interior side; hover shows the
   **tooltip**; moving the cursor along it **magnifies** nearby icons.
9. Switch back to **Compact** → returns to the free-floating chip bar at its
   remembered position (no snap).

---

## Done criteria

- `swift test` passes (Tasks 1-6 logic: DisplayMode, DockEdge, OverrideResolver,
  WindowOverrideStore, RecentIcons, EdgeSnapper, Settings back-compat).
- `swift build` + `./scripts/bundle.sh` succeed.
- Manual checklist in Task 14 passes.

## Notes / future

- Magnification uses a Gaussian falloff on analytic cell centers; if it feels off,
  tune `maxBump`/`sigma` or fall back to scaling only the hovered icon.
- Per-window overrides remain session-scoped by design (titles too unstable for
  cross-restart keys); the recent-icons library bridges the gap.
