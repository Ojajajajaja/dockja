import SwiftUI
import AppKit
import DockjaCore

final class BarModel: ObservableObject {
    @Published var icon: NSImage?
    @Published var windows: [WindowInfo] = []

    func update(icon: NSImage?, windows: [WindowInfo]) {
        self.icon = icon
        self.windows = windows
    }
}

struct BarView: View {
    @ObservedObject var model: BarModel
    let onSelect: (WindowInfo) -> Void

    // Fixed chip geometry so every entry is the same size regardless of title.
    private let chipWidth: CGFloat = 150
    private let chipHeight: CGFloat = 28
    private let iconSize: CGFloat = 16

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(model.windows.enumerated()), id: \.offset) { _, win in
                Button {
                    onSelect(win)
                } label: {
                    ZStack {
                        // Name centered within the whole chip; horizontal padding
                        // keeps it clear of the icon on both sides so short names
                        // sit visually centered.
                        Text(win.displayLabel)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, iconSize + 10)
                        if let icon = model.icon {
                            HStack {
                                Image(nsImage: icon).resizable()
                                    .frame(width: iconSize, height: iconSize)
                                Spacer(minLength: 0)
                            }
                            .padding(.leading, 6)
                        }
                    }
                    .frame(width: chipWidth, height: chipHeight)
                    .background(win.isActive ? Color.accentColor.opacity(0.3)
                                             : Color.gray.opacity(0.15))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .opacity(win.isMinimized ? 0.5 : 1.0)
            }
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .fixedSize()
    }
}
