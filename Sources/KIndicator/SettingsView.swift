import KIndicatorCore
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, layers, knob, mouse, launchActions, connection, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .layers: "Layers"
        case .knob: "Knob"
        case .mouse: "Mouse"
        case .launchActions: "Launch Actions"
        case .connection: "Connection"
        case .about: "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "slider.horizontal.3"
        case .layers: "square.3.layers.3d"
        case .knob: "dial.medium"
        case .mouse: "computermouse"
        case .launchActions: "command"
        case .connection: "cable.connector"
        case .about: "info.circle"
        }
    }
}

/// A sidebar of sections and a rounded panel of rows, without a title bar.
struct SettingsView: View {
    static let windowID = "settings"
    static let tabKey = "settingsTab"

    @ObservedObject var monitor: KeyboardMonitor
    @ObservedObject var settings: AppSettings
    @ObservedObject var lighting: LightingController
    @ObservedObject var microphone: MicrophoneMonitor
    @ObservedObject var maps: KeyboardMaps
    @ObservedObject var roomLight: AmbientLightSensor
    let knob: KnobController
    let mouse: MouseController
    let updates: UpdateChecker
    @AppStorage(SettingsView.tabKey) private var tab = SettingsTab.layers
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginNeedsApproval = LoginItem.needsApproval

    private var layerRows: Int {
        max(monitor.layerCount ?? AppSettings.defaultLayerNames.count, 1)
    }

    /// Dark mode: #1E1E1E window, #252525 panel. Light mode: the system window colour
    /// and an off-white panel. Grays are given in sRGB: `NSColor(white:)` is gamma-2.2
    /// gray and comes out lighter than its number.
    private static let windowColor = Color(nsColor: NSColor(name: nil) { appearance in
        isDark(appearance) ? gray(0x1E) : .windowBackgroundColor
    })

    private static let panelColor = Color(nsColor: NSColor(name: nil) { appearance in
        isDark(appearance) ? gray(0x25) : gray(0xF7)
    })

    private static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private static func gray(_ level: CGFloat) -> NSColor {
        NSColor(srgbRed: level / 255, green: level / 255, blue: level / 255, alpha: 1)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(SettingsTab.allCases) { item in
                    SettingsSidebarItem(title: item.title, systemImage: item.systemImage,
                                        isSelected: tab == item) { tab = item }
                }
                Spacer(minLength: 0)
            }
            .frame(width: 190)

