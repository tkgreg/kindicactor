import AppKit
import ApplicationServices
import KIndicatorCore
import OSLog
import QuartzCore

private let log = Logger(subsystem: "local.kindicator", category: "scroll")

/// Smooth scrolling's engine, on a thread of its own: the event tap that takes the wheel's
/// notches, the display link that times each frame of a glide on the screen under the
/// pointer, and posting the frames. A busy main thread never holds up anyone's scrolling, and
/// the tap never times out because of it. How far each frame moves is `ScrollMotion`'s.
///
/// Wheel notches only: events that scroll smoothly by themselves (trackpads, the Magic Mouse,
/// tablets, screen sharing) are continuous or carry phases, and are left alone. Each frame is
/// a fresh continuous pixel event, posted where a mouse's would be.
final class ScrollEngine: NSObject, @unchecked Sendable {
    /// Marks the frames posted here, so the tap lets them through.
    private static let mark: Int64 = 0x4B49_4E44_5343_524C // "KINDSCRL"
    /// A glide whose frames stopped coming this long ago is finished at once.
    private static let stall = 0.25

    // Handed over from the main thread.
    private let lock = NSLock()
    private var sharedSettings = SmoothScrolling()
    private var sharedLinks: [CGDirectDisplayID: CADisplayLink] = [:]
    private var linksChanged = false
    /// Called on the scroll thread when display links stopped working.
    var onLinksFailed: (@Sendable () -> Void)?

    // The scroll thread's own.
    private var thread: Thread?
    private var runLoop: CFRunLoop?
    private var tap: CFMachPort?
    /// The links added to this thread's run loop.
    private var scheduled: [CADisplayLink] = []
    private var activeLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    private var lastFrameUptime = 0.0
    private var watchdog: Timer?
    private var motion = ScrollMotion()
    private var settings = SmoothScrolling()
    private var postFlags: CGEventFlags = []
    private var bundleIDs: [pid_t: String] = [:]

    var isRunning: Bool { lock.withLock { tap != nil } }

    // MARK: - Main thread

