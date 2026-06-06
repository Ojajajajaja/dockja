import AppKit
import SwiftUI
import DockjaCore

@MainActor
final class BarPanelController: NSObject, NSWindowDelegate {
    private let panel: NSPanel
    private let model = BarModel()
    private let settings: SettingsStore
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
        let host = NSHostingView(rootView: root)
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

    // Persist position when the user drags the bar.
    func windowDidMove(_ notification: Notification) {
        settings.update { $0.barFrame = self.panel.frame }
    }
}
