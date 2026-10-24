import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, layers, launchActions, connection, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .layers: "Layers"
        case .launchActions: "Launch Actions"
        case .connection: "Connection"
        case .about: "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "slider.horizontal.3"
        case .layers: "square.3.layers.3d"
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
            SettingsNote(text: "Layers set to Keep saved show the lighting saved on the keyboard; change it from the menu bar › Lighting. Needs the cable or 2.4 GHz.")
        }
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
