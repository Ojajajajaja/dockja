import AppKit
import DockjaCore

/// Copies chosen images into the app's icon folder and tracks recents.
final class IconLibrary {
    private let dir: URL
    private let settings: SettingsStore

    init(settings: SettingsStore) {
        self.settings = settings
        dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("dockja/icons")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    /// Validate, copy into the library, register in recents. Returns the new path
    /// or nil if the file isn't a readable image / copy failed.
    func importImage(from url: URL) -> String? {
        guard NSImage(contentsOf: url) != nil else { return nil }
        let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension
        let dest = dir.appendingPathComponent(UUID().uuidString + "." + ext)
        do {
            try FileManager.default.copyItem(at: url, to: dest)
        } catch {
            return nil
        }
        var recents = RecentIcons(paths: settings.settings.recentIcons)
        recents.add(dest.path)
        settings.update { $0.recentIcons = recents.paths }
        return dest.path
    }

    var recents: [String] { settings.settings.recentIcons }
}
