import SwiftUI
import SwiftData
import WatchKit

/// The whole watch app: three glance-and-tap rows in the phone app's language —
/// emoji iconography, accent-tinted cards (feed teal · diaper amber · sleep
/// periwinkle), "quiet until it matters" urgency, and the same status copy as
/// the Home tiles ("2h 31m ago", "next bottle ~6:15 PM").
///
/// Ticking: the list re-renders on `TimelineView(.everyMinute)` — minute
/// granularity is all the "ago"/hint lines can show, and it's the schedule
/// watchOS keeps honoring in Always-On. The active sleep timer is a
/// self-ticking `Text(timerInterval:)`, so it counts up with zero view updates.
struct WatchRootView: View {
    @Environment(\.modelContext) private var context

    @Query(WatchRootView.lastFeedDescriptor) private var lastFeeds: [FeedEvent]
    @Query(WatchRootView.lastDiaperDescriptor) private var lastDiapers: [DiaperEvent]
    @Query(WatchRootView.openSleepDescriptor) private var openSleeps: [SleepEvent]
    @Query(WatchRootView.lastEndedSleepDescriptor) private var endedSleeps: [SleepEvent]
    @Query private var babies: [Baby]
    @Query private var allSettings: [SharedSettings]

    @State private var showDiaperPicker = false
    @State private var confirmation: Confirmation?
    @State private var confirmationTask: Task<Void, Never>?

    private var logger: QuickLogger { QuickLogger(context: context) }

    var body: some View {
        NavigationStack {
            Group {
                if babies.isEmpty {
                    waitingForSync
                } else {
                    rows
                }
            }
            .navigationTitle(babies.first?.name ?? "Two of Us")
            .containerBackground(
                LinearGradient(colors: [AppColor.indigoHi, AppColor.indigoNight],
                               startPoint: .top, endPoint: .bottom),
                for: .navigation)
        }
        .overlay {
            if let confirmation {
                ConfirmationMoment(confirmation: confirmation)
            }
        }
        .animation(.snappy, value: confirmation)
    }

    // MARK: Rows

    private var rows: some View {
        TimelineView(.everyMinute) { timeline in
            List {
                feedRow(now: timeline.date)
                diaperRow(now: timeline.date)
                sleepRow(now: timeline.date)
            }
        }
        .confirmationDialog("Diaper", isPresented: $showDiaperPicker) {
            ForEach(DiaperType.allCases) { type in
                Button("\(type.emoji) \(type.label)") { logDiaper(type) }
            }
        }
    }

    private func feedRow(now: Date) -> some View {
        let last = lastFeeds.first?.timestamp
        let urgency = Urgency.from(since: last, now: now, target: feedTarget(after: last))
        return EventRow(
            emoji: "🍼", title: "Feed", tint: AppColor.accentFeed,
            since: last.map { agoText($0, now: now) },
            urgency: urgency,
            hint: feedHint(now: now)
        ) { logFeed() }
            .accessibilityHint("Logs a bottle of \(OzFormat.string(logger.defaultFeedOz)) ounces")
    }

    private func diaperRow(now: Date) -> some View {
        let last = lastDiapers.first?.timestamp
        let urgency = Urgency.from(since: last, now: now, target: UrgencyDefaults.diaper)
        return EventRow(
            emoji: "💩", title: "Diaper", tint: AppColor.accentDiaper,
            since: last.map { agoText($0, now: now) },
            urgency: urgency,
            hint: diaperHint
        ) { showDiaperPicker = true }
            .accessibilityHint("Choose wet, dirty, or both")
    }

    @ViewBuilder
    private func sleepRow(now: Date) -> some View {
        if let open = openSleeps.first {
            ActiveSleepRow(babyName: babies.first?.name ?? "Baby", startedAt: open.startedAt) {
                toggleSleep()
            }
        } else {
            let lastEnd = endedSleeps.first?.endedAt
            let urgency = Urgency.from(since: lastEnd, now: now, target: UrgencyDefaults.sleep)
            EventRow(
                emoji: "💤", title: "Sleep", tint: AppColor.accentSleep,
                since: lastEnd.map { agoText($0, now: now) },
                urgency: urgency,
                hint: sleepHint(now: now)
            ) { toggleSleep() }
                .accessibilityHint("Starts the sleep timer")
        }
    }

