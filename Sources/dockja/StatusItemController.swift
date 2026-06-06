import AppKit
import DockjaCore

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let item: NSStatusItem
    private let isTrusted: () -> Bool
    private let currentMode: () -> DisplayMode
    private let onSetMode: (DisplayMode) -> Void
    private let onOpenPreferences: () -> Void
    private let onGrantAccessibility: () -> Void

    init(isTrusted: @escaping () -> Bool,
         currentMode: @escaping () -> DisplayMode,
         onSetMode: @escaping (DisplayMode) -> Void,
         onOpenPreferences: @escaping () -> Void,
         onGrantAccessibility: @escaping () -> Void) {
        self.isTrusted = isTrusted
        self.currentMode = currentMode
        self.onSetMode = onSetMode
        self.onOpenPreferences = onOpenPreferences
        self.onGrantAccessibility = onGrantAccessibility
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        item.button?.image = NSImage(systemSymbolName: "rectangle.stack",
                                     accessibilityDescription: "dockja")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if !isTrusted() {
            let grant = NSMenuItem(title: "Grant Accessibility…",
                                   action: #selector(grant), keyEquivalent: "")
            grant.target = self
            menu.addItem(grant)
            menu.addItem(.separator())
        }

        let mode = currentMode()
        let compact = NSMenuItem(title: "Compact", action: #selector(setCompact), keyEquivalent: "")
        compact.target = self
        compact.state = (mode == .compact) ? .on : .off
        menu.addItem(compact)

        let dock = NSMenuItem(title: "Apple Dock", action: #selector(setAppleDock), keyEquivalent: "")
        dock.target = self
        dock.state = (mode == .appleDock) ? .on : .off
        menu.addItem(dock)

        menu.addItem(.separator())

        let prefs = NSMenuItem(title: "Preferences…",
                               action: #selector(openPrefs), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit dockja",
                              action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func setCompact() { onSetMode(.compact) }
    @objc private func setAppleDock() { onSetMode(.appleDock) }
    @objc private func grant() { onGrantAccessibility() }
    @objc private func openPrefs() { onOpenPreferences() }
    @objc private func quit() { NSApp.terminate(nil) }
}
