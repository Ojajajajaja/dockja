import Foundation
import CoreGraphics

public struct Settings: Codable, Equatable {
    public var enabledBundleIDs: [String]
    public var barFrame: CGRect?
    public var displayMode: DisplayMode
    public var dockEdge: DockEdge
    public var dockParallel: CGFloat?
    public var recentIcons: [String]   // paths; managed via the RecentIcons helper
    public var dockIconSize: CGFloat   // Apple Dock icon size in points

    public init(enabledBundleIDs: [String] = [],
                barFrame: CGRect? = nil,
                displayMode: DisplayMode = .compact,
                dockEdge: DockEdge = .bottom,
                dockParallel: CGFloat? = nil,
                recentIcons: [String] = [],
                dockIconSize: CGFloat = 48) {
        self.enabledBundleIDs = enabledBundleIDs
        self.barFrame = barFrame
        self.displayMode = displayMode
        self.dockEdge = dockEdge
        self.dockParallel = dockParallel
        self.recentIcons = recentIcons
        self.dockIconSize = dockIconSize
    }

    // Backward-compatible: tolerate JSON written before these fields existed.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabledBundleIDs = try c.decodeIfPresent([String].self, forKey: .enabledBundleIDs) ?? []
        barFrame = try c.decodeIfPresent(CGRect.self, forKey: .barFrame)
        displayMode = try c.decodeIfPresent(DisplayMode.self, forKey: .displayMode) ?? .compact
        dockEdge = try c.decodeIfPresent(DockEdge.self, forKey: .dockEdge) ?? .bottom
        dockParallel = try c.decodeIfPresent(CGFloat.self, forKey: .dockParallel)
        recentIcons = try c.decodeIfPresent([String].self, forKey: .recentIcons) ?? []
        dockIconSize = try c.decodeIfPresent(CGFloat.self, forKey: .dockIconSize) ?? 48
    }
}

public final class SettingsStore {
    private let fileURL: URL
    public private(set) var settings: Settings

    public init(directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent("settings.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(Settings.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = Settings()
        }
    }

    public func update(_ mutate: (inout Settings) -> Void) {
        mutate(&settings)
        save()
    }

    public var enabledSet: Set<String> { Set(settings.enabledBundleIDs) }

    private func save() {
        do {
            let data = try JSONEncoder().encode(settings)
            try data.write(to: fileURL)
        } catch {
            FileHandle.standardError.write(Data("dockja: failed to save settings: \(error)\n".utf8))
        }
    }
}
