import Foundation
import FoundationModels

/// Generative features via Apple's Foundation Models.
///
/// The daily cards (`summary`, `outlook`) run on the on-device model — nothing
/// leaves the phone. The weekly patterns card (`weeklyPatterns`, iOS 27) is
/// the one exception: it sends the last two weeks of logs to Apple's Private
/// Cloud Compute, whose servers process the request on Apple silicon without
/// storing it and without any path to us; `docs/PRIVACY.md` spells this out
/// and the Settings toggle copy says so. Everything degrades gracefully:
/// `isAvailable` / `isCloudAvailable` are false on hardware without Apple
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

    // MARK: - Today's outlook (Phase 3)

    /// Turns the computed predictions into 1–2 forward-looking sentences —
    /// narrative AROUND the numbers, never the source of them. The digest
    /// carries every figure the model may use; the instructions forbid
    /// inventing others, because an LLM asked to predict confabulates and the
    /// prediction engine already did the arithmetic.
    static func outlook(digest: String, babyName: String) async -> String? {
        guard isAvailable else { return nil }
        let session = LanguageModelSession(instructions: """
            You are a warm, concise assistant inside a baby-tracking app used \
            by two new parents. You are writing for the parents — address \
            them, not the baby; refer to \(babyName) in the third person. \
            Given today's computed predictions and recent stats, write 1–2 \
            short forward-looking sentences about the hours ahead ("expect \
            …", "the 2:15 nap should …"). Use ONLY the numbers provided — \
            never invent or recalculate figures. Calm, plain tone. Never give \
            medical advice. No greeting, no bullet lists, no headers.
            """)
        do {
            let response = try await session.respond(to: digest)
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            AppLog.ai.error("Outlook generation failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - This week's patterns (Private Cloud Compute, iOS 27)

    /// Guided-generation shape for the weekly card: a headline and a few
    /// one-sentence observations the card renders line by line, rather than
    /// an essay the model would otherwise drift into with two weeks of input.
    @Generable
    struct WeeklyPatterns: Equatable {
        @Guide(description: "One sentence naming the single most notable change in the most recent week compared with the week before.")
        var headline: String
        @Guide(description: "Two or three one-sentence observations about trends in feeding, sleep, or diapers across the two weeks — specific to the numbers given, calm and plain, never medical advice.")
        var observations: [String]
    }

    /// Whether Apple's Private Cloud Compute model can be used right now.
    @available(iOS 27, *)
    static var isCloudAvailable: Bool {
        if case .available = PrivateCloudComputeLanguageModel.default.availability { return true }
        return false
    }

    /// Reads the two-week raw history (`HistoryDigest.render`) for trends the
    /// daily digests can't show. Cloud because the history doesn't fit the
    /// on-device context; guided generation because the numbers are all in
    /// the prompt and the model's job is to notice, not to compute.
    @available(iOS 27, *)
    static func weeklyPatterns(history: String, babyName: String) async -> WeeklyPatterns? {
        guard isCloudAvailable else { return nil }
        let session = LanguageModelSession(
            model: PrivateCloudComputeLanguageModel.default,
            instructions: """
            You are a warm, concise assistant inside a baby-tracking app used \
            by two new parents. You are writing for the parents — address \
            them, not the baby; refer to \(babyName) in the third person. You \
            are given every logged feed, sleep, and diaper from the last two \
            weeks. Compare the most recent seven days with the seven before \
            them and describe what changed and what held steady: feeding \
            cadence and bottle sizes by time of day, nap and night-stretch \
            lengths, diaper rhythm. Use ONLY the events provided; quote \
            times and amounts from them rather than estimating. Today is \
            incomplete — never treat it as a low day. Calm, plain tone. \
            Never give medical advice or say what \(babyName) should do.
            """)
        do {
            let response = try await session.respond(to: history, generating: WeeklyPatterns.self)
            return response.content
        } catch {
            AppLog.ai.error("Weekly patterns generation failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

}
