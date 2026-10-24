import Combine
import KIndicatorCore
import OSLog

private let log = Logger(subsystem: "local.kindicator", category: "maps")

/// What the keyboard says about its keys: which LED each one has, and what each one does
/// on each layer. The LED map is read whenever the keyboard starts answering (the mic
/// indicator needs it); the keymap only once something shows it. Both are read again after
/// another app had the keyboard open, since Keychron Launcher may have changed them.
@MainActor
final class KeyboardMaps: ObservableObject {
    @Published private(set) var ledMap: LEDMap?
    @Published private(set) var keymap: Keymap?

    private let monitor: KeyboardMonitor
    private var keymapWanted = false
    private var reading: Task<Void, Never>?
    private var readAgain = false
    private var subscriptions: Set<AnyCancellable> = []

    init(monitor: KeyboardMonitor) {
        self.monitor = monitor
    }

    /// The connected keyboard's bundled layout.
    var layout: KeyboardLayout? {
        monitor.productID.flatMap(KeyboardLayout.forProduct)
    }

    func start() {
        monitor.$status.removeDuplicates()
            .sink { [weak self] status in
                if case .connected = status { self?.read() }
            }
            .store(in: &subscriptions)
        // Another keyboard, or the dongle just named the paired one: read again for it.
        monitor.$productID.removeDuplicates().dropFirst()
            .sink { [weak self] _ in
                self?.ledMap = nil
                self?.keymap = nil
                self?.read()
            }
            .store(in: &subscriptions)
    }

    /// For a view showing the keymap: reads it now unless it's known.
    func loadKeymap() {
        keymapWanted = true
        if keymap == nil { read() }
    }

    private func read() {
        guard reading == nil else {
            readAgain = true
            return
        }
        reading = Task {
            // The matrix of the bundled layout, else the V6's.
            let rows = layout?.rows ?? 6
            let cols = layout?.cols ?? 20
            if let ledMap = await readLEDMap(rows: rows, cols: cols), ledMap != self.ledMap {
                log.notice("LED map: \(ledMap.leds.count) keys")
                self.ledMap = ledMap
            }
            if keymapWanted, let keymap = await readKeymap(layers: monitor.layerCount ?? 4, rows: rows, cols: cols),
               keymap != self.keymap {
                log.notice("keymap: \(keymap.layers.count) layers")
                self.keymap = keymap
            }
            reading = nil
            if readAgain {
                readAgain = false
                read()
            }
        }
    }

    private func readLEDMap(rows: Int, cols: Int) async -> LEDMap? {
        var leds: [[UInt8?]] = []
        for request in LEDMap.requests(rows: rows) {
            guard let reply = await monitor.request(request),
                  let row = KeyboardReply.ledNumbers(reply, cols: cols) else { return nil }
            leds.append(row)
        }
        return LEDMap(rows: leds)
    }

    private func readKeymap(layers: Int, rows: Int, cols: Int) async -> Keymap? {
        var buffer: [UInt8] = []
        for request in Keymap.requests(layerCount: layers, rows: rows, cols: cols) {
            guard case .keymapBuffer(_, let size) = request,
                  let reply = await monitor.request(request),
                  let chunk = KeyboardReply.keymapChunk(reply, size: size) else { return nil }
            buffer += chunk
        }
        return Keymap(buffer: buffer, layerCount: layers, rows: rows, cols: cols)
    }
}
