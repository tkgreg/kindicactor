import KIndicatorCore
import SwiftUI

/// The Scrolling page: smooth scrolling on or off, how it feels, keys that change it, a place
/// to try it, and apps it leaves alone.
struct ScrollingSettings: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var scroll: ScrollController

    var body: some View {
        let enabled = settings.smoothScrolling.enabled
        SettingsGroup(title: "Smooth Scrolling") {
            SettingsRow(title: "Smooth Scrolling",
                        description: "Turn a mouse wheel's notches into a smooth glide, like a trackpad's, the same on a 60 Hz and a 120 Hz screen. Trackpads and the Magic Mouse are left alone.") {
                Toggle("Smooth Scrolling", isOn: enabledBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            SettingsRow(title: "Distance per Notch",
                        description: "How far a notch scrolls while the wheel turns slowly.") {
                slider(\.distance, in: SmoothScrolling.distances, step: 5) { "\(Int($0)) px" }
            }
            SettingsRow(title: "Glide",
                        description: "How long a notch takes to come to rest. Shorter feels snappier, longer smoother.") {
                slider(\.glide, in: SmoothScrolling.glides, step: 0.01) { String(format: "%.2f s", $0) }
            }
            SettingsRow(title: "Speed Up When Spinning",
                        description: "Spin the wheel fast and each notch goes farther; turned slowly, notches stay precise.") {
                slider(\.acceleration, in: SmoothScrolling.accelerations, step: 0.1) { acceleration in
                    acceleration == 0 ? "Off" : String(format: "up to ×%.1f", ScrollMotion.speedUp(rate: .infinity, acceleration: acceleration))
                }
            }
            SettingsRow(title: "Reverse",
                        description: "Scroll the other way than macOS does with the wheel.") {
                HStack(spacing: 14) {
                    Toggle("Up and Down", isOn: $settings.smoothScrolling.reverseVertical)
                    Toggle("Sideways", isOn: $settings.smoothScrolling.reverseHorizontal)
                }
                .toggleStyle(.checkbox)
            }
            SettingsRow(title: "Faster While Holding",
                        description: "Notches go \(Int(SmoothScrolling.fasterBoost)) times as far.") {
                keyPicker($settings.smoothScrolling.fasterKey)
            }
            SettingsRow(title: "Without Smoothing While Holding",
                        description: "The wheel scrolls as it does by itself, e.g. so ⌘-scroll zooms as usual.") {
                keyPicker($settings.smoothScrolling.plainKey)
            }
            if enabled && !scroll.isRunning {
                SettingsRow(title: "Allow KIndicator to Change Scrolling",
                            description: "macOS lets KIndicator change scrolling only with Accessibility permission: turn KIndicator on in Privacy & Security › Accessibility.") {
                    Button("Open System Settings…") { KeyPresser.openAccessibilitySettings() }
                }
            }
            SettingsNote(text: status)
        }
        SettingsGroup(title: "Try It") {
            tryItHere
        }
        SettingsGroup(title: "Disable Smooth Scrolling in Apps") {
            SettingsNote(text: "Smooth scrolling is turned off in the apps below. They keep their normal mouse-wheel scrolling, without KIndicator's acceleration or reversal.")
            ForEach(settings.smoothScrolling.excludedApps) { app in
                HStack(spacing: 8) {
                    Image(nsImage: AppIcon.small(path: app.path, bundleID: app.bundleID))
                    Text(app.name)
                        .help(app.bundleID)
                    Spacer(minLength: 0)
                    Button {
                        settings.smoothScrolling.excludedApps.removeAll { $0.id == app.id }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Remove")
                }
            }
            AddAppMenu(added: Set(settings.smoothScrolling.excludedApps.map(\.bundleID))) { app in
                settings.smoothScrolling.excludedApps.append(app)
            }
        }
        .disabled(!enabled)
        // Turned on in System Settings meanwhile.
        .task(id: enabled) {
            while settings.smoothScrolling.enabled && !scroll.isRunning && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                scroll.refresh()
            }
        }
    }

    private var status: String {
        guard settings.smoothScrolling.enabled else { return "Mouse wheels scroll as macOS makes them." }
        guard scroll.isRunning else { return "Waiting for Accessibility permission." }
        return "Smoothing every mouse wheel. ⇧ scrolls sideways, as macOS does. If another app also smooths scrolling, turn that off there, so the wheel isn't smoothed twice."
    }

    /// Lines to scroll through, to feel the settings at once.
    private var tryItHere: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(1...200, id: \.self) { line in
                    Text(line % 10 == 0 ? "Line \(line) ———" : "Line \(line)")
                        .foregroundStyle(line % 10 == 0 ? .primary : .secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(12)
        }
        .frame(height: 160)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }

    private func slider(_ value: WritableKeyPath<SmoothScrolling, Double>, in range: ClosedRange<Double>, step: Double,
                        label: @escaping (Double) -> String) -> some View {
        HStack(spacing: 10) {
            // Rounded here rather than with the slider's step, which draws a tick per step.
            Slider(value: Binding(get: { settings.smoothScrolling[keyPath: value] },
                                  set: { settings.smoothScrolling[keyPath: value] = ($0 / step).rounded() * step }),
                   in: range)
                .frame(width: 180)
            Text(label(settings.smoothScrolling[keyPath: value]))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
        }
        .disabled(!settings.smoothScrolling.enabled)
    }

    private func keyPicker(_ key: Binding<ModifierKey?>) -> some View {
        Picker("Key", selection: key) {
            Text("None").tag(ModifierKey?.none)
            ForEach(ModifierKey.allCases, id: \.self) { key in
                Text(key.symbol).tag(Optional(key))
            }
        }
        .labelsHidden()
        .fixedSize()
        .disabled(!settings.smoothScrolling.enabled)
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { settings.smoothScrolling.enabled },
            set: { enabled in
                settings.smoothScrolling.enabled = enabled
                if enabled && !KeyPresser.isAllowed { KeyPresser.requestPermission() }
            }
        )
    }
}
