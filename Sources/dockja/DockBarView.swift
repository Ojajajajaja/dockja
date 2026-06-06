import SwiftUI
import AppKit
import CoreGraphics
import DockjaCore

struct DockBar: View {
    @ObservedObject var model: BarModel
    let onSelect: (WindowInfo) -> Void
    let onRightClick: (CGWindowID, NSView) -> Void

    private let baseSize: CGFloat = 48
    private let spacing: CGFloat = 10
    private let pad: CGFloat = 10
    private let maxBump: CGFloat = 22      // extra pixels at the cursor
    private let sigma: CGFloat = 60        // magnification falloff

    /// Pointer position along the main axis within the strip; nil when not hovering.
    @State private var hover: CGFloat?

    var body: some View {
        let horizontal = model.edge.isHorizontal
        let layout: AnyLayout = horizontal
            ? AnyLayout(HStackLayout(spacing: spacing))
            : AnyLayout(VStackLayout(spacing: spacing))
        layout {
            ForEach(Array(model.items.enumerated()), id: \.offset) { index, item in
                cell(index: index, item: item)
            }
        }
        .padding(pad)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .fixedSize()
        .coordinateSpace(name: "dock")
        .onContinuousHover(coordinateSpace: .named("dock")) { phase in
            switch phase {
            case .active(let p): hover = horizontal ? p.x : p.y
            case .ended: hover = nil
            }
        }
    }

    /// Each cell reserves a fixed square slot (baseSize + maxBump) so magnified
    /// icons never overflow/clip the fixed-size panel; the icon scales inside it.
    private var cellExtent: CGFloat { baseSize + maxBump }

    @ViewBuilder
    private func cell(index: Int, item: DisplayWindow) -> some View {
        let size = baseSize + bump(forCellAt: index)
        ZStack(alignment: dotAlignment) {
            if let icon = model.image(for: item) {
                Image(nsImage: icon).resizable()
                    .frame(width: size, height: size)
            } else {
                RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.3))
                    .frame(width: size, height: size)
            }
            if item.window.isActive {
                Circle().fill(Color.primary).frame(width: 6, height: 6).padding(1)
            }
        }
        .frame(width: cellExtent, height: cellExtent)
        .opacity(item.window.isMinimized ? 0.5 : 1.0)
        .help(item.name)                                   // hover tooltip
        .animation(.easeOut(duration: 0.12), value: hover)
        .onTapGesture { onSelect(item.window) }
        .background(RightClickCatcher { view in onRightClick(item.window.id, view) })
    }

    /// Magnification bump for the cell at `index` based on cursor distance, using
    /// the fixed slot extent for analytic cell centers.
    private func bump(forCellAt index: Int) -> CGFloat {
        guard let hover else { return 0 }
        let center = pad + CGFloat(index) * (cellExtent + spacing) + cellExtent / 2
        let d = hover - center
        return maxBump * exp(-(d * d) / (2 * sigma * sigma))
    }

    /// Active-window dot placed toward the screen interior.
    private var dotAlignment: Alignment {
        switch model.edge {
        case .bottom: return .top
        case .top: return .bottom
        case .left: return .trailing
        case .right: return .leading
        }
    }
}
