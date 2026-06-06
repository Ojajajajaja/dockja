import AppKit
import ApplicationServices
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
    private var statusItem: StatusItemController?
    private var refreshTimer: Timer?
    private var currentApp: NSRunningApplication?

    init() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("dockja")
        settings = SettingsStore(directory: appSupport)
        enumerator = WindowEnumerator(provider: provider)
        raiser = WindowRaiser(provider: provider)
        bar = BarPanelController(settings: settings)
        bar.onSelect = { [weak self] window in self?.raiser.raise(window) }
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
        frontmost.onChange = { [weak self] app in self?.handleFrontmost(app) }
        frontmost.start()
        handleFrontmost(NSWorkspace.shared.frontmostApplication)
    }

    static func promptAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    private func handleFrontmost(_ app: NSRunningApplication?) {
        currentApp = app
        // Stop the periodic refresh immediately: the old timer must not enumerate
        // against the newly-focused app before refresh() re-decides visibility.
        stopTimer()
        // Debounce so rapid app switching does not thrash the enumerate/show path.
        refreshDebouncer.call { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
    }

    private func refresh() {
        guard AXIsProcessTrusted(),
              let app = currentApp,
              let bundleID = app.bundleIdentifier else {
            bar.hide(); stopTimer(); return
        }
        let windows = enumerator.windows(forPID: app.processIdentifier)
        switch barState(frontmostBundleID: bundleID,
                        enabled: settings.enabledSet,
                        windowCount: windows.count) {
        case .hidden:
            bar.hide(); stopTimer()
        case .visible:
            bar.show(icon: app.icon, windows: windows)
            startTimer()
        }
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
        guard let app = currentApp else { return }
        let windows = enumerator.windows(forPID: app.processIdentifier)
        if windows.isEmpty {
            bar.hide(); stopTimer(); return
        }
        bar.update(icon: app.icon, windows: windows)
    }
}
