import AppKit

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let item: NSStatusItem
    private let isTrusted: () -> Bool
    private let onOpenPreferences: () -> Void
    private let onGrantAccessibility: () -> Void

    init(isTrusted: @escaping () -> Bool,
         onOpenPreferences: @escaping () -> Void,
         onGrantAccessibility: @escaping () -> Void) {
        self.isTrusted = isTrusted
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

    // Rebuild on open so the Accessibility status reflects current trust.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if !isTrusted() {
            let grant = NSMenuItem(title: "Grant Accessibility…",
                                   action: #selector(grant), keyEquivalent: "")
            grant.target = self
            menu.addItem(grant)
            menu.addItem(.separator())
        }
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

    @objc private func grant() { onGrantAccessibility() }
    @objc private func openPrefs() { onOpenPreferences() }
    @objc private func quit() { NSApp.terminate(nil) }
}
