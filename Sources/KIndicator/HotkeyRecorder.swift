import AppKit
import Carbon
import SwiftUI

/// Click, then press a shortcut; Escape cancels.
struct HotkeyRecorder: View {
    @Binding var hotkey: Hotkey?
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 4) {
            Button {
                isRecording ? stop() : start()
            } label: {
                Text(isRecording ? "Type shortcut…" : hotkey?.display ?? "Record Shortcut")
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
            .opacity(hotkey == nil || isRecording ? 0 : 1)
            .disabled(hotkey == nil || isRecording)
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        isRecording = true
        HotkeyCenter.shared.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated {
                if Int(event.keyCode) == kVK_Escape {
                    stop()
                } else if let recorded = Hotkey(event: event) {
                    hotkey = recorded
                    stop()
                } else {
                    NSSound.beep()
                }
            }
            return nil
        }
    }

    private func stop() {
        guard isRecording else { return }
        isRecording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        HotkeyCenter.shared.resume()
    }
}
