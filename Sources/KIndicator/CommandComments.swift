import Foundation
import KIndicatorCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Writes a command app's Finder comment from its name and command with Apple Intelligence, so
/// Spotlight finds the app by what it does, e.g. htop by "task manager". Only the model on this
/// Mac is used, never Private Cloud Compute, so the command never leaves the Mac.
enum CommandComments {
    enum Failure: LocalizedError {
        case unavailable
        case declined

        var errorDescription: String? {
            switch self {
            case .unavailable: "Apple Intelligence isn't available on this Mac."
            case .declined: "Apple Intelligence declined to describe this command. Write the comment yourself."
            }
        }
    }

    /// False before macOS 26, on Macs without Apple Intelligence, and while it's off or its model
    /// is still downloading.
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            return SystemLanguageModel.default.isAvailable
        }
        #endif
        return false
    }

    static func generate(name: String, command: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            return try await OnDevice.comment(name: name, command: command)
        }
        #endif
        throw Failure.unavailable
    }
}

#if canImport(FoundationModels)
@available(macOS 26, *)
private enum OnDevice {
    @Generable
    struct Description {
        @Guide(description: "One short sentence on what the program does for the user, in plain words.")
        var summary: String

        @Guide(description: "Lowercase words and short phrases, other than the summary's, that someone might type into Spotlight to find this app.",
               .count(5...10))
        var keywords: [String]
    }

    static func comment(name: String, command: String) async throws -> String {
        let session = LanguageModelSession(model: .default, instructions: """
            You describe Mac apps so that people find them with Spotlight. Each app runs one terminal \
            command in a window of its own; don't mention the terminal or the window. Say what the \
            program does for the user. For keywords, give what people would search for: other words \
            for the same thing, the program's full name, well-known apps that do the same, and its \
            category. Write in English.

            Example: an app named "Disk Usage" running "ncdu ~" gets the summary "Shows which \
            folders take up disk space, so you can delete what you don't need." and the keywords \
            disk space, storage, folder sizes, space analyzer, du, cleanup, daisydisk.
            """)
        do {
            let description = try await session.respond(to: "App name: \(name)\nCommand:\n\(command)",
                                                        generating: Description.self,
                                                        options: GenerationOptions(temperature: 0.3)).content
            return CommandApp.comment(summary: description.summary, keywords: description.keywords)
        } catch where isDeclined(error) {
            throw CommandComments.Failure.declined
        }
    }

    /// The model refused, or its guardrails stopped it; macOS 27 reports these as LanguageModelError.
    private static func isDeclined(_ error: any Error) -> Bool {
        if #available(macOS 27, *), let error = error as? LanguageModelError {
            switch error {
            case .guardrailViolation, .refusal: return true
            default: return false
            }
        }
        switch error as? LanguageModelSession.GenerationError {
        case .guardrailViolation, .refusal: return true
        default: return false
        }
    }
}
#endif
