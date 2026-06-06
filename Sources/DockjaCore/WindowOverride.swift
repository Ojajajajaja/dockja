import Foundation
import CoreGraphics

/// A per-window display override. Keyed elsewhere by CGWindowID.
public struct WindowOverride: Equatable {
    public var customName: String?
    public var iconPath: String?

    public init(customName: String? = nil, iconPath: String? = nil) {
        self.customName = customName
        self.iconPath = iconPath
    }

    /// True when there is nothing to remember (used to drop empty entries).
    public var isEmpty: Bool {
        (customName?.isEmpty ?? true) && (iconPath?.isEmpty ?? true)
    }
}

/// A window plus its resolved display name and optional custom icon path.
public struct DisplayWindow {
    public let window: WindowInfo
    public let name: String
    public let iconPath: String?

    public init(window: WindowInfo, name: String, iconPath: String?) {
        self.window = window
        self.name = name
        self.iconPath = iconPath
    }
}

/// Merges raw windows with per-window overrides into display models.
public struct OverrideResolver {
    public init() {}

    public func resolve(_ windows: [WindowInfo],
                        overrides: [CGWindowID: WindowOverride]) -> [DisplayWindow] {
        windows.map { w in
            let o = overrides[w.id]
            let name: String
            if let custom = o?.customName, !custom.isEmpty {
                name = custom
            } else {
                name = w.displayLabel
            }
            let iconPath = (o?.iconPath?.isEmpty == false) ? o?.iconPath : nil
            return DisplayWindow(window: w, name: name, iconPath: iconPath)
        }
    }
}
