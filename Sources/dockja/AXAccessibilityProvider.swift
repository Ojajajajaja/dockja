import AppKit
import ApplicationServices
import CoreGraphics
import DockjaCore

// Private AX SPI that maps an AXUIElement window to its CGWindowID. Stable for
// the window's lifetime; used by window managers (yabai, Amethyst, …). This is
// what gives each bar entry a fixed identity so its slot never changes.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

final class AXAccessibilityProvider: AccessibilityProvider {
    func windows(forPID pid: pid_t) -> [DockjaCore.WindowRef] {
        let appEl = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute as CFString, &value)
        guard err == .success, let arr = value as? [AXUIElement] else { return [] }
        return arr.map { DockjaCore.WindowRef(ax: $0) }
    }

    func windowID(_ window: DockjaCore.WindowRef) -> CGWindowID {
        guard let el = window.ax else { return 0 }
        var wid: CGWindowID = 0
        return _AXUIElementGetWindow(el, &wid) == .success ? wid : 0
    }

    func title(of window: DockjaCore.WindowRef) -> String? {
        copyString(window.ax, kAXTitleAttribute)
    }

    func isMinimized(_ window: DockjaCore.WindowRef) -> Bool {
        copyBool(window.ax, kAXMinimizedAttribute) ?? false
    }

    func isMain(_ window: DockjaCore.WindowRef) -> Bool {
        copyBool(window.ax, kAXMainAttribute) ?? false
    }

    func unminimize(_ window: DockjaCore.WindowRef) {
        guard let el = window.ax else { return }
        AXUIElementSetAttributeValue(el, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
    }

    func activateApp(pid: pid_t) {
        NSRunningApplication(processIdentifier: pid)?.activate()
    }

    func raise(_ window: DockjaCore.WindowRef) {
        guard let el = window.ax else { return }
        AXUIElementPerformAction(el, kAXRaiseAction as CFString)
    }

    func setMain(_ window: DockjaCore.WindowRef) {
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
