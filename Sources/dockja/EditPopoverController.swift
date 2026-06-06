import AppKit
import SwiftUI
import CoreGraphics
import DockjaCore

@MainActor
final class EditPopoverController {
    private var popover: NSPopover?

    var isShown: Bool { popover?.isShown ?? false }

    // Wired by AppCoordinator.
    var currentName: (CGWindowID) -> String = { _ in "" }
    var recents: () -> [String] = { [] }
    var onSetName: (CGWindowID, String) -> Void = { _, _ in }
    var onPickIcon: (CGWindowID, String) -> Void = { _, _ in }
    var onBrowse: (CGWindowID) -> Void = { _ in }
    var onReset: (CGWindowID) -> Void = { _ in }

    func show(for id: CGWindowID, relativeTo view: NSView, edge: DockEdge) {
        popover?.close()
        // The bar is non-activating; activate so the name field can take focus.
        NSApp.activate(ignoringOtherApps: true)

        let edit = EditView(
            name: currentName(id),
            recents: recents(),
            onName: { [weak self] in self?.onSetName(id, $0) },
            onPick: { [weak self] in self?.onPickIcon(id, $0); self?.popover?.close() },
            onBrowse: { [weak self] in self?.onBrowse(id); self?.popover?.close() },
            onReset: { [weak self] in self?.onReset(id); self?.popover?.close() }
        )
        let pop = NSPopover()
        pop.behavior = .transient
        pop.contentSize = NSSize(width: 300, height: 240)
        pop.contentViewController = NSHostingController(rootView: edit)

        // Anchor to the stable dock backdrop (not the icon view, which moves with
        // magnification/relayout) using a frozen snapshot of the icon's rect, and
        // open toward the screen interior so it never covers the dock.
        let anchor = view.window?.contentView ?? view
        let rect = view.convert(view.bounds, to: anchor)
        pop.show(relativeTo: rect, of: anchor, preferredEdge: interiorEdge(for: edge))
        popover = pop
    }

    /// The side facing the screen interior (so the popover doesn't cover the dock).
    private func interiorEdge(for edge: DockEdge) -> NSRectEdge {
        switch edge {
        case .bottom: return .maxY   // dock at bottom -> open upward
        case .top:    return .minY
        case .left:   return .maxX   // dock at left -> open to the right
        case .right:  return .minX
        }
    }
}

private struct EditView: View {
    @State private var name: String
    let recents: [String]
    let onName: (String) -> Void
    let onPick: (String) -> Void
    let onBrowse: () -> Void
    let onReset: () -> Void

    init(name: String, recents: [String],
         onName: @escaping (String) -> Void,
         onPick: @escaping (String) -> Void,
         onBrowse: @escaping () -> Void,
         onReset: @escaping () -> Void) {
        _name = State(initialValue: name)
        self.recents = recents
        self.onName = onName
        self.onPick = onPick
        self.onBrowse = onBrowse
        self.onReset = onReset
    }

    private let cols = [GridItem(.adaptive(minimum: 40), spacing: 6)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Éditer la fenêtre").font(.headline)

            HStack {
                Text("Nom")
                TextField("Nom", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: name) { _, newValue in onName(newValue) }
            }

            Text("Icônes récentes").font(.subheadline).foregroundStyle(.secondary)
            if recents.isEmpty {
                Text("Aucune — utilisez Parcourir…").font(.caption).foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: cols, spacing: 6) {
                    ForEach(recents, id: \.self) { path in
                        if let img = NSImage(contentsOfFile: path) {
                            Image(nsImage: img).resizable().frame(width: 36, height: 36)
                                .cornerRadius(6)
                                .onTapGesture { onPick(path) }
                        }
                    }
                }
            }

            HStack {
                Button("Parcourir…") { onBrowse() }
                Spacer()
                Button("Réinitialiser", role: .destructive) { onReset() }
            }
        }
        .padding()
        .frame(width: 300)
    }
}
