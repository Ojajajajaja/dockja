import Foundation
import CoreGraphics
@testable import DockjaCore

final class FakeAccessibilityProvider: AccessibilityProvider {
    struct FakeWindow {
        var title: String
        var minimized: Bool
        var main: Bool
        var standard: Bool
    }

    private var windowsByPID: [pid_t: [WindowRef]] = [:]
    private var data: [ObjectIdentifier: FakeWindow] = [:]
    /// Maps ObjectIdentifier → the integer label passed to addWindow, for readable call logs.
    private var labels: [ObjectIdentifier: Int] = [:]
    /// Ordered record of mutating calls, for asserting behavior.
    var calls: [String] = []

    func addWindow(pid: pid_t, id: Int, title: String,
                   minimized: Bool = false, main: Bool = false, standard: Bool = true) {
        let ref = WindowRef()
        let oid = ObjectIdentifier(ref)
        windowsByPID[pid, default: []].append(ref)
        data[oid] = FakeWindow(title: title, minimized: minimized, main: main, standard: standard)
        labels[oid] = id
    }

    private func label(_ window: WindowRef) -> Int { labels[ObjectIdentifier(window)] ?? -1 }

    func windows(forPID pid: pid_t) -> [WindowRef] { windowsByPID[pid] ?? [] }
    func isStandardWindow(_ window: WindowRef) -> Bool { data[ObjectIdentifier(window)]?.standard ?? true }
    func windowID(_ window: WindowRef) -> CGWindowID { CGWindowID(label(window)) }
    func title(of window: WindowRef) -> String? { data[ObjectIdentifier(window)]?.title }
    func isMinimized(_ window: WindowRef) -> Bool { data[ObjectIdentifier(window)]?.minimized ?? false }
    func isMain(_ window: WindowRef) -> Bool { data[ObjectIdentifier(window)]?.main ?? false }

    func unminimize(_ window: WindowRef) {
        calls.append("unminimize(\(label(window)))")
        data[ObjectIdentifier(window)]?.minimized = false
    }
    func activateApp(pid: pid_t) { calls.append("activate(\(pid))") }
    func raise(_ window: WindowRef) { calls.append("raise(\(label(window)))") }
    func setMain(_ window: WindowRef) { calls.append("setMain(\(label(window)))") }
}
