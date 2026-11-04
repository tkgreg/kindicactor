import AppKit
import KIndicatorCore
import SwiftTerm
import SwiftUI

/// One window running the app's command in the user's shell; the app quits with the window.
/// The command comes from the bundle's Info.plist (see `CommandApp`). Run outside a bundle, e.g.
/// `.build/debug/CommandHost htop`, it runs its arguments instead, or the shell.
@main
@MainActor
final class CommandHost: NSObject, NSApplicationDelegate, NSWindowDelegate, LocalProcessTerminalViewDelegate {
    private static let defaultFontSize: CGFloat = 13
    private static let fontSizeKey = "fontSize"

    private let app: CommandApp
    private let terminal = CommandTerminalView(frame: NSRect(x: 0, y: 0, width: 820, height: 520))
    private var window: NSWindow!
    private var isRunning = false
    private let commandPopover = NSPopover()

    static func main() {
        let host = CommandHost()
        let application = NSApplication.shared
        application.delegate = host
        application.setActivationPolicy(.regular)
        application.mainMenu = makeMainMenu(appName: host.app.name)
        withExtendedLifetime(host) { application.run() }
    }

    override init() {
        app = Bundle.main.infoDictionary.flatMap(CommandApp.init(infoPlist:)) ?? Self.fromArguments()
        super.init()
    }

    private static func fromArguments() -> CommandApp {
        let arguments = CommandLine.arguments.dropFirst()
        return CommandApp(name: "CommandHost", command: arguments.isEmpty ? "exec $SHELL" : arguments.joined(separator: " "),
                          whenDone: .keepOpen)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        terminal.processDelegate = self
        terminal.font = Self.font(size: UserDefaults.standard.object(forKey: Self.fontSizeKey) as? CGFloat
                                  ?? Self.defaultFontSize)
        terminal.nativeForegroundColor = Self.foregroundColor
        terminal.nativeBackgroundColor = Self.backgroundColor
        terminal.onInputWhileStopped = { [weak self] data in
            // Return runs the command again, as the line printed at its end says.
            if data.contains(13) { self?.start() }
        }

        window = NSWindow(contentRect: terminal.frame, styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = app.name
        window.contentView = terminal
        window.delegate = self
        window.tabbingMode = .disallowed
        addCommandButton()
        if !window.setFrameUsingName("CommandWindow") {
            window.center()
        }
        window.setFrameAutosaveName("CommandWindow")
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(terminal)
        NSApp.activate()
        start()
    }

    private func start() {
        let shell = Self.userShell
        let directory = (app.directory.map { ($0 as NSString).expandingTildeInPath })
            ?? FileManager.default.homeDirectoryForCurrentUser.path
        isRunning = true
        terminal.isStopped = false
        window.subtitle = ""
        terminal.startProcess(executable: shell, args: CommandApp.shellArguments(for: app.command),
                              environment: Self.environment(shell: shell), currentDirectory: directory)
    }

    /// The login shell from the user's account; apps opened from the Finder may not get `SHELL`.
    private static var userShell: String {
        if let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell {
            return String(cString: shell)
        }
        return ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    }

    /// The app's own environment (HOME, PATH, SSH_AUTH_SOCK, …) plus what a terminal sets.
    private static func environment(shell: String) -> [String] {
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        environment["SHELL"] = shell
        if environment["LANG"] == nil {
            environment["LANG"] = "en_US.UTF-8"
        }
        return environment.map { "\($0.key)=\($0.value)" }
    }

    // MARK: Colors and font

    private static func dynamic(dark: UInt32, light: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
    }

    private static let foregroundColor = dynamic(dark: 0xE6E6E6, light: 0x1E1E1E)
    private static let backgroundColor = dynamic(dark: 0x1E1E1E, light: 0xFFFFFF)

    private static func font(size: CGFloat) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    private func setFontSize(_ size: CGFloat) {
        let size = min(max(size, 8), 36)
        terminal.font = Self.font(size: size)
        UserDefaults.standard.set(size, forKey: Self.fontSizeKey)
    }

    @objc func biggerFont(_ sender: Any?) { setFontSize(terminal.font.pointSize + 1) }
    @objc func smallerFont(_ sender: Any?) { setFontSize(terminal.font.pointSize - 1) }
    @objc func defaultFont(_ sender: Any?) { setFontSize(Self.defaultFontSize) }

    // MARK: The process

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        isRunning = false
        switch app.whenDone {
        case .close:
            NSApp.terminate(nil)
            return
        case .closeIfSucceeded where exitCode == 0:
            NSApp.terminate(nil)
            return
        default:
            break
        }
        let status = switch exitCode {
        case 0: "Done"
        case let code?: "Exited with code \(code)"
        case nil: "Stopped"
        }
        window.subtitle = status
        terminal.isStopped = true
        // Dim, on a line of its own.
        terminal.feed(text: "\r\n\u{1B}[2m[\(status). Press Return to run it again.]\u{1B}[0m\r\n")
    }

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        window.subtitle = title
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    // MARK: The command button

