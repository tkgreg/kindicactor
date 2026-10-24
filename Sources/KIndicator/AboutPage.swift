import AppKit
import SwiftUI

/// Name, version and licence, read from the app bundle.
enum AppInfo {
    static let name = info("CFBundleName") ?? "KIndicator"
    static let version = info("CFBundleShortVersionString") ?? "–"
    static let build = info("CFBundleVersion")
    static let copyright = info("NSHumanReadableCopyright")
    static let repository = URL(string: "https://github.com/tkgreg/kindicactor")!

    /// The bundled LICENSE, one string per paragraph: the file's hard line breaks are
    /// joined so the text wraps to the window.
    static let licenseParagraphs: [String] = {
        guard let url = Bundle.main.url(forResource: "LICENSE", withExtension: nil),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.components(separatedBy: "\n\n")
            .map { $0.split(separator: "\n").joined(separator: " ") }
            .filter { !$0.isEmpty }
    }()

    private static func info(_ key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }
}

/// Settings › About: icon, version, update check and licence.
struct AboutPage: View {
    @ObservedObject var updates: UpdateChecker

    var body: some View {
        HStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 4) {
                Text(AppInfo.name)
                    .font(.title2.weight(.semibold))
                Text(versionLine)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if let copyright = AppInfo.copyright {
                    Text(copyright)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Link("View on GitHub", destination: AppInfo.repository)
                    .font(.callout)
                    .padding(.top, 2)
            }
        }
        SettingsGroup(title: "Updates") {
            SettingsRow(title: "Check for Updates", description: updateStatus) {
                updateControl
            }
        }
        SettingsGroup(title: "License") {
            if AppInfo.licenseParagraphs.isEmpty {
                Link("MIT License", destination: AppInfo.repository.appending(path: "blob/main/LICENSE"))
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(AppInfo.licenseParagraphs, id: \.self) { paragraph in
                        Text(paragraph)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            }
        }
    }

    private var versionLine: String {
        guard let build = AppInfo.build else { return "Version \(AppInfo.version)" }
        return "Version \(AppInfo.version) (\(build))"
    }

    private var updateStatus: String {
        switch updates.state {
        case .idle: "Looks for a newer release on GitHub."
        case .checking: "Checking GitHub…"
        case .upToDate: "You have the latest version."
        case .available(let version, _): "Version \(version) is available."
        case .failed(let message): "Couldn't check for updates: \(message)"
        }
    }

    @ViewBuilder private var updateControl: some View {
        switch updates.state {
        case .checking:
            ProgressView().controlSize(.small)
        case .available(_, let page):
            HStack {
                Button("Check Again") { updates.check() }
                Button("Download…") { NSWorkspace.shared.open(page) }
                    .keyboardShortcut(.defaultAction)
                    .help("Opens the release page on GitHub")
            }
        default:
            Button("Check Now") { updates.check() }
        }
    }
}
