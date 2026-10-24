import Foundation
import OSLog

private let log = Logger(subsystem: "local.kindicator", category: "updates")

/// Compares the running version with the latest release on GitHub. Only checks when asked.
@MainActor
final class UpdateChecker: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String, page: URL)
        case failed(String)
    }

    @Published private(set) var state = State.idle

    private static let latestRelease = URL(string: "https://api.github.com/repos/tkgreg/kindicactor/releases/latest")!

    /// The parts of GitHub's release JSON that matter here.
    private struct Release: Decodable {
        let tagName: String
        let htmlURL: URL

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }

        /// Tags are "v1.0.1".
        var version: String { tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName }
    }

    private struct HTTPError: LocalizedError {
        let status: Int

        var errorDescription: String? {
            switch status {
            case 403, 429: "GitHub's rate limit was reached; try again later."
            case 404: "No release found on GitHub."
            default: "GitHub answered with HTTP \(status)."
            }
        }
    }

    func check() {
        guard state != .checking else { return }
        state = .checking
        Task {
            do {
                let release = try await fetchLatest()
                // Numeric so that 1.0.10 counts as newer than 1.0.9.
                let isNewer = AppInfo.version.compare(release.version, options: .numeric) == .orderedAscending
                state = isNewer ? .available(version: release.version, page: release.htmlURL) : .upToDate
            } catch {
                log.error("update check failed: \(error)")
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func fetchLatest() async throws -> Release {
        var request = URLRequest(url: Self.latestRelease, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw HTTPError(status: http.statusCode)
        }
        return try JSONDecoder().decode(Release.self, from: data)
    }
}
