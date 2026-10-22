import Foundation
import IOKit.hid
import OSLog

private let log = Logger(subsystem: "local.kindicator", category: "monitor")

enum ConnectionKind: String, CaseIterable, Identifiable {
    case usb, dongle, bluetooth

    var id: String { rawValue }

    var title: String {
        switch self {
        case .usb: "USB cable"
        case .dongle: "2.4 GHz"
        case .bluetooth: "Bluetooth"
        }
    }
}

enum ConnectionPreference: String, CaseIterable, Identifiable {
    case auto, usb, dongle, bluetooth

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: "Auto"
        case .usb: ConnectionKind.usb.title
        case .dongle: ConnectionKind.dongle.title
        case .bluetooth: ConnectionKind.bluetooth.title
        }
    }

    func allows(_ kind: ConnectionKind) -> Bool {
        self == .auto || rawValue == kind.rawValue
    }
}

/// Reads the active layer through the Keychron Launcher raw HID interface
/// (usage page 0xFF60, usage 0x61). Keychron's ZMK firmware answers command 0xA3
/// with the highest active layer, so momentary Fn layers show up too.
///
/// Raw HID works over the USB cable and the 2.4 GHz dongle. Over Bluetooth the
/// firmware has no raw HID channel, so we can only report that it's connected.
@MainActor
final class KeyboardMonitor: ObservableObject {
    enum Status: Equatable {
        case searching
        case connected(ConnectionKind)
        case noReply(ConnectionKind)
        case bluetoothOnly
        /// Another app (e.g. Keychron Launcher in a browser) has the raw HID channel open.
        case paused(otherApp: String)
    }

    @Published private(set) var status: Status = .searching
    @Published private(set) var layer: Int?
    @Published private(set) var layerCount: Int?
    @Published private(set) var firmware: String?
    @Published private(set) var deviceName: String?

    var isConnected: Bool {
        if case .connected = status { true } else { false }
    }

    var preference: ConnectionPreference = .auto {
        didSet { refreshStatus() }
    }
    var pollInterval: Duration = .milliseconds(250)

    private enum Command {
        static let getLayerCount: UInt8 = 0x11
        static let getFirmwareVersion: UInt8 = 0xA1
        static let getActiveLayer: UInt8 = 0xA3
    }

    private static let vendorID = 0x3434
    private static let rawUsagePage = 0xFF60
    private static let rawUsage = 0x61

    private final class Endpoint {
        let device: IOHIDDevice
        let kind: ConnectionKind
        let name: String
        let outputSize: Int
        let inputBuffer: UnsafeMutablePointer<UInt8>
        let inputSize: Int
        var layer: Int?
        var lastReply: ContinuousClock.Instant?

        init(device: IOHIDDevice, kind: ConnectionKind, name: String) {
            self.device = device
            self.kind = kind
            self.name = name
            outputSize = max(device.intProperty(kIOHIDMaxOutputReportSizeKey) ?? 32, 32)
            inputSize = max(device.intProperty(kIOHIDMaxInputReportSizeKey) ?? 32, 32)
            inputBuffer = .allocate(capacity: inputSize)
        }

        deinit { inputBuffer.deallocate() }
    }

    private struct PendingRequest {
        let id: UUID
        let header: [UInt8]
        let continuation: CheckedContinuation<[UInt8]?, Never>
    }

    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private var endpoints: [ObjectIdentifier: Endpoint] = [:]
    private var bluetoothKeyboards: [ObjectIdentifier: String] = [:]
    private var activeEndpoint: Endpoint?
    private var pendingRequests: [PendingRequest] = []
    private var lastPollAt: ContinuousClock.Instant?
    private var otherApp: String?
    private var pollTask: Task<Void, Never>?

    /// How long the last answer stays valid. Generous on purpose: when Keychron Launcher
    /// connects it floods the 2.4 GHz link with keymap reads and our polls go unanswered
    /// for a few seconds, which shouldn't blank the indicator.
    private var freshness: Duration { max(.seconds(4), pollInterval * 4) }

