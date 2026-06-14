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
        do {
            let response = try await session.respond(to: digest)
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            // Distinguish "errored" from "unavailable" for QA — both currently
            // present to the user as a hidden card.
            AppLog.ai.error("Summary generation failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
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
        do {
            let response = try await session.respond(to: text, generating: ParsedLog.self)
            let parsed = response.content
            guard parsed.kind != "unknown" else { return nil }
            return parsed
        } catch {
            AppLog.ai.error("Parse failed for \"\(text, privacy: .private)\": \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Bounds

    /// Valid ranges for parsed values before they're written. The on-device model
    /// can hallucinate a 1000 oz feed or a wildly out-of-range time; callers check
    /// these and show a friendly message instead of silently clamping.
    enum Bounds {
        static let oz: ClosedRange<Double> = 0...32
        static let minutesAgo: ClosedRange<Int> = 0...1440   // up to 24h back
    }

    /// Validates a parsed feed/sleep entry's numeric fields. Returns a
    /// user-facing message when something's out of range, else nil (ok to apply).
    static func outOfRangeMessage(for parsed: ParsedLog) -> String? {
        if parsed.kind == "feed", let oz = parsed.amountOz,
           !oz.isFinite || !Bounds.oz.contains(oz) {
            return "That feed amount looks off — try something between 0 and 32 oz."
        }
        if !Bounds.minutesAgo.contains(parsed.minutesAgo) {
            return "That time looks off — try something within the last day."
        }
        return nil
    }
}
