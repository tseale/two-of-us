import SwiftUI

/// One day of daycare, aggregated for the card. Built by HomeView from
/// today's Brightwheel-imported events; nil counts render as dimmed circles.
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

/// The parents' window into Miller's day while he's at daycare — one card in
/// place of the old report-paragraph + "at daycare" strip pair. Three stat
/// circles carry the whole summary (total oz, changes, sleep), the sleep one
/// turning into a pulsing live counter while Brightwheel has a nap started
/// but not ended. A circle pops when its number grows, so a fresh bottle
/// from the daycare feed registers as a little moment, not a silent redraw.
/// After pickup the same card renders the finished day in its quiet form.
struct DaycareCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let babyName: String
    let day: DaycareDaySummary
    /// Non-nil while he's there: when the daycare day began (check-in marker,
    /// or the first daycare event standing in for a missed one).
    let liveSince: Date?
    /// Start of a nap Brightwheel has begun but not ended — pulses the sleep
    /// circle with a counting timer.
    let liveNapStartedAt: Date?
    let now: Date

    private enum Stat { case feed, diaper, sleep }
    @State private var popped: Set<Stat> = []
    @State private var pulsing = false

    private var isLive: Bool { liveSince != nil }
    private var napping: Bool { isLive && liveNapStartedAt != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\u{1F3EB}").font(.title3)
                VStack(alignment: .leading, spacing: 1) {
                    Text(isLive ? "\(babyName) is at daycare" : "\(babyName)'s day at daycare")
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
            HStack(spacing: 0) {
                statCircle(.feed, emoji: "🍼", color: AppColor.accentFeed,
                           value: feedValue, active: day.feedCount > 0,
                           label: feedLabel)
                statCircle(.diaper, emoji: "💩", color: AppColor.accentDiaper,
                           value: day.diaperCount > 0 ? "\(day.diaperCount)" : "—",
                           active: day.diaperCount > 0,
                           label: day.diaperCount > 0
                               ? Plural.count(day.diaperCount, "diaper change")
                               : "no diaper changes yet")
                statCircle(.sleep, emoji: "💤", color: AppColor.accentSleep,
                           value: sleepValue, active: napping || day.napSeconds > 0,
                           label: sleepLabel, pulse: napping)
            }
            if let extras {
                Text(extras)
                    .font(.caption)
                    .foregroundStyle(AppColor.text3)
            }
            if day.medicationCount > 0 {
                // Medication gets its own red line — never buried in a circle.
                Text("\(Plural.count(day.medicationCount, "medication")) given — see the timeline.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppColor.accentMedication)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            // A soft wash of the three accents — warm, not clinical — laid
            // over the standard card color so hairline + dark mode behave
            // exactly like every other card.
            LinearGradient(colors: [AppColor.accentFeed.opacity(0.10),
                                    AppColor.accentSleep.opacity(0.12)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: .rect(cornerRadius: 18)
        )
        .surfaceCard(cornerRadius: 18)
        .onChange(of: day) { old, new in
            if new.feedOz > old.feedOz || new.feedCount > old.feedCount { pop(.feed) }
            if new.diaperCount > old.diaperCount { pop(.diaper) }
            if new.napSeconds > old.napSeconds || new.napCount > old.napCount { pop(.sleep) }
        }
        .onChange(of: liveNapStartedAt) { old, new in
            if new != nil, old == nil { pop(.sleep) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    // MARK: Circles

    private func statCircle(_ stat: Stat, emoji: String, color: Color,
                            value: String, active: Bool, label: String,
                            pulse: Bool = false) -> some View {
        ZStack {
            if pulse && !reduceMotion {
                // A ring breathing outward — "he's asleep right now", calmly.
                Circle()
                    .stroke(color.opacity(0.7), lineWidth: 2)
                    .frame(width: 66, height: 66)
                    .scaleEffect(pulsing ? 1.25 : 1)
                    .opacity(pulsing ? 0 : 0.8)
                    .animation(.easeOut(duration: 1.6).repeatForever(autoreverses: false),
                               value: pulsing)
                    .onAppear { pulsing = true }
                    .onDisappear { pulsing = false }
            }
            VStack(spacing: 2) {
                Text(emoji).font(.system(size: 17))
                Text(value)
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(active ? AppColor.text : AppColor.text3)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(width: 66, height: 66)
            .background(color.opacity(active ? 0.22 : 0.08), in: Circle())
            .overlay(Circle().strokeBorder(color.opacity(active ? 0.5 : 0.15),
                                           lineWidth: pulse ? 2 : 1.5))
            .scaleEffect(popped.contains(stat) ? 1.12 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.55),
                       value: popped)
        }
        .frame(maxWidth: .infinity)
        .opacity(active ? 1 : 0.6)
        .accessibilityLabel(label)
    }

    /// A short grow-and-settle when a stat gains a new event — the moment a
    /// fresh Brightwheel entry lands.
    private func pop(_ stat: Stat) {
        guard !reduceMotion else { return }
        popped.insert(stat)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.45))
            popped.remove(stat)
        }
    }

    // MARK: Values

    private var feedValue: String {
        guard day.feedCount > 0 else { return "—" }
        return day.feedOz > 0 ? "\(OzFormat.string(day.feedOz)) oz" : "\(day.feedCount)"
    }

    private var feedLabel: String {
        day.feedCount > 0
            ? "\(Plural.count(day.feedCount, "bottle")), \(OzFormat.string(day.feedOz)) ounces total"
            : "no bottles yet"
    }

    private var sleepLabel: String {
        if napping, let start = liveNapStartedAt {
            return "napping right now, \(TimeFormatting.duration(from: start, to: now)) so far"
        }
        return day.napSeconds > 0
            ? "slept \(TimeFormatting.duration(minutes: Int(day.napSeconds / 60)))"
            : "no naps yet"
    }

    private var sleepValue: String {
        if napping, let start = liveNapStartedAt {
            return WakeWindow.shortLabel(max(0, now.timeIntervalSince(start)))
        }
        return day.napSeconds > 0 ? WakeWindow.shortLabel(day.napSeconds) : "—"
    }

    /// "since 7:51 AM · 3h 12m" while he's there; "7:51 AM – 4:30 PM · 8h 39m"
    /// once the day is done.
    private var subtitle: String? {
        if let liveSince {
            return "since \(TimeFormatting.clock(liveSince)) · \(TimeFormatting.duration(from: liveSince, to: now))"
        }
        guard let checkIn = day.checkIn else { return nil }
        guard let checkOut = day.checkOut, checkOut > checkIn else {
            return "from \(TimeFormatting.clock(checkIn))"
        }
        return "\(TimeFormatting.clock(checkIn)) – \(TimeFormatting.clock(checkOut))"
            + " · \(TimeFormatting.duration(from: checkIn, to: checkOut))"
    }

    /// The gentler extras under the circles — the parts of the day that
    /// aren't a tracker stat but make it feel like his day, not a dashboard.
    private var extras: String? {
        var parts: [String] = []
        if day.activityCount > 0 {
            parts.append("\(day.activityCount) " + (day.activityCount == 1 ? "activity" : "activities"))
        }
        if day.photoCount > 0 { parts.append(Plural.count(day.photoCount, "photo")) }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ") + " on the timeline"
    }

    private var accessibilitySummary: String {
        var parts = [isLive ? "\(babyName) is at daycare" : "\(babyName)'s day at daycare"]
        if let subtitle { parts.append(subtitle) }
        if day.feedCount > 0 {
            parts.append("\(Plural.count(day.feedCount, "bottle")), \(OzFormat.string(day.feedOz)) ounces total")
        }
        if day.diaperCount > 0 { parts.append(Plural.count(day.diaperCount, "diaper change")) }
        if napping, let start = liveNapStartedAt {
            parts.append("napping right now, \(TimeFormatting.duration(from: start, to: now)) so far")
        } else if day.napSeconds > 0 {
            parts.append("slept \(TimeFormatting.duration(minutes: Int(day.napSeconds / 60)))")
        }
        if let extras { parts.append(extras) }
        return parts.joined(separator: ", ")
    }
}

#Preview("Live, napping") {
    DaycareCard(
        babyName: "Miller",
        day: {
            var d = DaycareDaySummary()
            d.feedCount = 2; d.feedOz = 5.5; d.diaperCount = 3
            d.napCount = 1; d.napSeconds = 45 * 60
            d.activityCount = 2; d.photoCount = 3
            d.checkIn = .now.addingTimeInterval(-3 * 3600)
            return d
        }(),
        liveSince: .now.addingTimeInterval(-3 * 3600),
        liveNapStartedAt: .now.addingTimeInterval(-12 * 60),
        now: .now
    )
    .padding()
    .background(AppColor.bg)
    .preferredColorScheme(.dark)
}
