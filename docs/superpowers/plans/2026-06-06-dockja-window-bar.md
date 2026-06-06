# dockja — Per-App Window Bar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A macOS menu-bar agent that shows a floating, draggable bar listing only the windows of the currently-focused enabled app, where clicking an entry raises that exact window.

**Architecture:** Swift Package Manager project. A pure library target `DockjaCore` holds all testable logic (models, window enumeration, raising, settings, visibility rules) behind an `AccessibilityProvider` protocol. The executable target `dockja` holds AppKit/SwiftUI glue and the real Accessibility-API provider. Unit tests drive `DockjaCore` with a fake provider; AppKit glue is verified by compilation + manual run.

**Tech Stack:** Swift 6.2, AppKit, SwiftUI, ApplicationServices (Accessibility API `AXUIElement`), Swift Package Manager. macOS 14+.

---

## File Structure

```
Package.swift
Resources/Info.plist                       # LSUIElement bundle plist
scripts/bundle.sh                          # assemble dockja.app around the built binary
Sources/
  DockjaCore/                              # pure, unit-tested logic
    Models.swift                           # WindowRef, WindowInfo, AppConfig
    AccessibilityProvider.swift            # protocol abstracting all AX side-effects
    WindowEnumerator.swift                 # app pid -> [WindowInfo]
    WindowRaiser.swift                     # raise a specific window
    SettingsStore.swift                    # Settings + JSON persistence
    BarVisibility.swift                    # pure show/hide decision
    Debouncer.swift                        # coalesce rapid refreshes
  dockja/                                  # AppKit/SwiftUI glue (compiled, manually verified)
    main.swift                             # NSApplication entry, .accessory policy
    AppDelegate.swift
    AXAccessibilityProvider.swift          # real AccessibilityProvider via AXUIElement
    FrontmostAppObserver.swift             # NSWorkspace active-app notifications
    AppCoordinator.swift                   # wires everything; trust check; refresh timer
    BarPanelController.swift               # non-activating floating NSPanel + BarModel
    BarView.swift                          # SwiftUI bar content
    StatusItemController.swift             # menu-bar item + menu
    PreferencesController.swift            # SwiftUI app checklist + Add app
Tests/
  DockjaCoreTests/
    Fakes.swift                            # FakeAccessibilityProvider
    ModelsTests.swift
    WindowEnumeratorTests.swift
    WindowRaiserTests.swift
    SettingsStoreTests.swift
    BarVisibilityTests.swift
    DebouncerTests.swift
```

**Responsibility boundaries:** every side-effect that touches the live system (reading/raising windows, activating apps) goes through `AccessibilityProvider`. `WindowEnumerator`, `WindowRaiser`, and the visibility rule depend only on that protocol and are fully unit-tested with `FakeAccessibilityProvider`. The executable target supplies the real provider and the UI. This is the seam that keeps logic testable headlessly.

---

## Task 1: Project scaffold + core models

**Files:**
- Create: `Package.swift`
- Create: `Sources/DockjaCore/Models.swift`
- Create: `Sources/dockja/main.swift` (temporary stub, replaced in Task 11)
- Test: `Tests/DockjaCoreTests/ModelsTests.swift`

- [ ] **Step 1: Write `Package.swift`**

```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "dockja",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "DockjaCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "dockja",
            dependencies: ["DockjaCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "DockjaCoreTests",
            dependencies: ["DockjaCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
```

- [ ] **Step 2: Write `Sources/DockjaCore/Models.swift`**

```swift
import Foundation
import ApplicationServices

/// Opaque handle to a window. Real provider wraps an `AXUIElement`;
/// tests construct refs with a synthetic id (ax == nil).
public final class WindowRef {
    public let ax: AXUIElement?
    public let id: Int
    public init(ax: AXUIElement) { self.ax = ax; self.id = -1 }
    public init(testID id: Int) { self.ax = nil; self.id = id }
}

public struct WindowInfo {
    public let ref: WindowRef
    public let title: String
    public let isMinimized: Bool
    public let isActive: Bool
    public let pid: pid_t

    public init(ref: WindowRef, title: String, isMinimized: Bool, isActive: Bool, pid: pid_t) {
        self.ref = ref
        self.title = title
        self.isMinimized = isMinimized
        self.isActive = isActive
        self.pid = pid
    }

    public var displayLabel: String { title.isEmpty ? "Untitled" : title }
}

public struct AppConfig: Equatable {
    public var bundleID: String
    public var displayName: String
    public var enabled: Bool
    public init(bundleID: String, displayName: String, enabled: Bool) {
        self.bundleID = bundleID
        self.displayName = displayName
        self.enabled = enabled
    }
}
```

