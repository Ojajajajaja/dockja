import Foundation
import CoreGraphics
import ApplicationServices

/// Opaque handle to a window. Real provider wraps an `AXUIElement`;
/// tests construct refs with no backing AX element.
public final class WindowRef {
    public let ax: AXUIElement?
    public init(ax: AXUIElement) { self.ax = ax }
    /// Synthetic ref for tests (no backing AX element).
    public init() { self.ax = nil }
}

public struct WindowInfo {
    public let ref: WindowRef
    /// Stable identifier for the window's lifetime (CGWindowID). Used to keep
    /// the bar's entry order fixed even when AX reorders windows by focus.
    /// 0 when the underlying id is unavailable.
    public let id: CGWindowID
    public let title: String
    public let isMinimized: Bool
    public let isActive: Bool
    public let pid: pid_t

    public init(ref: WindowRef, id: CGWindowID, title: String, isMinimized: Bool, isActive: Bool, pid: pid_t) {
        self.ref = ref
        self.id = id
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
