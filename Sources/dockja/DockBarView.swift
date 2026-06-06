import SwiftUI
import AppKit
import CoreGraphics
import DockjaCore

/// Layout geometry shared by the dock view and the panel controller (the
/// controller needs it to size/position the panel and place the hover label).
enum DockMetrics {
    static let spacing: CGFloat = 6
    static let pad: CGFloat = 8
    static let maxBump: CGFloat = 22      // peak magnification growth
    static let dotGap: CGFloat = 3
    static let dotSize: CGFloat = 5

    /// Length of the icon row at rest (no magnification).
    static func restExtent(count: Int, iconSize: CGFloat) -> CGFloat {
        guard count > 0 else { return 0 }
        return CGFloat(count) * iconSize + CGFloat(count - 1) * spacing
    }

    /// Length along the strip; reserves one bump of growth + end padding so
    /// magnified icons (which push their neighbors) never overflow.
    static func mainLength(count: Int, iconSize: CGFloat) -> CGFloat {
        restExtent(count: count, iconSize: iconSize) + maxBump + 2 * pad
    }

    /// Thickness across the strip: grown icon + dot + gap + padding.
    static func crossThickness(iconSize: CGFloat) -> CGFloat {
        iconSize + maxBump + dotGap + dotSize + 2 * pad
    }

    static func contentSize(count: Int, iconSize: CGFloat, horizontal: Bool) -> CGSize {
        let m = mainLength(count: count, iconSize: iconSize)
        let c = crossThickness(iconSize: iconSize)
        return horizontal ? CGSize(width: m, height: c) : CGSize(width: c, height: m)
    }

    /// Rest center of icon `index` along the main axis, from the content's
    /// leading edge (the row is centered within the reserved length).
    static func center(_ index: Int, count: Int, iconSize: CGFloat) -> CGFloat {
        let leading = (mainLength(count: count, iconSize: iconSize)
                       - restExtent(count: count, iconSize: iconSize)) / 2
        return leading + CGFloat(index) * (iconSize + spacing) + iconSize / 2
    }

    static func index(at pos: CGFloat, count: Int, iconSize: CGFloat) -> Int? {
        guard count > 0 else { return nil }
        let leading = (mainLength(count: count, iconSize: iconSize)
                       - restExtent(count: count, iconSize: iconSize)) / 2
        let local = pos - leading
        guard local >= 0 else { return nil }
        let i = Int(local / (iconSize + spacing))
        return (i >= 0 && i < count) ? i : nil
    }
}

struct DockBar: View {
    @ObservedObject var model: BarModel
    let onSelect: (WindowInfo) -> Void
    let onRightClick: (CGWindowID, NSView) -> Void
    let onHoverIndex: (Int?) -> Void

    private let sigma: CGFloat = 50
    @State private var hover: CGFloat?

    private var iconSize: CGFloat { model.iconSize }
    private var count: Int { model.items.count }
    private var horizontal: Bool { model.edge.isHorizontal }

    var body: some View {
        let size = DockMetrics.contentSize(count: count, iconSize: iconSize, horizontal: horizontal)
        let layout: AnyLayout = horizontal
            ? AnyLayout(HStackLayout(spacing: DockMetrics.spacing))
            : AnyLayout(VStackLayout(spacing: DockMetrics.spacing))

        layout {
            ForEach(Array(model.items.enumerated()), id: \.offset) { index, item in
                cell(index: index, item: item)
            }
        }
        .frame(width: size.width, height: size.height)   // fixed; row is centered, icons push within
        .coordinateSpace(name: "dock")
        .onContinuousHover(coordinateSpace: .named("dock")) { phase in
            switch phase {
            case .active(let p):
                let m = horizontal ? p.x : p.y
                hover = m
                onHoverIndex(DockMetrics.index(at: m, count: count, iconSize: iconSize))
            case .ended:
                hover = nil
                onHoverIndex(nil)
            }
        }
    }

    // MARK: - Cell

    @ViewBuilder
    private func cell(index: Int, item: DisplayWindow) -> some View {
        let s = iconSize + bump(index)
        let inset = DockMetrics.dotSize + DockMetrics.dotGap
        let cross = DockMetrics.crossThickness(iconSize: iconSize) - 2 * DockMetrics.pad
        ZStack(alignment: dotAlignment) {
            icon(item, size: s)
                .padding(edgeSet, inset)            // leave room for the dot at the edge
            if item.window.isActive {
                Circle().fill(Color.primary.opacity(0.85))
                    .frame(width: DockMetrics.dotSize, height: DockMetrics.dotSize)
                    .padding(edgeSet, 1)
            }
        }
        .frame(width: horizontal ? nil : cross, height: horizontal ? cross : nil)
        .opacity(item.window.isMinimized ? 0.45 : 1.0)
        .contentShape(Rectangle())
        .onTapGesture { onSelect(item.window) }
        .overlay(RightClickCatcher { view in onRightClick(item.window.id, view) })
    }

    @ViewBuilder
    private func icon(_ item: DisplayWindow, size: CGFloat) -> some View {
        let radius = size * 0.225
        Group {
            if let image = model.image(for: item) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Color.gray.opacity(0.3)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .animation(.easeOut(duration: 0.12), value: hover)
    }

    // MARK: - Magnification

    private func bump(_ index: Int) -> CGFloat {
        guard let hover else { return 0 }
        let d = hover - DockMetrics.center(index, count: count, iconSize: iconSize)
        return DockMetrics.maxBump * exp(-(d * d) / (2 * sigma * sigma))
    }

    // MARK: - Per-edge placement of the active dot (on the edge side, with a gap)

    private var dotAlignment: Alignment {
        switch model.edge {
        case .bottom: return .bottom
        case .top: return .top
        case .left: return .leading
        case .right: return .trailing
        }
    }

    private var edgeSet: Edge.Set {
        switch model.edge {
        case .bottom: return .bottom
        case .top: return .top
        case .left: return .leading
        case .right: return .trailing
        }
    }
}

/// The floating hover-name bubble shown next to the hovered icon (its own panel,
/// so it is never clipped by the dock window).
struct DockLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(.thinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.18)))
            .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
    }
}
