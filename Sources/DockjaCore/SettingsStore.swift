import Foundation
import CoreGraphics

public struct Settings: Codable, Equatable {
    public var enabledBundleIDs: [String]
    public var barFrame: CGRect?
    public init(enabledBundleIDs: [String] = [], barFrame: CGRect? = nil) {
        self.enabledBundleIDs = enabledBundleIDs
        self.barFrame = barFrame
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
        guard let data = try? JSONEncoder().encode(settings) else { return }
        try? data.write(to: fileURL)
    }
}
