import SwiftUI
import AppKit
import CoreGraphics
import DockjaCore

/// Layout metrics shared between the dock view and the panel controller (the
/// controller needs them to place the floating hover-name label).
enum DockMetrics {
    static let baseSize: CGFloat = 48
    static let maxBump: CGFloat = 24
    static let spacing: CGFloat = 10
    static let pad: CGFloat = 12
    static var cellExtent: CGFloat { baseSize + maxBump }

    /// Center of cell `index` along the main axis, measured from the dock's
    /// leading content edge (includes the outer pad).
    static func center(_ index: Int) -> CGFloat {
        pad + CGFloat(index) * (cellExtent + spacing) + cellExtent / 2
    }
}

struct DockBar: View {
    @ObservedObject var model: BarModel
    let onSelect: (WindowInfo) -> Void
    let onRightClick: (CGWindowID, NSView) -> Void
    let onHoverIndex: (Int?) -> Void

    private let sigma: CGFloat = 55

    @State private var hover: CGFloat?

    private var count: Int { model.items.count }

    var body: some View {
        let horizontal = model.edge.isHorizontal
        let layout: AnyLayout = horizontal
            ? AnyLayout(HStackLayout(spacing: DockMetrics.spacing))
            : AnyLayout(VStackLayout(spacing: DockMetrics.spacing))

        layout {
            ForEach(Array(model.items.enumerated()), id: \.offset) { index, item in
                cell(index: index, item: item)
            }
        }
        .padding(DockMetrics.pad)
        .background(dockBackground)
        .fixedSize()
        .coordinateSpace(name: "dock")
        .onContinuousHover(coordinateSpace: .named("dock")) { phase in
            switch phase {
            case .active(let p):
                hover = horizontal ? p.x : p.y
                onHoverIndex(hoveredIndex())
            case .ended:
                hover = nil
                onHoverIndex(nil)
            }
        }
    }

    // MARK: - Cells

    @ViewBuilder
    private func cell(index: Int, item: DisplayWindow) -> some View {
        let size = DockMetrics.baseSize + bump(forCellAt: index)
        ZStack(alignment: dotAlignment) {
            icon(for: item, size: size)
            if item.window.isActive {
                Circle().fill(Color.primary.opacity(0.85))
                    .frame(width: 6, height: 6)
                    .padding(2)
            }
        }
        .frame(width: DockMetrics.cellExtent, height: DockMetrics.cellExtent)
        .opacity(item.window.isMinimized ? 0.45 : 1.0)
        .contentShape(Rectangle())
        .onTapGesture { onSelect(item.window) }
        .overlay(RightClickCatcher { view in onRightClick(item.window.id, view) })
    }

    @ViewBuilder
    private func icon(for item: DisplayWindow, size: CGFloat) -> some View {
        let radius = size * 0.225   // macOS squircle-ish corner
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

    // MARK: - Glass background

    private var dockBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
    }

    // MARK: - Magnification + hover index

    private func bump(forCellAt index: Int) -> CGFloat {
        guard let hover else { return 0 }
        let d = hover - DockMetrics.center(index)
        return DockMetrics.maxBump * exp(-(d * d) / (2 * sigma * sigma))
    }

    private func hoveredIndex() -> Int? {
        guard let hover, count > 0 else { return nil }
        let local = hover - DockMetrics.pad
        guard local >= 0 else { return nil }
        let idx = Int(local / (DockMetrics.cellExtent + DockMetrics.spacing))
        return (idx >= 0 && idx < count) ? idx : nil
    }

    private var dotAlignment: Alignment {
        switch model.edge {
        case .bottom: return .top
        case .top: return .bottom
        case .left: return .trailing
        case .right: return .leading
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
