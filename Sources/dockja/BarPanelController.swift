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
    /// True while the user is dragging the panel; suppresses the periodic
    /// reposition so a content refresh can't yank the bar back to its edge.
    private var isUserDragging = false

    var onSelect: ((WindowInfo) -> Void)?
    var onRightClick: ((CGWindowID, NSView) -> Void)?

    init(settings: SettingsStore) {
        self.settings = settings
        let initial = NSRect(x: 200, y: 200, width: 200, height: 80)  // placeDocked repositions on first show
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

        model.edge = settings.settings.dockEdge

        let root = BarView(
            model: model,
            onSelect: { [weak self] win in self?.onSelect?(win) },
            onRightClick: { [weak self] id, view in self?.onRightClick?(id, view) },
            onHoverIndex: { [weak self] idx in self?.showLabel(idx) }
        )
        let host = FirstMouseHostingView(rootView: root)
        host.autoresizingMask = [.width, .height]
        // Real "glass": an NSVisualEffectView blurring what's behind the window,
        // with the transparent SwiftUI dock content layered on top.
        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 22
        blur.layer?.cornerCurve = .continuous
        blur.layer?.masksToBounds = true
        blur.layer?.borderWidth = 1
        blur.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        host.frame = blur.bounds
        blur.addSubview(host)
        panel.contentView = blur
    }

    // MARK: - Appearance

    func setAppearance(edge: DockEdge) {
        model.edge = edge
        model.iconSize = settings.settings.dockIconSize
        DispatchQueue.main.async { [weak self] in self?.repositionForMode() }
    }

    func show(items: [DisplayWindow], appIcon: NSImage?) {
        model.iconSize = settings.settings.dockIconSize
        model.update(items: items, appIcon: appIcon)
        resizeAndPlace()
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func update(items: [DisplayWindow], appIcon: NSImage?) {
        model.iconSize = settings.settings.dockIconSize
        model.update(items: items, appIcon: appIcon)
        resizeAndPlace()
    }

    func hide() {
        if panel.isVisible { panel.orderOut(nil) }
        hideLabel()
    }

    // MARK: - Positioning

    /// Keep the dock flush to its current edge, sized analytically (deterministic,
    /// no fittingSize timing races, and matches what DockBar renders).
    private func resizeAndPlace() {
        guard !isUserDragging else { return }   // never reposition mid-drag
        let size = dockSize(for: model.edge)
        guard size.width > 1, size.height > 1 else { return }
        placeDocked(size: size)
    }

    private func dockSize(for edge: DockEdge) -> CGSize {
        DockMetrics.contentSize(count: model.items.count,
                                iconSize: settings.settings.dockIconSize,
                                horizontal: edge.isHorizontal)
    }

    /// Snap flush to the current edge using the saved parallel offset.
    private func placeDocked(size: CGSize) {
        let screen = (panel.screen ?? NSScreen.main)?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let parallel = settings.settings.dockParallel ?? defaultParallel(for: model.edge, size: size, screen: screen)
        let origin = snapper.origin(for: model.edge, size: size, parallel: parallel, screen: screen)
        let target = CGRect(origin: origin, size: size)
        let f = panel.frame
        if abs(f.width - target.width) < 0.5, abs(f.height - target.height) < 0.5,
           abs(f.origin.x - target.origin.x) < 0.5, abs(f.origin.y - target.origin.y) < 0.5 {
            return
        }
        setFrameProgrammatically(target)
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
        isUserDragging = true
        hideLabel()
        frameSaveDebouncer.call { [weak self] in
            guard let self else { return }
            self.isUserDragging = false
            self.snapToNearestEdge()
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
        let size = dockSize(for: edge)
        let parallel = edge.isHorizontal ? panel.frame.origin.x : panel.frame.origin.y
        let origin = snapper.origin(for: edge, size: size, parallel: parallel, screen: screen)
        setFrameProgrammatically(CGRect(origin: origin, size: size))
        settings.update {
            $0.dockEdge = edge
            $0.dockParallel = parallel
        }
    }

    private func setFrameProgrammatically(_ frame: CGRect) {
        isAdjustingFrame = true
        panel.setFrame(frame, display: true)
        isAdjustingFrame = false
    }

    // MARK: - Hover name label (its own floating panel, never clipped by the dock)

    private var labelPanel: NSPanel?
    private var labelIndex: Int?

    private func showLabel(_ index: Int?) {
        guard let index, index >= 0, index < model.items.count else { hideLabel(); return }
        if index == labelIndex, labelPanel?.isVisible == true { return }   // already shown
        labelIndex = index

        let host = NSHostingView(rootView: DockLabel(text: model.items[index].name))
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize

        let lp = labelPanel ?? makeLabelPanel()
        lp.setContentSize(size)
        lp.contentView = host
        lp.setFrameOrigin(labelOrigin(for: index, size: size))
        if !lp.isVisible { lp.orderFront(nil) }
        labelPanel = lp
    }

    private func hideLabel() {
        labelIndex = nil
        labelPanel?.orderOut(nil)
    }

    private func makeLabelPanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.level = .floating
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        return p
    }

    /// Screen origin for the hover label: just outside the dock on the interior
    /// side, centered on the hovered icon.
    private func labelOrigin(for index: Int, size: CGSize) -> CGPoint {
        let f = panel.frame
        let gap: CGFloat = 6
        let main = DockMetrics.center(index, count: model.items.count,
                                      iconSize: settings.settings.dockIconSize)
        switch model.edge {
        case .bottom:
            return CGPoint(x: f.minX + main - size.width / 2, y: f.maxY + gap)
        case .top:
            return CGPoint(x: f.minX + main - size.width / 2, y: f.minY - gap - size.height)
        case .left:
            return CGPoint(x: f.maxX + gap, y: f.maxY - main - size.height / 2)
        case .right:
            return CGPoint(x: f.minX - gap - size.width, y: f.maxY - main - size.height / 2)
        }
    }
}

/// Hosting view that responds to the first click even when its window is not key.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
