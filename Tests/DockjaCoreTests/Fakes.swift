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
