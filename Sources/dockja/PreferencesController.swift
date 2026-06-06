import AppKit
import SwiftUI
import UniformTypeIdentifiers
import DockjaCore

@MainActor
final class PreferencesController {
    static let shared = PreferencesController()
    private var window: NSWindow?
    /// Called when a setting that affects the live dock changes (e.g. icon size).
    var onChange: () -> Void = {}

    func show(settings: SettingsStore) {
        if window == nil {
            let view = PreferencesView(settings: settings, onChange: onChange)
            let hosting = NSHostingController(rootView: view)
            let win = NSWindow(contentViewController: hosting)
            win.title = "dockja Preferences"
            win.styleMask = [.titled, .closable]
            win.setContentSize(NSSize(width: 360, height: 440))
            window = win
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct AppRow: Identifiable {
    let id: String      // bundleID
    let name: String
    let icon: NSImage?
}

private struct PreferencesView: View {
    let settings: SettingsStore
    let onChange: () -> Void
    @State private var enabled: Set<String> = []
    @State private var apps: [AppRow] = []
    @State private var iconSize: CGFloat = 48

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Enabled apps").font(.headline)
            List(apps) { app in
                Toggle(isOn: binding(for: app.id)) {
                    HStack {
                        if let icon = app.icon {
                            Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                        }
                        Text(app.name)
                    }
                }
            }
            Button("Add app…") { addApp() }

            Divider()
            Text("Taille des icônes").font(.headline)
            HStack {
                Slider(value: $iconSize, in: 32...96, step: 1)
                    .onChange(of: iconSize) { _, newValue in
                        settings.update { $0.dockIconSize = newValue }
                        onChange()
                    }
                Text("\(Int(iconSize)) px")
                    .monospacedDigit()
                    .frame(width: 50, alignment: .trailing)
            }
        }
        .padding()
        .onAppear(perform: load)
    }

    private func load() {
        enabled = settings.enabledSet
        iconSize = settings.settings.dockIconSize
        var rows: [String: AppRow] = [:]
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            if let id = app.bundleIdentifier {
                rows[id] = AppRow(id: id, name: app.localizedName ?? id, icon: app.icon)
            }
        }
        for id in enabled where rows[id] == nil {
            rows[id] = AppRow(id: id, name: id, icon: nil)
        }
        apps = rows.values.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { enabled.contains(id) },
            set: { isOn in
                if isOn { enabled.insert(id) } else { enabled.remove(id) }
                settings.update { $0.enabledBundleIDs = Array(enabled) }
            }
        )
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return }
        let name = (bundle.infoDictionary?["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        enabled.insert(id)
        settings.update { $0.enabledBundleIDs = Array(enabled) }
        if !apps.contains(where: { $0.id == id }) {
            apps.append(AppRow(id: id, name: name,
                               icon: NSWorkspace.shared.icon(forFile: url.path)))
            apps.sort { $0.name.lowercased() < $1.name.lowercased() }
        }
    }
}
