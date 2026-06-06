import SwiftUI
import AppKit
import CoreGraphics
import DockjaCore

final class BarModel: ObservableObject {
    @Published var edge: DockEdge = .bottom
    @Published var iconSize: CGFloat = 48
    @Published var items: [DisplayWindow] = []

    private var iconCache: [String: NSImage] = [:]
    private var appIconCache: [pid_t: NSImage] = [:]

    func update(items: [DisplayWindow]) {
        self.items = items
    }

    /// The original app icon for a window's process (also used for the badge).
    func appIcon(forPID pid: pid_t) -> NSImage? {
        if let cached = appIconCache[pid] { return cached }
        guard let img = NSRunningApplication(processIdentifier: pid)?.icon else { return nil }
        appIconCache[pid] = img
        return img
    }

    /// The icon to display: custom override if set & loadable, else the app icon.
    func image(for item: DisplayWindow) -> NSImage? {
        if let path = item.iconPath {
            if let cached = iconCache[path] { return cached }
            if let img = NSImage(contentsOfFile: path) {
                iconCache[path] = img
                return img
            }
        }
        return appIcon(forPID: item.window.pid)
    }

    /// True when a custom icon is shown (so the original-app badge is needed).
    func hasCustomIcon(_ item: DisplayWindow) -> Bool {
        guard let path = item.iconPath else { return false }
        return NSImage(contentsOfFile: path) != nil
    }
}

struct BarView: View {
    @ObservedObject var model: BarModel
    let onSelect: (WindowInfo) -> Void
    let onRightClick: (CGWindowID, NSView) -> Void
    let onHoverIndex: (Int?) -> Void

    var body: some View {
        DockBar(model: model,
                onSelect: onSelect,
                onRightClick: onRightClick,
                onHoverIndex: onHoverIndex)
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
