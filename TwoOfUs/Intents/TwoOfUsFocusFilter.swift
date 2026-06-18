import AppIntents

/// Lets each iOS Focus (Sleep, Work, …) reconfigure how Two of Us notifies.
///
/// The user adds this filter under Settings → Focus → <a Focus> → Focus Filters
/// and flips the toggles per-Focus. When that Focus activates, the system runs
/// `perform()`, which persists the config to the App Group so `NotificationManager`
/// (even in a background notification launch) can read it.
///
/// - `muteCoParent` silences the passive "the other parent logged…" + daily
///   summary notifications.
/// - `onlyUrgent` keeps only the time-sensitive feed/diaper reminders.
///
/// Time-sensitive reminders are never suppressed — they're the urgent channel,
/// and AlarmKit remains the overnight breakthrough regardless.
struct TwoOfUsFocusFilter: SetFocusFilterIntent {
    static var title: LocalizedStringResource = "Two of Us"
    static var description = IntentDescription(
        "Choose how Two of Us notifies you while this Focus is on.")

    @Parameter(title: "Mute co-parent activity", default: false)
    var muteCoParent: Bool

    @Parameter(title: "Only urgent reminders", default: false)
    var onlyUrgent: Bool

    /// Per-configuration summary shown in the Focus settings UI.
    var displayRepresentation: DisplayRepresentation {
        var parts: [String] = []
        if muteCoParent { parts.append("Co-parent muted") }
        if onlyUrgent { parts.append("Urgent only") }
        let subtitle = parts.isEmpty ? "Default notifications" : parts.joined(separator: " · ")
        return DisplayRepresentation(title: "Two of Us", subtitle: "\(subtitle)")
    }

    func perform() async throws -> some IntentResult {
        let defaults = AppGroup.userDefaults
        defaults?.set(muteCoParent, forKey: NotificationManager.focusMuteCoParentKey)
        defaults?.set(onlyUrgent, forKey: NotificationManager.focusOnlyUrgentKey)
        return .result()
    }
}
