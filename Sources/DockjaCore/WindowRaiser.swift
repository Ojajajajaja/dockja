import Foundation

public struct WindowRaiser {
    private let provider: AccessibilityProvider
    public init(provider: AccessibilityProvider) { self.provider = provider }

    public func raise(_ window: WindowInfo) {
        if provider.isMinimized(window.ref) {
            provider.unminimize(window.ref)
        }
        provider.activateApp(pid: window.pid)
        provider.raise(window.ref)
        provider.setMain(window.ref)
    }
}
