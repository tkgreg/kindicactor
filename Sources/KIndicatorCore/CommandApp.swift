import Foundation

/// A shell command made into an app of its own: a window running the command, which Spotlight,
/// Launchpad, the Dock and launch actions open like any other app. KIndicator writes the app's
/// bundle; CommandHost, the program inside it, reads these settings back from its Info.plist.
package struct CommandApp: Equatable, Sendable {
    /// What the window does once the command ends, as Terminal's "When the shell exits".
    package enum WhenDone: String, CaseIterable, Sendable {
        case close, closeIfSucceeded, keepOpen

        package var title: String {
            switch self {
            case .close: "Close the window"
            case .closeIfSucceeded: "Close if it succeeded"
            case .keepOpen: "Keep the window open"
            }
        }
    }

    /// The icon's background.
    package enum Tint: String, CaseIterable, Sendable {
        case graphite, blue, green, orange, red, purple

        package var title: String { rawValue.capitalized }
    }

    /// Part of the bundle ID, so a renamed app keeps its window position and font size.
    package var id: String
    package var name: String
    /// A line for the user's shell, e.g. `htop` or `cd ~/src/site && npm run dev`.
    package var command: String
    /// Where the command starts; nil is the home folder. May start with `~`.
    package var directory: String?
    /// An SF Symbol name, otherwise up to three characters.
    package var icon: String
    package var tint: Tint
    package var whenDone: WhenDone
    /// The app's Finder comment, which Spotlight searches: what it does, in other words than its name.
    package var comment: String

    package init(id: String = UUID().uuidString.lowercased(), name: String, command: String,
                 directory: String? = nil, icon: String = "terminal", tint: Tint = .graphite,
                 whenDone: WhenDone = .closeIfSucceeded, comment: String = "") {
        self.id = id
        self.name = name
        self.command = command
        self.directory = directory
        self.icon = icon
        self.tint = tint
        self.whenDone = whenDone
        self.comment = comment
    }

    package static let bundleIDPrefix = "local.kindicator.command."

    private enum Key {
        static let command = "KICommand"
        static let directory = "KIDirectory"
        static let icon = "KIIcon"
        static let tint = "KITint"
        static let whenDone = "KIWhenDone"
        static let comment = "KIComment"
    }

    package var bundleID: String { Self.bundleIDPrefix + id }

    /// The name with the characters a file name can't have replaced; "Command" when blank.
    package var fileName: String {
        let name = name.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return name.isEmpty || name.hasPrefix(".") ? "Command" : name
    }

    /// The bundle's Info.plist. `executable` is the program's file name in Contents/MacOS.
    package func infoPlist(executable: String, version: String) -> [String: Any] {
        var plist: [String: Any] = [
            "CFBundleDevelopmentRegion": "en",
            "CFBundleExecutable": executable,
            "CFBundleIconFile": "AppIcon",
            "CFBundleIdentifier": bundleID,
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleName": name,
            "CFBundleDisplayName": name,
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": version,
            "CFBundleVersion": version,
            "LSMinimumSystemVersion": "15.0",
            "NSHighResolutionCapable": true,
            Key.command: command,
            Key.icon: icon,
            Key.tint: tint.rawValue,
            Key.whenDone: whenDone.rawValue,
            Key.comment: comment,
        ]
        plist[Key.directory] = directory
        return plist
    }

    /// Reads an app back from its Info.plist; nil for apps KIndicator didn't make.
    package init?(infoPlist: [String: Any]) {
        guard let bundleID = infoPlist["CFBundleIdentifier"] as? String, bundleID.hasPrefix(Self.bundleIDPrefix),
              let command = infoPlist[Key.command] as? String
        else { return nil }
        self.init(id: String(bundleID.dropFirst(Self.bundleIDPrefix.count)),
                  name: infoPlist["CFBundleName"] as? String ?? "Command",
                  command: command,
                  directory: infoPlist[Key.directory] as? String,
                  icon: infoPlist[Key.icon] as? String ?? "terminal",
                  tint: (infoPlist[Key.tint] as? String).flatMap(Tint.init) ?? .graphite,
                  whenDone: (infoPlist[Key.whenDone] as? String).flatMap(WhenDone.init) ?? .closeIfSucceeded,
                  comment: infoPlist[Key.comment] as? String ?? "")
    }

    /// A Finder comment from a generated description: the sentence, then on a line of its own the
    /// words to find the app by, without repeats or ones the sentence already has.
    package static func comment(summary: String, keywords: [String]) -> String {
        let summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        var seen = Set(summary.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
        let keywords = keywords
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        return keywords.isEmpty ? summary : "\(summary)\n\(keywords.joined(separator: ", "))"
    }

    /// Arguments for the user's shell, as Terminal starts it: a login shell, for the PATH set in
    /// .zprofile (e.g. Homebrew's), and interactive, for the one set in .zshrc (e.g. nvm's).
    package static func shellArguments(for command: String) -> [String] {
        ["-l", "-i", "-c", command]
    }
}
