import SwiftUI

struct SettingsView: View {
    static let windowID = "settings"

    @ObservedObject var monitor: KeyboardMonitor
    @ObservedObject var settings: AppSettings
    @ObservedObject var lighting: LightingController
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginNeedsApproval = LoginItem.needsApproval

    private var layerRows: Int {
        max(monitor.layerCount ?? AppSettings.defaultLayerNames.count, 1)
    }

    var body: some View {
        Form {
            Section {
                ForEach(0..<layerRows, id: \.self) { layer in
                    LabeledContent {
                        HStack(spacing: 8) {
                            TextField("Name", text: nameBinding(for: layer),
                                      prompt: Text(AppSettings.placeholderName(for: layer)))
                                .help("Name")
                            TextField("Icon", text: iconBinding(for: layer),
                                      prompt: Text(AppSettings.placeholderIcon(for: layer)))
                                .help("Icon: SF Symbol name or up to 3 letters")
                                .frame(width: 90)
                            Image(nsImage: MenuBarImage.icon(settings.icon(for: layer)))
                                .renderingMode(.template)
                                .frame(width: 22)
                        }
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                    } label: {
                        layerLabel(layer)
                    }
                }
            } header: {
                Text("Layers")
            } footer: {
                Text("Icon: an SF Symbol name such as sun.max, moon or globe, or up to 3 letters to show in a square. Press Fn or flip the Mac/Win switch to see which layer is which: the green dot follows the active layer.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Change lighting with layer", isOn: $settings.layerLightingEnabled)
                ForEach(0..<layerRows, id: \.self) { layer in
                    LabeledContent {
                        HStack(spacing: 8) {
                            Picker("Lighting", selection: effectBinding(for: layer)) {
                                Text("Keep saved").tag(-1)
                                Divider()
                                ForEach(LightingEffect.ids, id: \.self) { effect in
                                    Text(LightingEffect.name(effect)).tag(Int(effect))
                                }
                            }
                            // Hidden rather than removed so the pickers stay aligned.
                            ColorPicker("Color", selection: colorBinding(for: layer), supportsOpacity: false)
                                .opacity(settings.lighting(for: layer) == nil ? 0 : 1)
                                .disabled(settings.lighting(for: layer) == nil)
                        }
                        .labelsHidden()
                        .disabled(!settings.layerLightingEnabled)
                    } label: {
                        layerLabel(layer)
                    }
                }
            } header: {
                Text("Lighting per layer")
            } footer: {
                Text("While a layer with its own lighting is active, the keyboard shows it without saving it. Layers set to Keep saved show your saved lighting (menu bar › Lighting). Needs the cable or 2.4 GHz.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Read layer via", selection: $settings.connection) {
                    ForEach(ConnectionPreference.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                if let model = monitor.model {
                    LabeledContent("Keyboard", value: model)
                }
                LabeledContent("Status", value: monitor.status.description)
                if let firmware = monitor.firmware {
                    LabeledContent("Firmware", value: firmware)
                }
            } header: {
                Text("Connection")
            } footer: {
                Text("Auto uses whichever connection answers, preferring the cable. Over Bluetooth the keyboard firmware doesn't expose the layer, so use 2.4 GHz or the cable.")
                    .foregroundStyle(.secondary)
            }

            Section("Menu bar") {
                Picker("Show", selection: $settings.menuBarStyle) {
                    ForEach(MenuBarStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                Picker("Check layer every", selection: $settings.pollIntervalMs) {
                    ForEach(AppSettings.pollIntervals, id: \.self) { ms in
                        Text(ms < 1000 ? "\(ms) ms" : "\(ms / 1000) s").tag(ms)
                    }
                }
            }

            Section("General") {
                Toggle("Open at login", isOn: launchAtLoginBinding)
                if loginNeedsApproval {
                    Button("Allow in System Settings…") { LoginItem.openSystemSettings() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .frame(minHeight: 400, idealHeight: 720)
        .onAppear(perform: refreshLoginItem)
    }

    private func layerLabel(_ layer: Int) -> some View {
        HStack(spacing: 6) {
            Text("Layer \(layer)")
            if monitor.layer == layer {
                Image(systemName: "circle.fill")
                    .foregroundStyle(.green)
                    .imageScale(.small)
                    .help("Active now")
            }
        }
    }

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
