import Foundation

public enum DockEdge: String, Codable, Equatable {
    case top
    case bottom
    case left
    case right

    public var isHorizontal: Bool { self == .top || self == .bottom }
}