    /// A button at the title bar's right end that shows the exact command, to read or copy.
    private func addCommandButton() {
        let button = NSButton(image: NSImage(systemSymbolName: "info.circle", accessibilityDescription: "Command")!,
                              target: self, action: #selector(toggleCommand(_:)))
        button.isBordered = false
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = "Show the command"
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 36, height: 28))
        button.frame = NSRect(x: 6, y: 4, width: 22, height: 20)
        button.autoresizingMask = [.minYMargin, .maxYMargin]
        container.addSubview(button)

        let accessory = NSTitlebarAccessoryViewController()
        accessory.view = container
        accessory.layoutAttribute = .trailing
        window.addTitlebarAccessoryViewController(accessory)

        let content = NSHostingController(rootView: CommandInfo(app: app, copy: { [weak self] in
            self?.copyCommand(nil)
        }))
        content.sizingOptions = .preferredContentSize
        commandPopover.contentViewController = content
        commandPopover.behavior = .transient
    }

    @objc func toggleCommand(_ sender: NSButton) {
        if commandPopover.isShown {
            commandPopover.performClose(sender)
        } else {
            commandPopover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        }
    }

    @objc func copyCommand(_ sender: Any?) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(app.command, forType: .string)
    }

    // MARK: Quitting

    /// The app is its window: closing it quits, which asks first while the command runs.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NSApp.terminate(nil)
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard isRunning, let window else { return .terminateNow }
        // A sheet on a minimized or hidden window would wait unseen.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        let alert = NSAlert()
        alert.messageText = "Quit \(app.name)?"
        alert.informativeText = "Its command is still running. Quitting stops it."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in
            sender.reply(toApplicationShouldTerminate: response == .alertFirstButtonReturn)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        if isRunning {
            terminal.terminate()
        }
    }

    // MARK: Menus

    private static func makeMainMenu(appName: String) -> NSMenu {
        let mainMenu = NSMenu()
        func add(_ title: String, _ items: [NSMenuItem]) -> NSMenu {
            let menu = NSMenu(title: title)
            items.forEach(menu.addItem)
            let item = NSMenuItem()
            item.submenu = menu
            mainMenu.addItem(item)
            return menu
        }
        func item(_ title: String, _ action: Selector, _ key: String = "",
                  _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            return item
        }

        _ = add(appName, [
            item("About \(appName)", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            item("Hide \(appName)", #selector(NSApplication.hide(_:)), "h"),
            item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            item("Show All", #selector(NSApplication.unhideAllApplications(_:))),
            .separator(),
            item("Quit \(appName)", #selector(NSApplication.terminate(_:)), "q"),
        ])
        _ = add("Edit", [
            item("Copy", #selector(TerminalView.copy(_:)), "c"),
            item("Paste", #selector(TerminalView.paste(_:)), "v"),
            item("Select All", #selector(NSResponder.selectAll(_:)), "a"),
            .separator(),
            item("Copy Command", #selector(copyCommand(_:)), "c", [.command, .shift]),
        ])
        _ = add("View", [
            item("Bigger", #selector(biggerFont(_:)), "="),
            item("Smaller", #selector(smallerFont(_:)), "-"),
            item("Default Size", #selector(defaultFont(_:)), "0"),
        ])
        NSApp.windowsMenu = add("Window", [
            item("Close", #selector(NSWindow.performClose(_:)), "w"),
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Zoom", #selector(NSWindow.performZoom(_:))),
        ])
        return mainMenu
    }
}

/// The command button's popover: the command as it runs, its folder, and a Copy button.
struct CommandInfo: View {
    let app: CommandApp
    let copy: () -> Void
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(app.command)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 12) {
                Label(app.directory ?? "~", systemImage: "folder")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer(minLength: 0)
                Button(copied ? "Copied" : "Copy Command") {
                    copy()
                    copied = true
                }
            }
        }
        .padding(14)
        .frame(width: 420)
        .onAppear { copied = false }
    }
}

/// Once the command has ended, typing goes to `onInputWhileStopped` instead of nowhere.
final class CommandTerminalView: LocalProcessTerminalView {
    var isStopped = false
    var onInputWhileStopped: ((ArraySlice<UInt8>) -> Void)?

    override func send(source: TerminalView, data: ArraySlice<UInt8>) {
        if isStopped {
            onInputWhileStopped?(data)
        } else {
            super.send(source: source, data: data)
        }
    }
}
