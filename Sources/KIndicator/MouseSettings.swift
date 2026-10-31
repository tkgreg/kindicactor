import KIndicatorCore
import SwiftUI

/// The Mouse page: mouse buttons on or off, how long a click waits for a second one, and what
/// clicking and double-clicking each button does in all apps and in single apps.
struct MouseSettings: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var mouse: MouseController
    @State private var keyCapture = ShortcutCapture()

    var body: some View {
        let enabled = settings.mouseControl.enabled
        SettingsGroup(title: "Mouse") {
            SettingsRow(title: "Control Mouse Buttons with KIndicator",
                        description: "Give the middle, Back and Forward buttons a media key or any shortcut for a click and for a double-click, with different actions per app. A button with a double-click action waits a moment after a click to see whether a second one follows.") {
                Toggle("Control Mouse Buttons with KIndicator", isOn: enabledBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            SettingsRow(title: "Double-Click Speed",
                        description: "How long a click waits for the second one. Shorter makes single clicks quicker; longer leaves more time to double-click.") {
                HStack(spacing: 10) {
                    Slider(value: $settings.mouseControl.doubleClickInterval, in: MouseControl.intervals, step: 0.05)
                        .frame(width: 180)
                    Text(String(format: "%.2f s", settings.mouseControl.doubleClickInterval))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 50, alignment: .trailing)
                }
                .disabled(!enabled)
            }
            SettingsRow(title: "Mouse Keys",
                        description: "Some mice send a key for a button of their own, e.g. F13. Click Add Key, then press that button: it gets actions like the others below. KIndicator takes the key over while this is on.") {
                mouseKeys
                    .disabled(!enabled)
            }
            if enabled && !(mouse.isWatching && KeyPresser.isAllowed) {
                SettingsRow(title: "Allow KIndicator to Watch the Mouse",
                            description: "macOS lets KIndicator see the mouse's buttons and press keys only with Accessibility permission: turn KIndicator on in Privacy & Security › Accessibility.") {
                    Button("Open System Settings…") { KeyPresser.openAccessibilitySettings() }
                }
            }
            SettingsNote(text: status)
        }
        SettingsGroup(title: "Actions") {
            AppActionsGrid(columns: [("Click", "Click as Usual"), ("Double-Click", "Nothing")],
                           rows: settings.mouseControl.allButtons.map { ($0.title, [.click($0), .doubleClick($0)]) },
                           rowsTitle: "Button",
                           allApps: $settings.mouseControl.allApps, apps: $settings.mouseControl.apps,
                           presets: [("Back and Forward as ⌘[ and ⌘]", .navigation)])
            SettingsNote(text: "Safari ignores the Back and Forward buttons: set their clicks to Back and Forward (⌘[ and ⌘]) to use them there. Only a button with a double-click action waits for a second click. An app's dimmed actions are the ones for all apps. Shortcuts are pressed in the frontmost app.")
        }
        .disabled(!enabled)
        // Turned on in System Settings meanwhile.
        .task(id: enabled) {
            while settings.mouseControl.enabled && !mouse.isWatching && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                mouse.refresh()
            }
        }
    }

    /// The keys added, each with a remove button, and Add Key.
    private var mouseKeys: some View {
        HStack(spacing: 6) {
            ForEach(settings.mouseControl.keys, id: \.self) { key in
                HStack(spacing: 4) {
                    Text(key.display)
                    Button {
                        settings.mouseControl.removeKey(key)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Remove \(key.display) and its actions")
                }
                .padding(.leading, 8)
                .padding(.trailing, 4)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.primary.opacity(0.08)))
            }
            Button(keyCapture.isActive ? "Press the Button…" : "Add Key…") {
                keyCapture.isActive ? keyCapture.stop() : addKey()
            }
        }
    }

    /// F-keys, or keys with modifiers: a plain letter would take over typing.
    private func addKey() {
        keyCapture.start { key in
            guard let key, !settings.mouseControl.keys.contains(key) else { return }
            settings.mouseControl.keys.append(key)
        }
    }

    private var status: String {
        guard settings.mouseControl.enabled else { return "The mouse's buttons click as usual." }
        guard mouse.isWatching else { return "Waiting for Accessibility permission." }
        let keys = settings.mouseControl.keys.map(\.display)
        let also = keys.isEmpty ? "" : ", and the keys \(ListFormatter.localizedString(byJoining: keys))"
        return "Watching the middle, Back and Forward buttons of every mouse connected\(also). If another mouse app also has actions for these buttons, turn those off there, so the two don't both act."
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { settings.mouseControl.enabled },
            set: { enabled in
                settings.mouseControl.enabled = enabled
                if enabled && !KeyPresser.isAllowed { KeyPresser.requestPermission() }
            }
        )
    }
}
