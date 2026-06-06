import AppKit
import ApplicationServices
import CoreGraphics
import UniformTypeIdentifiers
import DockjaCore

@MainActor
final class AppCoordinator {
    private let provider = AXAccessibilityProvider()
    private let enumerator: WindowEnumerator
    private let raiser: WindowRaiser
    private let settings: SettingsStore
    private let frontmost = FrontmostAppObserver()
    private let bar: BarPanelController
    private let refreshDebouncer = Debouncer(interval: 0.1)
    private var orderStabilizer = WindowOrderStabilizer()
    private let overrides = WindowOverrideStore()
    private let resolver = OverrideResolver()
    private let icons: IconLibrary
    private let editPopover = EditPopoverController()
    private var statusItem: StatusItemController?
    private var refreshTimer: Timer?
    private var trustTimer: Timer?
    private var currentApp: NSRunningApplication?

    init() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("dockja")
        settings = SettingsStore(directory: appSupport)
        enumerator = WindowEnumerator(provider: provider)
        raiser = WindowRaiser(provider: provider)
        icons = IconLibrary(settings: settings)
        bar = BarPanelController(settings: settings)
        bar.onSelect = { [weak self] window in self?.raiser.raise(window) }
        bar.onRightClick = { [weak self] id, view in
            guard id != 0 else { return }   // no stable id -> can't safely scope an override
            self?.editPopover.show(for: id, relativeTo: view)
        }
        wireEditPopover()
    }

    func start() {
        statusItem = StatusItemController(
            isTrusted: { AXIsProcessTrusted() },
            onOpenPreferences: { [weak self] in
                guard let self else { return }
                PreferencesController.shared.show(settings: self.settings)
            },
            onGrantAccessibility: { Self.promptAccessibility() }
        )
        bar.setAppearance(edge: settings.settings.dockEdge)
        PreferencesController.shared.onChange = { [weak self] in self?.refresh() }
        frontmost.onChange = { [weak self] app in self?.handleFrontmost(app) }
        frontmost.start()
        handleFrontmost(NSWorkspace.shared.frontmostApplication)
        startTrustPollingIfNeeded()
    }

    static func promptAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    // MARK: - Edit popover wiring

    private func wireEditPopover() {
        editPopover.currentName = { [weak self] id in self?.overrides.override(for: id).customName ?? "" }
        editPopover.recents = { [weak self] in self?.icons.recents ?? [] }
        editPopover.onSetName = { [weak self] id, name in
            self?.overrides.setName(name.isEmpty ? nil : name, for: id)
            self?.refresh()
        }
        editPopover.onPickIcon = { [weak self] id, path in
            self?.overrides.setIcon(path, for: id)
            self?.refresh()
        }
        editPopover.onReset = { [weak self] id in
            self?.overrides.reset(id)
            self?.refresh()
        }
        editPopover.onBrowse = { [weak self] id in
            guard let self else { return }
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.image]
            panel.allowsMultipleSelection = false
            NSApp.activate(ignoringOtherApps: true)
            guard panel.runModal() == .OK, let url = panel.url,
                  let path = self.icons.importImage(from: url) else { return }
            self.overrides.setIcon(path, for: id)
            self.refresh()
        }
    }

    // MARK: - Refresh

    private func handleFrontmost(_ app: NSRunningApplication?) {
        // Ignore our own activation (e.g. when the edit popover takes keyboard
        // focus): keep showing the real target app's bar instead of hiding it.
        if let app, app.processIdentifier == NSRunningApplication.current.processIdentifier {
            return
        }
        currentApp = app
        stopTimer()
        refreshDebouncer.call { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
    }

    private func refresh() {
        guard let windows = currentUnitWindows() else {
            bar.hide(); stopTimer(); return
        }
        bar.show(items: resolveAndPruneWindows(windows))
        startTimer()
    }

    private func startTimer() {
        guard refreshTimer == nil else { return }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshEntriesOnly() }
        }
    }

    private func stopTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func refreshEntriesOnly() {
        guard let windows = currentUnitWindows() else {
            bar.hide(); stopTimer(); return
        }
        bar.update(items: resolveAndPruneWindows(windows))
    }

    /// Windows to display for the current frontmost app: its group's merged
    /// windows (if grouped), or just its own. nil = nothing to show (hide).
    private func currentUnitWindows() -> [WindowInfo]? {
        guard AXIsProcessTrusted(),
              let app = currentApp,
              let bundleID = app.bundleIdentifier,
              let unit = GroupResolver.unit(frontmost: bundleID,
                                            enabled: settings.enabledSet,
                                            groups: settings.settings.groups)
        else { return nil }
        let windows = windowsForUnit(unit)
        return windows.isEmpty ? nil : windows
    }

    /// Enumerate + stabilize windows for every running process of each bundle ID,
    /// clustered in the unit's order (so a group reads app-by-app).
    private func windowsForUnit(_ bundleIDs: [String]) -> [WindowInfo] {
        var result: [WindowInfo] = []
        for bid in bundleIDs {
            let apps = NSWorkspace.shared.runningApplications.filter {
                $0.bundleIdentifier == bid && $0.activationPolicy == .regular
            }
            for app in apps {
                let ws = orderStabilizer.stableOrder(
                    pid: app.processIdentifier,
                    windows: enumerator.windows(forPID: app.processIdentifier))
                result.append(contentsOf: ws)
            }
        }
        return result
    }

    /// Resolve overrides into display models and prune dead window ids.
    private func resolveAndPruneWindows(_ windows: [WindowInfo]) -> [DisplayWindow] {
        overrides.prune(keeping: Set(windows.map { $0.id }))
        return resolver.resolve(windows, overrides: overrides.overrides())
    }

    // MARK: - Trust polling

    private func startTrustPollingIfNeeded() {
        guard !AXIsProcessTrusted() else { return }
        trustTimer?.invalidate()
        trustTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                guard AXIsProcessTrusted() else { return }
                self.trustTimer?.invalidate()
                self.trustTimer = nil
                self.refresh()
            }
        }
    }
}
