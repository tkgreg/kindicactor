import AppKit
import ImageIO
import KIndicatorCore
import OSLog
import UniformTypeIdentifiers

private let log = Logger(subsystem: "local.kindicator", category: "command-apps")

/// A command app found in ~/Applications.
struct InstalledCommandApp: Identifiable {
    var app: CommandApp
    var url: URL

    var id: String { app.id }
}

/// Writes command apps into ~/Applications and finds them there again. The bundles are the
/// only record, so an app thrown away in the Finder is simply gone from the list.
@MainActor
final class CommandAppStore: ObservableObject {
    static let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")

    @Published private(set) var apps: [InstalledCommandApp] = []
    /// The user hasn't let KIndicator control Finder, so Get Info doesn't show the comments.
    @Published private(set) var finderCommentsBlocked = false

    enum SaveError: LocalizedError {
        case hostMissing
        case nameTaken(String)
        case signingFailed(String)

        var errorDescription: String? {
            switch self {
            case .hostMissing: "CommandHost is missing from KIndicator.app."
            case .nameTaken(let name): "~/Applications already has an app named “\(name)”."
            case .signingFailed(let output): "Couldn't sign the app: \(output)"
            }
        }
    }

    func reload() {
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: nil)) ?? []
        apps = urls.filter { $0.pathExtension == "app" }
            .compactMap { url in
                let plist = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist")) as? [String: Any]
                return plist.flatMap(CommandApp.init(infoPlist:)).map { InstalledCommandApp(app: $0, url: url) }
            }
            .sorted { $0.app.name.localizedStandardCompare($1.app.name) == .orderedAscending }
    }

    /// Writes the app's bundle, replacing `existing` (which may have another name), and returns
    /// where it is. The bundle is built aside and moved in whole, so an app that's open keeps
    /// running from the old files.
    @discardableResult
    func save(_ app: CommandApp, replacing existing: URL?) throws -> URL {
        guard let host = Bundle.main.url(forAuxiliaryExecutable: "CommandHost") else { throw SaveError.hostMissing }
        let fm = FileManager.default
        let destination = Self.folder.appendingPathComponent(app.fileName + ".app")
        if destination != existing, fm.fileExists(atPath: destination.path) {
            throw SaveError.nameTaken(app.fileName)
        }

        try fm.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        let staging = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: Self.folder,
                                 create: true)
        defer { try? fm.removeItem(at: staging) }
        let bundle = staging.appendingPathComponent(destination.lastPathComponent)
        let contents = bundle.appendingPathComponent("Contents")
        try fm.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        try fm.createDirectory(at: contents.appendingPathComponent("Resources"), withIntermediateDirectories: true)

        // Read and written rather than copied, so no quarantine flag comes along from KIndicator.app.
        let executable = contents.appendingPathComponent("MacOS/\(app.fileName)")
        try Data(contentsOf: host).write(to: executable)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let plist = try PropertyListSerialization.data(
            fromPropertyList: app.infoPlist(executable: app.fileName, version: version), format: .xml, options: 0)
        try plist.write(to: contents.appendingPathComponent("Info.plist"))
        try CommandAppIcon.writeICNS(for: app, to: contents.appendingPathComponent("Resources/AppIcon.icns"))
        try Self.signAdHoc(bundle)

        if let existing, fm.fileExists(atPath: existing.path) {
            if existing == destination {
                _ = try fm.replaceItemAt(destination, withItemAt: bundle)
            } else {
                try fm.moveItem(at: bundle, to: destination)
                try fm.removeItem(at: existing)
            }
        } else {
            try fm.moveItem(at: bundle, to: destination)
        }
        Self.setFinderComment(app.comment, on: destination)
        // Finder only when there's something to show or to clear, so making an app without a
        // comment doesn't ask for permission to control Finder.
        let previous = apps.first { $0.url == existing }?.app.comment ?? ""
        if !app.comment.isEmpty || !previous.isEmpty {
            finderCommentsBlocked = !Self.askFinderToSetComment(app.comment, on: destination)
        }
        // So Spotlight, Launchpad and the Dock see the new name and icon now.
        LSRegisterURL(destination as CFURL, true)
        log.notice("saved \(destination.path, privacy: .public)")
        reload()
        return destination
    }

    func moveToTrash(_ installed: InstalledCommandApp) throws {
        try FileManager.default.trashItem(at: installed.url, resultingItemURL: nil)
        reload()
    }

    /// Writes the comment where the Finder keeps it, as an attribute Spotlight indexes; set on the
    /// bundle once it's in place, as the signature doesn't cover it.
    private static func setFinderComment(_ comment: String, on url: URL) {
        let name = "com.apple.metadata:kMDItemFinderComment"
        let comment = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !comment.isEmpty else {
            removexattr(url.path, name, 0)
            return
        }
        guard let data = try? PropertyListSerialization.data(fromPropertyList: comment, format: .binary, options: 0)
        else { return }
        let status = data.withUnsafeBytes { setxattr(url.path, name, $0.baseAddress, data.count, 0, 0) }
        if status != 0 {
            log.error("can't set the Finder comment of \(url.path, privacy: .public): \(errno)")
        }
    }

    /// Get Info shows the comment kept in the folder's .DS_Store, not the attribute, and only Finder
    /// writes that. macOS asks once whether KIndicator may control Finder; false if it may not.
    /// Spotlight finds the app by the attribute either way.
    private static func askFinderToSetComment(_ comment: String, on url: URL) -> Bool {
        func quoted(_ text: String) -> String {
            "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        let source = "tell application \"Finder\" to set comment of (POSIX file \(quoted(url.path)) as alias) to \(quoted(comment))"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        guard let error else { return true }
        log.error("Finder didn't set the comment: \(error, privacy: .public)")
        // errAEEventNotPermitted: not allowed in Privacy & Security › Automation.
        return error[NSAppleScript.errorNumber] as? Int != -1743
    }

    /// Apple silicon runs only signed code. An ad-hoc signature, made here, needs no certificate,
    /// and an app made on this Mac isn't quarantined, so Gatekeeper doesn't ask about it either.
    private static func signAdHoc(_ bundle: URL) throws {
        let codesign = Process()
        codesign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        codesign.arguments = ["--force", "--sign", "-", bundle.path]
        let output = Pipe()
        codesign.standardError = output
        try codesign.run()
        codesign.waitUntilExit()
        guard codesign.terminationStatus == 0 else {
            let message = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw SaveError.signingFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}

/// A command app's icon: its SF Symbol or letters in white on a tile of its tint.
enum CommandAppIcon {
    private static func colors(_ tint: CommandApp.Tint) -> (top: UInt32, bottom: UInt32) {
        switch tint {
        case .graphite: (0x4A4F5C, 0x1C1F26)
        case .blue: (0x4A8DF8, 0x1D4FC4)
        case .green: (0x3CC36B, 0x13804A)
        case .orange: (0xFFA33A, 0xE0600F)
        case .red: (0xFF5F57, 0xC0231C)
        case .purple: (0xB57BF2, 0x6A35C2)
        }
    }

    private static func color(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    /// For the settings page.
    static func image(for app: CommandApp, size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            draw(app, in: rect)
            return true
        }
    }

    static func writeICNS(for app: CommandApp, to url: URL) throws {
        let sizes = [16, 32, 64, 128, 256, 512, 1024]
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.icns.identifier as CFString,
                                                                sizes.count, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        for size in sizes {
            guard let image = bitmap(app, pixels: size) else { throw CocoaError(.fileWriteUnknown) }
            CGImageDestinationAddImage(destination, image, nil)
        }
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }

    private static func bitmap(_ app: CommandApp, pixels: Int) -> CGImage? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        draw(app, in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage
    }

    /// The tile sits on the macOS icon grid: 824 of 1024 points, with room for its shadow.
    private static func draw(_ app: CommandApp, in rect: NSRect) {
        let scale = rect.width / 1024
        let tile = NSRect(x: 100 * scale, y: 100 * scale, width: 824 * scale, height: 824 * scale)
        let shape = NSBezierPath(roundedRect: tile, xRadius: 185 * scale, yRadius: 185 * scale)
        let colors = colors(app.tint)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowOffset = NSSize(width: 0, height: -10 * scale)
        shadow.shadowBlurRadius = 24 * scale
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadow.set()
        color(colors.bottom).setFill()
        shape.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGradient(starting: color(colors.top), ending: color(colors.bottom))?.draw(in: shape, angle: -90)

        if let symbol = NSImage(systemSymbolName: app.icon, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 400 * scale, weight: .medium)
                .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))) {
            // Fit the symbol's longer side to 56% of the tile.
            let fit = tile.width * 0.56 / max(symbol.size.width, symbol.size.height)
            let size = NSSize(width: symbol.size.width * fit, height: symbol.size.height * fit)
            symbol.draw(in: NSRect(x: tile.midX - size.width / 2, y: tile.midY - size.height / 2,
                                   width: size.width, height: size.height))
            return
        }

        let text = String(app.icon.trimmingCharacters(in: .whitespaces).prefix(3))
        let font = NSFont.systemFont(ofSize: (text.count <= 1 ? 480 : text.count == 2 ? 360 : 270) * scale,
                                     weight: .semibold)
        let letters = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.white])
        // Centre the ink, not the advance width, so side bearings don't skew it.
        let ink = CTLineGetImageBounds(CTLineCreateWithAttributedString(letters), nil)
        letters.draw(at: NSPoint(x: tile.midX - ink.midX, y: tile.midY - font.capHeight / 2 + font.descender))
    }
}
