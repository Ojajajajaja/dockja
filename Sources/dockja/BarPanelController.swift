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