    // MARK: Status copy (mirrors the phone's Home tiles)

    /// "2h 15m ago", except sub-minute reads "just now" (never "just now ago").
    private func agoText(_ date: Date, now: Date) -> String {
        let since = TimeFormatting.since(date, now: now)
        return since == "just now" ? since : "\(since) ago"
    }

    private func feedTarget(after last: Date?) -> TimeInterval {
        guard let settings = allSettings.first else { return 180 * 60 }
        guard let last else { return TimeInterval(settings.targetFeedIntervalMinutes * 60) }
        return settings.feedInterval(after: last)
    }

    private func feedHint(now: Date) -> String {
        guard let last = lastFeeds.first?.timestamp else { return "log a bottle" }
        let next = last.addingTimeInterval(feedTarget(after: last))
        return next < now
            ? "bottle was due ~\(TimeFormatting.clock(next))"
            : "next bottle ~\(TimeFormatting.clock(next))"
    }

    private var diaperHint: String {
        guard let last = lastDiapers.first?.timestamp else { return "log a change" }
        return "changed at \(TimeFormatting.clock(last))"
    }

    private func sleepHint(now: Date) -> String {
        guard let lastEnd = endedSleeps.first?.endedAt else { return "start timer" }
        let next = lastEnd.addingTimeInterval(UrgencyDefaults.sleep)
        return next < now
            ? "nap was due ~\(TimeFormatting.clock(next))"
            : "next nap ~\(TimeFormatting.clock(next))"
    }

    // MARK: Waiting state

