import Foundation

public struct WindowEnumerator {
    private let provider: AccessibilityProvider
    public init(provider: AccessibilityProvider) { self.provider = provider }

    public func windows(forPID pid: pid_t) -> [WindowInfo] {
        provider.windows(forPID: pid).map { ref in
            WindowInfo(
                ref: ref,
                title: provider.title(of: ref) ?? "",
                isMinimized: provider.isMinimized(ref),
                isActive: provider.isMain(ref),
                pid: pid
            )
        }
    }
}