    /// Starts the tap and the thread; false when macOS doesn't allow the tap (Accessibility).
    func start(settings: SmoothScrolling, links: [CGDirectDisplayID: CADisplayLink]) -> Bool {
        update(settings)
        replaceLinks(links)
        let mask = [CGEventType.scrollWheel, .leftMouseDown, .rightMouseDown]
            .reduce(CGEventMask(0)) { $0 | 1 << $1.rawValue }
        guard let tap = CGEvent.tapCreate(
            tap: .cgAnnotatedSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask,
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let engine = Unmanaged<ScrollEngine>.fromOpaque(context).takeUnretainedValue()
                return engine.handle(type, event) ? Unmanaged.passUnretained(event) : nil
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque())
        else {
            log.error("can't watch the scroll wheel")
            return false
        }
        lock.withLock { self.tap = tap }

        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [self] in
            let loop = CFRunLoopGetCurrent()!
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, lock.withLock { self.tap }, 0)
            CFRunLoopAddSource(loop, source, .commonModes)
            lock.withLock { runLoop = loop }
            ready.signal()
            CFRunLoopRun()
            CFRunLoopRemoveSource(loop, source, .commonModes)
        }
        thread.name = "KIndicator scrolling"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        self.thread = thread
        log.notice("smooth scrolling on")
        return true
    }

    func stop() {
        guard let loop = lock.withLock({ () -> CFRunLoop? in
            defer { runLoop = nil }
            return runLoop
        }) else { return }
        CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue) { [self] in
            stopGlide()
            scheduled.forEach { $0.invalidate() }
            scheduled = []
            activeLink = nil
            lock.withLock {
                if let tap {
                    CGEvent.tapEnable(tap: tap, enable: false)
                    CFMachPortInvalidate(tap)
                }
                tap = nil
            }
            CFRunLoopStop(loop)
        }
        CFRunLoopWakeUp(loop)
        thread = nil
        log.notice("smooth scrolling off")
    }

    func update(_ settings: SmoothScrolling) {
        lock.withLock { sharedSettings = settings }
    }

    /// The display links to time frames with, one per screen, made on the main thread.
    func replaceLinks(_ links: [CGDirectDisplayID: CADisplayLink]) {
        lock.withLock {
            sharedLinks = links
            linksChanged = true
        }
    }

    // MARK: - Scroll thread

    /// Whether to let the event through.
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap = lock.withLock({ tap }) { CGEvent.tapEnable(tap: tap, enable: true) }
            log.error("scroll tap was turned off; on again")
            return true
        case .leftMouseDown, .rightMouseDown:
            // A click stops a glide, as on a trackpad.
            stopGlide()
            return true
        case .scrollWheel:
            break
        default:
            return true
        }
        guard event.getIntegerValueField(.eventSourceUserData) != Self.mark else { return true }
        // Smooth already: a trackpad, the Magic Mouse, a tablet, screen sharing. Touching one
        // stops a wheel's glide.
        if event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
            || event.getIntegerValueField(.scrollWheelEventScrollPhase) != 0
            || event.getIntegerValueField(.scrollWheelEventMomentumPhase) != 0
            || event.getIntegerValueField(.scrollWheelEventScrollCount) != 0 {
            stopGlide()
            return true
        }

        settings = lock.withLock { sharedSettings }
        let target = pid_t(truncatingIfNeeded: event.getIntegerValueField(.eventTargetUnixProcessID))
        // Some wheel events have no usable target process. In that case the active
        // app is the best available destination for deciding whether to smooth.
        let activeApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let destination = bundleID(of: target) ?? activeApp
        guard !settings.excludes(destination), !settings.excludes(activeApp) else {
            stopGlide()
            return true
        }

        let flags = event.flags
        var vertical = Self.lines(event, axis: 1)
        var horizontal = Self.lines(event, axis: 2)
        // Shift scrolls sideways. macOS turns a plain wheel's events sideways itself, but not
        // the smooth ones posted here, so it's done here unless macOS already did.
        if flags.contains(.maskShift) && horizontal == 0 {
            swap(&vertical, &horizontal)
        }
        if settings.reverseVertical { vertical = -vertical }
        if settings.reverseHorizontal { horizontal = -horizontal }

        if let plain = settings.plainKey, flags.rawValue & plain.flag != 0 {
            // The wheel's own scrolling, e.g. so ⌘-scroll zooms; only reversed if set.
            stopGlide()
            Self.reverse(event, vertical: settings.reverseVertical, horizontal: settings.reverseHorizontal)
            return true
        }

        let now = ProcessInfo.processInfo.systemUptime
        if motion.isMoving && now - lastFrameUptime > Self.stall {
            // Frames stopped coming (a display asleep, a link gone): send the rest now.
            log.error("no frames for \(now - self.lastFrameUptime, format: .fixed(precision: 2)) s; finishing the glide")
            post(motion.finish())
            pauseFrames()
            onLinksFailed?()
        }
        let boost = settings.fasterKey.map { flags.rawValue & $0.flag != 0 } == true ? SmoothScrolling.fasterBoost : 1
        if vertical != 0 {
            motion.notch(.vertical, lines: vertical, at: now, distance: settings.distance,
                         acceleration: settings.acceleration, boost: boost)
        }
        if horizontal != 0 {
            motion.notch(.horizontal, lines: horizontal, at: now, distance: settings.distance,
                         acceleration: settings.acceleration, boost: boost)
        }
        // Frames carry the keys held at the last notch, less the ones used up here.
        var used = CGEventFlags.maskShift
        if let faster = settings.fasterKey { used.insert(CGEventFlags(rawValue: faster.flag)) }
        postFlags = flags.subtracting(used)
        runFrames(on: Self.display(at: event.location))
        return false
    }

    /// The wheel's movement on an axis (1 vertical, 2 horizontal), in lines.
    private static func lines(_ event: CGEvent, axis: Int) -> Double {
        let fixed = event.getDoubleValueField(axis == 1 ? .scrollWheelEventFixedPtDeltaAxis1 : .scrollWheelEventFixedPtDeltaAxis2)
        if fixed != 0 { return fixed }
        return Double(event.getIntegerValueField(axis == 1 ? .scrollWheelEventDeltaAxis1 : .scrollWheelEventDeltaAxis2))
    }

    private static func reverse(_ event: CGEvent, vertical: Bool, horizontal: Bool) {
        let axes: [(Bool, CGEventField, CGEventField, CGEventField)] = [
            (vertical, .scrollWheelEventDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventPointDeltaAxis1),
            (horizontal, .scrollWheelEventDeltaAxis2, .scrollWheelEventFixedPtDeltaAxis2, .scrollWheelEventPointDeltaAxis2),
        ]
        for (reversed, lines, fixed, points) in axes where reversed {
            event.setIntegerValueField(lines, value: -event.getIntegerValueField(lines))
            event.setDoubleValueField(fixed, value: -event.getDoubleValueField(fixed))
            event.setIntegerValueField(points, value: -event.getIntegerValueField(points))
        }
    }

    private static func display(at point: CGPoint) -> CGDirectDisplayID {
        var display = CGMainDisplayID()
        var count: UInt32 = 0
        CGGetDisplaysWithPoint(point, 1, &display, &count)
        return count > 0 ? display : CGMainDisplayID()
    }

    /// The app a scroll goes to, by process; remembered, as processes keep their app.
    private func bundleID(of pid: pid_t) -> String? {
        if let known = bundleIDs[pid] { return known }
        guard pid > 0, let id = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier else { return nil }
        if bundleIDs.count > 200 { bundleIDs.removeAll() }
        bundleIDs[pid] = id
        return id
    }

    /// Frames from the display link of the screen the pointer is on.
    private func runFrames(on display: CGDirectDisplayID) {
        let (changed, available) = lock.withLock { () -> (Bool, [CGDirectDisplayID: CADisplayLink]) in
            defer { linksChanged = false }
            return (linksChanged, sharedLinks)
        }
        if changed {
            // Screens changed: the old links go.
            scheduled.forEach { $0.invalidate() }
            scheduled = []
            activeLink = nil
        }
        guard let link = available[display] ?? available.values.first else {
            // No display link at all: no glide, just the distance at once.
            post(motion.finish())
            return
        }
        if !scheduled.contains(where: { $0 === link }) {
            link.add(to: .current, forMode: .common)
            scheduled.append(link)
        }
        if activeLink !== link {
            activeLink?.isPaused = true
            activeLink = link
            lastTimestamp = nil
        }
        if link.isPaused {
            link.isPaused = false
            lastTimestamp = nil
            lastFrameUptime = ProcessInfo.processInfo.systemUptime
        }
        if watchdog == nil {
            let timer = Timer(timeInterval: Self.stall, repeats: true) { [weak self] _ in self?.checkFrames() }
            RunLoop.current.add(timer, forMode: .common)
            watchdog = timer
        }
    }

    @objc func frame(_ link: CADisplayLink) {
        guard link === activeLink else {
            link.isPaused = true
            return
        }
        // The first frame of a glide moves one frame's time.
        let dt = lastTimestamp.map { link.timestamp - $0 } ?? (link.targetTimestamp - link.timestamp)
        lastTimestamp = link.timestamp
        lastFrameUptime = ProcessInfo.processInfo.systemUptime
        post(motion.advance(by: dt, glide: settings.glide))
        // Arrived: no frames until the next notch, which still counts toward the spin.
        if !motion.isMoving { pauseFrames() }
    }

    /// While gliding: frames that stopped coming finish the glide at once.
    private func checkFrames() {
        guard motion.isMoving else { return pauseFrames() }
        guard ProcessInfo.processInfo.systemUptime - lastFrameUptime > Self.stall else { return }
        log.error("display link stopped; finishing the glide")
        post(motion.finish())
        pauseFrames()
        onLinksFailed?()
    }

    /// Drops the rest of a glide: a click, a trackpad, ⌘-scroll.
    private func stopGlide() {
        motion.stop()
        pauseFrames()
    }

    private func pauseFrames() {
        activeLink?.isPaused = true
        lastTimestamp = nil
        watchdog?.invalidate()
        watchdog = nil
    }

    private func post(_ pixels: (horizontal: Int, vertical: Int)) {
        // A glide can outlive an app switch or a change to the exclusion list.
        // Stop before sending any remaining synthetic scrolling into an excluded app.
        let currentSettings = lock.withLock { sharedSettings }
        guard currentSettings.enabled,
              !currentSettings.excludes(NSWorkspace.shared.frontmostApplication?.bundleIdentifier) else {
            stopGlide()
            return
        }
        guard pixels.horizontal != 0 || pixels.vertical != 0,
              let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                                  wheel1: Int32(clamping: pixels.vertical), wheel2: Int32(clamping: pixels.horizontal),
                                  wheel3: 0)
        else { return }
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.eventSourceUserData, value: Self.mark)
        event.flags = postFlags
        if let pointer = CGEvent(source: nil)?.location { event.location = pointer }
        event.post(tap: .cghidEventTap)
    }
}
