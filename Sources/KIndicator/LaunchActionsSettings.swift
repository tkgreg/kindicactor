import AppKit
import SwiftUI

/// The Launch Actions page: one row per `LaunchAction` (shortcut, input source, app).
struct LaunchActionsSettings: View {
    @ObservedObject var settings: AppSettings
    @State private var inputSources = InputSources.available()

    var body: some View {
        SettingsGroup(title: "Launch actions") {
            SettingsNote(text: "Press a shortcut anywhere: KIndicator switches the input source, then opens the app. In Keychron Launcher, set a key's macro (e.g. F4) to press the shortcut.")
            ForEach($settings.launchActions) { $action in
                HStack(spacing: 10) {
                    HotkeyRecorder(hotkey: $action.hotkey)
                    Picker("Input source", selection: $action.inputSourceID) {
                        Text("Keep input").tag(String?.none)
                        ForEach(inputSources) { source in
                            Text(source.name).tag(Optional(source.id))
                        }
                    }
                    .frame(width: 130)
                    appMenu(for: $action)
                    Spacer(minLength: 0)
                    Button {
                        remove(action)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Remove")
                }
                .labelsHidden()
            }
            Button("Add Launch Action") {
                settings.launchActions.append(.makeDefault())
            }
        }
        .onAppear { inputSources = InputSources.available() }
    }

    private func appMenu(for action: Binding<LaunchAction>) -> some View {
        Menu {
            if let launchpad = LaunchAction.launchpadPath {
                Button("Launchpad") { action.wrappedValue.appPath = launchpad }
            }
            Button("Choose App…") { chooseApp(for: action) }
            Divider()
            Button("No App") { action.wrappedValue.appPath = nil }
        } label: {
            if let path = action.wrappedValue.appPath {
                Label {
                    Text(path == LaunchAction.launchpadPath ? "Launchpad" : FileManager.default.displayName(atPath: path))
                } icon: {
                    Image(nsImage: Self.icon(path))
                }
            } else {
                Text("No app")
            }
        }
        .frame(width: 150)
    }

    private func chooseApp(for action: Binding<LaunchAction>) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            action.wrappedValue.appPath = url.path
        }
    }

    private func remove(_ action: LaunchAction) {
        settings.launchActions.removeAll { $0.id == action.id }
    }

    private static func icon(_ path: String) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: path)
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }
}
