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
    private var isAdjustingFrame = false
    /// True while the user is dragging the panel; suppresses the periodic
    /// reposition so a content refresh can't yank the bar back to its edge.
    private var isUserDragging = false

    // Auto-hide
    private var isActive = false        // an enabled app is focused (dock logically shown)
    private var isRevealed = true       // currently slid into view
    private var autoHideTimer: Timer?
    private var hideAt: Date?
    private let revealHotZone: CGFloat = 3
    private let autoHideDelay: TimeInterval = 0.6

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
        panel.isMovableByWindowBackground = false   // we drive dragging ourselves (glued to edges)
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
        let blur = DragBlurView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 22
        blur.layer?.cornerCurve = .continuous
        blur.layer?.masksToBounds = true
        blur.layer?.borderWidth = 1
        blur.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        blur.onDrag = { [weak self] global in self?.liveDrag(to: global) }
        blur.onDragEnd = { [weak self] in self?.persistDockPosition() }
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
        isActive = true
        model.iconSize = settings.settings.dockIconSize
        model.update(items: items, appIcon: appIcon)
        if settings.settings.autoHide { startAutoHide() } else { stopAutoHide(); isRevealed = true }
        placeForState(animated: false)
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func update(items: [DisplayWindow], appIcon: NSImage?) {
        model.iconSize = settings.settings.dockIconSize
        model.update(items: items, appIcon: appIcon)
        if settings.settings.autoHide { startAutoHide() } else { stopAutoHide(); isRevealed = true }
        placeForState(animated: false)
    }

    func hide() {
        isActive = false
        stopAutoHide()
        if panel.isVisible { panel.orderOut(nil) }
        hideLabel()
    }

    // MARK: - Positioning

    private func resizeAndPlace() { placeForState(animated: false) }

    /// Place the panel either flush at its edge (revealed) or fully off-screen
    /// (auto-hidden), sized analytically so it matches what DockBar renders.
    private func placeForState(animated: Bool) {
        guard !isUserDragging else { return }
        let shown = shownFrame()
        guard shown.width > 1, shown.height > 1 else { return }
        let target = (settings.settings.autoHide && !isRevealed) ? hiddenFrame(shown: shown) : shown
        if !animated, framesEqual(panel.frame, target) { return }
        setFrame(target, animated: animated)
    }

    private func dockSize(for edge: DockEdge) -> CGSize {
        DockMetrics.contentSize(count: model.items.count,
                                iconSize: settings.settings.dockIconSize,
                                horizontal: edge.isHorizontal)
    }

    /// The flush-at-edge frame (visible position).
    private func shownFrame() -> CGRect {
        let screen = dockScreen()
        let size = dockSize(for: model.edge)
        let parallel = settings.settings.dockParallel ?? defaultParallel(for: model.edge, size: size, screen: screen)
        let origin = snapper.origin(for: model.edge, size: size, parallel: parallel, screen: screen)
        return CGRect(origin: origin, size: size)
    }

    /// Same frame shifted fully off-screen toward its edge (hidden position).
    private func hiddenFrame(shown: CGRect) -> CGRect {
        var f = shown
        switch model.edge {
        case .bottom: f.origin.y = shown.minY - shown.height
        case .top:    f.origin.y = shown.maxY
        case .left:   f.origin.x = shown.minX - shown.width
        case .right:  f.origin.x = shown.maxX
        }
        return f
    }

    private func defaultParallel(for edge: DockEdge, size: CGSize, screen: CGRect) -> CGFloat {
        edge.isHorizontal ? screen.midX - size.width / 2 : screen.midY - size.height / 2
    }

    private func dockScreen() -> CGRect {
        (panel.screen ?? NSScreen.main)?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    }

    private func setFrame(_ frame: CGRect, animated: Bool) {
        isAdjustingFrame = true
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
        isAdjustingFrame = false
    }

    private func framesEqual(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 0.5 && abs(a.minY - b.minY) < 0.5
            && abs(a.width - b.width) < 0.5 && abs(a.height - b.height) < 0.5
    }

    /// Called when the edge changes; positions immediately.
    private func repositionForMode() {
        resizeAndPlace()
    }

    // MARK: - Auto-hide

    private func startAutoHide() {
        guard autoHideTimer == nil else { return }
        isRevealed = false
        autoHideTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.autoHideTick() }
        }
    }

    private func stopAutoHide() {
        autoHideTimer?.invalidate()
        autoHideTimer = nil
        hideAt = nil
    }

    private func autoHideTick() {
        guard isActive, settings.settings.autoHide, !isUserDragging else { return }
        let mouse = NSEvent.mouseLocation
        let shown = shownFrame()
        let inHot = hotZone(shown: shown).contains(mouse)
        let inDock = isRevealed && shown.insetBy(dx: -8, dy: -8).contains(mouse)
        if inHot || inDock {
            hideAt = nil
            if !isRevealed { isRevealed = true; placeForState(animated: true) }
        } else if isRevealed {
            if hideAt == nil {
                hideAt = Date().addingTimeInterval(autoHideDelay)
            } else if Date() >= hideAt! {
                isRevealed = false
                hideAt = nil
                hideLabel()
                placeForState(animated: true)
            }
        }
    }

    /// Thin hot band at the screen edge, only across the dock's span.
    private func hotZone(shown: CGRect) -> CGRect {
        let screen = dockScreen()
        let t = revealHotZone
        switch model.edge {
        case .bottom: return CGRect(x: shown.minX, y: screen.minY, width: shown.width, height: t)
        case .top:    return CGRect(x: shown.minX, y: screen.maxY - t, width: shown.width, height: t)
        case .left:   return CGRect(x: screen.minX, y: shown.minY, width: t, height: shown.height)
        case .right:  return CGRect(x: screen.maxX - t, y: shown.minY, width: t, height: shown.height)
        }
    }

    // MARK: - Dragging (custom: the dock stays glued to the nearest edge, live)

    /// Called continuously while the user drags the dock background. The dock
    /// follows the cursor but always sticks to the nearest screen edge, flipping
    /// orientation live — no free-floating, no settle pause.
    private func liveDrag(to global: NSPoint) {
        isUserDragging = true
        isRevealed = true
        hideLabel()
        let screen = screenContaining(global)
        let edge = snapper.nearestEdge(barCenter: global, screen: screen)
        model.edge = edge
        let size = dockSize(for: edge)
        let parallel = edge.isHorizontal ? global.x - size.width / 2 : global.y - size.height / 2
        let origin = snapper.origin(for: edge, size: size, parallel: parallel, screen: screen)
        setFrameProgrammatically(CGRect(origin: origin, size: size))
    }

    private func persistDockPosition() {
        isUserDragging = false
        let parallel = model.edge.isHorizontal ? panel.frame.origin.x : panel.frame.origin.y
        settings.update {
            $0.dockEdge = self.model.edge
            $0.dockParallel = parallel
        }
    }

    private func screenContaining(_ point: NSPoint) -> CGRect {
        let s = NSScreen.screens.first { $0.frame.contains(point) } ?? panel.screen ?? NSScreen.main
        return s?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
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

/// Visual-effect backdrop that also drives custom edge-glued dragging. It only
/// receives mouse events on the dock's empty/border areas (icon clicks are
/// handled by the SwiftUI layer in front).
private final class DragBlurView: NSVisualEffectView {
    var onDrag: ((NSPoint) -> Void)?
    var onDragEnd: (() -> Void)?
    override func mouseDown(with event: NSEvent) { /* become the drag origin */ }
    override func mouseDragged(with event: NSEvent) { onDrag?(NSEvent.mouseLocation) }
    override func mouseUp(with event: NSEvent) { onDragEnd?() }
}
