import Foundation
import CoreGraphics

/// Pure geometry for docking the bar to a screen edge. AppKit coordinates
/// (origin bottom-left, y up). `screen` should be a visible-frame rect.
public struct EdgeSnapper {
    public init() {}

    public func nearestEdge(barCenter c: CGPoint, screen s: CGRect) -> DockEdge {
        let dLeft = c.x - s.minX
        let dRight = s.maxX - c.x
        let dBottom = c.y - s.minY
        let dTop = s.maxY - c.y
        let m = min(dLeft, dRight, dBottom, dTop)
        if m == dLeft { return .left }
        if m == dRight { return .right }
        if m == dBottom { return .bottom }
        return .top
    }

    /// Origin that places `size` flush against `edge`, with the parallel axis
    /// (x for top/bottom, y for left/right) set to `parallel`, clamped on-screen.
    public func origin(for edge: DockEdge, size: CGSize,
                       parallel: CGFloat, screen s: CGRect) -> CGPoint {
        switch edge {
        case .bottom:
            return CGPoint(x: clamp(parallel, s.minX, s.maxX - size.width), y: s.minY)
        case .top:
            return CGPoint(x: clamp(parallel, s.minX, s.maxX - size.width), y: s.maxY - size.height)
        case .left:
            return CGPoint(x: s.minX, y: clamp(parallel, s.minY, s.maxY - size.height))
        case .right:
            return CGPoint(x: s.maxX - size.width, y: clamp(parallel, s.minY, s.maxY - size.height))
        }
    }

    private func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        guard hi > lo else { return lo }
        return max(lo, min(hi, v))
    }
}
