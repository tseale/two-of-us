import Foundation

/// One sleep from the log, as the sky needs it: when it began, and when it
/// ended if it has. A plain value, so the night's rules never touch a
/// SwiftData row and can be tested with literal dates (`NightRuleTests`).
///
/// Home hands the sky only the LIVE sleeps (soft-deleted rows left out): a
/// deleted sleep is simply absent, which is how deleting tonight's sleep
/// un-begins the night. `id` is carried for the hand token and for telling
/// rows apart; no rule may key on it, because editing a sleep replaces the
/// row with a new one under a new id (`EventStore.editSleep`).
struct SleepSpan: Equatable {
    let id: UUID
    /// The claimed start: now for a tap, the bassinet's own time for a SNOO
    /// sleep, whatever a parent set after an edit.
    let start: Date
    /// Nil while he is still asleep.
    let end: Date?

    /// Still running: the sleep the sleep card is counting.
    var isRunning: Bool { end == nil }
}
