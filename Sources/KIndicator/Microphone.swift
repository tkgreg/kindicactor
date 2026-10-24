import AppKit
import CoreAudio
import OSLog

private let log = Logger(subsystem: "local.kindicator", category: "microphone")

/// Which apps are recording from a microphone, from Core Audio's process objects. Needs
/// no permission: KIndicator only asks whether a process is recording, never records.
///
/// Listening on the processes themselves never fired on macOS 26, but input devices report
/// when they start running. So devices are watched, and while one runs the processes are
/// checked twice a second (a check takes about 2.5 ms).
@MainActor
final class MicrophoneMonitor: ObservableObject {
    /// Names of the apps recording now; empty while no microphone is in use.
    @Published private(set) var recordingApps: [String] = []

    var inUse: Bool { !recordingApps.isEmpty }

    /// Input devices whose running state is watched.
    private var watched: Set<AudioObjectID> = []
    private var running: [AudioObjectID] = []
    private var recheck: Task<Void, Never>?

    func start() {
        // Devices come and go: headsets, an iPhone used as a microphone.
        var address = Self.address(kAudioHardwarePropertyDevices)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.update() }
        }
        update()
    }

    private func update() {
        let devices = Self.objects(kAudioHardwarePropertyDevices).filter(Self.hasInput)
        for device in devices where !watched.contains(device) {
            var address = Self.address(kAudioDevicePropertyDeviceIsRunningSomewhere)
            AudioObjectAddPropertyListenerBlock(device, &address, .main) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.update() }
            }
        }
        watched = Set(devices)

        // A device also runs while it only plays sound (a headset), so ask the processes.
        let running = devices.filter(Self.isRunning)
        if running != self.running {
            log.notice("input devices running: \(running.isEmpty ? "none" : running.map(Self.name(ofDevice:)).joined(separator: ", "), privacy: .public)")
            self.running = running
        }
        let apps = running.isEmpty ? [] : Self.objects(kAudioHardwarePropertyProcessObjectList)
            .filter(Self.isRecording).map(Self.name(ofProcess:))
        if apps != recordingApps {
            log.notice("recording: \(apps.isEmpty ? "none" : apps.joined(separator: ", "), privacy: .public)")
            recordingApps = apps
        }

        recheck?.cancel()
        recheck = running.isEmpty ? nil : Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.update()
        }
    }

    private static func objects(_ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = address(selector)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr else { return [] }
        return objects
    }

    private static func hasInput(_ device: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                 mScope: kAudioDevicePropertyScopeInput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func isRunning(_ device: AudioObjectID) -> Bool {
        flag(kAudioDevicePropertyDeviceIsRunningSomewhere, of: device)
    }

    private static func isRecording(_ process: AudioObjectID) -> Bool {
        flag(kAudioProcessPropertyIsRunningInput, of: process)
    }

    private static func flag(_ selector: AudioObjectPropertySelector, of object: AudioObjectID) -> Bool {
        var address = address(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr && value != 0
    }

    /// The app's name, else its bundle ID ("com.apple.WebKit.GPU" for a page in Safari).
    private static func name(ofProcess process: AudioObjectID) -> String {
        var address = address(kAudioProcessPropertyPID)
        var pid: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        if AudioObjectGetPropertyData(process, &address, 0, nil, &size, &pid) == noErr,
           let name = NSRunningApplication(processIdentifier: pid)?.localizedName {
            return name
        }
        return string(kAudioProcessPropertyBundleID, of: process) ?? (pid != 0 ? "pid \(pid)" : "process \(process)")
    }

    private static func name(ofDevice device: AudioObjectID) -> String {
        string(kAudioObjectPropertyName, of: device) ?? "device \(device)"
    }

    private static func string(_ selector: AudioObjectPropertySelector, of object: AudioObjectID) -> String? {
        var address = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr,
              let string = value?.takeRetainedValue() as String?, !string.isEmpty else { return nil }
        return string
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }
}
