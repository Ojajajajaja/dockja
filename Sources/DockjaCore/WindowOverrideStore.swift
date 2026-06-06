import Foundation
import CoreGraphics

/// In-memory per-window overrides, keyed by CGWindowID (stable for the window's
/// lifetime). Not persisted: overrides are intentionally lost when the window
/// or its app closes.
public final class WindowOverrideStore {
    private var map: [CGWindowID: WindowOverride] = [:]

    public init() {}

    public func overrides() -> [CGWindowID: WindowOverride] { map }

    public func override(for id: CGWindowID) -> WindowOverride { map[id] ?? WindowOverride() }

    public func setName(_ name: String?, for id: CGWindowID) {
        var o = map[id] ?? WindowOverride()
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        o.customName = (trimmed?.isEmpty == true) ? nil : trimmed
        store(o, for: id)
    }

    public func setIcon(_ path: String?, for id: CGWindowID) {
        var o = map[id] ?? WindowOverride()
        o.iconPath = path
        store(o, for: id)
    }

    public func reset(_ id: CGWindowID) { map[id] = nil }

    public func prune(keeping liveIDs: Set<CGWindowID>) {
        map = map.filter { liveIDs.contains($0.key) }
    }

    private func store(_ o: WindowOverride, for id: CGWindowID) {
        map[id] = o.isEmpty ? nil : o
    }
}
