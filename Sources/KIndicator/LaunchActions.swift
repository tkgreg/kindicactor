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
    private var subscription: AnyCancellable?

    init(settings: AppSettings) {
        self.settings = settings
    }

    func start() {
        subscription = settings.$launchActions.sink { [weak self] actions in
            self?.register(actions)
        }
    }

    private func register(_ actions: [LaunchAction]) {
        HotkeyCenter.shared.set(actions.compactMap { action in
            action.hotkey.map { hotkey in
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
