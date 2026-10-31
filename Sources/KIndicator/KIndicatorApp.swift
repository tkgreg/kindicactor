import AppKit
import Combine
import KIndicatorCore
import SwiftUI

@main
struct KIndicatorApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(monitor: appDelegate.monitor, settings: appDelegate.settings,
                        lighting: appDelegate.lighting)
        } label: {
            MenuBarLabel(monitor: appDelegate.monitor, settings: appDelegate.settings)
        }
        .menuBarExtraStyle(.menu)

        Window("KIndicator", id: SettingsView.windowID) {
            SettingsView(monitor: appDelegate.monitor, settings: appDelegate.settings,
                         lighting: appDelegate.lighting, microphone: appDelegate.microphone,
                         maps: appDelegate.maps, roomLight: appDelegate.roomLight, knob: appDelegate.knob,
                         updates: appDelegate.updates)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings()
    let monitor = KeyboardMonitor()
    let updates = UpdateChecker()
    let microphone = MicrophoneMonitor()
    let roomLight = AmbientLightSensor()
    lazy var maps = KeyboardMaps(monitor: monitor)
    lazy var lighting = LightingController(monitor: monitor, settings: settings, microphone: microphone, maps: maps,
                                             roomLight: roomLight)
    lazy var launchActions = LaunchActionRunner(settings: settings)
    lazy var knob = KnobController(monitor: monitor, settings: settings, maps: maps)
    private var subscriptions: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings.$connection
            .sink { [monitor] in monitor.preference = $0 }
            .store(in: &subscriptions)
        settings.$pollIntervalMs
            .sink { [monitor] in monitor.pollInterval = .milliseconds($0) }
            .store(in: &subscriptions)
        settings.$roomBrightness.map(\.enabled).removeDuplicates()
            .sink { [roomLight] in roomLight.isRunning = $0 }
            .store(in: &subscriptions)
        monitor.start()
        microphone.start()
        maps.start()
        lighting.start()
        launchActions.start()
        knob.start()
        LoginItem.enableOnFirstLaunch()
    }

    /// Quitting waits for the keyboard to get its own lighting back, up to a moment: a keyboard
    /// that doesn't answer shouldn't keep the app open.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let lighting = lighting
        Task {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await lighting.restoreBeforeQuit() }
                group.addTask { try? await Task.sleep(for: .seconds(1.5)) }
                await group.next()
                group.cancelAll()
            }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

struct MenuBarLabel: View {
    @ObservedObject var monitor: KeyboardMonitor
    @ObservedObject var settings: AppSettings

    var body: some View {
        if let layer = monitor.layer {
            let name = settings.name(for: layer)
            switch settings.menuBarStyle {
            case .icon:
                Image(nsImage: MenuBarImage.icon(settings.icon(for: layer)))
                    .accessibilityLabel(name)
            case .iconAndName:
                Image(nsImage: MenuBarImage.icon(MenuBarImage.icon(settings.icon(for: layer)), followedBy: name))
            case .name:
                Text(name)
            }
        } else {
            Image(systemName: "keyboard.badge.ellipsis")
        }
    }
}

struct MenuContent: View {
    @ObservedObject var monitor: KeyboardMonitor
    @ObservedObject var settings: AppSettings
    @ObservedObject var lighting: LightingController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let layer = monitor.layer {
            Text("Layer \(layer): \(settings.name(for: layer))")
        }
        if let keyboard = monitor.model ?? monitor.deviceName {
            Text(keyboard)
        }
        Text(statusLine)
        Divider()
        LightingMenu(monitor: monitor, settings: settings, lighting: lighting, openSettings: openSettings)
        Picker("Connection", selection: $settings.connection) {
            ForEach(ConnectionPreference.allCases) { option in
                Text(option.title).tag(option)
            }
        }
        Button("About KIndicator") { openSettings(.about) }
        Button("Settings…") { openSettings() }
            .keyboardShortcut(",")
        Divider()
        Button("Quit KIndicator") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    /// "Connected via 2.4 GHz · Per-key RGB": the connection plus the saved lighting effect.
    private var statusLine: String {
        guard monitor.status.allowsLighting, let saved = lighting.saved else { return monitor.status.description }
        return "\(monitor.status.description) · \(LightingEffect.name(saved.effect))"
    }

    private func openSettings(_ tab: SettingsTab? = nil) {
        if let tab {
            UserDefaults.standard.set(tab.rawValue, forKey: SettingsView.tabKey)
        }
        openWindow(id: SettingsView.windowID)
        // Asking to activate while the menu is still closing is ignored, and opening a
        // window doesn't raise a menu bar app: do both once the menu is gone.
        DispatchQueue.main.async {
            NSApp.activate()
            let window = NSApp.windows.first { $0.identifier?.rawValue.hasPrefix(SettingsView.windowID) == true }
            window?.makeKeyAndOrderFront(nil)
            window?.orderFrontRegardless()
        }
    }
}

/// Changes the saved lighting effect.
struct LightingMenu: View {
    @ObservedObject var monitor: KeyboardMonitor
    @ObservedObject var settings: AppSettings
    @ObservedObject var lighting: LightingController
    let openSettings: (SettingsTab?) -> Void

    var body: some View {
        Menu("Lighting") {
            if let saved = lighting.saved, monitor.status.allowsLighting {
                Menu("Effect: \(LightingEffect.name(saved.effect))") {
                    ForEach(LightingEffect.ids, id: \.self) { effect in
                        check(LightingEffect.name(effect), saved.effect == effect) { $0.effect = effect }
                        if effect == 0 { Divider() }
                    }
                }
                Divider()
                if settings.hasLayerLighting {
                    Toggle("Change with Layer", isOn: $settings.layerLightingEnabled)
                }
                if AmbientLightSensor.isAvailable {
                    Toggle("Adjust Brightness to Room Light", isOn: $settings.roomBrightness.enabled)
                }
                Button("Lighting per Layer…") { openSettings(.layers) }
            } else {
                Text(monitor.status.lightingUnavailable)
            }
        }
    }

    private func check(_ title: String, _ isOn: Bool, _ update: @escaping (inout Lighting) -> Void) -> some View {
        Toggle(title, isOn: Binding(get: { isOn }, set: { _ in lighting.change(update) }))
    }
}

extension KeyboardMonitor.Status {
    var description: String {
        switch self {
        case .searching: "Keyboard not found"
        case .connected(let kind): "Connected via \(kind.title)"
        case .noReply(let kind): "No answer via \(kind.title) (asleep or on another connection)"
        case .bluetoothOnly: "On Bluetooth: layer can't be read"
        case .paused(let app): "Paused while \(app) has the keyboard open"
        }
    }

    /// Lighting stays usable through short silences so menu items don't change under the
    /// pointer; changes wait for the keyboard to answer.
    var allowsLighting: Bool {
        switch self {
        case .connected, .noReply: true
        case .searching, .bluetoothOnly, .paused: false
        }
    }

    var lightingUnavailable: String {
        switch self {
        case .bluetoothOnly: "Not available over Bluetooth"
        case .paused(let app): "Paused while \(app) has the keyboard open (e.g. Keychron Launcher)"
        default: "Connect the keyboard by cable or 2.4 GHz"
        }
    }
}
