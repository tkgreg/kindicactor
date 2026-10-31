import AppKit
import Carbon
import KIndicatorCore
import SwiftUI

/// Click, then press a shortcut; Escape cancels.
struct HotkeyRecorder: View {
    @Binding var hotkey: Hotkey?
    @State private var capture = ShortcutCapture()

    var body: some View {
        HStack(spacing: 4) {
            Button {
                capture.isActive ? capture.stop() : start()
            } label: {
                Text(capture.isActive ? "Type shortcut…" : hotkey?.display ?? "Record Shortcut")
                    .frame(width: 116)
            }
            // Hidden rather than removed so rows stay aligned.
            Button {
                hotkey = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Clear shortcut")
            .opacity(hotkey == nil || capture.isActive ? 0 : 1)
            .disabled(hotkey == nil || capture.isActive)
        }
        .onDisappear(perform: capture.stop)
    }

    private func start() {
        capture.start { recorded in
            if let recorded { hotkey = recorded }
        }
    }
}

/// Takes the next key pressed in KIndicator's windows as a shortcut; Escape cancels. Global
/// hotkeys are off meanwhile, so pressing one records it instead of running it.
@MainActor
@Observable
final class ShortcutCapture {
    private(set) var isActive = false
    @ObservationIgnored private var monitor: Any?

    /// `done` gets the shortcut, or nil when cancelled. `allowsPlainKeys` takes a key without
    /// modifiers too, for a shortcut KIndicator presses.
    func start(allowsPlainKeys: Bool = false, done: @escaping (Hotkey?) -> Void) {
        stop()
        isActive = true
        HotkeyCenter.shared.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated {
                if Int(event.keyCode) == kVK_Escape {
                    self?.stop()
                    done(nil)
                } else if let recorded = Hotkey(event: event, allowsPlainKeys: allowsPlainKeys) {
                    self?.stop()
                    done(recorded)
                } else {
                    NSSound.beep()
                }
            }
            return nil
        }
    }

    func stop() {
        guard isActive else { return }
        isActive = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        HotkeyCenter.shared.resume()
    }
}
