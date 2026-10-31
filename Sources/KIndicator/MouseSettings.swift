import KIndicatorCore
import SwiftUI

/// The Mouse page: double-clicks of Back and Forward on or off, how long a click waits for
/// the second one, and what a double-click does in all apps and in single apps.
struct MouseSettings: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var mouse: MouseController

    var body: some View {
        let enabled = settings.mouseControl.enabled
        SettingsGroup(title: "Mouse") {
            SettingsRow(title: "Double-Click Back and Forward",
                        description: "Double-click a mouse's Back or Forward button for a media key or any shortcut, with different actions per app. A single click still goes back or forward, a moment later: KIndicator waits to see whether a second click follows.") {
                Toggle("Double-Click Back and Forward", isOn: enabledBinding)
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
            if enabled && !(mouse.isWatching && KeyPresser.isAllowed) {
                SettingsRow(title: "Allow KIndicator to Watch the Mouse",
                            description: "macOS lets KIndicator see the mouse's buttons and press keys only with Accessibility permission: turn KIndicator on in Privacy & Security › Accessibility.") {
                    Button("Open System Settings…") { KeyPresser.openAccessibilitySettings() }
                }
            }
            SettingsNote(text: status)
        }
        SettingsGroup(title: "Actions") {
            AppActionsGrid(inputs: [(.back, "Double-Click Back"), (.forward, "Double-Click Forward")],
                           allApps: $settings.mouseControl.allApps, apps: $settings.mouseControl.apps)
            SettingsNote(text: "Only a button with an action waits for a second click; one left at Nothing clicks at once. An app's dimmed actions are the ones for all apps. Shortcuts are pressed in the frontmost app.")
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

    private var status: String {
        guard settings.mouseControl.enabled else { return "Back and Forward click as usual." }
        guard mouse.isWatching else { return "Waiting for Accessibility permission." }
        return "Watching the Back and Forward buttons of every mouse connected (buttons 4 and 5)."
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
