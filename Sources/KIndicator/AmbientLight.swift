import Foundation
import IOKit
import KIndicatorCore
import OSLog

private let log = Logger(subsystem: "local.kindicator", category: "room light")

/// The room's light from the Mac's ambient light sensor, beside the camera of MacBooks
/// and iMacs. Asks once a second while running; needs no permission.
///
/// The sensor's driver publishes `CurrentLux` in the IORegistry, but changes it only in
/// coarse steps (3, then 5 lux). Live readings come from IOKit's private HID event system,
/// the way display brightness apps read the sensor; the registry is the fallback.
@MainActor
final class AmbientLightSensor: ObservableObject {
    /// The light the keyboard's brightness follows, in lux (see `RoomLightPlan.light`);
    /// nil while not running, or while the lid is closed over the sensor.
    @Published private(set) var lux: Double?
    @Published private(set) var lidClosed = false

    /// Whether this Mac has a sensor; Macs without a built-in display don't.
    static let isAvailable = {
        let service = sensorService()
        defer { IOObjectRelease(service) }
        return service != 0
    }()

    var isRunning = false {
        didSet {
            guard isRunning != oldValue else { return }
            ticker?.cancel()
            ticker = nil
            readings = []
            lux = nil
            guard isRunning, Self.isAvailable else { return }
            log.notice("reading the sensor through \(self.reader == nil ? "the IORegistry" : "HID events", privacy: .public)")
            ticker = Task { [weak self] in
                while !Task.isCancelled {
                    self?.read()
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        }
    }

    private var readings: [Double] = []
    private var ticker: Task<Void, Never>?
    private lazy var reader = HIDLightReader()
    private lazy var service = Self.sensorService()
    private lazy var powerDomain = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))

    private func read() {
        let closed = (IORegistryEntryCreateCFProperty(powerDomain, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Bool) ?? false
        if closed != lidClosed {
            log.notice("lid \(closed ? "closed: sensor covered" : "open", privacy: .public)")
            lidClosed = closed
        }
        guard !closed else {
            readings = []
            lux = nil
            return
        }
        guard let reading = reader?.lux() ?? registryLux() else { return }
        readings = (readings + [reading]).suffix(RoomLightPlan.readings)
        guard let median = RoomLightPlan.median(readings) else { return }
        let light = RoomLightPlan.light(median, current: lux)
        if light != lux {
            log.notice("room light \(light, format: .fixed(precision: 0), privacy: .public) lux")
            lux = light
        }
    }

    private func registryLux() -> Double? {
        (IORegistryEntryCreateCFProperty(service, "CurrentLux" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? NSNumber)?.doubleValue
    }

    /// The sensor's HID service: vendor usage page 0xFF00, usage 4.
    private static func sensorService() -> io_service_t {
        let matching = IOServiceMatching("IOHIDEventService") as NSMutableDictionary
        matching["IOPropertyMatch"] = HIDLightReader.usage
        return IOServiceGetMatchingService(kIOMainPortDefault, matching)
    }
}

/// Reads the sensor through IOKit's private HID event system: an ambient light event from
/// the sensor's HID service. The functions are found with dlsym, so without them there's
/// just no reader.
private final class HIDLightReader {
    static var usage: NSDictionary { ["PrimaryUsagePage": 0xFF00, "PrimaryUsage": 4] }

    private typealias ClientCreate = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    private typealias SetMatching = @convention(c) (AnyObject, CFDictionary) -> Void
    private typealias CopyServices = @convention(c) (AnyObject) -> Unmanaged<CFArray>?
    private typealias CopyEvent = @convention(c) (AnyObject, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
    private typealias GetFloatValue = @convention(c) (AnyObject, Int32) -> Double

    /// `kIOHIDEventTypeAmbientLightSensor`; its level field is the type shifted by 16.
    private static let ambientLight: Int64 = 12

    private let client: AnyObject
    private let service: AnyObject
    private let copyEvent: CopyEvent
    private let getFloatValue: GetFloatValue

    init?() {
        guard let create = Self.function("IOHIDEventSystemClientCreate", as: ClientCreate.self),
              let setMatching = Self.function("IOHIDEventSystemClientSetMatching", as: SetMatching.self),
              let copyServices = Self.function("IOHIDEventSystemClientCopyServices", as: CopyServices.self),
              let copyEvent = Self.function("IOHIDServiceClientCopyEvent", as: CopyEvent.self),
              let getFloatValue = Self.function("IOHIDEventGetFloatValue", as: GetFloatValue.self),
              let client = create(kCFAllocatorDefault)?.takeRetainedValue()
        else { return nil }
        setMatching(client, Self.usage)
        guard let service = (copyServices(client)?.takeRetainedValue() as? [AnyObject])?.first else { return nil }
        self.client = client
        self.service = service
        self.copyEvent = copyEvent
        self.getFloatValue = getFloatValue
    }

    func lux() -> Double? {
        guard let event = copyEvent(service, Self.ambientLight, 0, 0)?.takeRetainedValue() else { return nil }
        return getFloatValue(event, Int32(Self.ambientLight << 16))
    }

    private static func function<T>(_ name: String, as type: T.Type) -> T? {
        dlsym(UnsafeMutableRawPointer(bitPattern: -2), name).map { unsafeBitCast($0, to: type) }  // RTLD_DEFAULT
    }
}
