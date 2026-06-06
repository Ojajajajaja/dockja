import Foundation

/// Ordered, de-duplicated, capped list of recently used icon file paths.
public struct RecentIcons: Codable, Equatable {
    public private(set) var paths: [String]

    public init(paths: [String] = []) { self.paths = paths }

    public mutating func add(_ path: String, cap: Int = 12) {
        paths.removeAll { $0 == path }
        paths.insert(path, at: 0)
        if paths.count > cap { paths = Array(paths.prefix(cap)) }
    }
}
