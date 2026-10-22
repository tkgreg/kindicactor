import AppKit
import SwiftUI

/// Settings rows for `LaunchAction`s: shortcut, input source, app.
struct LaunchActionsSection: View {
    @ObservedObject var settings: AppSettings
    @State private var inputSources = InputSources.available()

    var body: some View {
        Section {
            ForEach($settings.launchActions) { $action in
                HStack(spacing: 8) {
                    HotkeyRecorder(hotkey: $action.hotkey)
                    Picker("Input source", selection: $action.inputSourceID) {
                        Text("Keep input").tag(String?.none)
                        ForEach(inputSources) { source in
                            Text(source.name).tag(Optional(source.id))
                        }
                    }
                    .frame(width: 110)
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
        } header: {
            Text("Launch actions")
        } footer: {
            Text("Press the shortcut anywhere: KIndicator switches the input source, then opens the app. In Keychron Launcher, set a key's macro (e.g. F4) to press the shortcut.")
                .foregroundStyle(.secondary)
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
        .frame(width: 130)
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