- [ ] **Step 3: Write temporary `Sources/dockja/main.swift`**

```swift
// Replaced in Task 11 with the real NSApplication entry point.
print("dockja")
```

- [ ] **Step 4: Write the failing test `Tests/DockjaCoreTests/ModelsTests.swift`**

```swift
import XCTest
@testable import DockjaCore

final class ModelsTests: XCTestCase {
    func testDisplayLabelUsesTitleWhenPresent() {
        let info = WindowInfo(ref: WindowRef(testID: 1), title: "Gmail",
                              isMinimized: false, isActive: true, pid: 1)
        XCTAssertEqual(info.displayLabel, "Gmail")
    }

    func testDisplayLabelFallsBackWhenTitleEmpty() {
        let info = WindowInfo(ref: WindowRef(testID: 2), title: "",
                              isMinimized: false, isActive: false, pid: 1)
        XCTAssertEqual(info.displayLabel, "Untitled")
    }
}
```

- [ ] **Step 5: Build and test**

Run: `swift test`
Expected: PASS (2 tests). Build of both targets succeeds.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources Tests
git commit -m "Scaffold SPM project with core models"
```

---

## Task 2: AccessibilityProvider protocol + fake

**Files:**
- Create: `Sources/DockjaCore/AccessibilityProvider.swift`
- Create: `Tests/DockjaCoreTests/Fakes.swift`

- [ ] **Step 1: Write `Sources/DockjaCore/AccessibilityProvider.swift`**

```swift
import Foundation

/// Every live-system side-effect goes through this protocol so that
/// WindowEnumerator / WindowRaiser stay testable with a fake.
public protocol AccessibilityProvider {
    func windows(forPID pid: pid_t) -> [WindowRef]
    func title(of window: WindowRef) -> String?
    func isMinimized(_ window: WindowRef) -> Bool
    func isMain(_ window: WindowRef) -> Bool
    func unminimize(_ window: WindowRef)
    func activateApp(pid: pid_t)
    func raise(_ window: WindowRef)
    func setMain(_ window: WindowRef)
}
```

- [ ] **Step 2: Write `Tests/DockjaCoreTests/Fakes.swift`**

```swift
import Foundation
@testable import DockjaCore

final class FakeAccessibilityProvider: AccessibilityProvider {
    struct FakeWindow {
        var title: String
        var minimized: Bool
        var main: Bool
    }

    private var windowsByPID: [pid_t: [WindowRef]] = [:]
    private var data: [Int: FakeWindow] = [:]
    /// Ordered record of mutating calls, for asserting behavior.
    var calls: [String] = []

    func addWindow(pid: pid_t, id: Int, title: String,
                   minimized: Bool = false, main: Bool = false) {
        let ref = WindowRef(testID: id)
        windowsByPID[pid, default: []].append(ref)
        data[id] = FakeWindow(title: title, minimized: minimized, main: main)
    }

    func windows(forPID pid: pid_t) -> [WindowRef] { windowsByPID[pid] ?? [] }
    func title(of window: WindowRef) -> String? { data[window.id]?.title }
    func isMinimized(_ window: WindowRef) -> Bool { data[window.id]?.minimized ?? false }
    func isMain(_ window: WindowRef) -> Bool { data[window.id]?.main ?? false }

    func unminimize(_ window: WindowRef) {
        calls.append("unminimize(\(window.id))")
        data[window.id]?.minimized = false
    }
    func activateApp(pid: pid_t) { calls.append("activate(\(pid))") }
    func raise(_ window: WindowRef) { calls.append("raise(\(window.id))") }
    func setMain(_ window: WindowRef) { calls.append("setMain(\(window.id))") }
}
```

- [ ] **Step 3: Build to verify it compiles**

Run: `swift build`
Expected: builds with no errors (no tests reference the fake yet).

- [ ] **Step 4: Commit**

```bash
git add Sources/DockjaCore/AccessibilityProvider.swift Tests/DockjaCoreTests/Fakes.swift
git commit -m "Add AccessibilityProvider protocol and fake"
```

---

## Task 3: WindowEnumerator

**Files:**
- Create: `Sources/DockjaCore/WindowEnumerator.swift`
- Test: `Tests/DockjaCoreTests/WindowEnumeratorTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import DockjaCore

