import Foundation
import FoundationModels

/// On-device generative features via Apple's Foundation Models (iOS 26).
///
/// Everything here runs locally — nothing about your baby ever leaves the device —
/// and degrades gracefully: `isAvailable` is false on hardware without Apple
/// Intelligence (or when the model is still downloading / disabled), and every
/// call returns nil rather than throwing so callers can simply hide the UI.
enum BabyIntelligence {
    /// Whether the on-device model is ready to use right now.
    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    // MARK: - Plain-English summary

    /// Generates a short, warm recap from a pre-computed stats digest.
    /// Returns nil if the model is unavailable or generation fails.
    static func summary(digest: String, babyName: String) async -> String? {
        guard isAvailable else { return nil }
        let session = LanguageModelSession(instructions: """
            You are a warm, concise assistant inside a baby-tracking app used by \
            two new parents. Given a digest of \(babyName)'s feeding, sleep, and \
            diaper stats, write 2–3 short sentences surfacing the most useful \
            patterns — feeding cadence, the longest sleep stretch, the busiest \
            feeding hour, anything notable or encouraging. Calm, plain tone. \
            Never give medical advice. No bullet lists, no headers.
            """)
        let response = try? await session.respond(to: digest)
        return response?.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Natural-language logging

    /// A single log entry extracted from free text. `kind` is one of
    /// "feed", "diaper", "sleepStart", "sleepEnd", or "unknown".
    @Generable
    struct ParsedLog {
        @Guide(description: "One of: feed, diaper, sleepStart, sleepEnd, unknown")
        var kind: String
        @Guide(description: "Bottle amount in fluid ounces if this is a feed, else null")
        var amountOz: Double?
        @Guide(description: "If a diaper, one of: wet, dirty, both; else null")
        var diaperType: String?
        @Guide(description: "How many minutes ago the event happened. 0 if it just happened or is unclear.")
        var minutesAgo: Int
    }

    /// Parses one log entry from text like "had 4oz at 2am". Returns nil
    /// when the model is unavailable, generation fails, or nothing was recognized.
    static func parseLog(_ text: String, now: Date) async -> ParsedLog? {
        guard isAvailable, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let clock = now.formatted(date: .omitted, time: .shortened)
        let session = LanguageModelSession(instructions: """
            Extract exactly one baby-care log entry from the user's text. The \
            current time is \(clock); use it to turn relative or clock times \
            (\"2am\", \"20 minutes ago\") into minutesAgo. If the text is not a \
            feed, diaper, or sleep event, set kind to "unknown".
            """)
        let response = try? await session.respond(to: text, generating: ParsedLog.self)
        guard let parsed = response?.content, parsed.kind != "unknown" else { return nil }
        return parsed
    }
}
