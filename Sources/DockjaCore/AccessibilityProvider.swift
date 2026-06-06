import Foundation
import CoreGraphics

/// Every live-system side-effect goes through this protocol so that
/// WindowEnumerator / WindowRaiser stay testable with a fake.
public protocol AccessibilityProvider {
    func windows(forPID pid: pid_t) -> [WindowRef]
    /// Stable window id (CGWindowID), or 0 if unavailable.
    func windowID(_ window: WindowRef) -> CGWindowID
    func title(of window: WindowRef) -> String?
    func isMinimized(_ window: WindowRef) -> Bool
    func isMain(_ window: WindowRef) -> Bool
    func unminimize(_ window: WindowRef)
    func activateApp(pid: pid_t)
    func raise(_ window: WindowRef)
    func setMain(_ window: WindowRef)
}
