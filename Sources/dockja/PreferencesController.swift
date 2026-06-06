import AppKit
import SwiftUI
import UniformTypeIdentifiers
import DockjaCore

@MainActor
final class PreferencesController {
    static let shared = PreferencesController()
    private var window: NSWindow?
    /// Called when a setting that affects the live dock changes.
    var onChange: () -> Void = {}

    /// True while the Preferences window is on screen (blocks dock auto-hide).
    var isOpen: Bool { window?.isVisible ?? false }

    func show(settings: SettingsStore) {
        if window == nil {
            let view = PreferencesView(settings: settings, onChange: onChange)
            let hosting = NSHostingController(rootView: view)
            let win = NSWindow(contentViewController: hosting)
            win.title = "dockja Preferences"
            win.styleMask = [.titled, .closable]
            win.setContentSize(NSSize(width: 420, height: 600))
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
    @State private var autoHide = false
    @State private var autoHideDelay: Double = 3
    @State private var groups: [AppGroup] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                appsSection
                Divider()
                iconSizeSection
                Toggle("Masquer automatiquement", isOn: $autoHide)
                    .onChange(of: autoHide) { _, newValue in
                        settings.update { $0.autoHide = newValue }
                        onChange()
                    }
                if autoHide {
                    HStack {
                        Text("Délai avant masquage")
                        Slider(value: $autoHideDelay, in: 1...10, step: 0.5)
                            .onChange(of: autoHideDelay) { _, v in
                                settings.update { $0.autoHideDelay = v }
                                onChange()
                            }
                        Text(String(format: "%.1f s", autoHideDelay))
                            .monospacedDigit()
                            .frame(width: 50, alignment: .trailing)
                    }
                }
                Divider()
                groupsSection
            }
            .padding()
        }
        .onAppear(perform: load)
    }

    // MARK: - Sections

    private var appsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Apps activées").font(.headline)
            ForEach(apps) { app in
                Toggle(isOn: binding(for: app.id)) {
                    HStack {
                        if let icon = app.icon {
                            Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                        }
                        Text(app.name)
                    }
                }
            }
            Button("Ajouter une app…") { addApp() }
        }
    }

    private var iconSizeSection: some View {
        VStack(alignment: .leading, spacing: 4) {
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
    }

    private var groupsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Groupes").font(.headline)
                Spacer()
                Button("Nouveau groupe") { addGroup() }
            }
            if groups.isEmpty {
                Text("Aucun groupe. Les apps non groupées ont leur propre dock.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach($groups) { $group in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        TextField("Nom du groupe", text: $group.name)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: group.name) { _, _ in saveGroups() }
                        Button(role: .destructive) { deleteGroup(group.id) } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                    ForEach(group.bundleIDs, id: \.self) { bid in
                        HStack {
                            Text(appName(bid)).font(.caption)
                            Spacer()
                            Button { removeMember(bid, from: group.id) } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    let addable = addableApps(for: group)
                    if !addable.isEmpty {
                        Menu("Ajouter une app au groupe") {
                            ForEach(addable) { row in
                                Button(row.name) { addMember(row.id, to: group.id) }
                            }
                        }
                        .frame(maxWidth: 220)
                    }
                }
                .padding(8)
                .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: - Data

    private func load() {
        enabled = settings.enabledSet
        iconSize = settings.settings.dockIconSize
        autoHide = settings.settings.autoHide
        autoHideDelay = settings.settings.autoHideDelay
        groups = settings.settings.groups
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
                onChange()
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

    // MARK: - Groups

    private func appName(_ bid: String) -> String { apps.first { $0.id == bid }?.name ?? bid }

    private func addableApps(for group: AppGroup) -> [AppRow] {
        apps.filter { enabled.contains($0.id) && !group.bundleIDs.contains($0.id) }
    }

    private func saveGroups() {
        settings.update { $0.groups = groups }
        onChange()
    }

    private func addGroup() {
        groups.append(AppGroup(id: UUID().uuidString, name: "Groupe", bundleIDs: []))
        saveGroups()
    }

    private func deleteGroup(_ id: String) {
        groups.removeAll { $0.id == id }
        saveGroups()
    }

    private func addMember(_ bid: String, to gid: String) {
        for i in groups.indices { groups[i].bundleIDs.removeAll { $0 == bid } }   // one group per app
        if let i = groups.firstIndex(where: { $0.id == gid }) { groups[i].bundleIDs.append(bid) }
        saveGroups()
    }

    private func removeMember(_ bid: String, from gid: String) {
        if let i = groups.firstIndex(where: { $0.id == gid }) {
            groups[i].bundleIDs.removeAll { $0 == bid }
        }
        saveGroups()
    }
}
