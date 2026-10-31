import AppKit
import ApplicationServices
import Combine
import KIndicatorCore
import OSLog

private let log = Logger(subsystem: "local.kindicator", category: "mouse")

/// Mouse double-clicks. While on, an event tap sees every mouse's Back and Forward presses
/// (buttons 3 and 4); `DoubleClick` decides which to hold back, which to send on and when a
/// double-click runs the frontmost app's action. A tap that can hold events back needs
/// Accessibility permission, as pressing the action's keys does.
@MainActor
final class MouseController: ObservableObject {
    /// Whether the side buttons are being watched; false while off or not allowed.
    @Published private(set) var isWatching = false

    /// Marks the clicks KIndicator sends on, so the tap lets them through.
    private static let replayMark: Int64 = 0x4B49_4E44 // "KIND"

    private let settings: AppSettings
    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var clicks = DoubleClick(interval: 0.3)
    private var timeoutTask: Task<Void, Never>?
    private var subscriptions: Set<AnyCancellable> = []

    init(settings: AppSettings) {
        self.settings = settings
    }

    func start() {
        settings.$mouseControl.map(\.enabled).removeDuplicates()
            .sink { [weak self] in self?.refresh(enabled: $0) }
            .store(in: &subscriptions)
    }

    /// Starts or stops watching; also when Accessibility may have been allowed meanwhile.
    func refresh(enabled: Bool? = nil) {
        let enabled = enabled ?? settings.mouseControl.enabled
        if enabled && tap == nil && AXIsProcessTrusted() {
            startTap()
        } else if !enabled && tap != nil {
            stopTap()
        }
        if isWatching != (tap != nil) { isWatching = tap != nil }
    }

    // MARK: - The tap

    private func startTap() {
        let mask = CGEventMask(1 << CGEventType.otherMouseDown.rawValue | 1 << CGEventType.otherMouseUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask,
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let pass = MainActor.assumeIsolated {
                    Unmanaged<MouseController>.fromOpaque(context).takeUnretainedValue().handle(type, event)
                }
                return pass ? Unmanaged.passUnretained(event) : nil
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque())
        else {
            log.error("can't watch the mouse buttons")
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.tap = tap
        tapSource = source
        log.notice("watching the mouse's Back and Forward buttons")
    }

    private func stopTap() {
        perform(clicks.flush())
        timeoutTask?.cancel()
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes) }
        tap = nil
        tapSource = nil
        log.notice("stopped watching the mouse")
    }

    /// Whether to let the event through.
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS turns a slow tap off; carry on.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return true
        case .otherMouseDown, .otherMouseUp:
            break
        default:
            return true
        }
        guard event.getIntegerValueField(.eventSourceUserData) != Self.replayMark,
              let button = MouseButton(buttonNumber: event.getIntegerValueField(.mouseEventButtonNumber))
        else { return true }

        let isDown = type == .otherMouseDown
        clicks.interval = settings.mouseControl.doubleClickInterval
        let wanted = isDown && settings.mouseControl.action(for: button, app: Self.frontmostApp) != .nothing
        let (pass, effects) = clicks.handle(button, isDown: isDown, at: Self.now, wanted: wanted)
        perform(effects)
        scheduleTimeout()
        return pass
    }

    private func scheduleTimeout() {
        timeoutTask?.cancel()
        guard let deadline = clicks.deadline else { return }
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, deadline - Self.now)))
            guard !Task.isCancelled, let self else { return }
            perform(clicks.timeout(at: Self.now))
            scheduleTimeout()
        }
    }

    private func perform(_ effects: [DoubleClick.Effect]) {
        for effect in effects {
            switch effect {
            case .replay(let button, let released):
                send(button, isDown: true)
                if released { send(button, isDown: false) }
            case .run(let button):
                let action = settings.mouseControl.action(for: button, app: Self.frontmostApp)
                log.debug("double-click \(button.rawValue, privacy: .public): \(action.title, privacy: .public)")
                KeyPresser.perform(action)
            }
        }
    }

    /// Sends on a press or release held back, where the pointer is now.
    private func send(_ button: MouseButton, isDown: Bool) {
        let location = CGEvent(source: nil)?.location ?? .zero
        guard let event = CGEvent(mouseEventSource: nil, mouseType: isDown ? .otherMouseDown : .otherMouseUp,
                                  mouseCursorPosition: location,
                                  mouseButton: CGMouseButton(rawValue: UInt32(button.buttonNumber)) ?? .center)
        else { return }
        event.setIntegerValueField(.mouseEventButtonNumber, value: button.buttonNumber)
        event.setIntegerValueField(.mouseEventClickState, value: 1)
        event.setIntegerValueField(.eventSourceUserData, value: Self.replayMark)
        event.post(tap: .cghidEventTap)
    }

    private static var now: Double { ProcessInfo.processInfo.systemUptime }

    private static var frontmostApp: String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }
}
