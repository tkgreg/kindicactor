import Foundation
import Testing
@testable import KIndicatorCore

struct CommandAppTests {
    @Test func infoPlistRoundTrip() {
        let app = CommandApp(id: "abc", name: "Dev Server", command: "npm run dev", directory: "~/src/site",
                             icon: "DEV", tint: .orange, whenDone: .keepOpen, comment: "Runs the site locally.")
        let plist = app.infoPlist(executable: "Dev Server", version: "1.4.0")
        #expect(plist["CFBundleIdentifier"] as? String == "local.kindicator.command.abc")
        #expect(plist["CFBundleExecutable"] as? String == "Dev Server")
        #expect(CommandApp(infoPlist: plist) == app)
    }

    @Test func otherAppsAreNotCommandApps() {
        #expect(CommandApp(infoPlist: ["CFBundleIdentifier": "com.apple.Terminal", "KICommand": "ls"]) == nil)
        #expect(CommandApp(infoPlist: ["CFBundleIdentifier": "local.kindicator.command.abc"]) == nil)
    }

    @Test func missingSettingsGetDefaults() {
        var plist = CommandApp(id: "abc", name: "htop", command: "htop").infoPlist(executable: "htop", version: "1")
        for key in ["KIDirectory", "KIIcon", "KITint", "KIWhenDone", "KIComment"] { plist[key] = nil }
        plist["KITint"] = "teal"
        let app = CommandApp(infoPlist: plist)
        #expect(app?.directory == nil)
        #expect(app?.icon == "terminal")
        #expect(app?.tint == .graphite)
        #expect(app?.whenDone == .closeIfSucceeded)
        #expect(app?.comment == "")
    }

    @Test func commentsFromGeneratedDescriptions() {
        let comment = CommandApp.comment(summary: " Shows running processes and their CPU use. ",
                                         keywords: ["Task Manager", "system monitor", "task manager", "cpu", " ", "Processes"])
        #expect(comment == "Shows running processes and their CPU use.\ntask manager, system monitor")
        #expect(CommandApp.comment(summary: "Lists files.", keywords: ["files"]) == "Lists files.")
    }

    @Test func fileNames() {
        #expect(CommandApp(name: " htop ", command: "htop").fileName == "htop")
        #expect(CommandApp(name: "a/b:c", command: "ls").fileName == "a-b-c")
        #expect(CommandApp(name: "  ", command: "ls").fileName == "Command")
        #expect(CommandApp(name: ".hidden", command: "ls").fileName == "Command")
    }

    @Test func runsInALoginInteractiveShell() {
        #expect(CommandApp.shellArguments(for: "cd ~/src && make") == ["-l", "-i", "-c", "cd ~/src && make"])
    }
}