    func start() {
        guard pollTask == nil else { return }

        // Watch every Keychron device plus every Bluetooth HID device: over Bluetooth
        // the keyboard may not report Keychron's vendor ID, so those are filtered by name.
        let matching: [[String: Any]] = [
            [kIOHIDVendorIDKey: Self.vendorID],
            [kIOHIDTransportKey: "Bluetooth Low Energy"],
            [kIOHIDTransportKey: "Bluetooth"],
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            let bytesOfMonitor = context!
            MainActor.assumeIsolated {
                Unmanaged<KeyboardMonitor>.fromOpaque(bytesOfMonitor).takeUnretainedValue().deviceAdded(device)
            }
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            let bytesOfMonitor = context!
            MainActor.assumeIsolated {
                Unmanaged<KeyboardMonitor>.fromOpaque(bytesOfMonitor).takeUnretainedValue().deviceRemoved(device)
            }
        }, context)
        // The manager itself is never opened: that would open keyboard interfaces too and
        // trigger the Input Monitoring prompt. Only the raw HID interfaces get opened.
        // Common modes, so replies keep arriving while a menu is open (event tracking mode).
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)

        pollTask = Task {
            while !Task.isCancelled {
                poll()
                try? await Task.sleep(for: pollInterval)
            }
        }
    }

    // MARK: - Devices

    private func deviceAdded(_ device: IOHIDDevice) {
        let id = ObjectIdentifier(device)
        let transport = (device.stringProperty(kIOHIDTransportKey) ?? "").lowercased()
        let name = device.stringProperty(kIOHIDProductKey) ?? "Keychron keyboard"
        let isKeychron = device.intProperty(kIOHIDVendorIDKey) == Self.vendorID
            || name.lowercased().contains("keychron")
        guard isKeychron else { return }

        let isRaw = device.intProperty(kIOHIDPrimaryUsagePageKey) == Self.rawUsagePage
            && device.intProperty(kIOHIDPrimaryUsageKey) == Self.rawUsage

        if !isRaw {
            let isKeyboard = device.intProperty(kIOHIDPrimaryUsagePageKey) == kHIDPage_GenericDesktop
                && device.intProperty(kIOHIDPrimaryUsageKey) == kHIDUsage_GD_Keyboard
            if transport.contains("bluetooth") && isKeyboard {
                bluetoothKeyboards[id] = name
                refreshStatus()
            }
            return
        }

        guard endpoints[id] == nil,
              IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess
        else { return }

        let kind: ConnectionKind
        if transport.contains("bluetooth") {
            kind = .bluetooth
        } else if name.lowercased().contains("link") || name.lowercased().contains("receiver") {
            kind = .dongle
        } else {
            kind = .usb
        }

        let endpoint = Endpoint(device: device, kind: kind, name: name)
        endpoints[id] = endpoint

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(
            device, endpoint.inputBuffer, endpoint.inputSize,
            { context, _, sender, _, _, report, length in
                let bytes = Array(UnsafeBufferPointer(start: report, count: length))
                guard let context, let sender else { return }
                let device = Unmanaged<IOHIDDevice>.fromOpaque(sender).takeUnretainedValue()
                MainActor.assumeIsolated {
                    Unmanaged<KeyboardMonitor>.fromOpaque(context).takeUnretainedValue()
                        .received(bytes, from: device)
                }
            }, context)

        send(Command.getActiveLayer, to: endpoint)
    }

    private func deviceRemoved(_ device: IOHIDDevice) {
        let id = ObjectIdentifier(device)
        if let endpoint = endpoints.removeValue(forKey: id) {
            IOHIDDeviceRegisterInputReportCallback(device, endpoint.inputBuffer, endpoint.inputSize, nil, nil)
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        bluetoothKeyboards.removeValue(forKey: id)
        refreshStatus()
    }

    // MARK: - Protocol

    private func poll() {
        otherApp = endpoints.values.lazy.compactMap(Self.otherApp(using:)).first
        // The keyboard drops a report that arrives while it's still handling another,
        // so the layer poll waits while a request is out, and stops while another app
        // talks to the keyboard: Launcher would get our replies and lose its own.
        if otherApp == nil, pendingRequests.isEmpty {
            for endpoint in endpoints.values where preference.allows(endpoint.kind) {
                send(Command.getActiveLayer, to: endpoint)
            }
            lastPollAt = .now
        }
        refreshStatus()
    }

    /// Sends `bytes` to the connected keyboard and waits for the reply, which echoes the
    /// first `headerLength` bytes of the request; resends when it gets lost. Nil when not
    /// connected or never answered.
    func request(_ bytes: [UInt8], headerLength: Int = 3, attempts: Int = 3,
                 timeout: Duration = .milliseconds(200)) async -> [UInt8]? {
        let hex = bytes.prefix(5).map { String(format: "%02x", $0) }.joined(separator: " ")
        for attempt in 1...attempts {
            // Give a layer poll that just went out time to be answered.
            while let lastPollAt, ContinuousClock.now - lastPollAt < .milliseconds(15) {
                try? await Task.sleep(for: .milliseconds(5))
            }
            guard let endpoint = activeEndpoint else {
                log.error("request \(hex, privacy: .public): no keyboard")
                return nil
            }
            if let reply = await exchange(bytes, headerLength: headerLength, timeout: timeout, with: endpoint) {
                return reply
            }
            log.error("request \(hex, privacy: .public): no reply (attempt \(attempt) of \(attempts))")
        }
        return nil
    }

    private func exchange(_ bytes: [UInt8], headerLength: Int, timeout: Duration,
                          with endpoint: Endpoint) async -> [UInt8]? {
        let id = UUID()
        return await withCheckedContinuation { continuation in
            pendingRequests.append(PendingRequest(id: id, header: Array(bytes.prefix(headerLength)),
                                                  continuation: continuation))
            send(bytes, to: endpoint)
            Task {
                try? await Task.sleep(for: timeout)
                finishRequest(id, with: nil)
            }
        }
    }

    /// Waits out a short silence, e.g. while Keychron Launcher keeps the link busy.
    func waitUntilConnected(timeout: Duration = .seconds(5)) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !isConnected {
            guard ContinuousClock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return true
    }

    /// Sends without waiting for the reply; for when the app is about to quit.
    func sendNow(_ bytes: [UInt8]) {
        if let activeEndpoint { send(bytes, to: activeEndpoint) }
    }

    /// False when the request was already answered.
    @discardableResult
    private func finishRequest(_ id: UUID, with reply: [UInt8]?) -> Bool {
        guard let index = pendingRequests.firstIndex(where: { $0.id == id }) else { return false }
        pendingRequests.remove(at: index).continuation.resume(returning: reply)
        return true
    }

    private func send(_ command: UInt8, to endpoint: Endpoint) {
        send([command], to: endpoint)
    }

    private func send(_ bytes: [UInt8], to endpoint: Endpoint) {
        var packet = [UInt8](repeating: 0, count: endpoint.outputSize)
        packet.replaceSubrange(0..<min(bytes.count, packet.count), with: bytes.prefix(packet.count))
        let result = IOHIDDeviceSetReport(endpoint.device, kIOHIDReportTypeOutput, 0, packet, packet.count)
        if result != kIOReturnSuccess {
            log.error("send \(String(format: "%02x", packet[0]), privacy: .public) failed: \(String(format: "0x%08x", result), privacy: .public)")
        }
    }

    /// Replies echo the request, so answers to Keychron Launcher's own polling
    /// (if it's open in a browser) land here too — they mean the same thing.
    private func received(_ bytes: [UInt8], from device: IOHIDDevice) {
        guard let endpoint = endpoints[ObjectIdentifier(device)], bytes.count >= 2 else { return }

        if let pending = pendingRequests.first(where: { bytes.starts(with: $0.header) }) {
            finishRequest(pending.id, with: bytes)
        }

        switch bytes[0] {
        case Command.getActiveLayer where bytes[1] < 32:
            let wasSilent = !isFresh(endpoint)
            if endpoint.layer != Int(bytes[1]) {
                log.notice("layer \(bytes[1]) via \(endpoint.kind.rawValue, privacy: .public)")
            }
            endpoint.layer = Int(bytes[1])
            endpoint.lastReply = .now
            // While paused this is a reply to the other app's own poll; send nothing back.
            if wasSilent && otherApp == nil {
                send(Command.getLayerCount, to: endpoint)
                send(Command.getFirmwareVersion, to: endpoint)
            }
        case Command.getLayerCount where (1...32).contains(bytes[1]):
            layerCount = Int(bytes[1])
        case Command.getFirmwareVersion:
            let text = bytes.dropFirst().prefix { $0 != 0 }
            firmware = String(decoding: text, as: UTF8.self)
        default:
            return
        }
        refreshStatus()
    }

    /// The name of another process that has this raw HID interface open, from the
    /// I/O Registry's user clients ("pid 123, Brave Browser").
    private static func otherApp(using endpoint: Endpoint) -> String? {
        var children = io_iterator_t()
        guard IORegistryEntryGetChildIterator(IOHIDDeviceGetService(endpoint.device), kIOServicePlane,
                                              &children) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(children) }
        let ownPrefix = "pid \(getpid()),"
        while case let child = IOIteratorNext(children), child != 0 {
            defer { IOObjectRelease(child) }
            guard let creator = IORegistryEntryCreateCFProperty(child, "IOUserClientCreator" as CFString,
                                                                kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? String,
                !creator.hasPrefix(ownPrefix) else { continue }
            return creator.split(separator: ",", maxSplits: 1).last
                .map { $0.trimmingCharacters(in: .whitespaces) } ?? creator
        }
        return nil
    }

    private func isFresh(_ endpoint: Endpoint) -> Bool {
        guard let lastReply = endpoint.lastReply else { return false }
        return ContinuousClock.now - lastReply < freshness
    }

    private func refreshStatus() {
        let allowed = endpoints.values.filter { preference.allows($0.kind) }
        let responding = allowed.filter(isFresh).max { a, b in
            // Prefer the cable when several connections answer, then the most recent reply.
            if (a.kind == .usb) != (b.kind == .usb) { return b.kind == .usb }
            return a.lastReply! < b.lastReply!
        }

        // Paused: no requests, but the layer can still follow replies to the other app's polls.
        activeEndpoint = otherApp == nil ? responding : nil
        let newStatus: Status
        if let otherApp, !allowed.isEmpty {
            newStatus = .paused(otherApp: otherApp)
            setIfChanged(\.layer, responding?.layer)
            setIfChanged(\.deviceName, (responding ?? allowed.first)?.name)
        } else if let responding {
            newStatus = .connected(responding.kind)
            setIfChanged(\.layer, responding.layer)
            setIfChanged(\.deviceName, responding.name)
        } else {
            if !bluetoothKeyboards.isEmpty && preference.allows(.bluetooth) {
                newStatus = .bluetoothOnly
                setIfChanged(\.deviceName, bluetoothKeyboards.values.first)
            } else if let endpoint = allowed.first {
                newStatus = .noReply(endpoint.kind)
                setIfChanged(\.deviceName, endpoint.name)
            } else {
                newStatus = .searching
                setIfChanged(\.deviceName, nil)
            }
            setIfChanged(\.layer, nil)
        }
        if status != newStatus {
            log.notice("status: \(String(describing: newStatus), privacy: .public) (\(self.deviceName ?? "-", privacy: .public))")
        }
        setIfChanged(\.status, newStatus)
    }

    /// Avoids publishing (and redrawing the menu bar) on every poll when nothing changed.
    private func setIfChanged<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<KeyboardMonitor, T>, _ value: T) {
        if self[keyPath: keyPath] != value { self[keyPath: keyPath] = value }
    }
}

private extension IOHIDDevice {
    func intProperty(_ key: String) -> Int? {
        IOHIDDeviceGetProperty(self, key as CFString) as? Int
    }

    func stringProperty(_ key: String) -> String? {
        IOHIDDeviceGetProperty(self, key as CFString) as? String
    }
}
