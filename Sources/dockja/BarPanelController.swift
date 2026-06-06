import AppKit
import SwiftUI
import DockjaCore

@MainActor
final class BarPanelController: NSObject, NSWindowDelegate {
    private let panel: NSPanel
    private let model = BarModel()
    private let settings: SettingsStore
    private let frameSaveDebouncer = Debouncer(interval: 0.4)
    /// True while we resize the panel programmatically, so the resulting move
    /// notification isn't mistaken for a user drag and persisted.
    private var isAdjustingFrame = false
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
        // FirstMouseHostingView so a click on the freshly-shown non-activating
        // panel triggers the button immediately, instead of only making the
        // panel key and requiring a second click.
        let host = FirstMouseHostingView(rootView: root)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
    }

    func show(icon: NSImage?, windows: [WindowInfo]) {
        model.update(icon: icon, windows: windows)
        resizeToFit()
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func update(icon: NSImage?, windows: [WindowInfo]) {
        model.update(icon: icon, windows: windows)
        resizeToFit()
    }

    func hide() {
        if panel.isVisible { panel.orderOut(nil) }
    }

    // Persist position when the user drags the bar. Debounced so a drag's
    // continuous move events don't write the settings file on every tick.
    // Skipped during programmatic resizes so auto-fit doesn't drift the saved spot.
    func windowDidMove(_ notification: Notification) {
        guard !isAdjustingFrame else { return }
        frameSaveDebouncer.call { [weak self] in
            guard let self else { return }
            self.settings.update { $0.barFrame = self.panel.frame }
        }
    }

    // Size the panel to its fixed-size content, anchoring the top-left corner so
    // the bar grows/shrinks rightward/downward from where the user placed it.
    private func resizeToFit() {
        guard let host = panel.contentView else { return }
        let fitting = host.fittingSize
        guard fitting.width > 1, fitting.height > 1 else { return }
        var frame = panel.frame
        if abs(frame.width - fitting.width) < 0.5, abs(frame.height - fitting.height) < 0.5 {
            return
        }
        let topY = frame.origin.y + frame.size.height   // AppKit origin is bottom-left
        frame.size = fitting
        frame.origin.y = topY - fitting.height
        isAdjustingFrame = true
        panel.setFrame(frame, display: true)
        isAdjustingFrame = false
    }
}

/// Hosting view that responds to the first click even when its window is not
/// key — needed so entries in the non-activating bar fire on the first click.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
