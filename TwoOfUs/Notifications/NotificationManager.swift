import Foundation
import UserNotifications
import Intents

/// Owns the user-facing local-notification layer (`UserNotifications`).
///
/// Two jobs:
/// 1. **Co-parent activity** — when a feed/sleep/diaper logged by the *other*
///    parent syncs in, post a calm, informational notification (driven from
///    `SyncManager`). Styled as a Communication Notification so it carries the
///    sender's avatar and can be promoted in Focus.
/// 2. **Gentle reminders** — soft, snoozable "feed due / diaper due" nudges,
///    (re)scheduled whenever an event is logged. These are deliberately distinct
///    from the AlarmKit feed alarm (`FeedAlarmManager`), which is the single loud
///    reminder that pierces Silent/Focus overnight: when the AlarmKit feed
///    reminder is on, the gentle feed reminder stands down to avoid double-firing.
///
/// Everything is silent (no sound — the app's design ethos), per-device, and
/// honors per-user quiet hours. Reads go through `QuickLogger` (the App
/// Group-shared store) so this works identically from the app and from a
/// background notification-action launch.
enum NotificationManager {
    /// How long after the last diaper to nudge (AlarmKit only covers feeds).
    static let diaperReminderInterval: TimeInterval = 3 * 3600
    /// Window the daily summary fires in (local hour, 24h).
    static let milestoneHour = 21
    /// Ignore co-parent events older than this when deciding to notify, so a
    /// participant joining (which pulls full history) doesn't fire a flood.
    static let coParentRecencyWindow: TimeInterval = 15 * 60

    private static var center: UNUserNotificationCenter { .current() }
    private static var prefs: LocalPrefs { .shared }

    // MARK: Setup

    /// Registers the categories that give notifications their action buttons.
    /// Call once at launch (`AppDelegate.didFinishLaunching`).
    static func registerCategories() {
        let logFeed = UNNotificationAction(
            identifier: NotificationID.Action.logFeed,
            title: "Log feed",
            options: [],
            icon: UNNotificationActionIcon(systemImageName: "drop.fill")
        )
        let snooze = UNNotificationAction(
            identifier: NotificationID.Action.snooze,
            title: "Snooze 30m",
            options: [],
            icon: UNNotificationActionIcon(systemImageName: "clock")
        )
        let logWet = UNNotificationAction(
            identifier: NotificationID.Action.logDiaperWet,
            title: "Wet",
            options: [],
            icon: UNNotificationActionIcon(systemImageName: "drop")
        )
        let logDirty = UNNotificationAction(
            identifier: NotificationID.Action.logDiaperDirty,
            title: "Dirty",
            options: [],
            icon: UNNotificationActionIcon(systemImageName: "leaf")
        )

        let feed = UNNotificationCategory(
            identifier: NotificationID.Category.reminderFeed,
            actions: [logFeed, snooze],
            intentIdentifiers: [],
            options: []
        )
        let diaper = UNNotificationCategory(
            identifier: NotificationID.Category.reminderDiaper,
            actions: [logWet, logDirty, snooze],
            intentIdentifiers: [],
            options: []
        )
        // Informational categories: default tap opens the app, no extra buttons.
        let coParent = UNNotificationCategory(
            identifier: NotificationID.Category.coParent,
            actions: [], intentIdentifiers: [], options: []
        )
        let milestone = UNNotificationCategory(
            identifier: NotificationID.Category.milestone,
            actions: [], intentIdentifiers: [], options: []
        )

        center.setNotificationCategories([feed, diaper, coParent, milestone])
    }

