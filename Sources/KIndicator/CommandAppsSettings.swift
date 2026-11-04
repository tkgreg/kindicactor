import AppKit
import KIndicatorCore
import SwiftUI

/// The Command Apps page: the apps made so far, and an editor for a new or changed one.
struct CommandAppsSettings: View {
    @ObservedObject var settings: AppSettings
    @StateObject private var store = CommandAppStore()
    /// Not optional: the editor's fields are bound to it and SwiftUI updates them once more as the
    /// editor goes away, so unwrapping a draft set to nil on Save would crash.
    @State private var draft = Draft(app: CommandApp(name: "", command: ""))
    @State private var isEditing = false
    @State private var canGenerate = false
    @State private var isGenerating = false

    /// The app being made or changed; `existing` is where it's saved now.
    struct Draft {
        var app: CommandApp
        var existing: URL?
        var error: String?
        /// Create App writes a missing comment once; if that fails, the user writes it or goes without.
        var triedGenerating = false
    }

    var body: some View {
        SettingsGroup(title: "Command apps") {
            SettingsNote(text: "Make a command into an app with its own window, e.g. htop, a dev server or an AI agent. It's saved in ~/Applications, so Spotlight, Launchpad and the Dock open it like any app. To open it with a shortcut, add a launch action for it.")
            ForEach(store.apps) { installed in
                row(installed)
            }
            if store.finderCommentsBlocked {
                SettingsRow(title: "Finder can't show the comments",
                            description: "Allow KIndicator to control Finder, then save the app again. Spotlight finds the apps by their comments anyway.") {
                    Button("Open Automation Settings…") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
                    }
                }
            }
            if !isEditing {
                Button("New Command App") {
                    edit(Draft(app: CommandApp(name: "", command: "")))
                }
            }
        }
        .onAppear {
            store.reload()
            canGenerate = CommandComments.isAvailable
        }
        if isEditing {
            editor($draft)
        }
    }

    private func row(_ installed: InstalledCommandApp) -> some View {
        HStack(spacing: 12) {
            Image(nsImage: CommandAppIcon.image(for: installed.app, size: 36))
            VStack(alignment: .leading, spacing: 2) {
                Text(installed.app.name)
                    .font(.body.weight(.medium))
                Text(Self.firstLine(of: installed.app.command))
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
            Button("Open") {
                NSWorkspace.shared.openApplication(at: installed.url, configuration: NSWorkspace.OpenConfiguration())
            }
            Button("Edit") {
                edit(Draft(app: installed.app, existing: installed.url))
            }
            .disabled(isEditing)
            Menu {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([installed.url]) }
                Divider()
                Button("Move to Trash") { moveToTrash(installed) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private func editor(_ draft: Binding<Draft>) -> some View {
        SettingsGroup(title: draft.wrappedValue.existing == nil ? "New command app" : "Edit command app") {
            SettingsRow(title: "Name", description: "As Spotlight, Launchpad and the Dock show it.") {
                TextField("Name", text: draft.app.name, prompt: Text("htop"))
                    .frame(width: 320)
            }
            // The whole width, as a command can be a script of several lines.
            VStack(alignment: .leading, spacing: 8) {
                SettingsRow(title: "Command",
                            description: "Runs in your shell, as in Terminal, so your PATH and aliases work. Several lines run as a script.") {
                    EmptyView()
                }
                CommandEditor(text: draft.app.command, placeholder: "e.g. cd ~/src/site && npm run dev")
                    .frame(height: 120)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.15))
                    )
            }
            VStack(alignment: .leading, spacing: 8) {
                SettingsRow(title: "Finder Comment", description: canGenerate
                            ? "Spotlight finds the app by these words too. Generate writes them from the name and command with Apple Intelligence, on this Mac; Create App does when it's empty."
                            : "Spotlight finds the app by these words too, e.g. task manager for htop.") {
                    if canGenerate {
                        HStack(spacing: 8) {
                            if isGenerating {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Button {
                                Task { await generateComment(draft) }
                            } label: {
                                Label("Generate", systemImage: "sparkles")
                            }
                            .disabled(isGenerating || !Self.isComplete(draft.wrappedValue.app))
                        }
                    }
                }
                TextField("Finder Comment", text: draft.app.comment,
                          prompt: Text("What the app does, and other words to find it by"), axis: .vertical)
                    .lineLimit(2...5)
            }
            SettingsRow(title: "Folder", description: "Where the command starts.") {
                HStack(spacing: 8) {
                    Text(draft.wrappedValue.app.directory ?? "Home folder")
                        .lineLimit(1)
                        .truncationMode(.head)
                        .foregroundStyle(.secondary)
                    Button("Choose…") { chooseFolder(for: draft) }
                    if draft.wrappedValue.app.directory != nil {
                        Button {
                            draft.wrappedValue.app.directory = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help("Start in the home folder")
                    }
                }
            }
            SettingsRow(title: "Icon", description: "An SF Symbol name such as terminal, server.rack or cpu, or up to 3 letters.") {
                HStack(spacing: 10) {
                    TextField("Icon", text: draft.app.icon, prompt: Text("terminal"))
                        .frame(width: 120)
                    Picker("Color", selection: draft.app.tint) {
                        ForEach(CommandApp.Tint.allCases, id: \.self) { tint in
                            Text(tint.title).tag(tint)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Image(nsImage: CommandAppIcon.image(for: draft.wrappedValue.app, size: 40))
                }
            }
            SettingsRow(title: "When the Command Ends") {
                Picker("When the Command Ends", selection: draft.app.whenDone) {
                    ForEach(CommandApp.WhenDone.allCases, id: \.self) { option in
                        Text(option.title).tag(option)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            if let error = draft.wrappedValue.error {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel") { isEditing = false }
                    .keyboardShortcut(.cancelAction)
                // ⌘↩, as Return starts a new line of the command.
                Button(draft.wrappedValue.existing == nil ? "Create App" : "Save") { save(draft) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .help("⌘↩")
                    .disabled(isGenerating || !Self.isComplete(draft.wrappedValue.app))
            }
        }
        .textFieldStyle(.roundedBorder)
    }

    private static func isComplete(_ app: CommandApp) -> Bool {
        !app.name.trimmingCharacters(in: .whitespaces).isEmpty
            && !app.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// A new app without a comment gets one first, so Spotlight finds it by what it does.
    private func save(_ draft: Binding<Draft>) {
        guard draft.wrappedValue.existing == nil, canGenerate, !draft.wrappedValue.triedGenerating,
              draft.wrappedValue.app.comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return write(draft) }
        draft.wrappedValue.triedGenerating = true
        Task {
            // On failure the editor stays open with the error, for the user to write the comment.
            if await generateComment(draft), isEditing {
                write(draft)
            }
        }
    }

    @discardableResult
    private func generateComment(_ draft: Binding<Draft>) async -> Bool {
        isGenerating = true
        defer { isGenerating = false }
        do {
            draft.wrappedValue.app.comment = try await CommandComments.generate(
                name: draft.wrappedValue.app.name.trimmingCharacters(in: .whitespaces),
                command: draft.wrappedValue.app.command.trimmingCharacters(in: .whitespacesAndNewlines))
            draft.wrappedValue.error = nil
            return true
        } catch {
            draft.wrappedValue.error = error.localizedDescription
            return false
        }
    }

    private func write(_ draft: Binding<Draft>) {
        var app = draft.wrappedValue.app
        app.name = app.name.trimmingCharacters(in: .whitespaces)
        app.command = app.command.trimmingCharacters(in: .whitespacesAndNewlines)
        app.comment = app.comment.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let url = try store.save(app, replacing: draft.wrappedValue.existing)
            if let old = draft.wrappedValue.existing?.path, old != url.path {
                for index in settings.launchActions.indices where settings.launchActions[index].appPath == old {
                    settings.launchActions[index].appPath = url.path
                }
            }
            isEditing = false
        } catch {
            draft.wrappedValue.error = error.localizedDescription
        }
    }

    private func moveToTrash(_ installed: InstalledCommandApp) {
        do {
            try store.moveToTrash(installed)
            // Launch actions that opened it keep their input source; ones left with nothing go.
            settings.launchActions = settings.launchActions.compactMap { action in
                guard action.appPath == installed.url.path else { return action }
                var action = action
                action.appPath = nil
                return action.inputSourceID == nil ? nil : action
            }
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    /// A script's first line, followed by "…".
    private static func firstLine(of command: String) -> String {
        let lines = command.split(separator: "\n", omittingEmptySubsequences: true)
        return lines.count > 1 ? "\(lines[0]) …" : command
    }

    private func edit(_ draft: Draft) {
        self.draft = draft
        isEditing = true
    }

    private func chooseFolder(for draft: Binding<Draft>) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            draft.wrappedValue.app.directory = (url.path as NSString).abbreviatingWithTildeInPath
        }
    }
}

/// A text area for a shell command: monospaced, with the Mac's smart quotes, dashes, text
/// replacement and spelling fixes off, as each would break a command (-- becomes —).
struct CommandEditor: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String

    func makeNSView(context: Context) -> NSScrollView {
        let textView = CommandTextView()
        textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = .width
        textView.textContainer?.widthTracksTextView = true
        textView.string = text
        textView.placeholder = placeholder
        textView.delegate = context.coordinator

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.text = $text
        guard let textView = scrollView.documentView as? NSTextView, textView.string != text else { return }
        textView.string = text
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}

/// Tab moves to the next field as in a text field; Escape doesn't offer word completions; an
/// empty command shows an example.
final class CommandTextView: NSTextView {
    var placeholder = "" {
        didSet { needsDisplay = true }
    }

    override func insertTab(_ sender: Any?) {
        window?.selectNextKeyView(self)
    }

    override func insertBacktab(_ sender: Any?) {
        window?.selectPreviousKeyView(self)
    }

    override func complete(_ sender: Any?) {}

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, let font else { return }
        let origin = NSPoint(x: textContainerOrigin.x + (textContainer?.lineFragmentPadding ?? 0),
                             y: textContainerOrigin.y)
        NSAttributedString(string: placeholder, attributes: [.font: font, .foregroundColor: NSColor.placeholderTextColor])
            .draw(at: origin)
    }
}
