import Foundation
import CoreGraphics

/// Keeps the bar's window entries in a fixed order per app, so focusing a
/// window does not make it jump to the front. Each window keeps its first-seen
/// slot; newly opened windows append at the end; closed windows drop out.
///
/// Ordering is remembered per pid, so returning to an app preserves its layout.
/// Duplicate ids (e.g. 0 when the underlying CGWindowID is unavailable) are
/// handled as a multiset so no window is ever dropped.
public struct WindowOrderStabilizer {
    private var orderByPID: [pid_t: [CGWindowID]] = [:]

    public init() {}

    public mutating func stableOrder(pid: pid_t, windows: [WindowInfo]) -> [WindowInfo] {
        // Available count of each live id (multiset).
        var available: [CGWindowID: Int] = [:]
        for w in windows { available[w.id, default: 0] += 1 }

        var newOrder: [CGWindowID] = []
        // 1. Keep remembered ids that still have a live instance, in remembered order.
        for id in orderByPID[pid] ?? [] {
            if let count = available[id], count > 0 {
                newOrder.append(id)
                available[id] = count - 1
            }
        }
        // 2. Append remaining (newly seen) live ids in their current live order.
        for w in windows {
            if let count = available[w.id], count > 0 {
                newOrder.append(w.id)
                available[w.id] = count - 1
            }
        }
        orderByPID[pid] = newOrder

        // Materialize windows in the resolved order, consuming buckets so that
        // duplicate ids each map to a distinct window instance.
        var byID: [CGWindowID: [WindowInfo]] = [:]
        for w in windows { byID[w.id, default: []].append(w) }
        var result: [WindowInfo] = []
        for id in newOrder {
            if var bucket = byID[id], !bucket.isEmpty {
                result.append(bucket.removeFirst())
                byID[id] = bucket
            }
        }
        return result
    }
}
