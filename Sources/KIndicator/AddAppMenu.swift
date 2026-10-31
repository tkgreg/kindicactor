import AppKit
import KIndicatorCore
import SwiftUI

/// Adds an app: one that's running, or one chosen in the Applications folder.
struct AddAppMenu: View {
    /// Bundle IDs already added, left out of the menu.
    let added: Set<String>
    let add: (AppRef) -> Void

    var body: some View {
        let running = NSWorkspace.shared.runningApplications
            .filter { app in
                app.activationPolicy == .regular && app.bundleURL != nil
                    && app.bundleIdentifier.map { !added.contains($0) && $0 != Bundle.main.bundleIdentifier } == true
            }
            .sorted { ($0.localizedName ?? "").localizedStandardCompare($1.localizedName ?? "") == .orderedAscending }
        Menu("Add App") {
            ForEach(running, id: \.processIdentifier) { app in
                Button {
                    choose(app.bundleURL!)
                } label: {
                    Label {
                        Text(app.localizedName ?? app.bundleIdentifier ?? "")
                    } icon: {
                        Image(nsImage: AppIcon.small(app.icon ?? NSWorkspace.shared.icon(forFile: app.bundleURL!.path)))
                    }
                }
            }
            if !running.isEmpty { Divider() }
            Button("Choose App…", action: chooseApp)
        }
        .fixedSize()
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add"
        if panel.runModal() == .OK, let url = panel.url {
            choose(url)
        }
    }

    private func choose(_ url: URL) {
        guard let bundleID = Bundle(url: url)?.bundleIdentifier else { return NSSound.beep() }
        guard !added.contains(bundleID) else { return }
        let name = (FileManager.default.displayName(atPath: url.path) as NSString).deletingPathExtension
        add(AppRef(bundleID: bundleID, name: name, path: url.path))
    }
}

/// Apps' icons at the size of a row.
enum AppIcon {
    /// The app where it was added, else wherever it is now, else a generic one.
    static func small(path: String?, bundleID: String) -> NSImage {
        let path = path.flatMap { FileManager.default.fileExists(atPath: $0) ? $0 : nil }
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?.path
        return small(path.map(NSWorkspace.shared.icon(forFile:)) ?? NSWorkspace.shared.icon(for: .application))
    }

    static func small(_ icon: NSImage) -> NSImage {
        let copy = icon.copy() as! NSImage
        copy.size = NSSize(width: 16, height: 16)
        return copy
    }
}