    private var waitingForSync: some View {
        ScrollView {
            VStack(spacing: 10) {
                CradleMark(size: 96)
                    .padding(.top, 4)
                Text("Waiting for your iPhone")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .multilineTextAlignment(.center)
                Text("Set up on your iPhone first — the watch syncs on its own.")
                    .font(.caption2)
                    .foregroundStyle(AppColor.text2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 4)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Actions

    private func logFeed() {
        let amount = logger.defaultFeedOz
        if logger.logFeed(amountOz: amount) != nil {
            didLog("🍼", "Logged \(OzFormat.string(amount)) oz", tint: AppColor.accentFeed)
        } else {
            didFail()
        }
    }

    private func logDiaper(_ type: DiaperType) {
        if logger.logDiaper(type) != nil {
            didLog(type.emoji, "Logged \(type.label.lowercased()) diaper", tint: AppColor.accentDiaper)
        } else {
            didFail()
        }
    }

    private func toggleSleep() {
        switch logger.toggleSleep() {
        case true?: didLog("💤", "Sleep started", tint: AppColor.accentSleep)
        case false?: didLog("💤", "Sleep ended", tint: AppColor.accentSleep)
        case nil: didFail()
        }
    }

    private func didLog(_ emoji: String, _ message: String, tint: Color) {
        // .click, not .success: watch haptics chime audibly when unmuted, and
        // "sound: none, ever" is a design rule — the baby may be asleep.
        WKInterfaceDevice.current().play(.click)
        WatchSyncManager.shared?.drainLoggerQueue()
        show(Confirmation(emoji: emoji, message: message, tint: tint, isFailure: false))
    }

    private func didFail() {
        WKInterfaceDevice.current().play(.failure)
        show(Confirmation(emoji: "🍼", message: "Couldn't log — try from the phone",
                          tint: AppColor.urgencyRed, isFailure: true))
    }

    private func show(_ c: Confirmation) {
        confirmationTask?.cancel()
        confirmation = c
        AccessibilityNotification.Announcement(c.message).post()
        confirmationTask = Task {
            try? await Task.sleep(for: .seconds(c.isFailure ? 2.4 : 1.8))
            guard !Task.isCancelled else { return }
            confirmation = nil
        }
    }

    // MARK: Queries

    private static var lastFeedDescriptor: FetchDescriptor<FeedEvent> {
        var d = FetchDescriptor<FeedEvent>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        d.fetchLimit = 1
        return d
    }

    private static var lastDiaperDescriptor: FetchDescriptor<DiaperEvent> {
        var d = FetchDescriptor<DiaperEvent>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        d.fetchLimit = 1
        return d
    }

    private static var openSleepDescriptor: FetchDescriptor<SleepEvent> {
        var d = FetchDescriptor<SleepEvent>(
            predicate: #Predicate { $0.endedAt == nil && $0.deletedAt == nil }
        )
        d.fetchLimit = 1
        return d
    }

    private static var lastEndedSleepDescriptor: FetchDescriptor<SleepEvent> {
        var d = FetchDescriptor<SleepEvent>(
            predicate: #Predicate { $0.deletedAt == nil && $0.endedAt != nil },
            sortBy: [SortDescriptor(\.endedAt, order: .reverse)]
        )
        d.fetchLimit = 1
        return d
    }
}

// MARK: - Row components

/// A log-tile row: emoji → rounded title → since-line (urgency-aware) → hint.
/// The accent-tinted card background is the widgets' sanctioned stand-in for
/// the phone's tinted glass tiles.
private struct EventRow: View {
    let emoji: String
    let title: String
    let tint: Color
    let since: String?
    let urgency: Urgency
    let hint: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(emoji)
                        .font(.body)
                    Text(title)
                        .font(.system(.headline, design: .rounded, weight: .bold))
                }
                if let since {
                    // Value first, marker after — the phone tiles' order.
                    HStack(spacing: 4) {
                        Text(since)
                            .font(.footnote.weight(urgency.needsAttention ? .semibold : .regular))
                            .foregroundStyle(urgency.needsAttention ? urgency.sinceTextColor : AppColor.text2)
                        if let marker = urgency.marker {
                            Image(systemName: marker)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(urgency.color)
                                .accessibilityHidden(true)
                        }
                    }
                }
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(AppColor.text2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
        .listRowBackground(tintedCard(tint))
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        var parts = [title]
        if let since { parts.append("\(since), \(urgency.accessibilityWord)") }
        parts.append(hint)
        return parts.joined(separator: ", ")
    }
}

/// The sanctioned stand-in for the phone's tinted glass tiles: the accent at
/// 18% composited OVER the card surface (exactly what the phone widgets do),
/// not over the scene gradient — bare tint over indigo muddies the hue and
/// sinks text contrast below AA.
private func tintedCard(_ tint: Color) -> some View {
    RoundedRectangle(cornerRadius: 12)
        .fill(AppColor.card)
        .overlay(RoundedRectangle(cornerRadius: 12).fill(tint.opacity(0.18)))
}

/// The Sleep row morphed in place while a sleep runs: periwinkle card, eyebrow
/// "MILLER IS SLEEPING", self-ticking rounded-mono timer, "since 7:42 PM".
/// Tap anywhere to wake (mirrors the phone's active-sleep card semantics).
private struct ActiveSleepRow: View {
    let babyName: String
    let startedAt: Date
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("💤")
                        .font(.caption)
                    Text("\(babyName) is sleeping")
                        .sectionLabelStyle(color: AppColor.accentSleep)
                }
                Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
                    .font(.system(.title2, design: .rounded, weight: .heavy).monospacedDigit())
                    .foregroundStyle(AppColor.text)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text("since \(TimeFormatting.clock(startedAt))")
                    .font(.caption2)
                    .foregroundStyle(AppColor.text2)
                Text("tap to wake")
                    .font(.caption2)
                    .foregroundStyle(AppColor.text2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
        }
        .listRowBackground(tintedCard(AppColor.accentSleep))
        .accessibilityLabel("\(babyName) is sleeping, since \(TimeFormatting.clock(startedAt))")
        .accessibilityHint("Ends the sleep session")
    }
}

// MARK: - Confirmation moment

private struct Confirmation: Equatable {
    let emoji: String
    let message: String
    let tint: Color
    let isFailure: Bool
}

/// The watch-native log confirmation: a brief full-screen moment (like ending
/// a workout), not an iOS toast. Big emoji, calm message, kind-tinted wash.
private struct ConfirmationMoment: View {
    let confirmation: Confirmation

    var body: some View {
        ZStack {
            Rectangle()
                .fill(AppColor.bg.opacity(0.88))
                .background(.ultraThinMaterial)
            VStack(spacing: 8) {
                if confirmation.isFailure {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(AppColor.urgencyRed)
                } else {
                    Text(confirmation.emoji)
                        .font(.system(size: 44))
                }
                Text(confirmation.message)
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
        }
        .ignoresSafeArea()
        .transition(.opacity)
    }
}
