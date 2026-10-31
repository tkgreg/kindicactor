import AppKit
import ApplicationServices
import Combine
import KIndicatorCore
import QuartzCore

/// Starts and stops the smooth scrolling engine as the settings say, hands it the settings,
/// and makes its display links, one per screen, again whenever the screens change.
@MainActor
final class ScrollController: ObservableObject {
    /// Whether wheels are being smoothed; false while off or not allowed.
    @Published private(set) var isRunning = false

    private let settings: AppSettings
    private let engine = ScrollEngine()
    private var subscriptions: Set<AnyCancellable> = []

    init(settings: AppSettings) {
        self.settings = settings
    }

    func start() {
        engine.onLinksFailed = { [weak self] in
            Task { @MainActor in self?.makeLinks() }
        }
        settings.$smoothScrolling
            .sink { [weak self] in self?.apply($0) }
            .store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.makeLinks() }
            .store(in: &subscriptions)
    }

    /// Also when Accessibility may have been allowed meanwhile.
    func refresh() {
        apply(settings.smoothScrolling)
    }

    private func apply(_ smoothScrolling: SmoothScrolling) {
        engine.update(smoothScrolling)
        if smoothScrolling.enabled && !isRunning && AXIsProcessTrusted() {
            isRunning = engine.start(settings: smoothScrolling, links: links())
        } else if !smoothScrolling.enabled && isRunning {
            engine.stop()
            isRunning = false
        }
    }

    private func makeLinks() {
        guard isRunning else { return }
        engine.replaceLinks(links())
    }

    /// A paused display link per screen, by display, ticking the engine.
    private func links() -> [CGDirectDisplayID: CADisplayLink] {
        var links: [CGDirectDisplayID: CADisplayLink] = [:]
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
            let link = screen.displayLink(target: engine, selector: #selector(ScrollEngine.frame(_:)))
            link.isPaused = true
            links[CGDirectDisplayID(number.uint32Value)] = link
        }
        return links
    }
}
