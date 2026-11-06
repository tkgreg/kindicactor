import AppKit
import Combine
import KIndicatorCore
import OSLog

private let log = Logger(subsystem: "local.kindicator", category: "launch")

/// A global shortcut that switches the input source, then opens an app, e.g. so that
/// Launchpad's search gets English letters. Either part may be left out.
struct LaunchAction: Codable, Identifiable, Equatable {
    var id = UUID()
    var hotkey: Hotkey?
    var inputSourceID: String?
    var appPath: String?

    /// Launchpad became Apps in macOS 26.
    static let launchpadPath = ["/System/Applications/Apps.app", "/System/Applications/Launchpad.app"]
        .first { FileManager.default.fileExists(atPath: $0) }

    /// ABC (or U.S.) to Launchpad: the case this feature is for.
    static func makeDefault() -> LaunchAction {
        let english = InputSources.available().first {
            ["com.apple.keylayout.ABC", "com.apple.keylayout.US"].contains($0.id)
        }
        return LaunchAction(inputSourceID: english?.id, appPath: launchpadPath)
    }
}

@MainActor
final class LaunchActionRunner {
    private let settings: AppSettings
    private var subscriptions: Set<AnyCancellable> = []
    private var actions: [LaunchAction] = []
    /// The frontmost app's bundle, whose own shortcut is left to it: ⌘⇧N opens Zed from
    /// elsewhere, but in Zed it's Zed's ⌘⇧N.
    private var frontmost: (path: String?, bundleID: String?) = (nil, nil)

    init(settings: AppSettings) {
        self.settings = settings
    }

    func start() {
        noteFrontmost(NSWorkspace.shared.frontmostApplication)
        settings.$launchActions.sink { [weak self] actions in
            self?.actions = actions
            self?.register()
        }.store(in: &subscriptions)
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didActivateApplicationNotification)
            .sink { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                self?.noteFrontmost(app)
                self?.register()
            }.store(in: &subscriptions)
    }

    private func noteFrontmost(_ app: NSRunningApplication?) {
        frontmost = (app?.bundleURL.map(Self.resolved), app?.bundleIdentifier)
    }

    private static func resolved(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// Whether `action` opens the app that's frontmost now.
    private func opensFrontmost(_ action: LaunchAction) -> Bool {
        guard let appPath = action.appPath else { return false }
        let url = URL(fileURLWithPath: appPath)
        if let path = frontmost.path, Self.resolved(url) == path { return true }
        if let id = frontmost.bundleID, Bundle(url: url)?.bundleIdentifier == id { return true }
        return false
    }

    private func register() {
        HotkeyCenter.shared.set(actions.compactMap { action in
            guard !opensFrontmost(action) else { return nil }
            return action.hotkey.map { hotkey in
                (hotkey: hotkey, action: { [weak self] in self?.run(action) })
            }
        }, for: .launchActions)
    }

    private func run(_ action: LaunchAction) {
        if let inputSourceID = action.inputSourceID, !InputSources.select(inputSourceID) {
            log.error("input source \(inputSourceID, privacy: .public) not found")
        }
        if let appPath = action.appPath {
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: appPath),
                                               configuration: NSWorkspace.OpenConfiguration())
        }
        log.notice("ran: input \(action.inputSourceID ?? "-", privacy: .public), app \(action.appPath ?? "-", privacy: .public)")
    }
}
