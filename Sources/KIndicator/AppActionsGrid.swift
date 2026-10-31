import AppKit
import KIndicatorCore
import SwiftUI

/// A device's actions per app: rows for all apps, then rows for each app added, with a menu
/// per input. An app's inputs left to the all-apps action show it dimmed.
struct AppActionsGrid<Mapping: ActionMapping>: View {
    /// Column headings, and what Nothing means in each column.
    let columns: [(title: String, nothing: String)]
    /// An app's rows: a heading when there are several, then an input per column.
    let rows: [(title: String?, inputs: [Mapping.Input])]
    /// The heading over the rows' headings.
    var rowsTitle = ""
    @Binding var allApps: Mapping
    @Binding var apps: [AppActions<Mapping>]
    /// Whole mappings to fill an app's rows with; none hides the presets menu.
    var presets: [(name: String, mapping: Mapping)] = []

    private var hasRowTitles: Bool { rows.contains { $0.title != nil } }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 12) {
            GridRow {
                Text("App")
                if hasRowTitles { Text(rowsTitle) }
                ForEach(columns.indices, id: \.self) { index in
                    Text(columns[index].title)
                }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            appRows(mapping: $allApps, forApp: false) {
                Label("All Apps", systemImage: "square.grid.2x2")
            } remove: {}
            ForEach($apps) { $app in
                if hasRowTitles { Divider() }
                appRows(mapping: $app.mapping, forApp: true) {
                    Label {
                        Text(app.name).lineLimit(1)
                    } icon: {
                        Image(nsImage: AppIcon.small(path: app.path, bundleID: app.bundleID))
                    }
                    .help(app.bundleID)
                } remove: {
                    apps.removeAll { $0.id == app.id }
                }
            }
        }
        addAppMenu
    }

    /// An app's rows: its name, presets and remove button on the first.
    private func appRows<AppLabel: View>(mapping: Binding<Mapping>, forApp: Bool, @ViewBuilder label: () -> AppLabel,
                                         remove: @escaping () -> Void) -> some View {
        let label = label()
        return ForEach(rows.indices, id: \.self) { row in
            GridRow {
                if row == 0 {
                    label.frame(width: 120, alignment: .leading)
                } else {
                    Text("")
                }
                if hasRowTitles {
                    Text(rows[row].title ?? "")
                        .frame(minWidth: 60, alignment: .leading)
                }
                ForEach(rows[row].inputs.indices, id: \.self) { column in
                    let input = rows[row].inputs[column]
                    KeyActionMenu(action: actionBinding(mapping, input),
                                  inherited: forApp ? allApps[input] ?? .nothing : nil,
                                  nothingTitle: columns[column].nothing)
                }
                if row == 0 {
                    if !presets.isEmpty {
                        presetMenu(mapping, forApp: forApp)
                    }
                    if forApp {
                        Button(action: remove) {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help("Remove")
                    }
                }
            }
        }
    }

    /// Fills all of a row's actions; an app's can go back to the ones for all apps.
    private func presetMenu(_ mapping: Binding<Mapping>, forApp: Bool) -> some View {
        Menu {
            ForEach(presets.indices, id: \.self) { index in
                Button(presets[index].name) { mapping.wrappedValue = presets[index].mapping }
            }
            if forApp {
                Divider()
                Button("Same as All Apps") { mapping.wrappedValue = Mapping() }
            }
        } label: {
            Image(systemName: "wand.and.stars")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Presets")
    }

    private var addAppMenu: some View {
        AddAppMenu(added: Set(apps.map(\.bundleID))) { app in
            apps.append(AppActions(bundleID: app.bundleID, name: app.name, path: app.path))
        }
    }

    private func actionBinding(_ mapping: Binding<Mapping>, _ input: Mapping.Input) -> Binding<KeyAction?> {
        Binding(get: { mapping.wrappedValue[input] }, set: { mapping.wrappedValue[input] = $0 })
    }
}

/// What one input does: a media key, a recorded shortcut or nothing. An app's can be left
/// to the action for all apps, which then shows dimmed.
struct KeyActionMenu: View {
    @Binding var action: KeyAction?
    /// The action for all apps, in an app's menu; nil in the all-apps one.
    let inherited: KeyAction?
    /// What Nothing means here, e.g. Click as Usual.
    var nothingTitle = "Nothing"
    @State private var capture = ShortcutCapture()

    private static let sections: [(title: String, keys: [MediaKey])] = [
        ("Volume", [.volumeDown, .volumeUp, .mute, .preciseVolumeDown, .preciseVolumeUp]),
        ("Media", [.previousTrack, .playPause, .nextTrack]),
        ("Display", [.brightnessDown, .brightnessUp]),
    ]

    var body: some View {
        Group {
            if capture.isActive {
                Button("Type shortcut…") { capture.stop() }
            } else {
                Menu {
                    if let inherited {
                        check("Same as All Apps (\(title(inherited)))", action == nil) { action = nil }
                        Divider()
                    }
                    check(nothingTitle, action == .nothing) { action = .nothing }
                    ForEach(Self.sections, id: \.title) { section in
                        Section(section.title) {
                            ForEach(section.keys, id: \.self) { key in
                                check(key.title, action == .media(key)) { action = .media(key) }
                            }
                        }
                    }
                    Section("Shortcuts") {
                        ForEach(KeyAction.Shortcuts.all, id: \.name) { shortcut in
                            check("\(shortcut.name) (\(shortcut.hotkey.display))", action == .shortcut(shortcut.hotkey)) {
                                action = .shortcut(shortcut.hotkey)
                            }
                        }
                    }
                    Divider()
                    if case .shortcut(let hotkey) = action, !KeyAction.Shortcuts.all.contains(where: { $0.hotkey == hotkey }) {
                        check(hotkey.display, true) {}
                    }
                    Button("Record Shortcut…", action: record)
                } label: {
                    Text(title(action ?? inherited ?? .nothing))
                }
                .opacity(action == nil && inherited != nil ? 0.55 : 1)
            }
        }
        .frame(width: 140)
        .onDisappear(perform: capture.stop)
    }

    private func title(_ action: KeyAction) -> String {
        action == .nothing ? nothingTitle : action.title
    }

    private func record() {
        capture.start(allowsPlainKeys: true) { recorded in
            guard let recorded else { return }
            guard !KnobController.isKnobKey(recorded) else { return NSSound.beep() }
            action = .shortcut(recorded)
        }
    }

    private func check(_ title: String, _ isOn: Bool, _ select: @escaping () -> Void) -> some View {
        Toggle(title, isOn: Binding(get: { isOn }, set: { _ in select() }))
    }
}
