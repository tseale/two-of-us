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
            two new parents. You are writing for the parents and caregivers — \
            address them, not the baby. Refer to \(babyName) in the third person \
            (e.g. "\(babyName) has been sleeping…", never "you've been sleeping"). \
            Do not open with a greeting. Given a digest of \(babyName)'s feeding, \
            sleep, and diaper stats, write 2–3 short sentences surfacing the most \
            useful patterns — feeding cadence, the longest sleep stretch, the \
            busiest feeding hour, anything notable or encouraging. Calm, plain \
            tone. Never give medical advice. No bullet lists, no headers.
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

}
