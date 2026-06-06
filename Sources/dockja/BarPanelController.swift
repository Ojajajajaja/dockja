import AppKit
import SwiftUI
import DockjaCore

@MainActor
final class BarPanelController: NSObject, NSWindowDelegate {
    private let panel: NSPanel
    private let model = BarModel()
    private let settings: SettingsStore
    private let frameSaveDebouncer = Debouncer(interval: 0.4)
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
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func update(icon: NSImage?, windows: [WindowInfo]) {
        model.update(icon: icon, windows: windows)
    }

    func hide() {
        if panel.isVisible { panel.orderOut(nil) }
    }

    // Persist position when the user drags the bar. Debounced so a drag's
    // continuous move events don't write the settings file on every tick.
    func windowDidMove(_ notification: Notification) {
        frameSaveDebouncer.call { [weak self] in
            guard let self else { return }
            self.settings.update { $0.barFrame = self.panel.frame }
        }
    }
}

/// Hosting view that responds to the first click even when its window is not
/// key — needed so entries in the non-activating bar fire on the first click.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
