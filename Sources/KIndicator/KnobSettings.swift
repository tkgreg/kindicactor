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
            AppActionsGrid(columns: [("Turn Left", "Nothing"), ("Turn Right", "Nothing"), ("Press", "Nothing")],
                           rows: [(nil, [.turnLeft, .turnRight, .press])],
                           allApps: $settings.knobControl.allApps, apps: $settings.knobControl.apps,
                           presets: KnobPreset.all.map { ($0.name, $0.mapping) })
            SettingsNote(text: "Precise Volume changes the volume in quarter steps, as the volume keys do with ⌥⇧ held, and speeds up while you spin the knob: from one quarter step (about 1.6%) a click when turned slowly up to five (about 8%). An app's dimmed actions are the ones for all apps. Shortcuts are pressed in the frontmost app.")
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
}
