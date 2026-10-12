import SwiftUI

/// One day of daycare, aggregated for the cards. Built by HomeView from
/// today's Brightwheel-imported events.
struct DaycareDaySummary: Equatable {
    var feedCount = 0
    var feedOz: Double = 0
    var napCount = 0
    var napSeconds: TimeInterval = 0
    var diaperCount = 0
    var activityCount = 0
    var photoCount = 0
    var medicationCount = 0
    var checkIn: Date?          // first check-in of the day
    var checkOut: Date?         // last check-out of the day
    var hasAnythingElse = false // any other daycare event (note, mood, milestone…)

    var isEmpty: Bool {
        feedCount == 0 && napCount == 0 && diaperCount == 0 && activityCount == 0
            && photoCount == 0 && medicationCount == 0
            && checkIn == nil && checkOut == nil && !hasAnythingElse
    }
}

// MARK: - The hero (while he's at daycare)

/// The storybook page of Miller's day, shown while he's at daycare in place
/// of BOTH the TODAY card and the daycare card — they were the same three
/// numbers in two formats. The 24-hour ribbon keeps the day's shape, three
/// stat beads carry the whole-day totals (the sleep bead turning into a
/// pulsing live counter mid-nap), and a home/daycare split underneath says
/// what happened before drop-off versus what daycare has logged since.
/// Checkout dissolves it back into the plain TODAY card plus the quiet
/// finished-day card below.
struct DaycareDayHeroCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let babyName: String
    /// Today's full 24-hour ribbon — home and daycare events together.
    let marks: [RibbonMark]
    /// Whole-day totals (home + daycare), same numbers the TODAY card showed.
    let feedCount: Int
    let feedOz: Double
    let diaperCount: Int
    let sleepSeconds: TimeInterval
    /// The daycare-only slice, for the split row.
    let daycare: DaycareDaySummary
    /// When the daycare day began (check-in, or the first daycare event).
    let since: Date
    /// Start of a nap Brightwheel has begun but not ended.
    let liveNapStartedAt: Date?
    let now: Date
    var showFeed = true
    var showSleep = true
    var showDiaper = true

    private enum Stat { case feed, diaper, sleep }
    @State private var popped: Set<Stat> = []
    @State private var pulsing = false

    private var napping: Bool { liveNapStartedAt != nil }

    // The home side of the split is the day minus the daycare slice.
    private var homeOz: Double { max(0, feedOz - daycare.feedOz) }
    private var homeFeeds: Int { max(0, feedCount - daycare.feedCount) }
    private var homeChanges: Int { max(0, diaperCount - daycare.diaperCount) }
    private var homeSleep: TimeInterval { max(0, sleepSeconds - daycare.napSeconds) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\u{1F3EB}").font(.title3)
                Text("\(babyName)'s Day")
                    .font(.headline)
                    .foregroundStyle(AppColor.text)
                Spacer()
                Text("daycare since \(TimeFormatting.clock(since))")
                    .font(.caption)
                    .foregroundStyle(AppColor.text2)
                    .monospacedDigit()
            }

            DayRibbonView(marks: marks)
                .frame(height: 40)

            // The day's totals as three clean circles, straight on the card.
            HStack(spacing: 0) {
                if showFeed {
                    bead(.feed, emoji: "🍼", color: AppColor.accentFeed,
                         value: feedCount > 0 ? "\(OzFormat.string(feedOz)) oz" : "—",
                         label: feedCount > 0 ? Plural.count(feedCount, "feed") : "no feeds yet",
                         active: feedCount > 0)
                }
                if showDiaper {
                    bead(.diaper, emoji: "💩", color: AppColor.accentDiaper,
                         value: diaperCount > 0 ? "\(diaperCount)" : "—",
                         label: diaperCount == 1 ? "change" : "changes",
                         active: diaperCount > 0)
                }
                if showSleep {
                    bead(.sleep, emoji: "💤", color: AppColor.accentSleep,
                         value: sleepValue,
                         label: napping ? "napping now" : "sleep",
                         active: napping || sleepSeconds > 0,
                         pulse: napping)
                }
            }

            splitSection(icon: "🏠", title: "HOME", tint: AppColor.text2, lines: homeLines)
            splitSection(icon: "\u{1F3EB}", title: "DAYCARE", tint: AppColor.accentCheck, lines: daycareLines)
        }
        .padding(16)
        .background(
            // The storybook wash: warm peach rising into lavender, laid over
            // the standard card color so hairline + dark mode stay in family.
            LinearGradient(colors: [AppColor.accentDiaper.opacity(0.12),
                                    AppColor.accentSleep.opacity(0.14)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: .rect(cornerRadius: 20)
        )
        .surfaceCard(cornerRadius: 20)
        .onChange(of: feedOz) { old, new in if new > old { pop(.feed) } }
        .onChange(of: diaperCount) { old, new in if new > old { pop(.diaper) } }
        .onChange(of: sleepSeconds) { old, new in if new > old { pop(.sleep) } }
        .onChange(of: liveNapStartedAt) { old, new in
            if new != nil, old == nil { pop(.sleep) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
        // Stable hook for UI tests (doesn't affect the VoiceOver label above).
        .accessibilityIdentifier("daycareCard")
    }

    // MARK: Beads

    private func bead(_ stat: Stat, emoji: String, color: Color,
                      value: String, label: String, active: Bool,
                      pulse: Bool = false) -> some View {
        VStack(spacing: 6) {
            ZStack {
                if pulse && !reduceMotion {
                    Circle()
                        .stroke(color.opacity(0.7), lineWidth: 2)
                        .frame(width: 68, height: 68)
                        .scaleEffect(pulsing ? 1.25 : 1)
                        .opacity(pulsing ? 0 : 0.8)
                        .animation(.easeOut(duration: 1.6).repeatForever(autoreverses: false),
                                   value: pulsing)
                        .onAppear { pulsing = true }
                        .onDisappear { pulsing = false }
                }
                VStack(spacing: 1) {
                    Text(emoji).font(.system(size: 16))
                    Text(value)
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(active ? AppColor.text : AppColor.text3)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.horizontal, 4)
                }
                .frame(width: 68, height: 68)
                .background(color.opacity(active ? 0.24 : 0.10), in: Circle())
                .overlay(Circle().strokeBorder(color.opacity(active ? 0.5 : 0.18),
                                               lineWidth: pulse ? 2 : 1.5))
                .scaleEffect(popped.contains(stat) ? 1.12 : 1)
                .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.55),
                           value: popped)
            }
            Text(label)
                .sectionLabelStyle(color: AppColor.text3)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    /// A short grow-and-settle when a stat gains a new event — the moment a
    /// fresh entry lands, from either home or the daycare feed.
    private func pop(_ stat: Stat) {
        guard !reduceMotion else { return }
        popped.insert(stat)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.45))
            popped.remove(stat)
        }
    }

    /// Whole-day sleep; mid-nap the running nap joins the count live (its
    /// SleepEvent only lands when staff log the wake), so the bead ticks.
    private var sleepValue: String {
        var total = sleepSeconds
        if let start = liveNapStartedAt { total += max(0, now.timeIntervalSince(start)) }
        return total > 0 ? WakeWindow.shortLabel(total) : "—"
    }

    // MARK: Home / daycare split

    /// One emoji-tagged line in a split section — "🍼 10 oz (2 feeds)".
    private struct SplitLine: Identifiable {
        let emoji: String
        let text: String
        var tint: Color?
        var id: String { emoji + text }
    }

    private var homeLines: [SplitLine] {
        trackerLines(oz: homeOz, feeds: homeFeeds, changes: homeChanges, sleep: homeSleep)
    }

    /// The daycare section also carries the day's softer entries — photos,
    /// activities — and medication in its attention red.
    private var daycareLines: [SplitLine] {
        var lines = trackerLines(oz: daycare.feedOz, feeds: daycare.feedCount,
                                 changes: daycare.diaperCount, sleep: daycare.napSeconds)
        if daycare.activityCount > 0 {
            lines.append(SplitLine(
                emoji: "🎨",
                text: "\(daycare.activityCount) " + (daycare.activityCount == 1 ? "activity" : "activities")))
        }
        if daycare.photoCount > 0 {
            lines.append(SplitLine(emoji: "📸", text: Plural.count(daycare.photoCount, "photo")))
        }
        if daycare.medicationCount > 0 {
            lines.append(SplitLine(
                emoji: "💊",
                text: "\(Plural.count(daycare.medicationCount, "medication")) given — see the timeline",
                tint: AppColor.accentMedication))
        }
        return lines
    }

    private func trackerLines(oz: Double, feeds: Int, changes: Int,
                              sleep: TimeInterval) -> [SplitLine] {
        var lines: [SplitLine] = []
        if showFeed, feeds > 0 { lines.append(SplitLine(emoji: "🍼", text: feedText(oz: oz, feeds: feeds))) }
        if showDiaper, changes > 0 { lines.append(SplitLine(emoji: "💩", text: Plural.count(changes, "change"))) }
        if showSleep, sleep > 0 {
            lines.append(SplitLine(emoji: "💤", text: TimeFormatting.duration(minutes: Int(sleep / 60))))
        }
        return lines
    }

    private func feedText(oz: Double, feeds: Int) -> String {
        oz > 0 ? "\(OzFormat.string(oz)) oz (\(Plural.count(feeds, "feed")))" : Plural.count(feeds, "feed")
    }

    private func splitSection(icon: String, title: String, tint: Color,
                              lines: [SplitLine]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(icon).font(.caption2)
                Text(title)
                    .font(.caption2.weight(.bold))
                    .kerning(0.6)
                    .foregroundStyle(tint)
            }
            if lines.isEmpty {
                Text("nothing yet")
                    .font(.caption)
                    .foregroundStyle(AppColor.text3)
                    .padding(.leading, 20)
            } else {
                ForEach(lines) { line in
                    HStack(spacing: 6) {
                        Text(line.emoji).font(.caption)
                        Text(line.text)
                            .font(.caption.weight(line.tint == nil ? .regular : .medium))
                            .foregroundStyle(line.tint ?? AppColor.text2)
                            .monospacedDigit()
                    }
                    .padding(.leading, 20)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var accessibilitySummary: String {
        var parts = ["\(babyName) is at daycare since \(TimeFormatting.clock(since))"]
        if napping, let start = liveNapStartedAt {
            parts.append("napping right now, \(TimeFormatting.duration(from: start, to: now)) so far")
        }
        parts.append("at home: " + (homeLines.isEmpty ? "nothing yet"
            : homeLines.map(\.text).joined(separator: ", ")))
        parts.append("at daycare: " + (daycareLines.isEmpty ? "nothing yet"
            : daycareLines.map(\.text).joined(separator: ", ")))
        return parts.joined(separator: ", ")
    }
}

// MARK: - The finished day (after pickup)

/// The quiet form, shown after checkout in the old report card's position:
/// the daycare slice of the day with its attendance span. The TODAY card is
/// back above by then, so this stays daycare-only and calm.
struct DaycareCard: View {
    let babyName: String
    let day: DaycareDaySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\u{1F3EB}").font(.title3)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(babyName)'s day at daycare")
                        .font(.headline)
                        .foregroundStyle(AppColor.text)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(AppColor.text2)
                            .monospacedDigit()
                    }
                }
            }
            Text(summaryLine)
                .font(.subheadline)
                .foregroundStyle(AppColor.text)
                .fixedSize(horizontal: false, vertical: true)
            if let extras {
                Text(extras)
                    .font(.caption)
                    .foregroundStyle(AppColor.text3)
            }
            if day.medicationCount > 0 {
                Text("\(Plural.count(day.medicationCount, "medication")) given — see the timeline.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppColor.accentMedication)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .surfaceCard(cornerRadius: 18)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("daycareCard")
    }

    private var subtitle: String? {
        guard let checkIn = day.checkIn else { return nil }
        guard let checkOut = day.checkOut, checkOut > checkIn else {
            return "from \(TimeFormatting.clock(checkIn))"
        }
        return "\(TimeFormatting.clock(checkIn)) – \(TimeFormatting.clock(checkOut))"
            + " · \(TimeFormatting.duration(from: checkIn, to: checkOut))"
    }

    private var summaryLine: String {
        var parts: [String] = []
        if day.feedCount > 0 {
            parts.append("\(Plural.count(day.feedCount, "bottle")) (\(OzFormat.string(day.feedOz)) oz)")
        }
        if day.napCount > 0 {
            parts.append("\(Plural.count(day.napCount, "nap")) (\(TimeFormatting.duration(minutes: Int(day.napSeconds / 60))))")
        }
        if day.diaperCount > 0 { parts.append(Plural.count(day.diaperCount, "diaper change")) }
        guard !parts.isEmpty else { return "A quiet day at daycare." }
        return "\(babyName) had " + parts.formatted(.list(type: .and)) + "."
    }

    private var extras: String? {
        var parts: [String] = []
        if day.activityCount > 0 {
            parts.append("\(day.activityCount) " + (day.activityCount == 1 ? "activity" : "activities"))
        }
        if day.photoCount > 0 { parts.append(Plural.count(day.photoCount, "photo")) }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ") + " on the timeline"
    }
}

#Preview("Hero, napping") {
    DaycareDayHeroCard(
        babyName: "Miller",
        marks: [],
        feedCount: 3, feedOz: 7, diaperCount: 3, sleepSeconds: 4 * 3600 + 50 * 60,
        daycare: {
            var d = DaycareDaySummary()
            d.feedCount = 1; d.feedOz = 2; d.diaperCount = 1
            d.napCount = 1; d.napSeconds = 40 * 60
            d.activityCount = 2; d.photoCount = 3
            return d
        }(),
        since: .now.addingTimeInterval(-69 * 60),
        liveNapStartedAt: .now.addingTimeInterval(-12 * 60),
        now: .now
    )
    .padding()
    .background(AppColor.bg)
    .preferredColorScheme(.dark)
}