    /// Requests alert + badge authorization (never sound — the app is silent).
    /// Safe to call repeatedly; only prompts while undetermined.
    @discardableResult
    static func requestAuthorization() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        default:
            return (try? await center.requestAuthorization(options: [.alert, .badge])) ?? false
        }
    }

    // MARK: Scheduled reminders

    /// Re-arms the gentle feed/diaper reminders off the current store state.
    /// Call after any log and on app foreground. No-ops in demo mode.
    static func refreshScheduledReminders() {
        guard !prefs.demoModeEnabled else { return }
        center.removePendingNotificationRequests(withIdentifiers: [
            NotificationID.Request.feedReminder,
            NotificationID.Request.diaperReminder
        ])
        guard prefs.gentleRemindersEnabled, let logger = QuickLogger.make() else { return }

        // Feed: only when the loud AlarmKit reminder is OFF (avoid double-firing).
        if !prefs.feedReminderEnabled, let last = logger.lastFeed?.timestamp {
            scheduleReminder(
                id: NotificationID.Request.feedReminder,
                fireDate: last.addingTimeInterval(logger.targetFeedInterval),
                category: NotificationID.Category.reminderFeed,
                threadID: NotificationID.Thread.feed,
                title: "\(logger.babyName ?? "Baby") — feed due",
                body: "It's been about \(hoursLabel(logger.targetFeedInterval)) since the last bottle."
            )
        }

        // Diaper: AlarmKit doesn't cover diapers, so this is the only nudge.
        if let last = logger.lastDiaper?.timestamp {
            scheduleReminder(
                id: NotificationID.Request.diaperReminder,
                fireDate: last.addingTimeInterval(diaperReminderInterval),
                category: NotificationID.Category.reminderDiaper,
                threadID: NotificationID.Thread.diaper,
                title: "\(logger.babyName ?? "Baby") — diaper check",
                body: "It's been a while since the last change."
            )
        }
    }

    /// Schedules a single time-sensitive reminder for `fireDate`, replacing any
    /// pending one with the same id. Skips past-due times and quiet hours.
    private static func scheduleReminder(
        id: String, fireDate: Date, category: String,
        threadID: String, title: String, body: String,
        respectQuietHours: Bool = true
    ) {
        let interval = fireDate.timeIntervalSinceNow
        guard interval > 0 else { return }                  // already due
        // Auto-scheduled reminders honor quiet hours; a user-initiated snooze does
        // not — the parent explicitly asked to be reminded in 30 minutes.
        if respectQuietHours { guard !isWithinQuietHours(fireDate) else { return } }

        let content = makeContent(
            title: title, body: body, category: category, threadID: threadID,
            level: .timeSensitive, relevanceScore: 1.0
        )
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    /// Reschedules a reminder 30 minutes out after the user taps "Snooze".
    static func snooze(category: String) {
        guard !prefs.demoModeEnabled else { return }
        let fire = Date.now.addingTimeInterval(30 * 60)
        let babyName = QuickLogger.make()?.babyName ?? "Baby"
        switch category {
        case NotificationID.Category.reminderFeed:
            scheduleReminder(
                id: NotificationID.Request.feedReminder, fireDate: fire,
                category: category, threadID: NotificationID.Thread.feed,
                title: "\(babyName) — feed due", body: "Snoozed reminder.",
                respectQuietHours: false
            )
        case NotificationID.Category.reminderDiaper:
            scheduleReminder(
                id: NotificationID.Request.diaperReminder, fireDate: fire,
                category: category, threadID: NotificationID.Thread.diaper,
                title: "\(babyName) — diaper check", body: "Snoozed reminder.",
                respectQuietHours: false
            )
        default:
            break
        }
    }

    // MARK: Daily milestone

    /// Schedules (or clears) the calm end-of-day summary for the next
    /// `milestoneHour`, with **today's real counts** in the body. Re-armed on
    /// foreground and on every log so the pending copy stays fresh as the day
    /// fills in. Honors the per-user toggle and quiet hours.
    static func refreshDailyMilestone() {
        center.removePendingNotificationRequests(withIdentifiers: [NotificationID.Request.dailyMilestone])
        guard !prefs.demoModeEnabled, prefs.notifyMilestones else { return }
        guard let fireDate = nextMilestoneDate(), !isWithinQuietHours(fireDate) else { return }

        let logger = QuickLogger.make()
        let babyName = logger?.babyName ?? "your little one"
        let body = logger.map { summaryBody($0) } ?? "Tap to see \(babyName)'s day."

        let content = makeContent(
            title: "\(babyName)'s day",
            body: body,
            category: NotificationID.Category.milestone,
            threadID: NotificationID.Thread.milestone,
            level: .passive, relevanceScore: 0.3
        )
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: fireDate.timeIntervalSinceNow, repeats: false)
        center.add(UNNotificationRequest(
            identifier: NotificationID.Request.dailyMilestone, content: content, trigger: trigger))
    }

    /// The next occurrence of `milestoneHour` (today if still ahead, else tomorrow).
    private static func nextMilestoneDate() -> Date? {
        let cal = Calendar.current
        let now = Date.now
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        comps.hour = milestoneHour
        comps.minute = 0
        guard let todayFire = cal.date(from: comps) else { return nil }
        return todayFire > now ? todayFire : cal.date(byAdding: .day, value: 1, to: todayFire)
    }

    /// "8 feeds (24 oz) · 6 diapers · 5h 10m sleep" from today's totals.
    private static func summaryBody(_ logger: QuickLogger) -> String {
        let c = logger.todayCounts
        var parts: [String] = [
            c.feeds == 1 ? "1 feed (\(OzFormat.string(c.oz)) oz)" : "\(c.feeds) feeds (\(OzFormat.string(c.oz)) oz)",
            c.diapers == 1 ? "1 diaper" : "\(c.diapers) diapers"
        ]
        let sleep = logger.todaySleep
        if sleep >= 60 { parts.append("\(hoursLabel(sleep)) sleep") }
        return parts.joined(separator: " · ")
    }

    // MARK: Co-parent activity

    /// Posts an informational notification for an event the *other* parent logged.
    /// Gated by the per-kind toggle, quiet hours, demo mode, and a dedupe key so a
    /// re-delivered record never double-notifies. Styled as a Communication
    /// Notification (sender avatar) when the co-parent's photo is available.
    static func postCoParentActivity(
        eventID: UUID, dedupeSuffix: String, kind: EventKind,
        senderName: String, senderPhoto: Data?, body: String, threadID: String
    ) {
        guard !prefs.demoModeEnabled, isEnabled(for: kind) else { return }
        guard !isWithinQuietHours(.now), !focusSuppressesPassive else { return }

        let dedupeKey = "\(eventID.uuidString)-\(dedupeSuffix)"
        guard !hasPosted(dedupeKey) else { return }
        markPosted(dedupeKey)

        let content = makeContent(
            title: senderName, body: body,
            category: NotificationID.Category.coParent, threadID: threadID,
            level: .passive, relevanceScore: 0.6
        )
        let requestID = NotificationID.Request.coParent(dedupeKey)

        // Best-effort communication styling so the sender's face shows on the
        // notification. Falls back to the plain content if anything fails.
        Task {
            let finalContent = await communicationContent(
                base: content, senderName: senderName, senderPhoto: senderPhoto) ?? content
            try? await center.add(
                UNNotificationRequest(identifier: requestID, content: finalContent, trigger: nil))
        }
    }

    /// Wraps the content in an `INSendMessageIntent` so the system renders it as a
    /// message from the co-parent (avatar + name). Returns nil if styling fails.
    private static func communicationContent(
        base: UNNotificationContent, senderName: String, senderPhoto: Data?
    ) async -> UNNotificationContent? {
        let handle = INPersonHandle(value: senderName, type: .unknown)
        let image = senderPhoto.flatMap { INImage(imageData: $0) }
        let sender = INPerson(
            personHandle: handle, nameComponents: nil, displayName: senderName,
            image: image, contactIdentifier: nil, customIdentifier: nil)

        let intent = INSendMessageIntent(
            recipients: nil, outgoingMessageType: .outgoingMessageText,
            content: base.body, speakableGroupName: nil, conversationIdentifier: nil,
            serviceName: nil, sender: sender, attachments: nil)

        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .incoming
        try? await interaction.donate()

        return try? base.updating(from: intent)
    }

    // MARK: Notification-action responses

    /// Handles a tapped action button. Logging actions write through
    /// `QuickLogger` (App Group store) without opening the UI; the default tap
    /// falls through so the app simply launches. Called from `AppDelegate`.
    @MainActor
    static func handle(_ response: UNNotificationResponse) {
        guard !prefs.demoModeEnabled else { return }
        let category = response.notification.request.content.categoryIdentifier

        switch response.actionIdentifier {
        case NotificationID.Action.logFeed:
            if let logger = QuickLogger.make() { logger.logFeed(amountOz: logger.defaultFeedOz) }
            flushAndRearm()
        case NotificationID.Action.logDiaperWet:
            QuickLogger.make()?.logDiaper(.wet)
            flushAndRearm()
        case NotificationID.Action.logDiaperDirty:
            QuickLogger.make()?.logDiaper(.dirty)
            flushAndRearm()
        case NotificationID.Action.snooze:
            snooze(category: category)
        default:
            break   // default / dismiss — opening the app is enough
        }
    }

    /// After a background log: push the new record to CloudKit (if the app's sync
    /// engine is live) and re-arm the gentle reminders and feed alarm off the new state.
    @MainActor
    private static func flushAndRearm() {
        SyncManager.shared?.drainExtensionQueue()
        refreshScheduledReminders()
        // Re-arm the AlarmKit feed alarm. Without this, logging a feed from the
        // notification action button never reschedules the loud overnight alarm —
        // the app foreground would eventually fix it, but the alarm fires at the
        // wrong time if the parent doesn't open the app after a 2am notification log.
        if let logger = QuickLogger.make() {
            let babyName = logger.babyName ?? "Baby"
            let lastFeed = logger.lastFeed?.timestamp
            let interval = logger.targetFeedInterval
            Task { await FeedAlarmManager.reschedule(babyName: babyName, lastFeed: lastFeed, interval: interval) }
        }
    }

    // MARK: Content builder

    private static func makeContent(
        title: String, body: String, category: String, threadID: String,
        level: UNNotificationInterruptionLevel, relevanceScore: Double
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = category
        content.threadIdentifier = threadID
        content.interruptionLevel = level
        content.relevanceScore = relevanceScore   // ranks within the summary / stack
        content.sound = nil                        // the app never makes sound
        return content
    }

    // MARK: Gating helpers

    private static func isEnabled(for kind: EventKind) -> Bool {
        switch kind {
        case .feed: return prefs.notifyFeed
        case .sleep: return prefs.notifySleep
        case .diaper: return prefs.notifyDiaper
        }
    }

    // MARK: Focus filter (written by `TwoOfUsFocusFilter`, read here)
    //
    // The keys live in the App Group so a background notification launch sees the
    // same state the focus-filter intent wrote. Passive (co-parent / summary)
    // posts are suppressed while a filtered Focus is active; time-sensitive
    // reminders are the "urgent" channel and always get through.

    static let focusMuteCoParentKey = "focus.muteCoParent"
    static let focusOnlyUrgentKey = "focus.onlyUrgent"

    private static var focusSuppressesPassive: Bool {
        let d = AppGroup.userDefaults
        return (d?.bool(forKey: focusMuteCoParentKey) ?? false)
            || (d?.bool(forKey: focusOnlyUrgentKey) ?? false)
    }

    /// True if `date`'s local time falls inside the user's quiet-hours window
    /// (handles windows that wrap past midnight, e.g. 22:00–07:00).
    static func isWithinQuietHours(_ date: Date) -> Bool {
        guard prefs.quietHoursEnabled else { return false }
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute], from: date)
        let minutes = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        let start = prefs.quietHoursStartMinutes
        let end = prefs.quietHoursEndMinutes
        if start == end { return false }
        return start < end
            ? (minutes >= start && minutes < end)
            : (minutes >= start || minutes < end)   // wraps midnight
    }

    private static func hoursLabel(_ interval: TimeInterval) -> String {
        let minutes = Int(interval / 60)
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    // MARK: Dedupe (App Group, so a background launch shares state with the app)

    private static let postedKey = "notify.posted"
    private static let postedCap = 200

    private static func hasPosted(_ key: String) -> Bool {
        let arr = AppGroup.userDefaults?.array(forKey: postedKey) as? [String] ?? []
        return arr.contains(key)
    }

    private static func markPosted(_ key: String) {
        guard let d = AppGroup.userDefaults else { return }
        var arr = d.array(forKey: postedKey) as? [String] ?? []
        arr.append(key)
        if arr.count > postedCap { arr.removeFirst(arr.count - postedCap) }
        d.set(arr, forKey: postedKey)
    }
}
