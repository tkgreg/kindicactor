import AppKit
import KIndicatorCore
import SwiftUI

/// The Knob page: Knob Control on or off, its layers, and what turning and pressing the knob
/// does in all apps and in single apps.
struct KnobSettings: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var knob: KnobController
    @ObservedObject var monitor: KeyboardMonitor

    private var layerCount: Int {
        max(monitor.layerCount ?? AppSettings.defaultLayerNames.count, 1)
    }

    var body: some View {
        SettingsGroup(title: "Knob Control") {
            SettingsRow(title: "Control the Knob with KIndicator",
                        description: "Turn and press the knob for media keys or any shortcut, with different actions per app. Keychron Launcher can't put macros on the knob, so KIndicator sets it to send F18, F19 and F20 and turns those into your actions.") {
                Toggle("Control the Knob with KIndicator", isOn: enabledBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            SettingsRow(title: "On Layers",
                        description: "Where the knob sends F18-F20. On the other layers it keeps its own keys, e.g. lighting with Fn.") {
                HStack(spacing: 14) {
                    ForEach(0..<layerCount, id: \.self) { layer in
                        Toggle(settings.name(for: layer), isOn: layerBinding(layer))
                            .toggleStyle(.checkbox)
                    }
                }
                .disabled(!settings.knobControl.enabled)
            }
            if settings.knobControl.enabled && !knob.canPressKeys {
                SettingsRow(title: "Allow KIndicator to Press Keys",
                            description: "macOS lets KIndicator press media keys and shortcuts only with Accessibility permission: turn KIndicator on in Privacy & Security › Accessibility.") {
                    Button("Open System Settings…") { KeyPresser.openAccessibilitySettings() }
                }
            }
            SettingsNote(text: status)
        }
        SettingsGroup(title: "Actions") {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 12) {
                GridRow {
                    ForEach(["App", "Turn Left", "Turn Right", "Press"], id: \.self) { heading in
                        Text(heading)
                    }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                GridRow {
                    Label("All Apps", systemImage: "square.grid.2x2")
                        .frame(width: 120, alignment: .leading)
                    ForEach(KnobInput.allCases, id: \.self) { input in
                        KnobActionMenu(action: actionBinding($settings.knobControl.allApps, input), inherited: nil)
                    }
                    presetMenu($settings.knobControl.allApps, forApp: false)
                }
                ForEach($settings.knobControl.apps) { $app in
                    GridRow {
                        Label {
                            Text(app.name).lineLimit(1)
                        } icon: {
                            Image(nsImage: Self.icon(app))
                        }
                        .frame(width: 120, alignment: .leading)
                        .help(app.bundleID)
                        ForEach(KnobInput.allCases, id: \.self) { input in
                            KnobActionMenu(action: actionBinding($app.mapping, input),
                                           inherited: settings.knobControl.allApps[input] ?? .nothing)
                        }
                        presetMenu($app.mapping, forApp: true)
                        Button {
                            settings.knobControl.apps.removeAll { $0.id == app.id }
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
            SettingsNote(text: "Precise Volume changes the volume in quarter steps, as the volume keys do with ⌥⇧ held. An app's dimmed actions are the ones for all apps. Shortcuts are pressed in the frontmost app.")
        }
        .disabled(!settings.knobControl.enabled)
        // Turned on in System Settings meanwhile.
        .task(id: settings.knobControl.enabled) {
            while settings.knobControl.enabled && !knob.canPressKeys && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                knob.refreshPermission()
            }
        }
    }

    /// Where the knob stands, or why it can't be changed now.
    private var status: String {
        let enabled = settings.knobControl.enabled
        let layers = settings.knobControl.layers.filter { $0 < layerCount }.sorted().map(settings.name(for:))
        switch knob.state {
        case .off:
            return "The knob sends its own keys, as set in Keychron Launcher."
        case .on where layers.isEmpty:
            return "Pick the layers where KIndicator controls the knob."
        case .on:
            return "The knob sends F18, F19 and F20 on \(ListFormatter.localizedString(byJoining: layers)), saved on the keyboard. While KIndicator isn't running the knob does nothing there; turn Knob Control off to give it its own keys back."
        case .waiting:
            let what = enabled ? "The knob changes" : "The knob gets its own keys back"
            return "\(what) once KIndicator can reach the keyboard. \(monitor.status.lightingUnavailable)."
        case .unsupported:
            return "KIndicator knows where the knob is on the Keychron V6 Ultra 8K only."
        case .failed:
            return "The keyboard didn't answer. KIndicator tries again when it reconnects."
        }
    }

    /// Fills all three actions; an app's can go back to the ones for all apps.
    private func presetMenu(_ mapping: Binding<KnobMapping>, forApp: Bool) -> some View {
        Menu {
            ForEach(KnobPreset.all) { preset in
                Button(preset.name) { mapping.wrappedValue = preset.mapping }
            }
            if forApp {
                Divider()
                Button("Same as All Apps") { mapping.wrappedValue = KnobMapping() }
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
        let added = Set(settings.knobControl.apps.map(\.bundleID))
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
        guard !settings.knobControl.apps.contains(where: { $0.bundleID == bundleID }) else { return }
        let name = (FileManager.default.displayName(atPath: url.path) as NSString).deletingPathExtension
        settings.knobControl.apps.append(KnobAppMapping(bundleID: bundleID, name: name, path: url.path))
    }

    // MARK: - Bindings

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { settings.knobControl.enabled },
            set: { enabled in
                settings.knobControl.enabled = enabled
                if enabled { knob.requestPermission() }
            }
        )
    }

    private func layerBinding(_ layer: Int) -> Binding<Bool> {
        Binding(
            get: { settings.knobControl.layers.contains(layer) },
            set: { isOn in
                if isOn {
                    settings.knobControl.layers.insert(layer)
                } else {
                    settings.knobControl.layers.remove(layer)
                }
            }
        )
    }

    private func actionBinding(_ mapping: Binding<KnobMapping>, _ input: KnobInput) -> Binding<KnobAction?> {
        Binding(get: { mapping.wrappedValue[input] }, set: { mapping.wrappedValue[input] = $0 })
    }

    private static func icon(_ app: KnobAppMapping) -> NSImage {
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

/// What one of the knob's inputs does: a media key, a recorded shortcut or nothing. An app's
/// can be left to the action for all apps, which then shows dimmed.
struct KnobActionMenu: View {
    @Binding var action: KnobAction?
    /// The action for all apps, in an app's menu; nil in the all-apps one.
    let inherited: KnobAction?
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