final class WindowEnumeratorTests: XCTestCase {
    func testMapsWindowsWithTitlesAndFlags() {
        let fake = FakeAccessibilityProvider()
        fake.addWindow(pid: 42, id: 1, title: "Gmail", main: true)
        fake.addWindow(pid: 42, id: 2, title: "", minimized: true)

        let result = WindowEnumerator(provider: fake).windows(forPID: 42)

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].title, "Gmail")
        XCTAssertTrue(result[0].isActive)
        XCTAssertEqual(result[0].displayLabel, "Gmail")
        XCTAssertEqual(result[0].pid, 42)
        XCTAssertTrue(result[1].isMinimized)
        XCTAssertEqual(result[1].displayLabel, "Untitled")
    }

    func testReturnsEmptyForUnknownPID() {
        let fake = FakeAccessibilityProvider()
        XCTAssertTrue(WindowEnumerator(provider: fake).windows(forPID: 99).isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter WindowEnumeratorTests`
Expected: FAIL — `cannot find 'WindowEnumerator' in scope`.

- [ ] **Step 3: Write `Sources/DockjaCore/WindowEnumerator.swift`**

```swift
import Foundation

public struct WindowEnumerator {
    private let provider: AccessibilityProvider
    public init(provider: AccessibilityProvider) { self.provider = provider }

    public func windows(forPID pid: pid_t) -> [WindowInfo] {
        provider.windows(forPID: pid).map { ref in
            WindowInfo(
                ref: ref,
                title: provider.title(of: ref) ?? "",
                isMinimized: provider.isMinimized(ref),
                isActive: provider.isMain(ref),
                pid: pid
            )
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter WindowEnumeratorTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/DockjaCore/WindowEnumerator.swift Tests/DockjaCoreTests/WindowEnumeratorTests.swift
git commit -m "Add WindowEnumerator"
```

---

## Task 4: WindowRaiser

**Files:**
- Create: `Sources/DockjaCore/WindowRaiser.swift`
- Test: `Tests/DockjaCoreTests/WindowRaiserTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import DockjaCore

final class WindowRaiserTests: XCTestCase {
    func testRaiseUnminimizesThenActivatesRaisesSetsMain() {
        let fake = FakeAccessibilityProvider()
        fake.addWindow(pid: 7, id: 9, title: "W", minimized: true)
        let info = WindowEnumerator(provider: fake).windows(forPID: 7)[0]

        WindowRaiser(provider: fake).raise(info)

        XCTAssertEqual(fake.calls, ["unminimize(9)", "activate(7)", "raise(9)", "setMain(9)"])
    }

    func testRaiseSkipsUnminimizeWhenNotMinimized() {
        let fake = FakeAccessibilityProvider()
        fake.addWindow(pid: 7, id: 9, title: "W")
        let info = WindowEnumerator(provider: fake).windows(forPID: 7)[0]

        WindowRaiser(provider: fake).raise(info)

        XCTAssertEqual(fake.calls, ["activate(7)", "raise(9)", "setMain(9)"])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter WindowRaiserTests`
Expected: FAIL — `cannot find 'WindowRaiser' in scope`.

- [ ] **Step 3: Write `Sources/DockjaCore/WindowRaiser.swift`**

```swift
import Foundation

public struct WindowRaiser {
    private let provider: AccessibilityProvider
    public init(provider: AccessibilityProvider) { self.provider = provider }

    public func raise(_ window: WindowInfo) {
        if provider.isMinimized(window.ref) {
            provider.unminimize(window.ref)
        }
        provider.activateApp(pid: window.pid)
        provider.raise(window.ref)
        provider.setMain(window.ref)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter WindowRaiserTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/DockjaCore/WindowRaiser.swift Tests/DockjaCoreTests/WindowRaiserTests.swift
git commit -m "Add WindowRaiser"
```

---

## Task 5: SettingsStore

**Files:**
- Create: `Sources/DockjaCore/SettingsStore.swift`
- Test: `Tests/DockjaCoreTests/SettingsStoreTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import CoreGraphics
@testable import DockjaCore

final class SettingsStoreTests: XCTestCase {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("dockja-test-\(UUID().uuidString)")
    }

    func testDefaultsAreEmpty() {
        let store = SettingsStore(directory: tempDir())
        XCTAssertEqual(store.settings.enabledBundleIDs, [])
        XCTAssertNil(store.settings.barFrame)
        XCTAssertTrue(store.enabledSet.isEmpty)
    }

    func testRoundTripPersistsAcrossInstances() {
        let dir = tempDir()
        let store1 = SettingsStore(directory: dir)
        store1.update {
            $0.enabledBundleIDs = ["com.apple.Safari"]
            $0.barFrame = CGRect(x: 1, y: 2, width: 3, height: 4)
        }

        let store2 = SettingsStore(directory: dir)
        XCTAssertEqual(store2.settings.enabledBundleIDs, ["com.apple.Safari"])
        XCTAssertEqual(store2.settings.barFrame, CGRect(x: 1, y: 2, width: 3, height: 4))
        XCTAssertEqual(store2.enabledSet, ["com.apple.Safari"])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SettingsStoreTests`
Expected: FAIL — `cannot find 'SettingsStore' in scope`.

- [ ] **Step 3: Write `Sources/DockjaCore/SettingsStore.swift`**

```swift
import Foundation
import CoreGraphics

public struct Settings: Codable, Equatable {
    public var enabledBundleIDs: [String]
    public var barFrame: CGRect?
    public init(enabledBundleIDs: [String] = [], barFrame: CGRect? = nil) {
        self.enabledBundleIDs = enabledBundleIDs
        self.barFrame = barFrame
    }
}

public final class SettingsStore {
    private let fileURL: URL
    public private(set) var settings: Settings

    public init(directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent("settings.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(Settings.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = Settings()
        }
    }

    public func update(_ mutate: (inout Settings) -> Void) {
        mutate(&settings)
        save()
    }

    public var enabledSet: Set<String> { Set(settings.enabledBundleIDs) }

    private func save() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        try? data.write(to: fileURL)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SettingsStoreTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/DockjaCore/SettingsStore.swift Tests/DockjaCoreTests/SettingsStoreTests.swift
git commit -m "Add SettingsStore with JSON persistence"
```

---

## Task 6: BarVisibility rule

**Files:**
- Create: `Sources/DockjaCore/BarVisibility.swift`
- Test: `Tests/DockjaCoreTests/BarVisibilityTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import DockjaCore

final class BarVisibilityTests: XCTestCase {
    let enabled: Set<String> = ["com.apple.Safari"]

    func testVisibleWhenEnabledAndHasWindows() {
        XCTAssertEqual(
            barState(frontmostBundleID: "com.apple.Safari", enabled: enabled, windowCount: 3),
            .visible(bundleID: "com.apple.Safari")
        )
    }

    func testHiddenWhenNotEnabled() {
        XCTAssertEqual(
            barState(frontmostBundleID: "com.apple.Mail", enabled: enabled, windowCount: 3),
            .hidden
        )
    }

    func testHiddenWhenEnabledButNoWindows() {
        XCTAssertEqual(
            barState(frontmostBundleID: "com.apple.Safari", enabled: enabled, windowCount: 0),
            .hidden
        )
    }

    func testHiddenWhenNoFrontmostApp() {
        XCTAssertEqual(
            barState(frontmostBundleID: nil, enabled: enabled, windowCount: 3),
            .hidden
        )
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter BarVisibilityTests`
Expected: FAIL — `cannot find 'barState' in scope`.

- [ ] **Step 3: Write `Sources/DockjaCore/BarVisibility.swift`**

```swift
import Foundation

public enum BarState: Equatable {
    case hidden
    case visible(bundleID: String)
}

/// Pure decision: show the bar only when an enabled app is frontmost
/// and it has at least one window. (No 1-window suppression — avoids flicker.)
public func barState(frontmostBundleID: String?,
                     enabled: Set<String>,
                     windowCount: Int) -> BarState {
    guard let id = frontmostBundleID, enabled.contains(id), windowCount >= 1 else {
        return .hidden
    }
    return .visible(bundleID: id)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter BarVisibilityTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/DockjaCore/BarVisibility.swift Tests/DockjaCoreTests/BarVisibilityTests.swift
git commit -m "Add bar visibility rule"
```

---

## Task 7: Debouncer

**Files:**
- Create: `Sources/DockjaCore/Debouncer.swift`
- Test: `Tests/DockjaCoreTests/DebouncerTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import DockjaCore

final class DebouncerTests: XCTestCase {
    func testCoalescesRapidCallsIntoOne() {
        let d = Debouncer(interval: 0.05)
        var count = 0
        for _ in 0..<5 { d.call { count += 1 } }

        let settle = expectation(description: "settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { settle.fulfill() }
        wait(for: [settle], timeout: 1.0)

        XCTAssertEqual(count, 1)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter DebouncerTests`
Expected: FAIL — `cannot find 'Debouncer' in scope`.

- [ ] **Step 3: Write `Sources/DockjaCore/Debouncer.swift`**

```swift
import Foundation

public final class Debouncer {
    private let interval: TimeInterval
    private let queue: DispatchQueue
    private var workItem: DispatchWorkItem?

    public init(interval: TimeInterval, queue: DispatchQueue = .main) {
        self.interval = interval
        self.queue = queue
    }

    public func call(_ action: @escaping () -> Void) {
        workItem?.cancel()
        let item = DispatchWorkItem(block: action)
        workItem = item
        queue.asyncAfter(deadline: .now() + interval, execute: item)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter DebouncerTests`
Expected: PASS (1 test).

- [ ] **Step 5: Run the full suite**

Run: `swift test`
Expected: PASS — all tests from Tasks 1-7 green.

- [ ] **Step 6: Commit**

```bash
git add Sources/DockjaCore/Debouncer.swift Tests/DockjaCoreTests/DebouncerTests.swift
git commit -m "Add Debouncer"
```

---

## Task 8: Real AXAccessibilityProvider

**Files:**
- Create: `Sources/dockja/AXAccessibilityProvider.swift`

This conforms `DockjaCore.AccessibilityProvider` to the live Accessibility API. Not unit-tested (touches the system); verified by compilation here and by manual run in Task 14.

- [ ] **Step 1: Write `Sources/dockja/AXAccessibilityProvider.swift`**

```swift
import AppKit
import ApplicationServices
import DockjaCore

final class AXAccessibilityProvider: AccessibilityProvider {
    func windows(forPID pid: pid_t) -> [WindowRef] {
        let appEl = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute as CFString, &value)
        guard err == .success, let arr = value as? [AXUIElement] else { return [] }
        return arr.map { WindowRef(ax: $0) }
    }

    func title(of window: WindowRef) -> String? {
        copyString(window.ax, kAXTitleAttribute)
    }

    func isMinimized(_ window: WindowRef) -> Bool {
        copyBool(window.ax, kAXMinimizedAttribute) ?? false
    }

    func isMain(_ window: WindowRef) -> Bool {
        copyBool(window.ax, kAXMainAttribute) ?? false
    }

    func unminimize(_ window: WindowRef) {
        guard let el = window.ax else { return }
        AXUIElementSetAttributeValue(el, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
    }

    func activateApp(pid: pid_t) {
        NSRunningApplication(processIdentifier: pid)?.activate()
    }

    func raise(_ window: WindowRef) {
        guard let el = window.ax else { return }
        AXUIElementPerformAction(el, kAXRaiseAction as CFString)
    }

    func setMain(_ window: WindowRef) {
        guard let el = window.ax else { return }
        AXUIElementSetAttributeValue(el, kAXMainAttribute as CFString, kCFBooleanTrue)
    }

    // MARK: - AX attribute helpers

    private func copyString(_ el: AXUIElement?, _ attr: String) -> String? {
        guard let el else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private func copyBool(_ el: AXUIElement?, _ attr: String) -> Bool? {
        guard let el else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &value) == .success else { return nil }
        return value as? Bool
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build`
Expected: builds with no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/dockja/AXAccessibilityProvider.swift
git commit -m "Add real Accessibility-API provider"
```

---

## Task 9: FrontmostAppObserver

**Files:**
- Create: `Sources/dockja/FrontmostAppObserver.swift`

- [ ] **Step 1: Write `Sources/dockja/FrontmostAppObserver.swift`**

```swift
import AppKit

/// Fires whenever the frontmost application changes.
final class FrontmostAppObserver {
    private var token: NSObjectProtocol?
    var onChange: ((NSRunningApplication?) -> Void)?

    func start() {
        token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.onChange?(app)
        }
    }

    deinit {
        if let token { NSWorkspace.shared.notificationCenter.removeObserver(token) }
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: builds with no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/dockja/FrontmostAppObserver.swift
git commit -m "Add frontmost-app observer"
```

---

## Task 10: Bar panel + SwiftUI view

**Files:**
- Create: `Sources/dockja/BarView.swift`
- Create: `Sources/dockja/BarPanelController.swift`

- [ ] **Step 1: Write `Sources/dockja/BarView.swift`**

```swift
import SwiftUI
import AppKit
import DockjaCore

final class BarModel: ObservableObject {
    @Published var icon: NSImage?
    @Published var windows: [WindowInfo] = []

    func update(icon: NSImage?, windows: [WindowInfo]) {
        self.icon = icon
        self.windows = windows
    }
}

struct BarView: View {
    @ObservedObject var model: BarModel
    let onSelect: (WindowInfo) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(model.windows.enumerated()), id: \.offset) { _, win in
                Button {
                    onSelect(win)
                } label: {
                    HStack(spacing: 4) {
                        if let icon = model.icon {
                            Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                        }
                        Text(win.displayLabel)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: 140, alignment: .leading)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(win.isActive ? Color.accentColor.opacity(0.3)
                                             : Color.gray.opacity(0.15))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .opacity(win.isMinimized ? 0.5 : 1.0)
            }
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .fixedSize()
    }
}
```

- [ ] **Step 2: Write `Sources/dockja/BarPanelController.swift`**

```swift
import AppKit
import SwiftUI
import DockjaCore

@MainActor
final class BarPanelController: NSObject, NSWindowDelegate {
    private let panel: NSPanel
    private let model = BarModel()
    private let settings: SettingsStore
    var onSelect: ((WindowInfo) -> Void)?

    init(settings: SettingsStore) {
        self.settings = settings
        let initial = settings.settings.barFrame ?? NSRect(x: 200, y: 200, width: 320, height: 64)
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

        let root = BarView(model: model) { [weak self] win in self?.onSelect?(win) }
        let host = NSHostingView(rootView: root)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
    }

    func show(icon: NSImage?, windows: [WindowInfo]) {
        model.update(icon: icon, windows: windows)
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func update(icon: NSImage?, windows: [WindowInfo]) {
        model.update(icon: icon, windows: windows)
    }

    func hide() {
        if panel.isVisible { panel.orderOut(nil) }
    }

    // Persist position when the user drags the bar.
    func windowDidMove(_ notification: Notification) {
        settings.update { $0.barFrame = self.panel.frame }
    }
}
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: builds with no errors.

- [ ] **Step 4: Commit**

```bash
git add Sources/dockja/BarView.swift Sources/dockja/BarPanelController.swift
git commit -m "Add floating bar panel and SwiftUI view"
```

---

## Task 11: StatusItemController

**Files:**
- Create: `Sources/dockja/StatusItemController.swift`

- [ ] **Step 1: Write `Sources/dockja/StatusItemController.swift`**

```swift
import AppKit

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let item: NSStatusItem
    private let isTrusted: () -> Bool
    private let onOpenPreferences: () -> Void
    private let onGrantAccessibility: () -> Void

    init(isTrusted: @escaping () -> Bool,
         onOpenPreferences: @escaping () -> Void,
         onGrantAccessibility: @escaping () -> Void) {
        self.isTrusted = isTrusted
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

    // Rebuild on open so the Accessibility status reflects current trust.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if !isTrusted() {
            let grant = NSMenuItem(title: "Grant Accessibility…",
                                   action: #selector(grant), keyEquivalent: "")
            grant.target = self
            menu.addItem(grant)
            menu.addItem(.separator())
        }
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

    @objc private func grant() { onGrantAccessibility() }
    @objc private func openPrefs() { onOpenPreferences() }
    @objc private func quit() { NSApp.terminate(nil) }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: builds with no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/dockja/StatusItemController.swift
git commit -m "Add menu-bar status item"
```

---

## Task 12: PreferencesController

**Files:**
- Create: `Sources/dockja/PreferencesController.swift`

- [ ] **Step 1: Write `Sources/dockja/PreferencesController.swift`**

```swift
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import DockjaCore

@MainActor
final class PreferencesController {
    static let shared = PreferencesController()
    private var window: NSWindow?

    func show(settings: SettingsStore) {
        if window == nil {
            let view = PreferencesView(settings: settings)
            let hosting = NSHostingController(rootView: view)
            let win = NSWindow(contentViewController: hosting)
            win.title = "dockja Preferences"
            win.styleMask = [.titled, .closable]
            win.setContentSize(NSSize(width: 360, height: 440))
            window = win
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct AppRow: Identifiable {
    let id: String      // bundleID
    let name: String
    let icon: NSImage?
}

private struct PreferencesView: View {
    let settings: SettingsStore
    @State private var enabled: Set<String> = []
    @State private var apps: [AppRow] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Enabled apps").font(.headline)
            List(apps) { app in
                Toggle(isOn: binding(for: app.id)) {
                    HStack {
                        if let icon = app.icon {
                            Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                        }
                        Text(app.name)
                    }
                }
            }
            Button("Add app…") { addApp() }
        }
        .padding()
        .onAppear(perform: load)
    }

    private func load() {
        enabled = settings.enabledSet
        var rows: [String: AppRow] = [:]
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            if let id = app.bundleIdentifier {
                rows[id] = AppRow(id: id, name: app.localizedName ?? id, icon: app.icon)
            }
        }
        for id in enabled where rows[id] == nil {
            rows[id] = AppRow(id: id, name: id, icon: nil)
        }
        apps = rows.values.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { enabled.contains(id) },
            set: { isOn in
                if isOn { enabled.insert(id) } else { enabled.remove(id) }
                settings.update { $0.enabledBundleIDs = Array(enabled) }
            }
        )
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return }
        let name = (bundle.infoDictionary?["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        enabled.insert(id)
        settings.update { $0.enabledBundleIDs = Array(enabled) }
        if !apps.contains(where: { $0.id == id }) {
            apps.append(AppRow(id: id, name: name,
                               icon: NSWorkspace.shared.icon(forFile: url.path)))
            apps.sort { $0.name.lowercased() < $1.name.lowercased() }
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: builds with no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/dockja/PreferencesController.swift
git commit -m "Add preferences window with app checklist"
```

---

## Task 13: AppCoordinator

**Files:**
- Create: `Sources/dockja/AppCoordinator.swift`

Wires provider → enumerator/raiser, frontmost observer, refresh timer, bar panel, status item, preferences. Holds the Accessibility trust gate.

- [ ] **Step 1: Write `Sources/dockja/AppCoordinator.swift`**

```swift
import AppKit
import ApplicationServices
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
    private var statusItem: StatusItemController?
    private var refreshTimer: Timer?
    private var currentApp: NSRunningApplication?

    init() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("dockja")
        settings = SettingsStore(directory: appSupport)
        enumerator = WindowEnumerator(provider: provider)
        raiser = WindowRaiser(provider: provider)
        bar = BarPanelController(settings: settings)
        bar.onSelect = { [weak self] window in self?.raiser.raise(window) }
    }

    func start() {
        statusItem = StatusItemController(
            isTrusted: { AXIsProcessTrusted() },
            onOpenPreferences: { [weak self] in
                guard let self else { return }
                PreferencesController.shared.show(settings: self.settings)
            },
            onGrantAccessibility: { Self.promptAccessibility() }
        )
        frontmost.onChange = { [weak self] app in self?.handleFrontmost(app) }
        frontmost.start()
        handleFrontmost(NSWorkspace.shared.frontmostApplication)
    }

    static func promptAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    private func handleFrontmost(_ app: NSRunningApplication?) {
        currentApp = app
        // Debounce so rapid app switching does not thrash the enumerate/show path.
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
        let windows = enumerator.windows(forPID: app.processIdentifier)
        switch barState(frontmostBundleID: bundleID,
                        enabled: settings.enabledSet,
                        windowCount: windows.count) {
        case .hidden:
            bar.hide(); stopTimer()
        case .visible:
            bar.show(icon: app.icon, windows: windows)
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
        let windows = enumerator.windows(forPID: app.processIdentifier)
        if windows.isEmpty {
            bar.hide(); stopTimer(); return
        }
        bar.update(icon: app.icon, windows: windows)
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: builds with no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/dockja/AppCoordinator.swift
git commit -m "Add app coordinator wiring components together"
```

---

## Task 14: App entry point + run

**Files:**
- Modify: `Sources/dockja/main.swift` (replace stub from Task 1)
- Create: `Sources/dockja/AppDelegate.swift`

- [ ] **Step 1: Write `Sources/dockja/AppDelegate.swift`**

```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppCoordinator.promptAccessibility()
        let coordinator = AppCoordinator()
        coordinator.start()
        self.coordinator = coordinator
    }
}
```

- [ ] **Step 2: Replace `Sources/dockja/main.swift`**

```swift
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // menu-bar agent, no Dock icon
app.run()
```

- [ ] **Step 3: Build the whole thing**

Run: `swift build`
Expected: builds with no errors.

- [ ] **Step 4: Run the full test suite**

Run: `swift test`
Expected: PASS — all DockjaCore tests green.

- [ ] **Step 5: Commit**

```bash
git add Sources/dockja/main.swift Sources/dockja/AppDelegate.swift
git commit -m "Add application entry point as menu-bar agent"
```

---

## Task 15: App bundle packaging + manual verification

**Files:**
- Create: `Resources/Info.plist`
- Create: `scripts/bundle.sh`

A bundled `.app` gives a stable identity for the Accessibility permission (the permission is keyed to the binary; a stable bundle avoids re-granting on every rebuild).

- [ ] **Step 1: Write `Resources/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>dockja</string>
    <key>CFBundleIdentifier</key><string>com.ojajajajaja.dockja</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleExecutable</key><string>dockja</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSUIElement</key><true/>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
</dict>
</plist>
```

- [ ] **Step 2: Write `scripts/bundle.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/dockja"

APP="dockja.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$BIN" "$APP/Contents/MacOS/dockja"

echo "Built $APP"
echo "Launch:  open $APP"
```

- [ ] **Step 3: Make it executable and build the bundle**

Run: `chmod +x scripts/bundle.sh && ./scripts/bundle.sh`
Expected: prints `Built dockja.app`. A `dockja.app` directory exists.

- [ ] **Step 4: Add dockja.app to .gitignore**

Append to `.gitignore`:
```
dockja.app/
```

- [ ] **Step 5: Commit**

```bash
git add Resources/Info.plist scripts/bundle.sh .gitignore
git commit -m "Add app bundle packaging script"
```

- [ ] **Step 6: Manual verification (user runs on their Mac)**

This requires a GUI session, Accessibility permission, and visual confirmation — it cannot be automated headlessly. Checklist:

1. `open dockja.app` — a menu-bar icon (stacked-rectangles) appears; no Dock icon.
2. Click the menu-bar icon → if untrusted, "Grant Accessibility…" is shown. Click it → System Settings → Privacy & Security → Accessibility → enable **dockja**. (First launch also auto-prompts.)
3. Click the icon → **Preferences…** → enable an app with several windows (e.g. Safari).
4. Focus that app with 2+ windows → the floating bar appears listing each window by title.
5. Click a bar entry → that exact window raises and focuses.
6. Open/close/retitle a window in that app → the bar updates within ~1s.
7. Switch to a non-enabled app → the bar hides. Switch back → it reappears.
8. Drag the bar to a new spot → quit and relaunch → it reopens at the saved spot.

---

## Done criteria

- `swift test` passes (Tasks 1-7 logic).
- `swift build` and `./scripts/bundle.sh` succeed.
- Manual checklist in Task 15 Step 6 passes on the user's Mac.

## Future (out of scope, per spec §9)

- Per-window custom logo images (map title pattern → image), replacing the app icon in `BarView`. `AppConfig` already reserves room; add `logoRules` + a resolver consulted in `refreshEntriesOnly`/`BarView`.
- AX observers (`AXObserverCreate`) to replace the 0.7s poll with event-driven updates.
- Vertical orientation, keyboard switching, close/minimize from the bar.
