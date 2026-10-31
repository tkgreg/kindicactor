import AppKit
import KIndicatorCore
import SwiftUI

/// A device's actions per app: a row for all apps, then one per app added, with a menu per
/// input. An app's inputs left to the all-apps action show it dimmed.
struct AppActionsGrid<Mapping: ActionMapping>: View {
    /// The columns: each input and its heading.
    let inputs: [(input: Mapping.Input, title: String)]
    @Binding var allApps: Mapping
    @Binding var apps: [AppActions<Mapping>]
    /// Whole mappings to fill a row with; none hides the presets menu.
    var presets: [(name: String, mapping: Mapping)] = []

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 12) {
            GridRow {
                Text("App")
                ForEach(inputs.indices, id: \.self) { index in
                    Text(inputs[index].title)
                }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            GridRow {
                Label("All Apps", systemImage: "square.grid.2x2")
                    .frame(width: 120, alignment: .leading)
                ForEach(inputs.indices, id: \.self) { index in
                    KeyActionMenu(action: actionBinding($allApps, inputs[index].input), inherited: nil)
                }
                if !presets.isEmpty {
                    presetMenu($allApps, forApp: false)
                }
            }
            ForEach($apps) { $app in
                GridRow {
                    Label {
                        Text(app.name).lineLimit(1)
                    } icon: {
                        Image(nsImage: Self.icon(app))
                    }
                    .frame(width: 120, alignment: .leading)
                    .help(app.bundleID)
                    ForEach(inputs.indices, id: \.self) { index in
                        KeyActionMenu(action: actionBinding($app.mapping, inputs[index].input),
                                      inherited: allApps[inputs[index].input] ?? .nothing)
                    }
                    if !presets.isEmpty {
                        presetMenu($app.mapping, forApp: true)
                    }
                    Button {
                        apps.removeAll { $0.id == app.id }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Remove")
                }
            }
        }
        addAppMenu
    }

    /// Fills all of a row's actions; an app's can go back to the ones for all apps.
    private func presetMenu(_ mapping: Binding<Mapping>, forApp: Bool) -> some View {
        Menu {
            ForEach(presets.indices, id: \.self) { index in
                Button(presets[index].name) { mapping.wrappedValue = presets[index].mapping }
            }
            if forApp {
                Divider()
                Button("Same as All Apps") { mapping.wrappedValue = Mapping() }
            }
        } label: {
            Image(systemName: "wand.and.stars")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Presets")
    }

    private var addAppMenu: some View {
        let added = Set(apps.map(\.bundleID))
        let running = NSWorkspace.shared.runningApplications
            .filter { app in
                app.activationPolicy == .regular && app.bundleURL != nil
                    && app.bundleIdentifier.map { !added.contains($0) && $0 != Bundle.main.bundleIdentifier } == true
            }
            .sorted { ($0.localizedName ?? "").localizedStandardCompare($1.localizedName ?? "") == .orderedAscending }
        return Menu("Add App") {
            ForEach(running, id: \.processIdentifier) { app in
                Button {
                    add(app.bundleURL!)
                } label: {
                    Label {
                        Text(app.localizedName ?? app.bundleIdentifier ?? "")
                    } icon: {
                        Image(nsImage: Self.small(app.icon ?? NSWorkspace.shared.icon(forFile: app.bundleURL!.path)))
                    }
                }
            }
            if !running.isEmpty { Divider() }
            Button("Choose App…", action: chooseApp)
        }
        .fixedSize()
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add"
        if panel.runModal() == .OK, let url = panel.url {
            add(url)
        }
    }

    private func add(_ url: URL) {
        guard let bundleID = Bundle(url: url)?.bundleIdentifier else { return NSSound.beep() }
        guard !apps.contains(where: { $0.bundleID == bundleID }) else { return }
        let name = (FileManager.default.displayName(atPath: url.path) as NSString).deletingPathExtension
        apps.append(AppActions(bundleID: bundleID, name: name, path: url.path))
    }

    private func actionBinding(_ mapping: Binding<Mapping>, _ input: Mapping.Input) -> Binding<KeyAction?> {
        Binding(get: { mapping.wrappedValue[input] }, set: { mapping.wrappedValue[input] = $0 })
    }

    private static func icon(_ app: AppActions<Mapping>) -> NSImage {
        let path = app.path.flatMap { FileManager.default.fileExists(atPath: $0) ? $0 : nil }
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID)?.path
        return small(path.map(NSWorkspace.shared.icon(forFile:)) ?? NSWorkspace.shared.icon(for: .application))
    }

    private static func small(_ icon: NSImage) -> NSImage {
        let copy = icon.copy() as! NSImage
        copy.size = NSSize(width: 16, height: 16)
        return copy
    }
}

/// What one input does: a media key, a recorded shortcut or nothing. An app's can be left
/// to the action for all apps, which then shows dimmed.
struct KeyActionMenu: View {
    @Binding var action: KeyAction?
    /// The action for all apps, in an app's menu; nil in the all-apps one.
    let inherited: KeyAction?
    @State private var capture = ShortcutCapture()

    private static let sections: [(title: String, keys: [MediaKey])] = [
        ("Volume", [.volumeDown, .volumeUp, .mute, .preciseVolumeDown, .preciseVolumeUp]),
        ("Media", [.previousTrack, .playPause, .nextTrack]),
        ("Display", [.brightnessDown, .brightnessUp]),
    ]

    var body: some View {
        Group {
            if capture.isActive {
                Button("Type shortcut…") { capture.stop() }
            } else {
                Menu {
                    if let inherited {
                        check("Same as All Apps (\(inherited.title))", action == nil) { action = nil }
                        Divider()
                    }
                    check("Nothing", action == .nothing) { action = .nothing }
                    ForEach(Self.sections, id: \.title) { section in
                        Section(section.title) {
                            ForEach(section.keys, id: \.self) { key in
                                check(key.title, action == .media(key)) { action = .media(key) }
                            }
                        }
                    }
                    Divider()
                    if case .shortcut(let hotkey) = action {
                        check(hotkey.display, true) {}
                    }
                    Button("Record Shortcut…", action: record)
                } label: {
                    Text((action ?? inherited ?? .nothing).title)
                }
                .opacity(action == nil && inherited != nil ? 0.55 : 1)
            }
        }
        .frame(width: 140)
        .onDisappear(perform: capture.stop)
    }

    private func record() {
        capture.start(allowsPlainKeys: true) { recorded in
            guard let recorded else { return }
            guard !KnobController.isKnobKey(recorded) else { return NSSound.beep() }
            action = .shortcut(recorded)
        }
    }

    private func check(_ title: String, _ isOn: Bool, _ select: @escaping () -> Void) -> some View {
        Toggle(title, isOn: Binding(get: { isOn }, set: { _ in select() }))
    }
}
