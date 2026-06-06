import Foundation

/// A named group of apps whose windows are shown together in one merged dock.
public struct AppGroup: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var bundleIDs: [String]

    public init(id: String, name: String, bundleIDs: [String] = []) {
        self.id = id
        self.name = name
        self.bundleIDs = bundleIDs
    }
}

public enum GroupResolver {
    /// The bundle IDs to display for the given frontmost app, or nil to hide.
    /// - A non-enabled frontmost app hides the dock.
    /// - A frontmost app that belongs to a group shows that group's enabled
    ///   members (in their listed order).
    /// - Otherwise the frontmost app shows on its own (per-app dock).
    public static func unit(frontmost: String?,
                            enabled: Set<String>,
                            groups: [AppGroup]) -> [String]? {
        guard let f = frontmost, enabled.contains(f) else { return nil }
        if let group = groups.first(where: { $0.bundleIDs.contains(f) }) {
            let members = group.bundleIDs.filter { enabled.contains($0) }
            return members.isEmpty ? [f] : members
        }
        return [f]
    }
}
