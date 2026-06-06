import Foundation

public enum BarState: Equatable {
    case hidden
    case visible(bundleID: String)
}

/// Pure decision: show the bar only when an enabled app is frontmost
/// and it has at least one window. (No 1-window suppression — avoids flicker.)
public func barState(frontmostBundleID: String?,
                     enabled: Set<String>,
                     windowCount: Int) -> BarState {
    guard let id = frontmostBundleID, enabled.contains(id), windowCount >= 1 else {
        return .hidden
    }
    return .visible(bundleID: id)
}
