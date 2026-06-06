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

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(model.windows.enumerated()), id: \.offset) { _, win in
                Button {
                    onSelect(win)
                } label: {
                    HStack(spacing: 4) {
                        if let icon = model.icon {
                            Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                        }
                        Text(win.displayLabel)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: 140, alignment: .leading)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
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