            ScrollView {
                VStack(alignment: .leading, spacing: 36) {
                    page
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Self.panelColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08))
            )
        }
        // Room for the window buttons above the sidebar.
        .padding(.top, 44)
        .padding([.horizontal, .bottom], 20)
        .frame(width: 940, height: 560)
        .background(Self.windowColor.ignoresSafeArea())
        .onAppear(perform: refreshLoginItem)
    }

    @ViewBuilder private var page: some View {
        switch tab {
        case .general: generalPage
        case .layers: layersPage
        case .knob: KnobSettings(settings: settings, knob: knob, monitor: monitor)
        case .mouse: MouseSettings(settings: settings, mouse: mouse)
        case .launchActions: LaunchActionsSettings(settings: settings)
        case .connection: connectionPage
        case .about: AboutPage(updates: updates)
        }
    }

    // MARK: - Pages

    @ViewBuilder private var generalPage: some View {
        SettingsGroup(title: "Menu bar") {
            SettingsRow(title: "Show",
                        description: "What the menu bar shows for the active layer.") {
                Picker("Show", selection: $settings.menuBarStyle) {
                    ForEach(MenuBarStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
        }
        SettingsGroup(title: "Startup") {
            SettingsRow(title: "Open at Login",
                        description: "Start KIndicator automatically when you log in.") {
                Toggle("Open at Login", isOn: launchAtLoginBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            if loginNeedsApproval {
                SettingsRow(title: "Needs approval",
                            description: "macOS asks you to allow KIndicator in Login Items.") {
                    Button("Open System Settings…") { LoginItem.openSystemSettings() }
                }
            }
        }
    }

    /// One row per layer: name and icon for the menu bar, lighting for the keyboard.
    @ViewBuilder private var layersPage: some View {
        SettingsGroup(title: "Layers") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    ForEach(["Layer", "Name", "Icon", "Lighting", "Color"], id: \.self) { heading in
                        Text(heading)
                    }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                ForEach(0..<layerRows, id: \.self) { layer in
                    GridRow {
                        HStack(spacing: 6) {
                            Text("Layer \(layer)")
                                .font(.body.weight(.medium))
                            if monitor.layer == layer {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 7))
                                    .foregroundStyle(.green)
                                    .help("Active now")
                            }
                        }
                        TextField("Name", text: nameBinding(for: layer),
                                  prompt: Text(AppSettings.placeholderName(for: layer)))
                            .frame(width: 110)
                        HStack(spacing: 6) {
                            TextField("Icon", text: iconBinding(for: layer),
                                      prompt: Text(AppSettings.placeholderIcon(for: layer)))
                                .frame(width: 60)
                                .help("SF Symbol name or up to 3 letters")
                            Image(nsImage: MenuBarImage.icon(settings.icon(for: layer)))
                                .renderingMode(.template)
                                .frame(width: 22)
                        }
                        Picker("Lighting", selection: effectBinding(for: layer)) {
                            Text("Keep saved").tag(-1)
                            Divider()
                            ForEach(LightingEffect.ids, id: \.self) { effect in
                                Text(LightingEffect.name(effect)).tag(Int(effect))
                            }
                        }
                        .frame(width: 160)
                        .disabled(!settings.layerLightingEnabled)
                        // Hidden rather than removed so the columns stay put.
                        HStack(spacing: 6) {
                            ColorPicker("Color", selection: colorBinding(for: layer), supportsOpacity: false)
                            HexColorField(hue: settings.lighting(for: layer)?.hue ?? 0,
                                          saturation: settings.lighting(for: layer)?.saturation ?? 255) { hue, saturation in
                                guard var lighting = settings.lighting(for: layer) else { return }
                                lighting.hue = hue
                                lighting.saturation = saturation
                                settings.setLighting(lighting, for: layer)
                            }
                        }
                        .opacity(settings.lighting(for: layer) == nil ? 0 : 1)
                        .disabled(settings.lighting(for: layer) == nil || !settings.layerLightingEnabled)
                    }
                }
            }
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            SettingsNote(text: "Name and icon show in the menu bar. An icon is an SF Symbol name such as sun.max, moon or globe, or up to 3 letters shown in a box. Press Fn or flip the Mac/Win switch to see which layer is which: the green dot follows the active layer.")
        }
        SettingsGroup(title: "Lighting") {
            SettingsRow(title: "Change Lighting with Layer",
                        description: "Show a layer's own effect while it's active, without saving it on the keyboard.") {
                Toggle("Change Lighting with Layer", isOn: $settings.layerLightingEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            SettingsRow(title: "Lights Off While Display Sleeps",
                        description: "Turn the keyboard's lights off when the Mac's display sleeps, and back on when it wakes, without saving it on the keyboard.") {
                Toggle("Lights Off While Display Sleeps", isOn: $settings.lightsOffWhileDisplaysSleep)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            SettingsNote(text: "Layers set to Keep saved show the lighting saved on the keyboard; change it from the menu bar › Lighting. Needs the cable or 2.4 GHz.")
        }
        SettingsGroup(title: "Brightness") {
            SettingsRow(title: "Adjust Brightness to Room Light",
                        description: "Dim the keyboard in a dark room and brighten it in a bright one, using the Mac's ambient light sensor, without saving it on the keyboard.") {
                Toggle("Adjust Brightness to Room Light", isOn: $settings.roomBrightness.enabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            .disabled(!AmbientLightSensor.isAvailable)
            SettingsRow(title: "In a Dark Room") {
                brightnessSlider(\.dark)
            }
            SettingsRow(title: "In a Bright Room") {
                brightnessSlider(\.bright)
            }
            SettingsNote(text: roomLightStatus)
        }
        SettingsGroup(title: "Mic Indicator") {
            SettingsRow(title: "Light a Key While Mic Is in Use",
                        description: "While any app records from a microphone, the key shows this colour, without saving it on the keyboard.") {
                Toggle("Light a Key While Mic Is in Use", isOn: $settings.micIndicator.enabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            SettingsRow(title: "Color") {
                HStack(spacing: 6) {
                    if maps.layout == nil {
                        Picker("Key", selection: $settings.micIndicator.key) {
                            ForEach(MicIndicator.fallbackKeys, id: \.key) { key in
                                Text(key.name).tag(key.key)
                            }
                        }
                        .fixedSize()
                    }
                    ColorPicker("Color", selection: micColorBinding, supportsOpacity: false)
                    HexColorField(hue: settings.micIndicator.hue, saturation: settings.micIndicator.saturation) { hue, saturation in
                        settings.micIndicator.hue = hue
                        settings.micIndicator.saturation = saturation
                    }
                }
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .disabled(!settings.micIndicator.enabled)
            }
            SettingsRow(title: "Style") {
                Picker("Style", selection: $settings.micIndicator.style) {
                    Text("Pulse").tag(MicIndicator.Style.pulse)
                    Text("Steady").tag(MicIndicator.Style.steady)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .disabled(!settings.micIndicator.enabled)
            }
            if let layout = maps.layout {
                micKeyPicker(layout)
            }
            SettingsNote(text: micStatus)
        }
    }

    /// The keyboard drawn with each key's function on the active layer; click the key that
    /// should light up. Keys without an LED (the knob) can't be picked.
    private func micKeyPicker(_ layout: KeyboardLayout) -> some View {
        let layer = monitor.layer ?? 0
        let indicator = settings.micIndicator
        return KeyboardLayoutView(
            layout: layout,
            selection: Binding(get: { indicator.key }, set: { if let key = $0 { settings.micIndicator.key = key } }),
            isEnabled: { key in !key.isKnob && (maps.ledMap.map { $0.led(at: key.position) != nil } ?? true) },
            fill: { key in key.position == indicator.key ? Self.color(hue: indicator.hue, saturation: indicator.saturation) : nil }
        ) { key in
            let resolved = maps.keymap?.resolved(layer: layer, at: key.position)
            // A key the active layer leaves transparent shows the lower layer's function, dimmed.
            Text(resolved.map { Keycode.label($0.keycode, customNames: layout.customKeycodeNames) } ?? "")
                .opacity(resolved.map { $0.layer == layer } ?? true ? 1 : 0.5)
        }
        .disabled(!indicator.enabled)
        .onAppear { maps.loadKeymap() }
    }

    /// A brightness of the range, in percent.
    private func brightnessSlider(_ end: WritableKeyPath<RoomBrightness, UInt8>) -> some View {
        let brightness = settings.roomBrightness[keyPath: end]
        return HStack(spacing: 10) {
            Slider(value: Binding(get: { Double(brightness) / 255 },
                                  set: { settings.roomBrightness[keyPath: end] = UInt8(($0 * 255).rounded()) }))
                .frame(width: 180)
            Text(Self.percent(brightness))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
        .disabled(!settings.roomBrightness.enabled)
    }

    /// What the sensor sees now and the brightness it gives, or why it can't.
    private var roomLightStatus: String {
        guard AmbientLightSensor.isAvailable else {
            return "This Mac has no ambient light sensor. MacBooks and iMacs have one, beside the camera."
        }
        let room = settings.roomBrightness
        let how = "Between a dark room (\(Int(RoomBrightness.darkLux)) lux or less) and a bright one (\(Int(RoomBrightness.brightLux)) lux or more) the brightness changes gradually. The keyboard's light keys change it until the room's light changes; its saved brightness comes back when this is off or KIndicator quits."
        guard room.enabled else { return how }
        let now: String
        if roomLight.lidClosed {
            now = "The lid is closed over the sensor, so the keyboard shows its saved brightness."
        } else if let lux = roomLight.lux {
            let light = switch lux {
            case RoomBrightness.darkLux: "dark"
            case RoomBrightness.brightLux: "bright"
            default: "about \(Int(lux.rounded())) lux"
            }
            now = "The room is \(light) now, so the keyboard is at \(Self.percent(room.brightness(lux: lux)))."
        } else {
            now = "Reading the sensor…"
        }
        return "\(now) \(how)"
    }

    private static func percent(_ brightness: UInt8) -> String {
        "\(Int((Double(brightness) / 255 * 100).rounded()))%"
    }

    /// Who's using the microphone, and why the key can't light up, if it can't.
    private var micStatus: String {
        let apps = microphone.recordingApps
        let now = apps.isEmpty ? "No app is using a microphone." : "In use by \(apps.joined(separator: ", "))."
        var needs = "The key lights up with the Per-key RGB effect, also on layers set to Solid Color"
        if let effect = lighting.saved?.effect, effect != LightingEffect.perKeyRGB {
            needs += "; the keyboard is on \(LightingEffect.name(effect)) (menu bar › Lighting › Effect)"
        }
        let pick = maps.layout == nil ? "" : " Click the key that should light up."
        return "\(now)\(pick) \(needs). Needs the cable or 2.4 GHz."
    }

    @ViewBuilder private var connectionPage: some View {
        SettingsGroup(title: "Keyboard") {
            SettingsRow(title: "Model") {
                Text(monitor.model ?? "–").foregroundStyle(.secondary)
            }
            SettingsRow(title: "Status") {
                Text(monitor.status.description).foregroundStyle(.secondary)
            }
            if let firmware = monitor.firmware {
                SettingsRow(title: "Firmware") {
                    Text(firmware).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
        }
        SettingsGroup(title: "Connection") {
            SettingsRow(title: "Read Layer Via",
                        description: "Auto uses whichever connection answers, preferring the cable. Over Bluetooth the keyboard doesn't report its layer.") {
                Picker("Read Layer Via", selection: $settings.connection) {
                    ForEach(ConnectionPreference.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            SettingsRow(title: "Check Layer Every",
                        description: "How often KIndicator asks the keyboard for its layer.") {
                Picker("Check Layer Every", selection: $settings.pollIntervalMs) {
                    ForEach(AppSettings.pollIntervals, id: \.self) { ms in
                        Text(ms < 1000 ? "\(ms) ms" : "\(ms / 1000) s").tag(ms)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
        }
    }

    // MARK: - Bindings

    /// -1 means Keep saved.
    private func effectBinding(for layer: Int) -> Binding<Int> {
        Binding(
            get: { settings.lighting(for: layer).map { Int($0.effect) } ?? -1 },
            set: { effect in
                guard effect >= 0 else { return settings.setLighting(nil, for: layer) }
                var lighting = settings.lighting(for: layer) ?? LayerLighting(effect: 0, hue: 0, saturation: 255)
                lighting.effect = UInt8(effect)
                settings.setLighting(lighting, for: layer)
            }
        )
    }

    private func colorBinding(for layer: Int) -> Binding<Color> {
        Binding(
            get: {
                let lighting = settings.lighting(for: layer) ?? LayerLighting(effect: 0, hue: 0, saturation: 255)
                return Color(hue: Double(lighting.hue) / 255, saturation: Double(lighting.saturation) / 255, brightness: 1)
            },
            set: { color in
                guard var lighting = settings.lighting(for: layer),
                      let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                lighting.hue = UInt8((rgb.hueComponent * 255).rounded())
                lighting.saturation = UInt8((rgb.saturationComponent * 255).rounded())
                settings.setLighting(lighting, for: layer)
            }
        )
    }

    private var micColorBinding: Binding<Color> {
        Binding(
            get: { Self.color(hue: settings.micIndicator.hue, saturation: settings.micIndicator.saturation) },
            set: { color in
                guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                var indicator = settings.micIndicator
                indicator.hue = UInt8((rgb.hueComponent * 255).rounded())
                indicator.saturation = UInt8((rgb.saturationComponent * 255).rounded())
                settings.micIndicator = indicator
            }
        )
    }

    private static func color(hue: UInt8, saturation: UInt8) -> Color {
        Color(hue: Double(hue) / 255, saturation: Double(saturation) / 255, brightness: 1)
    }

    private func nameBinding(for layer: Int) -> Binding<String> {
        Binding(
            get: { layer < settings.layerNames.count ? settings.layerNames[layer] : "" },
            set: { settings.setName($0, for: layer) }
        )
    }

    private func iconBinding(for layer: Int) -> Binding<String> {
        Binding(
            get: { layer < settings.layerIcons.count ? settings.layerIcons[layer] : "" },
            set: { settings.setIcon($0, for: layer) }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { enabled in
                LoginItem.setEnabled(enabled)
                refreshLoginItem()
            }
        )
    }

    private func refreshLoginItem() {
        launchAtLogin = LoginItem.isEnabled || LoginItem.needsApproval
        loginNeedsApproval = LoginItem.needsApproval
    }
}
