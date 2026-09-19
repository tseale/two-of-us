import Foundation
import FoundationModels
import Observation

/// One conversation in the "Ask about Miller" sheet: an on-device
/// Foundation Models session that can read the log through
/// `CareEventsTool` and answers in plain sentences. Follow-ups share the
/// session, so "and the day before?" works. Nothing leaves the phone.
@MainActor
@Observable
final class AskSession {
    struct Message: Identifiable, Equatable {
        enum Role { case user, assistant }
        let id = UUID()
        let role: Role
        var text: String
    }

    let babyName: String
    private(set) var messages: [Message] = []
    private(set) var isResponding = false
    private let session: LanguageModelSession

    /// Starters that map onto what the tool can answer well.
    var suggestions: [String] {
        ["How were the nights this week?",
         "When was the last dirty diaper?",
         "How much did \(babyName) eat yesterday?",
         "What's the longest nap lately?"]
    }

    init(babyName: String) {
        self.babyName = babyName
        session = LanguageModelSession(
            tools: [CareEventsTool()],
            instructions: Instructions("""
                You are a calm, concise assistant inside a baby-tracking app used by \
                two new parents. You are talking to the parents — refer to \
                \(babyName) in the third person. Answer questions about \
                \(babyName)'s feeds, sleep, diapers, and notes by calling the \
                lookUpCareEvents tool first, then answering from the events it \
                returns. Quote times and amounts from the events; never invent \
                any. If the events don't cover the question, say so plainly. \
                Two or three short sentences, no lists, no headers. Never give \
                medical advice — if asked whether something is normal or what \
                to do, suggest asking the pediatrician.
                """))
    }

    func ask(_ question: String) async {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isResponding else { return }
        messages.append(Message(role: .user, text: trimmed))
        isResponding = true
        defer { isResponding = false }
        do {
            let response = try await session.respond(to: trimmed)
            messages.append(Message(role: .assistant,
                                    text: response.content.trimmingCharacters(in: .whitespacesAndNewlines)))
        } catch {
            AppLog.ai.error("Ask failed: \(error.localizedDescription, privacy: .public)")
            messages.append(Message(role: .assistant,
                                    text: "I couldn't answer that one. Try rephrasing, or ask about a specific day."))
        }
    }
}
